#!/usr/bin/env python3
"""Root/network-namespace-only cryptographic TLS and secret fault regressions."""
import hashlib, http.server, os, pathlib, shutil, signal, ssl, subprocess, tempfile, threading, time, types, unittest, uuid
ROOT = pathlib.Path(__file__).resolve().parents[1]

class Security(unittest.TestCase):
 def setUp(self):
  self.assertEqual(os.geteuid(), 0)
  self.assertNotEqual(os.readlink('/proc/self/ns/net'), os.readlink('/proc/1/ns/net'))
  self.r = pathlib.Path('/tmp/homedirect-security-' + uuid.uuid4().hex)
  self.r.mkdir(mode=0o700); self.addCleanup(shutil.rmtree, self.r)
  self.token = self.r/'router.token'; self.token.write_text('r'*32); self.token.chmod(0o600)
  now=int(time.time()*1000)
  self.session=self.r/'session'; self.session.write_text(f'{now} '+ 'a'*32 + f' {now+100000} {time.monotonic()+100:.9f} 18444 0\n'); self.session.chmod(0o600)
 def compile(self, shim=None):
  binary=self.r/('publisher' if shim else 'production')
  args=['gcc','-Wall','-Wextra','-Werror']
  if shim: args += [f'-DCURL_PROGRAM="{shim}"']
  subprocess.run(args+[str(ROOT/'src/publisher.c'),'-o',str(binary)],check=True)
  return binary
 def runpub(self,binary,env=None):
  return subprocess.run([str(binary),'--begin',str(self.r)],env={**os.environ,**(env or {})},capture_output=True,timeout=4)
 def test_credential_boundaries_and_metadata(self):
  calls=self.r/'calls'
  shim=self.r/'curl';shim.write_text('#!/usr/bin/python3\nimport sys\nsys.stdin.read()\nopen('+repr(str(calls))+',"a").write("request\\n")\nprint("204",end="")\n');shim.chmod(0o700)
  binary=self.compile(shim)
  for size in (31,32,128,129,4096):
   with self.subTest(size=size):
    self.token.write_text('r'*size)
    before=calls.read_text() if calls.exists() else ''
    result=self.runpub(binary)
    if size in (32,128): self.assertEqual(result.returncode,0)
    else:
     self.assertNotEqual(result.returncode,0,'oversized/undersized credential accepted')
     self.assertEqual(calls.read_text() if calls.exists() else '',before)
  for value in ('r'*32+'\n', 'r'*31+'"', 'r'*31+'\\', 'r'*31+'\x00'):
   self.token.write_text(value)
   before=calls.read_text()
   self.assertNotEqual(self.runpub(binary).returncode,0)
   self.assertEqual(calls.read_text(),before)
  self.token.write_text('r'*32)
  for target in (self.token,self.session):
   for fault in ('owner','mode','symlink','hardlink'):
    with self.subTest(target=target.name,fault=fault):
     saved=self.r/'saved';extra=self.r/'extra'
     before=calls.read_text()
     if fault=='owner':os.chown(target,65534,65534)
     elif fault=='mode':target.chmod(0o644)
     elif fault=='symlink':target.rename(saved);target.symlink_to(saved)
     else:os.link(target,extra)
     try:
      self.assertNotEqual(self.runpub(binary).returncode,0)
      self.assertEqual(calls.read_text(),before)
     finally:
      if fault=='owner':os.chown(target,0,0)
      elif fault=='mode':target.chmod(0o600)
      elif fault=='symlink':target.unlink();saved.rename(target)
      else:extra.unlink()
 def test_real_tls_trust_hostname_and_environment_isolation(self):
  def openssl(*args):subprocess.run(['openssl',*args],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  ca=self.r/'ca.pem';cakey=self.r/'ca.key'
  openssl('req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(cakey),'-out',str(ca),'-days','1','-subj','/CN=HomeDirect fixture CA')
  observations=[]
  class Handler(http.server.BaseHTTPRequestHandler):
   def log_message(self,*a):pass
   def do_POST(self):
    observations.append((self.path,self.rfile.read(int(self.headers['Content-Length']))));self.send_response(204);self.end_headers()
  def fixture(name):
   key=self.r/(name+'.key');csr=self.r/(name+'.csr');cert=self.r/(name+'.pem');ext=self.r/(name+'.ext')
   openssl('req','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(csr),'-subj','/CN='+name)
   ext.write_text('subjectAltName=DNS:'+name+'\n')
   openssl('x509','-req','-in',str(csr),'-CA',str(ca),'-CAkey',str(cakey),'-CAcreateserial','-out',str(cert),'-days','1','-extfile',str(ext))
   server=http.server.HTTPServer(('127.0.0.1',443),Handler)
   context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(cert,key);server.socket=context.wrap_socket(server.socket,server_side=True)
   thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
   return server,thread
  # Compile-time transport fixture only: real curl still validates the fixed origin.
  # Namespace /etc/hosts maps that origin to loopback (runner uses private mount).
  curl_results=self.r/'curl-results'
  def shim(trust):
   p=self.r/('trusted-curl' if trust else 'system-curl')
   p.write_text('#!/usr/bin/python3\nimport os,sys,subprocess\nassert set(os.environ)<= {"PATH","LC_CTYPE"},os.environ\nassert sys.argv[1:]==["--disable","--config","-"]\nrc=subprocess.run(["/usr/bin/curl","--disable",'+ ('"--cacert",'+repr(str(ca))+',' if trust else '')+'"--config","-"]).returncode\nopen('+repr(str(curl_results))+',"w").write(str(rc))\nsys.exit(rc)\n');p.chmod(0o700);return p
  trusted=self.compile(shim(True));trusted.rename(self.r/'trusted');trusted=self.r/'trusted'
  system=self.compile(shim(False));system.rename(self.r/'system');system=self.r/'system'
  production=self.compile()
  poisoned={'CURL_CA_BUNDLE':str(ca),'SSL_CERT_FILE':str(ca),'SSL_CERT_DIR':str(self.r),'https_proxy':'http://127.0.0.1:1','ALL_PROXY':'http://127.0.0.1:1','HOME':str(self.r)}
  (self.r/'.curlrc').write_text('insecure\n')
  for name in ('stun-test.innonext.win','wrong.invalid'):
   server,thread=fixture(name)
   try:
    before=len(observations)
    self.assertNotEqual(self.runpub(system,poisoned).returncode,0)
    self.assertEqual(curl_results.read_text(),'60','must fail cryptographic certificate validation, not transport')
    self.assertNotEqual(self.runpub(production,poisoned).returncode,0)
    self.assertEqual(len(observations),before,'untrusted TLS sent HTTP credentials')
    result=self.runpub(trusted,poisoned)
    self.assertEqual(curl_results.read_text(),'0' if name=='stun-test.innonext.win' else '60')
    if name=='stun-test.innonext.win':
     self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(len(observations),before+1)
    else:
     self.assertNotEqual(result.returncode,0);self.assertEqual(len(observations),before,'hostname mismatch sent credentials')
   finally:server.shutdown();server.server_close();thread.join()
 def test_publication_snapshot_cleanup_faults(self):
  m=types.ModuleType('cleanup');m.__file__=str(ROOT/'tests/test-source-cleanup.py');exec(pathlib.Path(m.__file__).read_text(),m.__dict__)
  for role in ('controller','guardian','preparation'):
   for sig in (signal.SIGKILL,signal.SIGSTOP):
    with self.subTest(role=role,signal=sig.name):
     f=m.SourceCleanup();f.setUp();process=None
     try:
      f.provision_fixture();token=f.root/'etc/homedirect/router.token';token.write_text('r'*32);token.chmod(0o600)
      original=hashlib.sha256(token.read_bytes()).hexdigest()
      publisher=f.root/'usr/libexec/homedirect-publish'
      publisher.write_text('#!/bin/sh\n[ -s "$2/session" ] && [ -s "$2/router.token" ] || exit 2\necho snapshot > /tmp/rendering\nsleep 60\n');publisher.chmod(0o755)
      process=subprocess.Popen(['chroot',str(f.root),'/usr/libexec/homedirect-lease','--provision','3','18444','18443','example.com','example.com','publish'],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
      f.wait_rendering(process)
      generated=next(p for p in (f.root/'tmp').glob('homedirect-service-*') if p!=f.runtime)
      self.assertEqual((generated/'router.token').read_text(),'r'*32);self.assertTrue((generated/'session').stat().st_size>0)
      guardian=f.children(process.pid)[0];victim={'controller':process.pid,'guardian':guardian,'preparation':f.children(guardian)[0]}[role]
      os.kill(victim,sig)
      if role=='controller' and sig==signal.SIGSTOP:
       deadline=time.monotonic()+4
       while generated.exists() and time.monotonic()<deadline:time.sleep(.02)
       self.assertFalse(generated.exists());os.kill(victim,signal.SIGCONT)
      process.communicate(timeout=6)
      deadline=time.monotonic()+4
      while generated.exists() and time.monotonic()<deadline:time.sleep(.02)
      f.assert_provision_cleanup();self.assertFalse(generated.exists())
      self.assertEqual(hashlib.sha256(token.read_bytes()).hexdigest(),original)
      self.assertFalse((f.root/'tmp/ready').exists(),'engines started before accepted begin')
     finally:
      if process and process.poll() is None:
       os.kill(process.pid,signal.SIGCONT);process.kill();process.communicate(timeout=6)
      f.doCleanups()

if __name__=='__main__':unittest.main()
