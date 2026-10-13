#!/usr/bin/env python3
"""Exercise native persistence and fixed stdin CLI in an isolated compiled store."""
import os, pathlib, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
LUA=os.environ.get('LUA','/home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1')
DEV=pathlib.Path(os.environ.get('LUA_DEV','/home/eric/homestun-sdk-check/canonical-lua-dev/usr/include'))
BASE=pathlib.Path(os.environ.get('TEST_TMPDIR','/home/eric/homestun-sdk-check'))
SHARE=ROOT/'homepublish/files/usr/share/homepublish'
def wire(v):
    if isinstance(v,bool): return 'b1' if v else 'b0'
    if isinstance(v,int): return f'i{v};'
    if isinstance(v,str): return f's{len(v.encode())}:{v}'
    if isinstance(v,list): v=dict(enumerate(v,1))
    if isinstance(v,dict): return f't{len(v)}:'+''.join(wire(k)+wire(x) for k,x in v.items())
    raise TypeError(v)
with tempfile.TemporaryDirectory(prefix='canonical-suite.',dir=BASE) as tmp:
    t=pathlib.Path(tmp);store=t/'store'
    subprocess.run(['cc','-std=c99','-Wall','-Wextra','-Werror','-Wno-misleading-indentation','-fPIC','-shared',f'-I{DEV}/lua5.1',f'-I{DEV}/x86_64-linux-gnu',f'-DPRODUCT_ROOT="{store}"',str(ROOT/'homepublish/src/product-store.c'),'-o',str(t/'homepublish_store.so')],check=True)
    env=dict(os.environ,LUA_CPATH=f'{t}/?.so')
    subprocess.run([LUA,str(ROOT/'homepublish/tests/test-product-provider.lua'),str(ROOT)],env=env,check=True)
    (store/'state').unlink() # previous test deliberately leaves corrupt fixture
    cli=SHARE/'product-cli.lua'
    assert cli.is_file(), 'fixed configuration CLI missing'
    def call(request,ok=True):
        p=subprocess.run([LUA,str(cli)],input='HP1'+wire(request),text=True,capture_output=True,env=env)
        assert (p.returncode==0)==ok,(p.returncode,p.stdout,p.stderr)
        return p
    assert 'disabled' in call({'action':'status'}).stdout
    config={'schema_version':1,'services':[{'service_id':'nas','name':'NAS','hostname':'nas.example.test','backend':{'host':'192.168.1.10','port':8080,'allowed_ranges':['192.168.1.0/24']},'certificate_ref':'acme:nas','authentication_review':{'authentication':'confirmed','management':False}}],'access_profile':{'methods_allowed':['manual_ipv4'],'listeners':[{'family':'ipv4','address':'192.168.1.2','interface':'wan','zone':'wan','protocol':'tcp','internal_port':8443,'external_port':18443}]}}
    call({'action':'save','expected_revision':0,'config':config})
    saved=call({'action':'status'}).stdout
    assert 'nas.example.test' in saved and 'active_revision' not in saved and 'unsupported' in saved
    for field in ['path','desired_state','approval','active_revision']:
        call({'action':'save','expected_revision':1,'config':config,field:'forbidden'},False)
        assert call({'action':'status'}).stdout==saved
    call({'action':'save','expected_revision':0,'config':config},False)
    assert call({'action':'status'}).stdout==saved
    call({'action':'stop'})
    config['services'][0]['name']='pending'
    call({'action':'save','expected_revision':1,'config':config})
    status=call({'action':'status'}).stdout
    assert 'manual_stop_latchb1' in status and 'pending' in status and 'active_revision' not in status
    assert 'unsupported' in call({'action':'start'},False).stderr
    assert 'unsupported' in call({'action':'apply'},False).stderr
    p=subprocess.run([LUA,str(cli),'--path=/etc/config/firewall'],input='HP1'+wire({'action':'stop'}),text=True,capture_output=True,env=env)
    assert p.returncode!=0 and call({'action':'status'}).stdout==status
    call({'action':'status','path':'/etc/config/firewall'},False)
    original=(store/'state').read_bytes()
    (store/'state').unlink(); foreign=t/'foreign';foreign.write_bytes(original);(store/'state').symlink_to(foreign)
    call({'action':'status'},False);assert foreign.read_bytes()==original
    (store/'state').unlink();(store/'state').write_bytes(original);(store/'state').chmod(0o644)
    call({'action':'status'},False);(store/'state').chmod(0o600)
    import fcntl
    with open(store/'lock','r+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        assert 'busy' in call({'action':'stop'},False).stderr
    assert (store/'state').read_bytes()==original
    for bad in ['return os.execute("touch BAD")','HP1t1:s6:action','HP1t2:s6:actions6:statuss6:actions4:stop','HP1s999999999999999999999:']:
        p=subprocess.run([LUA,str(cli)],input=bad,text=True,capture_output=True,env=env)
        assert p.returncode!=0 and (store/'state').read_bytes()==original
    print('PASS CLI cross-process persistence, unsupported exposure, injection, symlink/mode/lock safety')
