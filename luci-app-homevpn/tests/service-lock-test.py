#!/usr/bin/env python3
"""Real parallel ash callers, authenticated nesting and forged inherited flag."""
import os,pathlib,subprocess,sys,tempfile,time
root=pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='hv-lock-') as d:
 p=pathlib.Path(d)
 (p/'lib').write_text((root/'usr/share/homevpn/service-lock.sh').read_text().replace('/var/lock/homevpn-service.lock',str(p/'lock')))
 (p/'child').write_text(f'. {p}/lib\nwork() {{ touch {p}/nested; }}\nhv_with_lock work\n')
 (p/'driver').write_text(f'''. {p}/lib
 work() {{
  touch {p}/entered
  busybox ash {p}/child || return 1
  while [ ! -f {p}/release ]; do sleep 0.02; done
 }}
 hv_with_lock work
 ''')
 (p/'rival').write_text(f'. {p}/lib\nwork() {{ touch {p}/rival-write; }}\nhv_with_lock work\n')
 a=subprocess.Popen(['busybox','ash',str(p/'driver')],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 try:
  deadline=time.monotonic()+5
  while not (p/'entered').exists() and time.monotonic()<deadline:time.sleep(.02)
  assert (p/'entered').exists(),'first caller never entered'
  env=dict(os.environ,HOMEVPN_SERVICE_LOCK_HELD='1')
  b=subprocess.run(['busybox','ash',str(p/'rival')],env=env,capture_output=True,text=True,timeout=5)
  assert b.returncode!=0 and not (p/'rival-write').exists(),'forged HELD bypasses live lock'
  (p/'release').touch();out,err=a.communicate(timeout=5)
  assert a.returncode==0 and (p/'nested').exists(),(out,err,'nested deadlock')
  c=subprocess.run(['busybox','ash',str(p/'rival')],capture_output=True,text=True,timeout=5)
  assert c.returncode==0 and (p/'rival-write').exists(),c.stderr
 finally:
  (p/'release').touch()
  if a.poll() is None:a.kill();a.wait()
 print('PASS real parallel lock: unrelated forged HELD blocked before write, nested child succeeds, next request succeeds')
