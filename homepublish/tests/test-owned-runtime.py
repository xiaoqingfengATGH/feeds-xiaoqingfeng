#!/usr/bin/env python3
"""Local native ownership residual regression; real guard startup/Stop, no installs."""
import os, pathlib, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='hp-owned-',dir=os.environ.get('TMPDIR')) as td:
    base=pathlib.Path(td);exe=base/'probe'
    subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-DHP_GUARD_TEST','-I'+str(ROOT/'homepublish/src'),str(ROOT/'homepublish/src/renewable-guard.c'),str(ROOT/'homepublish/tests/owned-runtime-probe.c'),'-o',str(exe)],check=True)
    cases=('clean','readonly','hardlink','symlink','replacement','directory','foreign-temp','startup0','startup1','startup2','startup3','stop','invalid')
    for case in cases:
        d=base/case;d.mkdir(mode=0o700)
        subprocess.run([str(exe),str(d),case],check=True,timeout=5)
    print('PASS native-owned runtime 13 residual/startup/Stop cases; foreign deletion never inferred')
