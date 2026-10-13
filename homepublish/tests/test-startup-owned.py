#!/usr/bin/env python3
"""Deterministic local startup ownership faults; metadata before fallback."""
import json, os, pathlib, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
CASES=os.environ['HP_START_CASES'].split(',') if os.environ.get('HP_START_CASES') else ['wfd'] if os.environ.get('HP_START_RED') else ['random','pair-controller','pair-guardian','pair-watchdog','fork-guardian','fork-watchdog','fork-provider','map-state','clean-guardian','clean-watchdog','clean-provider','invalid-gen','invalid-epoch','invalid-bound','invalid-child','invalid-nullguard','short-ready','pidfd-probe','pidfd-controller','pidfd-owner','pidfd-guardian-data','pidfd-watchdog-data','wfd','guardian-isolated','watchdog-isolated','provider-isolated','provider-ready','guardian-ready','activated','after-write']+[action+':'+stage for action in ['stop','kill'] for stage in ['guardian-isolated','watchdog-isolated','provider-isolated','guardian-ready','activated']]+['late-grant']*25
with tempfile.TemporaryDirectory(prefix='hp-startup-') as tmp:
 d=pathlib.Path(tmp);exe=d/'probe'
 subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-DHP_GUARD_TEST','-I'+str(ROOT/'src'),str(ROOT/'src/renewable-guard.c'),str(ROOT/'tests/startup-owned-faults.c'),*['-Wl,--wrap='+x for x in ['syscall','send','getrandom','socketpair','fork','mmap']],'-o',str(exe)],check=True)
 results=[]
 for index,case in enumerate(CASES):
  root=d/(case.replace(':','-')+'-'+str(index));root.mkdir(mode=0o700)
  p=subprocess.run([str(exe),str(root),case],capture_output=True,text=True,timeout=8)
  metadata=[{'name':str(f.relative_to(root)),'ino':f.lstat().st_ino,'mode':f.lstat().st_mode,'links':f.lstat().st_nlink,'size':f.lstat().st_size} for f in root.rglob('*')]
  results.append({'case':case,'rc':p.returncode,'output':p.stdout,'metadata':metadata})
  print(p.stdout,p.stderr,flush=True)
  if os.environ.get('HP_START_EVIDENCE'):
   pathlib.Path(os.environ['HP_START_EVIDENCE']).write_text(json.dumps(results,indent=2))
  assert p.returncode==0,(case,p.returncode,metadata)
 contract=d/'contract'
 subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-DHP_GUARD_TEST','-I'+str(ROOT/'src'),str(ROOT/'src/renewable-guard.c'),str(ROOT/'tests/startup-owned-contract.c'),'-o',str(contract)],check=True)
 for case in ['foreign-replacement','active-reentry']:
  root=d/case;root.mkdir(mode=0o700)
  p=subprocess.run([str(contract),str(root),case],capture_output=True,text=True,timeout=8)
  print(p.stdout,p.stderr,flush=True);assert p.returncode==0,(case,p.returncode)
 print('PASS startup ownership matrix',len(results),'and 2 ownership contracts')
