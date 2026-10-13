#!/usr/bin/env python3
"""3013d16 review regressions: real Lua/native store/CLI and syscall faults."""
import os, pathlib, subprocess, tempfile, sys
ROOT=pathlib.Path(__file__).resolve().parents[2]
LUA=os.environ.get('LUA','/home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1')
DEV=pathlib.Path(os.environ.get('LUA_DEV','/home/eric/homestun-sdk-check/canonical-lua-dev/usr/include'))
BASE=pathlib.Path(os.environ.get('TEST_TMPDIR','/home/eric/homestun-sdk-check'))
def wire(v):
    if isinstance(v,bool): return 'b1' if v else 'b0'
    if isinstance(v,int): return f'i{v};'
    if isinstance(v,str): return f's{len(v.encode())}:{v}'
    if isinstance(v,list): v=dict(enumerate(v,1))
    if isinstance(v,dict): return f't{len(v)}:'+''.join(wire(k)+wire(x) for k,x in v.items())
    raise TypeError(v)
with tempfile.TemporaryDirectory(prefix='product-review.',dir=BASE) as tmp:
    t=pathlib.Path(tmp);store=t/'store'
    subprocess.run(['cc','-std=c99','-Wall','-Wextra','-Werror','-Wno-misleading-indentation','-fPIC','-shared',f'-I{DEV}/lua5.1',f'-I{DEV}/x86_64-linux-gnu',f'-DPRODUCT_ROOT="{store}"',str(ROOT/'homepublish/src/product-store.c'),'-o',str(t/'homepublish_store.so')],check=True)
    env=dict(os.environ,LUA_CPATH=f'{t}/?.so')
    cases=sys.argv[1:] or ['sparse','journal','policy','revision','fault']
    for case in cases:
        if (store/'state').exists(): (store/'state').unlink()
        if case!='fault':
            subprocess.run([LUA,str(ROOT/'homepublish/tests/test-product-review.lua'),str(ROOT),case],env=env,check=True)
            if case=='journal':
                cli=ROOT/'homepublish/files/usr/share/homepublish/product-cli.lua'
                # Final Lua fixture is nonnormalized but valid: CLI must canonicalize.
                result=subprocess.run([LUA,str(cli)],input='HP1'+wire({'action':'status'}),text=True,capture_output=True,env=env)
                assert result.returncode==0 and 'SENTINEL_ONLY' not in result.stdout
                assert 's6:backupb0' not in result.stdout and 'continuous' in result.stdout
                original=(store/'state').read_bytes()
                # Insert sentinel into the known one-service HP1 array.
                needle=b's8:servicest1:i1;'
                assert needle in original
                hidden=b's8:servicest4:i100;t1:s6:secrets13:SENTINEL_ONLYi4;t0:i2;t0:i1;'
                (store/'state').write_bytes(original.replace(needle,hidden))
                result=subprocess.run([LUA,str(cli)],input='HP1'+wire({'action':'status'}),text=True,capture_output=True,env=env)
                assert result.returncode!=0 and 'SENTINEL_ONLY' not in result.stdout
                assert (store/'state').read_bytes()==original.replace(needle,hidden)
                print('PASS CLI canonical export and sparse sentinel rejection without writes')
            continue
        subprocess.run(['cc','-Wall','-Wextra','-Werror','-fPIC','-shared',str(ROOT/'homepublish/tests/product-store-fault.c'),'-ldl','-o',str(t/'fault.so')],check=True)
        cli=ROOT/'homepublish/files/usr/share/homepublish/product-cli.lua'
        config={'schema_version':1,'services':[{'service_id':'nas','name':'NAS','hostname':'nas.example.test','backend':{'host':'192.168.1.10','port':8080,'allowed_ranges':['192.168.1.0/24']},'certificate_ref':'acme:nas','authentication_review':{'authentication':'confirmed','management':False}}],'access_profile':{'methods_allowed':['manual_ipv4'],'listeners':[{'family':'ipv4','address':'192.168.1.2','interface':'wan','zone':'wan','protocol':'tcp','internal_port':8443,'external_port':18443}]}}
        def call(action,revision=0,stage=None):
            request={'action':action}
            if action=='save': request.update(expected_revision=revision,config=config)
            e=dict(env)
            if stage: e.update(LD_PRELOAD=str(t/'fault.so'),HP_FAULT=stage)
            return subprocess.run([LUA,str(cli)],input='HP1'+wire(request),text=True,capture_output=True,env=e)
        assert call('save').returncode==0
        # Put close first: the review's actual close-after-release EIO must go RED.
        for stage in ['close','write','filefsync','rename','dirfsync']:
            baseline=(store/'state').read_bytes();status=call('status').stdout
            import re
            revision=int(re.search(r's14:saved_revisioni(\d+);',status)[1])
            failed=call('save',revision,stage)
            assert failed.returncode!=0, f'{stage}: incorrectly reported successful save'
            assert not (store/'candidate').exists(),f'{stage}: owned candidate leaked'
            current=call('status');assert current.returncode==0
            if stage=='dirfsync':
                assert 'commit durability unknown; read status' in failed.stderr
                assert f's14:saved_revisioni{revision+1};' in current.stdout
                revision+=1
            else:
                assert (store/'state').read_bytes()==baseline,f'{stage}: published before failure'
                assert current.stdout==status,f'{stage}: changed revision'
            assert call('save',revision).returncode==0,f'{stage}: recovery failed'
            assert f's14:saved_revisioni{revision+1};' in call('status').stdout
            print(f'PASS fault {stage}: error, publication boundary, candidate cleanup, readback, recovery')
        # Safe owned crash candidate recovered, foreign candidate never removed.
        (store/'candidate').write_bytes(b'abandoned');(store/'candidate').chmod(0o600)
        status=call('status').stdout;revision=int(re.search(r's14:saved_revisioni(\d+);',status)[1])
        assert call('save',revision).returncode==0
        foreign=t/'foreign';foreign.write_bytes(b'FOREIGN');(store/'candidate').symlink_to(foreign)
        assert call('save',revision+1).returncode!=0
        assert foreign.read_bytes()==b'FOREIGN' and (store/'candidate').is_symlink()
        print('PASS crash candidate recovery and foreign candidate preservation')
