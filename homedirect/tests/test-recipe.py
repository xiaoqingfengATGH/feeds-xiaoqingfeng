#!/usr/bin/env python3
"""Exercise actual recipe with a minimal macro harness, NOT an SDK/ipk build."""
import pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Recipe(unittest.TestCase):
 def test_compile_install_target_artifacts_only(self):
  with tempfile.TemporaryDirectory(prefix='homedirect-recipe-') as d:
   p=pathlib.Path(d);(p/'include').mkdir();(p/'build').mkdir()
   (p/'rules.mk').write_text(f'''INCLUDE_DIR:={p}/include
BUILD_DIR:={p}/build
TARGET_CC:=gcc
TARGET_CFLAGS:=-Os -static
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
	$(call Package/homedirect/install,$(TOPDIR)/root)
endef
''')
   subprocess.run(['make','-f',str(ROOT/'Makefile'),f'TOPDIR={p}','all'],cwd=ROOT,check=True)
   installed=p/'root'; helper=installed/'usr/libexec/homedirect-lease'
   self.assertTrue((installed/'usr/libexec/homedirect-publish').exists(),'publisher missing from package')
   self.assertTrue(helper.exists());self.assertEqual(helper.read_bytes()[:4],b'\x7fELF')
   self.assertTrue((installed/'etc/init.d/homedirect').stat().st_mode&0o100)
   self.assertEqual((installed/'etc/homedirect').stat().st_mode&0o777,0o700)
   self.assertFalse(any('tests' in str(x) or x.suffix=='.bin' for x in installed.rglob('*')))
   self.assertIn("option enabled '0'",(installed/'etc/config/homedirect').read_text())
if __name__=='__main__':unittest.main()
