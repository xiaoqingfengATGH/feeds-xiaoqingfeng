import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Package(unittest.TestCase):
 def test_target_build_and_disabled_defaults(self):
  make=ROOT/'Makefile'
  self.assertTrue(make.exists(), 'missing OpenWrt package')
  text=make.read_text()
  self.assertIn('$(TARGET_CC)',text)
  self.assertIn('$(PKG_BUILD_DIR)/homedirect-lease',text)
  self.assertNotIn('tests/',text)
  defaults=(ROOT/'files/etc/config/homedirect').read_text()
  self.assertIn("option enabled '0'",defaults)
  self.assertIn("option exposure_approved '0'",defaults)
  self.assertIn("option publication_enabled '0'",defaults)
  self.assertIn("option router_token_file '/etc/homedirect/router.token'",defaults)
  options=[line.split()[1] for line in defaults.splitlines() if line.strip().startswith('option ')]
  self.assertNotIn('router_token',options)
  self.assertNotIn('token',options)
  self.assertIn('+curl +ca-bundle',text)
if __name__=='__main__': unittest.main()
