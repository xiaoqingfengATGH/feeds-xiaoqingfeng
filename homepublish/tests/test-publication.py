#!/usr/bin/env python3
"""Native publication tests: root, isolated network namespace only."""
import os,pathlib,subprocess,tempfile,time,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Publication(unittest.TestCase):
 def test_callback_native_adapter_exists(self):
  self.assertTrue((ROOT/'src/publisher.c').exists(),'missing authenticated native mapping adapter')
  subprocess.run(['gcc','-Wall','-Wextra','-Werror',str(ROOT/'src/publisher.c'),'-o','/dev/null'],check=True)
 def test_real_http_callback_to_worker(self):
  self.assertTrue((ROOT/'src/publisher.c').exists(),'missing authenticated native mapping adapter')
  self.assertEqual(os.geteuid(),0)
  self.assertNotEqual(os.readlink('/proc/self/ns/net'),os.readlink('/proc/1/ns/net'),'must isolate network')
  import http.server,json,threading,shutil
  node='/mnt/c/Users/xiaoq/AppData/Local/hermes/tools/node-26.7.0-win32-x64/node.exe'
  win=lambda p:'D:/'+str(p)[7:] if str(p).startswith('/mnt/d/') else str(p)  # WSL->Windows path for Windows node.exe
  bridge=subprocess.Popen([node,win(ROOT/'tests/publication-bridge.mjs')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
  self.assertEqual(bridge.stdout.readline().strip(),'READY')
  observations=[];stall=[False]
  class Handler(http.server.BaseHTTPRequestHandler):
   def log_message(self,*a):pass
   def do_POST(self):
    if stall[0]:time.sleep(3);self.send_response(204);self.end_headers();return
    b=self.rfile.read(int(self.headers['Content-Length'])).decode();observations.append(json.loads(b))
    bridge.stdin.write(json.dumps({'path':self.path,'method':'POST','headers':dict(self.headers),'body':b})+'\n');bridge.stdin.flush()
    self.send_response(json.loads(bridge.stdout.readline())['status']);self.end_headers()
  server=http.server.HTTPServer(('127.0.0.1',0),Handler);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
  try:
   with tempfile.TemporaryDirectory(prefix='homepublish-publication-',dir='/tmp') as d:
    # tempfile random names may contain underscores; production names are hex.
    import uuid
    r=pathlib.Path('/tmp/homepublish-publication-'+uuid.uuid4().hex);r.mkdir(mode=0o700)
    self.addCleanup(shutil.rmtree,r)
    now=int(time.time()*1000)
    (r/'router.token').write_text('r'*32);(r/'router.token').chmod(0o600)
    (r/'session').write_text(f'{now} '+ 'a'*32+f' {now+30000} {time.monotonic()+30:.6f} 18444 0\n');(r/'session').chmod(0o600)
    shim=r/'curlshim'
    shim.write_text('#!/usr/bin/python3\nimport os,sys\na=sys.argv[1:]\nassert a[:2]==["--disable","--config"]\nassert "--insecure" not in a and "--location" not in a\ns=sys.stdin.read(); assert "https://stun-test.innonext.win/" in s\ns=s.replace("https://stun-test.innonext.win/","http://127.0.0.1:'+str(server.server_port)+'/")\ns=s.replace("proto = \\"=https\\"","proto = \\"=http\\"")\nimport pathlib, subprocess\np=subprocess.run(["/usr/bin/curl"]+a,input=s,text=True);sys.exit(p.returncode)\n')
    shim.chmod(0o700)
    binary=r/'publisher';subprocess.run(['gcc','-Wall','-Wextra','-Werror',f'-DCURL_PROGRAM="{shim}"',str(ROOT/'src/publisher.c'),'-o',str(binary)],check=True)
    env={**os.environ,'HOMEPUBLISH_RUNTIME':str(r)}
    def run(*args):return subprocess.run([str(binary),*args],env=env,capture_output=True,text=True,timeout=5)
    self.assertEqual(run('--begin',str(r)).returncode,0)
    callback=['198.51.100.7','23456','2001::5ba0:c633:6407','18444','tcp','0.0.0.0']
    result=run(*callback);self.assertEqual(result.returncode,0,result.stderr)
    self.assertEqual(observations[-1]['port'],23456);self.assertEqual(observations[-1]['mappedIP'],'198.51.100.7')
    bridge.stdin.write(json.dumps({'path':'/go/nas','method':'GET','headers':{'Authorization':'Bearer '+'v'*32}})+'\n');bridge.stdin.flush()
    self.assertEqual(json.loads(bridge.stdout.readline())['location'],'https://nas-stun-test.innonext.win:23456/')
    count=len(observations)
    stall[0]=True;started=time.monotonic();self.assertNotEqual(run(*callback).returncode,0);self.assertLess(time.monotonic()-started,3)
    time.sleep(1.2);stall[0]=False
    for index,value in [(0,'999.1.1.1'),(1,'443'),(1,'2;id'),(3,'18445'),(4,'udp')]:
     bad=callback.copy();bad[index]=value;self.assertNotEqual(run(*bad).returncode,0)
    self.assertEqual(len(observations),count)
    # A wrong router secret reaches the real Worker and cannot mutate the lease.
    (r/'router.token').write_text('z'*32);self.assertNotEqual(run(*callback).returncode,0);(r/'router.token').write_text('r'*32)
    count=len(observations)
    self.assertNotIn('r'*32,result.stdout+result.stderr)
    (r/'router.token').chmod(0o644);self.assertNotEqual(run(*callback).returncode,0);(r/'router.token').chmod(0o600)
    (r/'router.token').rename(r/'original');(r/'router.token').symlink_to(r/'original');self.assertNotEqual(run(*callback).returncode,0)
    (r/'router.token').unlink();(r/'original').rename(r/'router.token')
    (r/'session').write_text(f'{now} '+ 'a'*32+f' {now+30000} nan 18444 0\n');self.assertNotEqual(run(*callback).returncode,0)
    (r/'session').write_text(f'{now} '+ 'a'*32+f' {now+30000} {time.monotonic()-1:.6f} 18444 0\n');self.assertNotEqual(run(*callback).returncode,0)
    self.assertEqual(len(observations),count)

  finally:
   server.shutdown();server.server_close();thread.join();bridge.terminate();bridge.wait(timeout=5)

 def test_native_optin_provision_callback_and_cleanup(self):
  import importlib.util
  import types
  m=types.ModuleType('cleanup');m.__file__=str(ROOT/'tests/test-source-cleanup.py');exec((ROOT/'tests/test-source-cleanup.py').read_text(),m.__dict__)
  f=m.SourceCleanup();f.setUp()
  try:
   f.provision_fixture();token=f.root/'etc/homepublish/router.token';token.write_text('r'*32);token.chmod(0o600)
   publisher=f.root/'usr/libexec/homepublish-publish'
   publisher.write_text('#!/bin/sh\nif [ "$1" = --begin ]; then [ -s "$2/session" ] && [ -s "$2/router.token" ] || exit 2; echo begin > /tmp/begun; else [ -n "$HOMEPUBLISH_RUNTIME" ] || exit 2; echo "$*" > /tmp/callback; fi\n');publisher.chmod(0o755)
   natmap=f.root/'usr/bin/natmap'
   natmap.write_text('#!/bin/sh\n[ -f /tmp/begun ] || exit 2\ncase "$*" in *"-e /usr/libexec/homepublish-publish"*) ;; *) exit 2;; esac\n/usr/libexec/homepublish-publish 198.51.100.7 23456 2001::5ba0:c633:6407 18444 tcp 0.0.0.0\necho ready > /tmp/ready\nsleep 60\n');natmap.chmod(0o755)
   process=subprocess.Popen(['chroot',str(f.root),'/usr/libexec/homepublish-lease','--provision','3','18444','18443','example.com','example.com','publish'],stderr=subprocess.PIPE)
   output=process.communicate(timeout=6)[1]
   self.assertEqual(process.returncode,0,output)
   self.assertEqual((f.root/'tmp/callback').read_text().split(),['198.51.100.7','23456','2001::5ba0:c633:6407','18444','tcp','0.0.0.0'])
   f.assert_provision_cleanup();self.assertEqual(token.read_text(),'r'*32)
  finally:f.doCleanups()

if __name__=='__main__':unittest.main()
