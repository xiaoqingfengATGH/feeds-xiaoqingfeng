#!/usr/bin/env python3
"""Interleave actual RPC processes at first UCI write and nested init apply."""
import json,os,pathlib,subprocess,sys,tempfile,time
root=pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='hv-rpc-lock-') as d:
 p=pathlib.Path(d);(p/'bin').mkdir()
 def exe(name,text):f=p/name;f.write_text('#!/bin/sh\n'+text);f.chmod(0o755)
 (p/'lib').write_text((root/'usr/share/homevpn/service-lock.sh').read_text().replace('/var/lock/homevpn-service.lock',str(p/'lock')))
 (p/'resolver').write_text(':\n')
 exe('bin/uci',f'''[ "$1" != -q ] || shift
 case "$1" in
 get) case "$2" in *.remote) echo vpn.example.test;; *.enabled) [ ! -f {p}/on ] && echo 0 || echo 1;; *.cert_mode) echo selfsigned;; *.ip_mode) echo lansubnet;; *) exit 1;; esac;;
 set|add|delete|commit)
  echo "$*" >> {p}/writes
  if [ -f {p}/hold ]; then touch {p}/entered; while [ -f {p}/hold ]; do sleep 0.02; done; fi;;
 esac
 ''')
 exe('init',f'''. {p}/lib
 apply() {{ echo "$*" >> {p}/applied; }}
 hv_with_lock apply "$@"
 ''')
 src=(root/'usr/libexec/rpcd/homevpn').read_text().replace('/usr/share/homevpn/service-lock.sh',str(p/'lib')).replace('/usr/share/homevpn/acme-resolve.sh',str(p/'resolver')).replace('/etc/init.d/homevpn',str(p/'init'))
 (p/'swan/x509').mkdir(parents=True);(p/'swan/private').mkdir();(p/'swan/x509ca').mkdir()
 exe('bin/pidof',f'[ -f {p}/on ]\n')
 exe('bin/swanctl',f'''. {p}/lib
 hv_lock_nested || exit 9
 echo "$*" >> {p}/creds
 while [ -f {p}/load-hold ]; do sleep 0.02; done
 ''')
 subprocess.run(['openssl','req','-x509','-newkey','ec','-pkeyopt','ec_paramgen_curve:prime256v1','-nodes','-keyout',str(p/'key.pem'),'-out',str(p/'cert.pem'),'-days','1','-subj','/CN=vpn.example.test','-addext','subjectAltName=DNS:vpn.example.test'],check=True,capture_output=True)
 src=src.replace('/etc/swanctl',str(p/'swan'))
 (p/'rpc').write_text(src)
 env=dict(os.environ,PATH=str(p/'bin')+':'+os.environ['PATH'])
 def call(method,arg):
  r=subprocess.run(['busybox','ash',str(p/'rpc'),'call',method],input=json.dumps(arg)+'\n',env=env,text=True,capture_output=True,timeout=5)
  assert r.returncode==0,(r.stdout,r.stderr)
  return json.loads(r.stdout)
 (p/'hold').touch()
 a=subprocess.Popen(['busybox','ash',str(p/'rpc'),'call','set_settings'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,text=True)
 a.stdin.write(json.dumps({'vpn_name':'first','ip_mode':'lansubnet'})+'\n');a.stdin.close();a.stdin=None
 try:
  deadline=time.monotonic()+5
  while not (p/'entered').exists() and time.monotonic()<deadline:time.sleep(.02)
  assert (p/'entered').exists(),'first RPC never reached UCI write'
  before=(p/'writes').read_text()
  for method,arg in [('set_enabled',{'enabled':False}),('set_settings',{'vpn_name':'rival'}),('upload_certs',{'server':'invalid fixture'}),('add_user',{}),('del_user',{}),('set_user_ip',{}),('provision',{})]:
   result=call(method,arg)
   assert result.get('ok') is False and 'busy' in result.get('error','').lower(),(method,result)
   assert (p/'writes').read_text()==before,(method,'partial writes while busy')
   assert not (p/'applied').exists(),(method,'apply while other RPC mutates')
 finally:
  (p/'hold').unlink(missing_ok=True)
  out,err=a.communicate(timeout=10)
 assert a.returncode==0 and json.loads(out).get('ok') is True,(out,err)
 assert (p/'applied').read_text().strip()=='regen','nested RPC/init did not apply'
 assert call('set_enabled',{'enabled':False})['ok'] is True
 result=call('upload_certs',{'server':(p/'cert.pem').read_text(),'key':(p/'key.pem').read_text(),'ca':(p/'cert.pem').read_text()})
 assert result.get('ok') is True,result
 assert not (p/'creds').exists(),'disabled upload must not call load-creds'
 assert not (p/'lock').exists(),'upload leaked lock'
 (p/'on').touch();(p/'load-hold').touch()
 a=subprocess.Popen(['busybox','ash',str(p/'rpc'),'call','upload_certs'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,text=True)
 a.stdin.write(json.dumps({'server':(p/'cert.pem').read_text(),'key':(p/'key.pem').read_text()})+'\n');a.stdin.close();a.stdin=None
 try:
  deadline=time.monotonic()+5
  while not (p/'creds').exists() and time.monotonic()<deadline:time.sleep(.02)
  assert (p/'creds').exists(),'enabled upload did not reload under authenticated lock'
  before=(p/'applied').read_text()
  result=call('set_enabled',{'enabled':False})
  assert result.get('ok') is False and 'busy' in result.get('error','').lower(),result
  assert (p/'applied').read_text()==before,'off interleaved with credential reload'
 finally:
  (p/'load-hold').unlink(missing_ok=True);out,err=a.communicate(timeout=10)
 assert a.returncode==0 and json.loads(out).get('ok') is True,(out,err)
 assert not (p/'lock').exists(),'enabled upload leaked lock'
 print('PASS real interleaved RPC: seven mutators busy before writes; nested apply; disabled upload skips credentials; enabled upload holds authenticated lock through load-creds')
