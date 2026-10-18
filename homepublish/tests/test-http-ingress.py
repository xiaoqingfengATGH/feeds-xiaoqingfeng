"""HTTP shared ingress regression tests against production Lua modules."""
import pathlib
import unittest
from lupa.lua51 import LuaRuntime
SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'files/usr/share/homepublish'
SETUP = '''
package.path=source..'/?.lua;'..package.path
function service(kind,id,host)
 local s={service_id=id,name=id,enabled=true,type=kind,
 backend={addressFamily='ipv4',host='192.168.1.10',port=8080,allowed_ranges={'192.168.1.0/24'}},
 authentication_review={authentication='confirmed',management=false}}
 if kind=='http_proxy' or kind=='https_proxy' then s.hostname=host or 'web.example';s.upstream_scheme='http' end
 if kind=='https_proxy' then s.certificate_mode='inherit' end
 if kind=='tls_passthrough' then s.hostname=host or 'tls.example' end
 if kind=='tcp_forward' then s.listen_port=25000 end
 return s
end
function config(services)
 return {schema_version=2,services=services,access_profile={listeners={{listener_id='public',family='ipv4',network='lan',address='192.168.1.1',port=24443}}}}
end
local C=require('canonical-v2')
function valid(c)local r,e=C.validate(c);assert(r,e);return r end
providers={mixed_ports={https=26000,reject=26001,http=26002},authorize_listener=function()return true end,
 authorize_backend=function()return true end,healthy=function()return true end,
 certificate_snapshot=function()return {certificate='/tmp/cert.pem',key='/tmp/key.pem'}end}
function rendered(c)local r,e=require('direct-renderer').render(c,providers);assert(r,e);return r end
'''
class HTTPIngressTests(unittest.TestCase):
    def run_lua(self, body):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.globals().source=SOURCE.as_posix()
        lua.execute(SETUP+body)

    def test_canonical_http_without_certificate_and_verified_upstream(self):
        self.run_lua('''
local c=config({service('http_proxy','http')})
assert(valid(c).services[1].hostname=='web.example')
c.services[1].upstream_scheme='https'
assert(not C.validate(c),'unverified upstream accepted')
c.services[1].upstream_tls={verify=true,server_name='backend.example'}
assert(valid(c).services[1].upstream_tls.verify)
c.services[1].upstream_tls.verify=false;assert(valid(c).services[1].upstream_tls.verify==false)
c.services[1].upstream_scheme='http';c.services[1].upstream_tls=nil
c.services[1].certificate_mode='inherit';assert(not C.validate(c),'HTTP certificate field accepted')
c.services[1].certificate_mode=nil;c.services[1].hostname='bad;host';assert(not C.validate(c))
''')
    def test_hostname_namespaces_and_http_lowering(self):
        self.run_lua('''
local c=config({service('http_proxy','http'),service('https_proxy','https')});c.default_certificate_ref='import:test'
valid(c)
local p,e=require('tcp-route-plan').compile(c);assert(p,e)
assert(#p.http_services==1 and #p.services==1)
assert(p.http_services[1].certificate_ref==nil)
c.services[2]=service('tls_passthrough','tls','web.example');valid(c)
c.services[3]=service('https_proxy','https');assert(not C.validate(c))
c.services[3]=service('http_proxy','http2','WEB.EXAMPLE');local r,e,d=C.validate(c)
assert(not r and d.error_code=='DOMAIN_CONFLICT')
local only=assert(require('tcp-route-plan').compile(config({service('http_proxy','http')})))
assert(#only.services==0 and #only.http_services==1)
''')

    def test_http_only_and_all_protocols_use_shared_ingress(self):
        self.run_lua('''
for _,mixed in ipairs({false,true}) do
 local services={service('http_proxy','http')}
 if mixed then
  services[2]=service('https_proxy','https');services[3]=service('tls_passthrough','tls')
  services[4]=service('ssh','ssh');services[5]=service('tcp_forward','tcp')
 end
 local c=config(services);if mixed then c.default_certificate_ref='import:test' end
 local certs=0;providers.certificate_snapshot=function()certs=certs+1;return {certificate='/tmp/cert.pem',key='/tmp/key.pem'}end
 local r=rendered(c);local n=r.configuration;local h=r.sslh_configuration
 assert(h and h:find('name: "http"; host: "127.0.0.1"; port: "26002"; proxyprotocol: 1;',1,true))
 assert(h:find('name: "anyprot"; host: "127.0.0.1"; port: "26001";',1,true))
 assert(n:find('listen 127.0.0.1:26002 proxy_protocol default_server; return 444;',1,true))
 assert(n:find('listen 127.0.0.1:26002 proxy_protocol; server_name web.example;',1,true))
 assert(not n:find('listen 127.0.0.1:26002 ssl',1,true))
 assert(n:find('map "$http_host" $homepublish_http_host_1 { default 0;',1,true),'strict raw Host guard missing')
 assert(n:find('"~*^web[.]example(:([1-9][0-9]{0,3}|',1,true),'NAT-compatible authority port guard missing')
 assert(n:find('real_ip_header proxy_protocol;',1,true))
 assert(n:find('proxy_set_header X-Forwarded-For $remote_addr;',1,true))
 assert(n:find('if ($request !~ "^[^ ]+ /") { return 444; }',1,true))
 assert(certs==(mixed and 1 or 0))
 local _,contexts=n:gsub('http {','');assert(contexts==1)
 if mixed then
  assert(h:find('name: "ssh";',1,true));assert(h:find('sni_hostnames: [ "tls.example" ];',1,true))
  assert(n:find('listen 192.168.1.1:25000;',1,true))
  assert(n:find('listen 127.0.0.1:26000 ssl proxy_protocol',1,true))
 end
end
local c=config({service('http_proxy','http')});c.services[1].upstream_scheme='https'
c.services[1].upstream_tls={verify=true,server_name='backend.example'}
local n=rendered(c).configuration
assert(n:find('proxy_ssl_verify on;',1,true) and n:find('proxy_ssl_name backend.example;',1,true))
providers.mixed_ports.http=26001;assert(not require('direct-renderer').render(c,providers),'internal collision accepted')
''')

    def test_http_coexists_with_each_route_family_and_keeps_authorization(self):
        self.run_lua('''
for _,kind in ipairs({'http_proxy','https_proxy','tls_passthrough','ssh','tcp_forward'}) do
 for _,family in ipairs({'ipv4','ipv6'}) do
  local c=config({service('http_proxy','http'),service(kind,'other','other.example')})
  if kind=='https_proxy' then c.default_certificate_ref='import:test' end
  if family=='ipv6' then c.access_profile.listeners[1].family='ipv6';c.access_profile.listeners[1].address='fd00::1' end
  local r=rendered(c);assert(r.sslh_configuration)
  assert(r.configuration:find('server_name web.example;',1,true))
  assert(r.configuration:find('server_name other.example;',1,true) or kind~='http_proxy')
 end
end
local c=config({service('http_proxy','http')})
providers.authorize_listener=function()return false end
assert(not require('direct-renderer').render(c,providers),'external approval bypassed')
providers.authorize_listener=function()return true end
providers.authorize_backend=function()return false end
assert(not require('direct-renderer').render(c,providers),'backend approval bypassed')
''')

if __name__ == '__main__': unittest.main()
