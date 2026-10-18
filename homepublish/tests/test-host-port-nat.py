"""Real renderer Host guard permits NAT-remapped ports, not foreign authorities."""
import pathlib
import re
import unittest
from lupa.lua51 import LuaRuntime
SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'files/usr/share/homepublish'

class HostPortNAT(unittest.TestCase):
 def test_same_hostname_with_external_port_for_http_and_https(self):
  lua = LuaRuntime(unpack_returned_tuples=True)
  lua.globals().source = SOURCE.as_posix()
  lua.execute("package.path=source..'/?.lua;'..package.path")
  render = lua.eval('''function(plain)
   local plan={access_profile={listeners={{family='ipv4',address='127.0.0.1',internal_port=41001,public_port=8443,protocol='tcp',interface='lo',zone='lan'}}},services={{hostname='home.iwonderful.top',certificate_ref='acme:fixture',upstream_scheme='https',upstream_tls={verify=false},backend={addressFamily='ipv4',host='192.168.1.254',port=443,allowed_ranges={'192.168.1.0/24'}}}}}
   local p={authorize_listener=function()return true end,authorize_backend=function()return true end,healthy=function()return true end,certificate_snapshot=function()return {certificate='/tmp/cert.pem',key='/tmp/key.pem'} end}
   local R=require('direct-renderer');local result,e
   if plain then result,e=R.render_http(plan,p) else result,e=R.render(plan,p) end
   assert(result,e);return result.configuration
  end''')
  for plain in [False, True]:
   config = render(plain)
   source, body = re.search(r'map "([^"]+)" \$homepublish_(?:http_)?host_1 \{(.*?)\n}', config, re.S).groups()
   patterns = re.findall(r'"~\*(.*?)" 1;', body)
   def accepts(host):
    value = source.replace('$http_host', host).replace('$server_port', '41001')
    return any(re.fullmatch(pattern, value, re.I) for pattern in patterns)
   for host in ['home.iwonderful.top:64443','home.iwonderful.top:8443','home.iwonderful.top','HOME.IWONDERFUL.TOP:443','home.iwonderful.top:1','home.iwonderful.top:65535']:
    self.assertTrue(accepts(host), (plain, host, config))
   for host in ['', 'evil.test:64443','home.iwonderful.top.evil:64443','homeXiwonderfulXtop:64443','home.iwonderful.top:0','home.iwonderful.top:65536','home.iwonderful.top:99999','home.iwonderful.top:0443','home.iwonderful.top:','home.iwonderful.top:443:1','home.iwonderful.top:abc','home.iwonderful.top.','home.iwonderful.top@evil.test:443']:
    self.assertFalse(accepts(host), (plain, host))
   self.assertIn('if ($host != "home.iwonderful.top") { return 444; }', config)
   if not plain:
    self.assertIn('if ($ssl_server_name !~* "^home[.]iwonderful[.]top$") { return 444; }', config)

if __name__ == '__main__': unittest.main(verbosity=2)
