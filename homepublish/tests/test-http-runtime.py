"""HTTP runtime contracts; optional diagnostics never gate startup."""
import pathlib
import unittest
from lupa.lua51 import LuaRuntime
SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'files/usr/share/homepublish'

class HTTPRuntimeTests(unittest.TestCase):
    def lua(self):
        l = LuaRuntime(unpack_returned_tuples=True)
        l.globals().source = SOURCE.as_posix()
        l.execute("package.path=source..'/?.lua;'..package.path")
        l.execute('''
function config()
 return {schema_version=2,access_profile={listeners={{listener_id='lan4',family='ipv4',network='lan',address='192.168.1.2',port=24443}},firewall={ipv4_zones={'wan'},ipv6_zones={}}},publication_policy={mode='continuous',boot_restore=false},services={{service_id='plain',name='Plain',enabled=true,type='http_proxy',hostname='plain.example.test',upstream_scheme='http',backend={addressFamily='ipv4',host='192.168.1.8',port=8080,allowed_ranges={'192.168.1.0/24'}},authentication_review={authentication='confirmed',management=false}}}}
end
''')
        return l

    def test_http_preflight_uses_shared_entry_and_trusted_proxy_policy(self):
        self.lua().execute('''
local load=dofile
dofile=function(path)
 if path==source..'/network-inventory.lua' then return {collect=function()return {summary='fixture'} end,resolve=function(l)return l end} end
 return load(path)
end
local p=load(source..'/preflight.lua').check(config(),1)
assert(p.source_address_policy.http_proxy=='trusted_internal_proxy_only','HTTP must advertise trusted proxy source policy')
assert(#p.endpoints==1 and p.endpoints[1].port==24443,'HTTP uses only the shared entry')
''')

    def test_status_advertises_http_service_capability(self):
        self.lua().execute('''
local load=dofile
-- Read-only absent-store fixture: execute the real provider/status serialization.
dofile=function(path)
 if path==source..'/product-store.lua' then return {transaction=function(fn)local _,result=fn(nil);return result end} end
 return load(path)
end
local out=load(source..'/product-provider.lua').handle({action='status'})
local seen={};for _,t in ipairs(out.capabilities.service_types or {}) do seen[t]=true end
assert(seen.http_proxy and seen.https_proxy and seen.tcp_forward,'status must advertise HTTP service capability')
''')

    def test_http_plan_has_no_certificate_or_backend_startup_gate(self):
        self.lua().execute('''
local c=config()
package.loaded['network-inventory']={collect=function()return {status='ok',zones={'wan'}} end,resolve=function(l)return l end}
package.loaded['device-integrations']={certificate_source=function()error('HTTP has no certificate requirement')end}
package.loaded['product-procd-group']={new=function()return {preflight=function()return true end} end}
io.popen=function()error('HTTP planning must not probe target or certificates')end
local V=require('product-v2-runtime').new({available=function()return true end,authorize=function()return true end,authorize_listener=function()return true end,authorize_backend=function()return true end,narrow=function(s)return s end,root='/tmp/homepublish-test',mixed_ports={http=41002,https=41001,reject=41003}})
local p,e=V.plan(c);assert(p,e);assert(#p.snapshots==0 and #p.services==1 and p.selected.plain.port==8080)
assert(p.sslh_configuration:find('name: "http"',1,true))
assert(p.configuration:find('listen 127.0.0.1:41002 proxy_protocol',1,true))
local endpoints=require('product-listeners').expected(p);local found=false
for _,v in ipairs(endpoints) do assert(v.port~=8080 and v.port~=41001);if v.port==41002 then found=true end end
assert(found,'plain internal HTTP listener is mandatory')
''')

    def test_provider_allocates_distinct_collision_safe_http_port(self):
        l = self.lua()
        l.globals().arg = l.table_from({1: SOURCE.as_posix()})
        l.execute((SOURCE.parents[3]/'tests/device-http-provider.lua').read_text())

    def test_http_shared_firewall_rules_deduplicate_https_and_disabled(self):
        self.lua().execute('''
local P=require('product-firewall-plan');local c=config();local inv={status='ok',zones={'wan'}}
local r,e=P.plan(c,inv);assert(r,e and e.error);assert(#r==1 and r[1].port==24443 and r[1].dest_ip=='192.168.1.2')
c.services[2]={};for k,v in pairs(c.services[1]) do c.services[2][k]=v end
local s=c.services[2];s.service_id='secure';s.type='https_proxy';s.certificate_mode='inherit'
c.default_certificate_ref='acme:fixture';assert(#assert(P.plan(c,inv))==1)
c.services[1].enabled=false;assert(#assert(P.plan(c,inv))==1)
c.services[2].enabled=false;assert(#assert(P.plan(c,inv))==0)
''')

    def test_plain_internal_listener_is_required_owned_and_not_backend(self):
        self.lua().execute('''
local L=require('product-listeners')
local p={configuration='http { server { listen 127.0.0.1:41002 proxy_protocol; server_name plain.example.test; location / { proxy_pass http://192.168.1.8:8080; } } }',sslh_configuration='listen: ( { host: "192.168.1.2"; port: "24443"; } ); protocols: ( { name: "http"; host: "127.0.0.1"; port: "41002"; } );'}
local e=L.expected(p);assert(#e==2 and e[1].port==41002 and e[2].port==24443)
local rows={{family='ipv4',address='127.0.0.1',port=41002,inode='1'},{family='ipv4',address='192.168.1.2',port=24443,inode='2'}}
assert(L.verify(e,rows,{nginx={['1']=true},sslh={['2']=true}}))
local ok,err=L.verify(e,rows,{nginx={},sslh={['2']=true}});assert(not ok and err:find('41002',1,true) and err:find('foreign listener',1,true))
table.remove(rows,1);ok,err=L.verify(e,rows,{nginx={['1']=true},sslh={['2']=true}});assert(not ok and err:find('not listening',1,true))
''')

    def test_http_probe_is_optional_tcp_for_either_upstream_scheme(self):
        self.lua().execute('''
local P=require('product-probe');local c=config();local calls=0
for _,scheme in ipairs({'http','https'}) do
 c.services[1].upstream_scheme=scheme
 local r=P.probe({service_id='plain'},{snapshot=function()return {saved_revision=1,saved_config=c} end,bounded=function(_,_,fn)return fn() end,connect=function(a,p,f)calls=calls+1;assert(a=='192.168.1.8' and p==8080 and f=='ipv4');return {ok=true} end})
 assert(r.ok and r.transport=='tcp' and r.application_health=='unverified')
end
assert(calls==2)
''')

    def test_http_readiness_and_lease_are_component_only(self):
        self.lua().execute('''
package.loaded['direct-renderer']={};package.loaded['direct-backend']={};package.loaded['device-integrations']={}
local healthy=true;local opens=0;local clock=100;os.time=function()return clock end
package.loaded['product-procd-group']={new=function()return {start=function(p,g)p.generation=g;return true end,healthy=function()return healthy,'nginx internal HTTP listener missing' end,stop=function()return true end} end}
local V=require('product-v2-runtime').new({available=function()return true end,firewall={reconcile=function(r,ttl)assert(#r==1 and r[1].port==24443 and ttl>0 and ttl<=3);opens=opens+1;return true end,clear=function()return true end}})
local p={services=config().services,snapshots={},listeners={},firewall_rules={{family='ipv4',zone='wan',protocol='tcp',port=24443}}}
io.popen=function()error('backend startup probe forbidden')end
assert(V.start(p,7,3000));local ok,r=V.readiness(p);assert(ok and r.plain.ready and opens==1)
healthy=false;assert(not V.readiness(p) and opens==1);assert(not V.renew() and opens==1)
healthy=true;clock=104;assert(not V.readiness(p) and opens==1);assert(V.stop())
''')

if __name__ == '__main__': unittest.main(verbosity=2)
