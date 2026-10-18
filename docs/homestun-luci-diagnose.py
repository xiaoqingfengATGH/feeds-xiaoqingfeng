import pathlib,subprocess,fcntl
root=pathlib.Path('/home/eric/homestun-sdk-check'); sdk=root/'openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64'; repo=pathlib.Path('/mnt/d/DevPortal/homelede/feeds-xiaoqingfeng-homestun')
with (root/'build.lock').open('a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 with (repo/'docs/homestun-luci-discovery-diagnostic.txt').open('w') as out:
  def show(path):
   p=sdk/path;out.write('\n### '+str(p)+'\n');out.write(p.read_text() if p.exists() else 'MISSING\n');out.flush()
  for path in ['feeds.conf','include/scan.mk','include/scan.awk','feeds/homestunlocal.index','feeds/homestunlocal.tmp/info/.files-packageinfo.mk','feeds/homestunlocal.tmp/info/.packageinfo-luci-app-homestun','feeds/homestunlocal/luci-app-homestun/Makefile'] :show(path)
  for p in (sdk/'feeds/homestunlocal.tmp').rglob('*'):
   out.write(str(p.relative_to(sdk))+'\n')
  out.flush()
  subprocess.run(['bash','-lc','./scripts/feeds update -i homestunlocal; make -f include/scan.mk SCAN_TARGET=packageinfo SCAN_DIR=feeds/homestunlocal SCAN_NAME=package SCAN_DEPTH=5 V=s'],cwd=sdk,stdout=out,stderr=subprocess.STDOUT)
