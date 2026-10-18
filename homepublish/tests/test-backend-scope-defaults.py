"""Service backend scope defaults: no user-maintained CIDRs."""
import pathlib, unittest
from lupa.lua51 import LuaRuntime
SOURCE=pathlib.Path(__file__).resolve().parents[1]/'files/usr/share/homepublish'
class BackendScope(unittest.TestCase):
 def test_no_ranges_defaults_and_legacy_compatibility(self):
  l=LuaRuntime(unpack_returned_tuples=True);l.globals().source=SOURCE.as_posix()
  l.execute("package.path=source..'/?.lua;'..package.path")
  l.execute('''
local C=require('canonical-v2');local B=require('direct-backend')
local c={schema_version=2,access_profile={listeners={{listener_id='lan',family='ipv4',network='lan',address='192.168.1.2',port=24443}}},publication_policy={mode='continuous',boot_restore=false},services={{service_id='web',name='Web',enabled=true,type='http_proxy',hostname='web.example.test',upstream_scheme='http',backend={addressFamily='ipv4',host='192.168.2.8',port=8080},authentication_review={authentication='confirmed',management=false}}}}
local v,e=C.validate(c);assert(v,'no-CIDR service rejected: '..tostring(e));assert(v.services[1].backend.allowed_ranges==nil)
local b=c.services[1].backend
local p={authorize_backend=function()return true end,healthy=function()return true end}
for _,host in ipairs({'10.0.0.8','172.16.0.8','192.168.99.8','127.0.0.1'}) do b.addressFamily='ipv4';b.host=host;assert(C.validate(c));assert(B.select(b,p)) end
b.addressFamily='ipv6';b.host='fd99::8';assert(C.validate(c));assert(B.select(b,p))
for _,host in ipairs({'8.8.8.8','169.254.169.254','224.0.0.1','0.0.0.0','2001:4860::8888','fe80::1','ff02::1','::','::ffff:192.168.1.8'}) do b.addressFamily=host:find(':',1,true) and 'ipv6' or 'ipv4';b.host=host;assert(not C.validate(c),'unsafe saved '..host);assert(not B.select(b,p),'unsafe rendered '..host) end
b.addressFamily='hostname';b.host='nas.example.test'
p.resolve=function()return {addresses={'192.168.2.8','fd99::8'},ttl=60,observed_at=1,resolver='test'} end
assert(C.validate(c));assert(B.select(b,p))
p.resolve=function()return {addresses={'192.168.2.8','8.8.8.8'},ttl=60,observed_at=1,resolver='test'} end
assert(not B.select(b,p),'mixed DNS answer accepted')
b.addressFamily='ipv4';b.host='192.168.2.8';b.allowed_ranges={'192.168.1.0/24'}
assert(not C.validate(c),'legacy restriction no longer enforced');assert(not B.select(b,p))
b.host='192.168.1.8';assert(C.validate(c));assert(B.select(b,p))
b.allowed_ranges=nil;b.host='192.168.2.8';assert(C.validate(c));assert(B.select(b,p))
c.services[1].authentication_review=nil
local Probe=require('product-probe');local connects=0
local deps={snapshot=function()return {saved_revision=1,saved_config=c} end,bounded=function(_,_,fn)return fn() end,connect=function()connects=connects+1;return {ok=true} end}
assert(Probe.probe({service_id='web'},deps).ok and connects==1)
b.addressFamily='hostname';b.host='nas.example.test'
deps.resolve=function()return {ok=true,addresses={'192.168.99.8','fd99::8'}} end
assert(Probe.probe({service_id='web'},deps).ok and connects==2)
for _,bad in ipairs({'8.8.8.8','2001:4860::8888','169.254.169.254','fe80::1','ff02::1'}) do
 deps.resolve=function()return {ok=true,addresses={'192.168.99.8',bad}} end
 local result=Probe.probe({service_id='web'},deps);assert(result.phase=='scope' and connects==2,'probe connected to mixed unsafe answer')
end
b.addressFamily='ipv4';b.host='192.168.2.8'
assert(C.validate(c),'declarative review must be optional')
package.loaded['device-integrations']={}
package.loaded['product-procd-group']={new=function()return {} end}
local V=require('product-v2-runtime').new({available=function()return true end,authorize=function()return true end})
assert(V.runtime_plan(c),'missing review blocks runtime')
c.services[1].authentication_review={authentication='unconfirmed',management=true}
assert(V.runtime_plan(c),'legacy declarations block runtime')
''')
if __name__=='__main__':unittest.main(verbosity=2)
