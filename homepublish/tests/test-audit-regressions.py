#!/usr/bin/env python3
"""Audit regressions: execute actual parser and actual observer failure paths."""
import ast, pathlib, os, subprocess, tempfile, json
ROOT=pathlib.Path(__file__).resolve().parent

def parser_red():
    from dependency_maps import validate_maps,parse_maps
    raw=sorted(pathlib.Path('/home/eric/homestun-sdk-check/openssl-engine-regression').glob('run-*/green/raw.maps'))[-1].read_text()
    rows=parse_maps(raw)
    expected={r['path'] for r in rows if r['inode'] and '/zoneinfo/' not in r['path']}
    contracts={r['path'] for r in rows if '/zoneinfo/' in r['path']}
    def inspect(r):return {'device':r['device'],'inode':r['inode'],'elf':r['path'] not in contracts,'verified':r['path'] in expected or r['path'] in contracts}
    validate_maps(raw,expected,inspect,contracts)
    for path,perms in [('/foreign/unmanifested.so','r-xp'),('/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64/staging_dir/target-x86_64_musl/root-x86/usr/lib/unmanifested.so','r-xp'),('/memfd:unknown (deleted)','r-xp'),('/foreign/readonly ELF.so','r--p'),('/foreign/data','r--p')]:
        extra='70000000-70001000 '+perms+' 00000000 08:01 999 '+path+'\n'
        try:validate_maps(raw+'\n'+extra,expected,inspect,contracts)
        except AssertionError:pass
        else:raise AssertionError('unknown accepted: '+path)
    missing=next(iter(expected))
    try:validate_maps('\n'.join(r['raw'] for r in rows if r['path']!=missing),expected,inspect,contracts)
    except AssertionError:pass
    else:raise AssertionError('missing expected accepted')
    r=parse_maps('70000000-70001000 r--p 00000000 00:01 999 /memfd:space name (deleted)')[0]
    assert r['path']=='/memfd:space name (deleted)' and r['inode']==999
    print('PASS complete maps negative matrix')

def observer_fault(kind):
    with tempfile.TemporaryDirectory(prefix='observer-fault-',dir='/home/eric/homestun-sdk-check') as td:
        d=pathlib.Path(td); probe=d/'probe.py'
        text=(ROOT/'test-openssl-engine.py').read_text()
        text=text.replace("SRC = pathlib.Path(__file__).resolve().parents[1] / 'src'",'SRC = pathlib.Path('+repr(str(ROOT.parent/'src'))+')')
        # Compiler injection uses the actual observer entry point, not a mock.
        cc_env={'HP_OBSERVER_CC':'/bin/false'} if kind=='compiler' else {}
        probe.write_text(text)
        foreign=d/'foreign sentinel';foreign.write_text('preserve');foreign_inode=foreign.stat().st_ino
        env={**os.environ,**cc_env,'HP_OPENSSL_ENGINE_EVIDENCE':str(d/'evidence'),'HP_OBSERVER_FAULT':kind}
        p=subprocess.run(['python3',str(probe)],env=env,capture_output=True,text=True,timeout=100)
        assert p.returncode!=0,(kind,p.stdout)
        runs=list((d/'evidence').glob('run-*'));assert len(runs)==1
        base=runs[0]
        assert not list(base.glob('*/owned')), 'RED: pre-trace owned directory leaked'
        observations=list(base.glob('*/observation.json'))
        assert observations,'RED: failed probe has no pre-cleanup metadata'
        out=json.loads(observations[0].read_text())
        assert out['failure'] and out['cleanup_owner']=='observer probe only; no guardians'
        assert not (base/'key.pem').exists() and not (base/'cert.pem').exists()
        assert base.exists(),'evidence must be retained'
        before=json.loads(next(base.glob('*/before-fallback.json')).read_text())
        assert before['failure'] and (before['pid'] is None if kind=='compiler' else before['pid'] is not None)
        if before['pid'] is not None:assert not pathlib.Path('/proc',str(before['pid'])).exists()
        assert foreign.read_text()=='preserve' and foreign.stat().st_ino==foreign_inode
        retained=pathlib.Path('/home/eric/homestun-sdk-check/audit-fault-evidence')/base.name
        retained.mkdir(parents=True)
        for q in base.glob('*/**/*'):
            if q.is_file() and q.name in ('observation.json','before-fallback.json','actual-open.json','raw.maps'):
                target=retained/q.relative_to(base);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(q.read_bytes())
        print('PASS observer fault',kind)

if __name__=='__main__':
    import sys
    if sys.argv[1]=='maps':parser_red()
    else:observer_fault(sys.argv[1])
