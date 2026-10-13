#!/usr/bin/env python3
"""Server-owned host manifest; never hashes attack inputs into authority."""
import hashlib, json, os, pathlib, shutil, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]; SRC=ROOT/'homepublish/src'
SDK=pathlib.Path('/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64/staging_dir/target-x86_64_musl/root-x86')
FILES=['lib/libc.so','usr/sbin/nginx','usr/lib/libpcre2-8.so.0.11.2','usr/lib/libssl.so.3','usr/lib/libcrypto.so.3','usr/lib/libz.so.1.3.1','lib/libgcc_s.so.1']
NAMES=['loader','nginx','libpcre2-8.so.0','libssl.so.3','libcrypto.so.3','libz.so.1','libgcc_s.so.1']
def manifest(d, source=SDK):
    # Authenticated by the host-test owner choosing known cached SDK, not by client.
    rows=[]
    for f,n in zip(FILES,NAMES):
        digest=hashlib.sha256((SDK/f).read_bytes()).hexdigest()
        rows.append('{'+json.dumps(f)+','+json.dumps(n)+','+json.dumps(digest)+'}')
    h=d/'trusted-profile.h';h.write_text('#define HP_TRUST_ROOT '+json.dumps(str(source))+'\nstatic const struct hp_trust_entry hp_trust_entries[]={'+','.join(rows)+'};\n')
    return h
with tempfile.TemporaryDirectory(prefix='provider-authority-',dir=os.environ.get('TMPDIR','/home/eric/homestun-sdk-check')) as td:
    d=pathlib.Path(td);source=d/'installation';source.mkdir()
    for f in FILES:
        p=source/f;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(SDK/f,p)
    header=manifest(d,source)
    for attack in ['exec-replaced']+[f+'-tamper' for f in FILES[0:1]+FILES[2:]]+[f+'-symlink' for f in FILES]:
        for f in FILES:
            p=source/f
            if p.exists() or p.is_symlink():p.unlink()
            shutil.copyfile(SDK/f,p)
        if attack=='exec-replaced':shutil.copyfile('/bin/true',source/'usr/sbin/nginx')
        elif attack.endswith('-symlink'):
            p=source/attack.removesuffix('-symlink');p.unlink();p.symlink_to(SDK/attack.removesuffix('-symlink'))
        else:
            p=source/attack.removesuffix('-tamper');data=bytearray(p.read_bytes());data[-1]^=1;p.write_bytes(data)
        vals={'HP_NGINX_LOADER':source/'lib/libc.so','HP_NGINX_EXEC':source/'usr/sbin/nginx','HP_NGINX_LIBS':str(source/'lib')+':'+str(source/'usr/lib'),'HP_NGINX_PREFIX':d,'HP_FOREIGN_SOCKET':d/'foreign.sock'}
        cmd=['cc','-std=c11','-Wall','-Wextra','-Werror','-DHP_GUARD_TEST','-I'+str(SRC),*[ '-D'+k+'='+json.dumps(str(v)) for k,v in vals.items()]]
        if (SRC/'trusted-nginx.c').exists():cmd+=['-DHP_TRUST_PROFILE_HEADER='+json.dumps(str(header)),str(SRC/'trusted-nginx.c')]
        subprocess.run(cmd+[str(SRC/'renewable-guard.c'),str(ROOT/'homepublish/tests/guardian-nginx-fixture.c'),'-o',str(d/'fixture'),'-l:libcrypto.so.3'],check=True)
        p=subprocess.run([str(d/'fixture'),'nginx','0'],capture_output=True,text=True,timeout=8,env={**os.environ,'HP_OWNED_RUNTIME':'1'})
        assert p.returncode==2 and 'rc=-1' in p.stdout,('untrusted executable accepted',p.returncode,p.stdout,p.stderr)
        assert not (d/'runtime').exists(),'native residue before fallback'
        print('PASS',attack,'rejected; runtime absent')
