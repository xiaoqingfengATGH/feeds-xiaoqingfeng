import pathlib, unittest
T=pathlib.Path(__file__).resolve().parent
class P1Safety(unittest.TestCase):
 def test_p1_no_native_dependency(self):
  for name in ('device-tcp-p1-provider.lua','device-tcp-p1-errors.lua','device-tcp-p1-backup.lua','test-product-provider.lua','test-product-review.lua','test-product.py','test-product-review.py'):
   s=(T/name).read_text()
   for token in ("require('homepublish_store')",'package.cpath','LUA_CPATH','product-store.c','LD_PRELOAD','fault.so'):
    self.assertNotIn(token,s,name)
if __name__=='__main__': unittest.main()
