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
   subprocess.run([str(exe),'expiry'],check=True,timeout=8)
if __name__=='__main__': unittest.main()
