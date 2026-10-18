#!/usr/bin/env python3
"""Exclusive, bounded SDK LuCI build, no installation or services."""
import fcntl, pathlib, subprocess, shutil, hashlib, json, os
root=pathlib.Path('/home/eric/homestun-sdk-check')
sdk=root/'openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64'
repo=pathlib.Path('/mnt/d/DevPortal/homelede/feeds-xiaoqingfeng-homestun')
def run(args,cwd=sdk):
 subprocess.run(args,cwd=cwd,check=True)
with (root/'build.lock').open('a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 for p in pathlib.Path('/proc').iterdir():
  if not p.name.isdigit():continue
  try:
   comm=(p/'comm').read_text().strip();cwd=(p/'cwd').resolve()
  except (OSError,RuntimeError):continue
  if comm in ('make','gmake') and (cwd==sdk or sdk in cwd.parents):raise RuntimeError('active SDK make')
 luci=root/'upstream/luci-d88390be4ec9722cb427fee03368fc8c8582627d'
 if not luci.exists():
  run(['curl','-fL','--retry','2','--max-time','120','-o',str(root/'upstream/luci.tar.gz'),'https://codeload.github.com/openwrt/luci/tar.gz/d88390be4ec9722cb427fee03368fc8c8582627d'])
  run(['tar','-xf',str(root/'upstream/luci.tar.gz'),'-C',str(root/'upstream')])
 dest=root/'source-feed/luci-app-homestun'
 if dest.exists():shutil.rmtree(dest)
 shutil.copytree(repo/'luci-app-homestun',dest)
 # DrvFS source permissions are commonly 0777: normalize the Linux feed copy
 # before luci.mk cp -pR, without changing production source or Windows ACLs.
 for p in [dest,*dest.rglob('*')]:
  p.chmod(0o755 if p.is_dir() else 0o644)
 (dest/'root/usr/libexec/rpcd/homestun').chmod(0o755)
 conf=sdk/'feeds.conf';s=conf.read_text()
 if 'src-link luci ' not in s:conf.write_text(s+'src-link luci '+str(luci)+'\n')
 os.environ['PATH']=str(root/'local-tools/usr/bin')+':'+os.environ['PATH']
 for k in ['CPATH','LIBRARY_PATH','LD_LIBRARY_PATH','PKG_CONFIG_PATH','PKG_CONFIG_SYSROOT_DIR']:os.environ.pop(k,None)
 run(['./scripts/feeds','update','luci'])
 # Feed scan can cache a failed dump made before luci.mk was linked.
 cache=sdk/'feeds/homestunlocal.tmp'
 if cache.exists():shutil.rmtree(cache)
 run(['./scripts/feeds','update','homestunlocal'])
 run(['./scripts/feeds','install','luci-app-homestun'])
 with (sdk/'.config').open('a') as f:f.write('\nCONFIG_PACKAGE_luci-app-homestun=m\n')
 run(['make','defconfig'])
 # A mode-only refresh does not invalidate SDK build stamps; clean this LuCI
 # package so old DrvFS permissions cannot survive in cached prepared trees.
 run(['timeout','60','make','package/feeds/homestunlocal/luci-app-homestun/clean','V=s'])
 run(['timeout','300','make','-j2','package/feeds/homestunlocal/luci-app-homestun/compile','V=s'])
 artifacts=list((sdk/'bin').rglob('luci-app-homestun*.ipk'))
 assert len(artifacts)==1,artifacts
 ipk=artifacts[0];target=repo/'docs/artifacts'/ipk.name;shutil.copy2(ipk,target)
 binding=[]
 for f in sorted((repo/'luci-app-homestun').rglob('*')):
  if not f.is_file():continue
  rel=f.relative_to(repo/'luci-app-homestun');a=hashlib.sha256(f.read_bytes()).hexdigest();b=hashlib.sha256((dest/rel).read_bytes()).hexdigest();assert a==b
  binding.append({'file':str(rel),'sha256':a})
 evidence={'artifact':target.name,'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'luci_revision':luci.name,'source_binding':binding}
 (repo/'docs/homestun-luci-sdk.json').write_text(json.dumps(evidence,indent=2)+'\n')
 print(json.dumps(evidence,indent=2))
