#!/usr/bin/env python3
"""Local native ownership residual regression; real guard startup/Stop, no installs."""
import os, pathlib, subprocess, tempfile, json, time
ROOT=pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='hp-owned-',dir=os.environ.get('TMPDIR')) as td:
    base=pathlib.Path(td);exe=base/'probe'
    subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-DHP_GUARD_TEST','-I'+str(ROOT/'homepublish/src'),str(ROOT/'homepublish/src/renewable-guard.c'),str(ROOT/'homepublish/tests/owned-runtime-probe.c'),'-o',str(exe)],check=True)
    cases=('pinned','clean','readonly','hardlink','symlink','replacement','directory','foreign-temp','startup0','startup1','startup2','startup3','stop','invalid')
    runs=(*cases, *('stop' for _ in range(100)))
    if os.environ.get('HP_OWNED_DIAG_TEST'):
        source=(ROOT/'homepublish/tests/owned-runtime-probe.c').read_text().replace('assert(write(fd,"R",1)==1);close(fd);','close(fd);_exit(24);')
        fault=base/'fault.c';fault.write_text(source)
        subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-DHP_GUARD_TEST','-I'+str(ROOT/'homepublish/src'),str(ROOT/'homepublish/src/renewable-guard.c'),str(fault),'-o',str(exe)],check=True)
        runs=('stop',)
    for index, case in enumerate(runs):
        d=base/(case+'-'+str(index));d.mkdir(mode=0o700)
        begin=time.monotonic()
        result=subprocess.run([str(exe),str(d),case],capture_output=True,text=True,timeout=5)
        if result.returncode:
            # Persist before TemporaryDirectory fallback; metadata only, never file bytes.
            metadata=[]
            for q in [d,*d.rglob('*')]:
                try:
                    z=q.lstat();metadata.append({'name':str(q.relative_to(d)),'device':z.st_dev,'inode':z.st_ino,'mode':z.st_mode,'links':z.st_nlink,'size':z.st_size})
                except FileNotFoundError:pass
            evidence=pathlib.Path('/home/eric/homestun-sdk-check/owned-readiness-evidence')
            evidence.mkdir(exist_ok=True)
            report={'case':case,'index':index,'exit':result.returncode,'elapsed_monotonic':time.monotonic()-begin,'runtime_before_fallback':metadata,'diagnostics':result.stderr,'window_ms':600,'watchdog_ms':200,'cleanup_result':'separate: metadata observed before harness deletion'}
            target=evidence/(base.name+'-'+str(index)+'.json');target.write_text(json.dumps(report,indent=2))
            if os.environ.get('HP_OWNED_DIAG_TEST'):
                assert 'READINESS_DIAG' in result.stderr,'RED: readiness failure has no pre-fallback diagnostics'
                assert 'read_errno=' in result.stderr and 'monotonic_ms=' in result.stderr
                end=time.monotonic()+3
                while (d/'runtime').exists() and time.monotonic()<end:time.sleep(.01)
                assert not (d/'runtime').exists(),'diagnostics do not substitute for native cleanup'
                print('PASS injected readiness failure diagnostics and separate native cleanup',target)
                continue
            raise AssertionError('native probe failed; pre-fallback evidence '+str(target))
        print(result.stdout,end='')
    if not os.environ.get('HP_OWNED_DIAG_TEST'):print('PASS native-owned runtime 14 residual/startup/Stop cases + 100 Stop repeats; foreign deletion never inferred')
