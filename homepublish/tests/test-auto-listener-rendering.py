"""Exercise real renderers with the installed provider's listener authorization."""
import pathlib
import unittest
from lupa.lua51 import LuaRuntime

SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'files/usr/share/homepublish'

class AutoListenerRenderingTests(unittest.TestCase):
    def test_listener_parser_keeps_wildcards_out_of_general_addresses(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().source = SOURCE.as_posix()
        lua.execute('''
package.path=source..'/?.lua;'..package.path
local A=require('direct-address')
for _,case in ipairs({{'ipv4','0.0.0.0',2},{'ipv6','::',8}}) do
 local family,address,width=unpack(case)
 local words,f=A.parse_listener({family=family,address=address,bind_mode='auto'})
 assert(f==family and #words==width)
 for _,v in ipairs(words) do assert(v==0) end
 assert(not pcall(A.parse,address),'general parser accepted wildcard')
 assert(not pcall(A.in_ranges,address,{'192.168.0.0/16'}),'range parser accepted wildcard')
 for _,mode in ipairs({'address','',false}) do
  assert(not pcall(A.parse_listener,{family=family,address=address,bind_mode=mode}))
 end
 assert(not pcall(A.parse_listener,{family=family,address=address}))
 assert(not pcall(A.parse_listener,{family=family=='ipv4' and 'ipv6' or 'ipv4',address=address,bind_mode='auto'}))
end
for _,address in ipairs({'192.168.1.1','fd00::1','0:0:0:0:0:0:0:0','0.0.0.00','::;','*','fe80::1','224.0.0.1'}) do
 assert(not pcall(A.parse_listener,{family=address:find(':',1,true) and 'ipv6' or 'ipv4',address=address,bind_mode='auto'}))
end
for _,case in ipairs({{'ipv4','192.168.1.1'},{'ipv6','fd00::1'}}) do
 for _,mode in ipairs({'address',false}) do
  local _,f=A.parse_listener({family=case[1],address=case[2],bind_mode=mode or nil})
  assert(f==case[1])
 end
end
''')

    def test_production_authorization_survives_route_lowering(self):
        for kind in ('https_proxy', 'tcp_forward', 'tls_passthrough', 'ssh', 'mixed'):
            for family in ('ipv4', 'ipv6'):
                with self.subTest(kind=kind, family=family):
                    lua = LuaRuntime(unpack_returned_tuples=True)
                    lua.globals().source = SOURCE.as_posix()
                    lua.globals().kind = kind
                    lua.globals().family = family
                    lua.execute('''
package.path=source..'/?.lua;'..package.path
-- Capture the actual fixed production callbacks without starting components.
local providers
package.loaded['product-v2-runtime']={new=function(o)providers=o;return {}end}
local execute=os.execute;os.execute=function()return 0 end
require('product-system-provider');os.execute=execute
local N=require('network-inventory')
local inventory=assert(N.normalize({interface={}},{{name='wan'}}))
N.collect=function()return inventory end
local address=family=='ipv4' and '0.0.0.0' or '::'
local c={schema_version=2,access_profile={listeners={{listener_id='public',family=family,
 bind_mode='auto',network='',address=address,port=24443}},
 firewall={ipv4_zones=family=='ipv4' and {'wan'} or {},ipv6_zones=family=='ipv6' and {'wan'} or {}}},
 default_certificate_ref='import:test',services={}}
local function service(t,i)
 local s={service_id='svc'..i,name='test',type=t,enabled=true,
 backend={addressFamily='ipv4',host='192.168.1.10',port=8080,allowed_ranges={'192.168.1.0/24'}},
 authentication_review={authentication='confirmed',management=false}}
 if t=='tcp_forward' then s.listen_port=25000
 elseif t=='https_proxy' then s.hostname='web.example';s.certificate_mode='inherit';s.upstream_scheme='http'
 elseif t=='tls_passthrough' then s.hostname='tls.example' end
 return s
end
if kind=='mixed' then
 for i,t in ipairs({'https_proxy','tcp_forward','tls_passthrough','ssh'})do c.services[i]=service(t,i)end
else c.services[1]=service(kind,1) end
providers.mixed_ports={https=26000,reject=26001}
providers.healthy=function()return true end
providers.certificate_snapshot=function()return {certificate='/tmp/cert.pem',key='/tmp/key.pem'}end
assert(providers.authorize_listener(c.access_profile.listeners[1]))
local lowered=assert(require('tcp-route-plan').compile(c))
assert(lowered.access_profile.listeners[1].bind_mode=='auto','route lowering lost bind mode')
assert(providers.authorize_listener(lowered.access_profile.listeners[1]),'route lowering lost listener authorization')
local authorize=providers.authorize_listener
local authorized_ports={}
providers.authorize_listener=function(l)
 assert(l.bind_mode=='auto' and l.address==address and l.family==family,'listener metadata lost')
 authorized_ports[l.internal_port]=true
 return authorize(l)
end
local r,e=require('direct-renderer').render(c,providers)
assert(r,e)
local text=r.configuration..(r.sslh_configuration or '')
assert(text:find(address,1,true),'wildcard listener disappeared')
local host=family=='ipv6' and '['..address..']' or address
if kind=='tcp_forward' or kind=='mixed' then
 assert(authorized_ports[25000],'independent TCP authorization lost')
 assert(r.configuration:find('listen '..host..':25000'..(family=='ipv6' and ' ipv6only=on' or '')..';',1,true),'TCP socket missing')
end
if kind~='tcp_forward' then assert(authorized_ports[24443],'shared authorization lost') end
if kind=='https_proxy' then
 assert(r.configuration:find('listen '..host..':24443 ssl'..(family=='ipv6' and ' ipv6only=on' or '')..' default_server;',1,true),'HTTPS socket missing')
elseif kind~='tcp_forward' then
 assert(r.sslh_configuration:find('{ host: "'..address..'"; port: "24443"; }',1,true),'sslh socket missing')
end
providers.authorize_listener=function()return false end
assert(not require('direct-renderer').render(c,providers),'automatic authorization bypassed')
providers.authorize_listener=authorize
-- The same production authorization must still deny unavailable fixed bindings.
c.access_profile.listeners[1].bind_mode='address'
c.access_profile.listeners[1].network='missing'
c.access_profile.listeners[1].address=family=='ipv4' and '192.168.1.1' or 'fd00::1'
local rejected=require('direct-renderer').render(c,providers)
assert(not rejected,'fixed address authorization was bypassed')
''')

if __name__ == '__main__':
    unittest.main()
