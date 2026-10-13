#!/usr/bin/env python3
"""Exercise actual recipe with a minimal macro harness, NOT an SDK/ipk build."""
import os, pathlib, subprocess, tempfile, unittest
DEV=pathlib.Path(os.environ.get('LUA_DEV','/home/eric/homestun-sdk-check/canonical-lua-dev/usr/include'))
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Recipe(unittest.TestCase):
 def test_compile_install_target_artifacts_only(self):
  with tempfile.TemporaryDirectory(prefix='homepublish-recipe-') as d:
   p=pathlib.Path(d);(p/'include').mkdir();(p/'build').mkdir()
   (p/'rules.mk').write_text(f'''INCLUDE_DIR:={p}/include
BUILD_DIR:={p}/build
TARGET_CC:=gcc
TARGET_CFLAGS:=-Os
TARGET_CPPFLAGS:=-I{DEV}/lua5.1 -I{DEV}/x86_64-linux-gnu
TARGET_LDFLAGS:=-L{p}
STAGING_DIR:={p}/staging
CP:=cp -fpR
INSTALL_DIR:=mkdir -p
INSTALL_BIN:=install -m0755
INSTALL_DATA:=install -m0644
INSTALL_CONF:=install -m0600
''')
   (p/'include/package.mk').write_text('''define BuildPackage
.PHONY: all
all:
	$(Build/Prepare)
	$(Build/Compile)
	$(call Package/homepublish/install,$(TOPDIR)/root)
endef
''')
   # Build a host PIC Lua library from the local cached source, never install it.
   archive=pathlib.Path(os.environ.get('LUA_SOURCE_TARBALL','/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64/dl/lua-5.1.5.tar.gz'))
   import tarfile
   with tarfile.open(archive) as tar: tar.extractall(p,filter='data')
   sources=[str(x) for x in (p/'lua-5.1.5/src').glob('*.c') if x.name not in ('lua.c','luac.c','print.c')]
   subprocess.run(['gcc','-fPIC','-shared','-O2','-o',str(p/'liblua.so'),*sources,'-lm','-ldl'],check=True)
   subprocess.run(['make','-f',str(ROOT/'Makefile'),f'TOPDIR={p}','all'],cwd=ROOT,check=True)
   module=p/'root/usr/lib/lua/homepublish_store.so'
   self.assertTrue(module.is_file(),'canonical native store missing from package')
   self.assertEqual(module.read_bytes(),(p/'build/homepublish-0.1.0/homepublish_store.so').read_bytes())
   self.assertIn('+liblua',(ROOT/'Makefile').read_text())
   subprocess.run([os.environ.get('LUA','/home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1'),'-e',"assert(type(require('homepublish_store').transaction)=='function')"],env=dict(os.environ,LUA_CPATH=f'{module.parent}/?.so',LD_LIBRARY_PATH=str(p)),check=True)
   self.assertTrue((p/'root/usr/share/homepublish/product-cli.lua').is_file())
   installed=p/'root'; helper=installed/'usr/libexec/homepublish-lease'
   self.assertTrue((installed/'usr/libexec/homepublish-publish').exists(),'publisher missing from package')
   self.assertTrue(helper.exists());self.assertEqual(helper.read_bytes()[:4],b'\x7fELF')
   self.assertTrue((installed/'etc/init.d/homepublish').stat().st_mode&0o100)
   self.assertEqual((installed/'etc/homepublish').stat().st_mode&0o777,0o700)
   self.assertFalse(any('tests' in str(x) or x.suffix=='.bin' for x in installed.rglob('*')))
   self.assertIn("option enabled '0'",(installed/'etc/config/homepublish').read_text())
if __name__=='__main__':unittest.main()
