#!/usr/bin/env python3
"""Whole-file token validation with deterministic short reads and EINTR."""
import os, pathlib, shutil, subprocess, time, types, unittest, uuid
ROOT=pathlib.Path(__file__).resolve().parents[1]
CASES=[(str(n),b'r'*n,32<=n<=128) for n in (31,32,127,128,129,512)]+[(name,b'r'*32+suffix,False) for name,suffix in [('newline',b'\n'),('nul',b'\0'),('invalid',b'!'),('nonascii',b'\xff')]]+[(name,b'r'*128+suffix,False) for name,suffix in [('128-newline',b'\n'),('128-nul',b'\0'),('128-invalid',b'!')]]+[('allowed',b'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.',True)]
class TokenValidation(unittest.TestCase):
 def setUp(self):
  self.assertEqual(os.geteuid(),0)
  self.r=pathlib.Path('/tmp/homepublish-token-'+uuid.uuid4().hex);self.r.mkdir(mode=0o700);self.addCleanup(shutil.rmtree,self.r)
 def test_publisher_whole_file_before_sequence_or_transport(self):
  token=self.r/'router.token';token.touch(mode=0o600)
  session=self.r/'session';calls=self.r/'calls';trace=self.r/'trace';expected=self.r/'expected'
  shim=self.r/'curl';shim.write_text('#!/usr/bin/python3\nimport pathlib,sys\npathlib.Path('+repr(str(calls))+').write_text("transport")\ns=sys.stdin.read()\nt=pathlib.Path('+repr(str(expected))+').read_text()\nassert "Authorization: Bearer "+t+chr(34) in s\nprint("204",end="")\n');shim.chmod(0o700)
  for injected in ('regular','short','eintr'):
   binary=self.r/'publisher';args=['gcc','-Wall','-Wextra','-Werror',f'-DCURL_PROGRAM="{shim}"',str(ROOT/'src/publisher.c')]
   if injected!='regular':args += [str(ROOT/'tests/token-io-injection.c'),f'-DTRACE_PATH="{trace}"','-Wl,--wrap=read','-Wl,--wrap=openat']
   if injected=='short':args += ['-DNO_EINTR']
   subprocess.run(args+['-o',str(binary)],check=True)
   for name,value,valid in CASES:
    with self.subTest(injected=injected,case=name):
     now=int(time.time()*1000);session.write_text(f'{now} '+ 'a'*32+f' {now+100000} {time.monotonic()+100:.9f} 18444 0\n');session.chmod(0o600);before=session.read_bytes()
     token.write_bytes(value);expected.write_bytes(value)
     for p in (calls,trace):p.unlink(missing_ok=True)
     result=subprocess.run([str(binary),'8.8.8.8','18443','unused','18444','tcp','0.0.0.0'],env={**os.environ,'HOMEPUBLISH_RUNTIME':str(self.r)},capture_output=True,timeout=5)
     if valid:
      self.assertEqual(result.returncode,0,result.stderr);self.assertTrue(calls.exists());self.assertEqual(session.read_text().split()[-1],'1')
     else:
      self.assertNotEqual(result.returncode,0);self.assertFalse(calls.exists());self.assertEqual(session.read_bytes(),before)
     if injected!='regular':
      events=trace.read_text();self.assertIn('short',events)
      if injected=='eintr':self.assertIn('interrupt',events)
      if len(value)<=128:self.assertIn('eof',events)
      else:self.assertNotIn('eof',events,'oversize must stop at bounded sentinel')
 def test_provision_rejects_before_token_snapshot(self):
  m=types.ModuleType('cleanup');m.__file__=str(ROOT/'tests/test-source-cleanup.py');exec(pathlib.Path(m.__file__).read_text(),m.__dict__)
  f=m.SourceCleanup();f.setUp();self.addCleanup(f.doCleanups);f.provision_fixture()
  trace=f.root/'tmp/token-io-log';token=f.root/'etc/homepublish/router.token';publisher=f.root/'usr/libexec/homepublish-publish'
  for injected in ('regular','short','eintr'):
   args=['gcc','-static','-Wall','-Wextra','-Werror',str(ROOT/'src/lease-supervisor.c'),str(ROOT/'tests/token-io-injection.c'),'-Wl,--wrap=read','-Wl,--wrap=openat']
   if injected=='regular':args+=['-DNO_READ_INJECTION']
   if injected=='short':args+=['-DNO_EINTR']
   subprocess.run(args+['-o',str(f.root/'usr/libexec/homepublish-lease')],check=True)
   for name,value,valid in CASES:
    with self.subTest(injected=injected,case=name):
     token.write_bytes(value);token.chmod(0o600)
     # Successful begin verifies the full token, not a truncated accepted prefix.
     expected=value.decode('ascii') if valid else 'invalid-must-not-be-copied'
     publisher.write_text('#!/bin/sh\necho begin > /tmp/transport\nIFS= read -r token < "$2/router.token" || :\n[ "$token" = "'+expected+'" ] && [ -s "$2/session" ] || exit 2\n');publisher.chmod(0o755)
     for p in (trace,f.root/'tmp/transport',f.root/'tmp/ready'):p.unlink(missing_ok=True)
     result=subprocess.run(['chroot',str(f.root),'/usr/libexec/homepublish-lease','--provision','1','18444','18443','example.com','example.com','publish'],capture_output=True,timeout=5)
     events=trace.read_text() if trace.exists() else ''
     self.assertEqual(token.read_bytes(),value);f.assert_provision_cleanup()
     generated=[p for p in (f.root/'tmp').glob('homepublish-service-*') if p!=f.runtime];self.assertEqual(generated,[])
     if valid:
      self.assertEqual(result.returncode,0,result.stderr);self.assertIn('snapshot',events);self.assertTrue((f.root/'tmp/transport').exists());self.assertTrue((f.root/'tmp/ready').exists())
     else:
      self.assertNotEqual(result.returncode,0);self.assertNotIn('snapshot',events,'invalid secret copied before validation');self.assertFalse((f.root/'tmp/transport').exists());self.assertFalse((f.root/'tmp/ready').exists())
     if injected!='regular':
      self.assertIn('short',events)
      if injected=='eintr':self.assertIn('interrupt',events)
      if len(value)<=128:self.assertIn('eof',events)
      else:self.assertNotIn('eof',events)
if __name__=='__main__':unittest.main()
