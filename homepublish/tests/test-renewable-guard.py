#!/usr/bin/env python3
"""Unprivileged Linux-only real process-control tests (no installed CLI)."""
import os, pathlib, subprocess, tempfile, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class Guardian(unittest.TestCase):
 def test_expiry_closes_stream(self):
  self.assertTrue((ROOT/'src/renewable-guard.c').exists(), 'independent renewable guardian missing')
  with tempfile.TemporaryDirectory(prefix='hp-guard-') as d:
   exe=pathlib.Path(d)/'fixture'
   subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-DHP_GUARD_TEST','-I'+str(ROOT/'src'),str(ROOT/'src/renewable-guard.c'),str(ROOT/'tests/renewable-guard-fixture.c'),'-o',str(exe)],check=True)
   faults=pathlib.Path(d)/'faults'
   subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-DHP_GUARD_TEST','-I'+str(ROOT/'src'),str(ROOT/'src/renewable-guard.c'),str(ROOT/'tests/renewable-start-faults.c'),'-Wl,--wrap=fork','-Wl,--wrap=syscall','-o',str(faults)],check=True)
   if os.environ.get('CASE') in (None,'startup'):
    for fault in ['1','2','3','pidfd']: subprocess.run([str(faults),fault],check=True,timeout=4)
    if os.environ.get('CASE')=='startup': return
   foreign=subprocess.Popen(['sleep','60'])
   sentinel=pathlib.Path(d)/'foreign';sentinel.write_bytes(b'foreign-preserved')
   try:
    cases=[os.environ['CASE']] if 'CASE' in os.environ else ['foreign-fd','expiry','renew','temporary','controller-kill','controller-stop','watchdog-stop','watchdog-kill','guardian-kill','guardian-stop','stop','stale-gen','stale-epoch','replay','auth','short']
    for case in cases:
     with self.subTest(case=case):
      subprocess.run([str(exe),case],check=True,timeout=8)
      self.assertIsNone(foreign.poll());self.assertEqual(sentinel.read_bytes(),b'foreign-preserved')
   finally: foreign.terminate();foreign.wait(timeout=2)
  self.assertFalse(pathlib.Path(d).exists())
  print('PASS foreign process/files preserved; fixture directory removed')
if __name__=='__main__': unittest.main()
