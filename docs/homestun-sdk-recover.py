#!/usr/bin/env python3
import os,pathlib,subprocess,fcntl,json,shutil,hashlib
root=pathlib.Path('/home/eric/homestun-sdk-check')
sdk=root/'openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64'
lock=(root/'build.lock').open('w')
fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
owned=[]
for p in pathlib.Path('/proc').iterdir():
    if not p.name.isdigit(): continue
    try:
        cwd=(p/'cwd').resolve(); cmd=(p/'cmdline').read_bytes().replace(b'\0',b' ').decode(errors='replace')
        if (cwd==sdk or sdk in cwd.parents or root/'upstream' in cwd.parents) and (p/'comm').read_text().strip() in ['make','ninja','cc1','cc1plus']:
            owned.append({'pid':int(p.name),'cwd':str(cwd),'cmd':cmd})
    except (OSError,RuntimeError): pass
assert not owned, owned
(root/'recovery-process-preflight.json').write_text(json.dumps(owned))
source=pathlib.Path('/mnt/d/DevPortal/homelede/feeds-xiaoqingfeng-homestun/homestun')
snapshot=root/'source-feed/homestun'
shutil.rmtree(snapshot)
shutil.copytree(source,snapshot)
source_hashes={str(p.relative_to(source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in source.rglob('*') if p.is_file()}
assert source_hashes == {str(p.relative_to(snapshot)):hashlib.sha256(p.read_bytes()).hexdigest() for p in snapshot.rglob('*') if p.is_file()}
(root/'dependency-source-binding.json').write_text(json.dumps(source_hashes,indent=2))
env=os.environ.copy();env['PATH']=str(root/'local-tools/usr/bin')+':'+env['PATH']
for k in ['CPATH','LIBRARY_PATH','LD_LIBRARY_PATH','PKG_CONFIG_PATH','PKG_CONFIG_SYSROOT_DIR']:env.pop(k,None)
# Incremental resume: do not repeat targeted recovery cleans.
with (root/'build-recovery.log').open('a') as log:
    result=subprocess.run(['timeout','-k','15','360','make','-j4','package/feeds/homestunlocal/homestun/compile','V=s'],cwd=sdk,env=env,stdout=log,stderr=subprocess.STDOUT)
print('BUILD_EXIT',result.returncode,flush=True)
print('IPKS',[str(p) for p in sdk.glob('bin/**/homestun_*.ipk')],flush=True)
raise SystemExit(result.returncode)
