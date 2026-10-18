import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parent
class LegacySafety(unittest.TestCase):
 def test_no_native_upload_or_unsafe_deploy(self):
  for name in ('run-device-tcp-p3-controller.py','run-device-tcp-p4-lifecycle.py','run-device-tcp-p4-policy.py'):
   with self.subTest(name=name):
    s=(ROOT/name).read_text()
    self.assertNotIn('tcp-p3-controller-store.so',s)
    self.assertNotIn('root@127.0.0.1',s)
    self.assertIn('prepare_legacy_fixture',s)
    self.assertNotIn('fastcgi_temp_path',s)
    self.assertIn('deployment is forbidden',s)
 def test_all_entrypoints_scope_store_before_provider(self):
  for name in ('device-tcp-p3-controller-cli.lua','device-tcp-p3-installed-cli.lua','device-tcp-p4-installed-cli.lua','device-tcp-p4-policy-rpc.lua','device-tcp-p4-negative-cli.lua'):
   with self.subTest(name=name):
    s=(ROOT/name).read_text()
    self.assertIn("dofile('/tmp/homepublish-tcp-p3/device-legacy-lua-scope.lua')",s)
    self.assertNotIn('package.cpath=',s)
if __name__=='__main__':unittest.main()
