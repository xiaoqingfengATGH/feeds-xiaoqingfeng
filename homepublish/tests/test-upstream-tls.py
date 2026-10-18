"""Optional upstream verification contracts (real Lua modules)."""
import pathlib
import unittest
from lupa.lua51 import LuaRuntime
SOURCE=pathlib.Path(__file__).resolve().parents[1]/'files/usr/share/homepublish'
class UpstreamTLS(unittest.TestCase):
 def test_optional_verification_and_safe_sni(self):
  l=LuaRuntime(unpack_returned_tuples=True);l.globals().source=SOURCE.as_posix()
  l.execute("package.path=source..'/?.lua;'..package.path")
  l.execute('''
local C=require('canonical-v2');local R=require('direct-renderer')
local c={schema_version=2,default_certificate_ref='acme:fixture',access_profile={listeners={{listener_id='lan',family='ipv4',network='lan',address='192.168.1.2',port=24443}}},publication_policy={mode='continuous',boot_restore=false},services={{service_id='web',name='Web',enabled=true,type='http_proxy',hostname='web.example.test',upstream_scheme='https',backend={addressFamily='ipv4',host='192.168.1.8',port=8443,allowed_ranges={'192.168.1.0/24'}},authentication_review={authentication='confirmed',management=false},upstream_tls={verify=false}}}}
local p={authorize_listener=function()return true end,authorize_backend=function()return true end,healthy=function()return true end,certificate_snapshot=function()return {certificate='/tmp/cert.pem',key='/tmp/key.pem'} end,mixed_ports={http=41002,https=41001,reject=41003}}
for _,typ in ipairs({'http_proxy','https_proxy'}) do
 local s=c.services[1];s.type=typ;s.certificate_mode=typ=='https_proxy' and 'inherit' or nil
 s.upstream_tls={verify=false};local v,e=C.validate(c);assert(v,e)
 local r,err=R.render(v,p);assert(r,err);assert(r.configuration:find('proxy_ssl_verify off;',1,true));assert(not r.configuration:find('proxy_ssl_name ',1,true))
 s.upstream_tls={verify=false,server_name='BACK.example.test'};v=assert(C.validate(c));assert(v.services[1].upstream_tls.server_name=='back.example.test');r=assert(R.render(v,p));assert(r.configuration:find('proxy_ssl_name back.example.test;',1,true))
 s.upstream_tls={server_name='back.example.test'};v=assert(C.validate(c));assert(v.services[1].upstream_tls.verify==true);r=assert(R.render(v,p));assert(r.configuration:find('proxy_ssl_verify on;',1,true))
 s.upstream_tls={verify=true};assert(not C.validate(c))
 for _,bad in ipairs({'x; proxy_ssl_verify off','x\\nserver {}','a/b','a b','$host','-x.test','x..test'}) do
  s.upstream_tls={verify=false,server_name=bad};assert(not C.validate(c),'unsafe SNI accepted')
  assert(not R.render(c,p),'renderer accepted unsafe SNI')
 end
 for _,bad in ipairs({'false',0,1}) do s.upstream_tls={verify=bad,server_name='back.example.test'};assert(not C.validate(c)) end
end
''')
if __name__=='__main__':unittest.main(verbosity=2)
