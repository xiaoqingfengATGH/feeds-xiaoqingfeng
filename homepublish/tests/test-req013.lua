-- SPDX-License-Identifier: Apache-2.0
-- REQ-013 RED: large-body 500 (worker cannot traverse private runtime root) and
-- LLM upstream 504 (fixed 5s proxy_read_timeout). Watch it fail before the fix.
local root=arg[1] or '.'
local path=root..'/homepublish/files/usr/share/homepublish/'
package.path=path..'?.lua;'..package.path
local C=require('canonical-v2');local R=require('direct-renderer');local P=require('tcp-route-plan')
local function v2service(overrides)
 local s={service_id='llm',name='LLM',enabled=true,type='https_proxy',hostname='vmware.innonext.win',certificate_mode='inherit',upstream_scheme='https',upstream_tls={verify=true,server_name='ai.iwonderful.top'},backend={addressFamily='ipv4',host='192.168.1.2',port=443,allowed_ranges={'192.168.1.0/24'}},dns={mode='manual'}}
 for k,v in pairs(overrides or {}) do s[k]=v end
 return s
end
local function v2config(services)
 return {schema_version=2,default_certificate_ref='acme:home_rsa',access_profile={listeners={{listener_id='v4',family='ipv4',network='lan',address='192.168.1.2',port=8443}},firewall={ipv4_zones={'lan'},ipv6_zones={}}},publication_policy={mode='continuous'},services=services or {v2service()}}
end
local function providers(backend_port)
 return {authorize_listener=function(l)return l.address=='192.168.1.2' and l.internal_port==8443 end,authorize_backend=function()return true end,healthy=function()return true end,certificate_snapshot=function()return {certificate='/tmp/homepublish-runtime/cert1.pem',key='/tmp/homepublish-runtime/key1.pem'} end}
end

-- 1) Schema: service-level read_timeout accepted and round-trips; nil stays nil (render default).
local c=v2config()
local n=C.validate(c);assert(n,'baseline v2 config rejected')
assert(n.services[1].read_timeout==nil,'read_timeout must stay nil when unset')
c.services[1].read_timeout=300
n=C.validate(c);assert(n and n.services[1].read_timeout==300,'read_timeout=300 rejected or lost')
print('PASS canonical v2 accepts service-level read_timeout=300')

-- 2) Schema: invalid values rejected (0, 3601, string, float, negative).
for _,bad in ipairs({0,3601,'300',3.5,-1}) do
 local d=v2config();d.services[1].read_timeout=bad
 assert(not C.validate(d),'read_timeout '..tostring(bad)..' must be rejected')
end
-- read_timeout only supports HTTP reverse proxies.
for _,kind in ipairs({'tls_passthrough','ssh','tcp_forward'}) do
 local d=v2config();d.services[1]=v2service({type=kind});d.services[1].hostname='other.example.test';d.services[1].read_timeout=60
 if kind=='tcp_forward' then d.services[1].listen_port=29443 end
 assert(not C.validate(d),kind..' read_timeout must be rejected')
end
print('PASS canonical v2 rejects invalid read_timeout values and non-proxy types')

-- 3) Render: proxy_read_timeout follows the service value (default 300s).
local r,e=R.render(C.validate(v2config()),providers());assert(r,'render failed: '..tostring(e))
assert(r.configuration:find('proxy_read_timeout 300s;',1,true),'default proxy_read_timeout 300s missing')
assert(not r.configuration:find('proxy_read_timeout 5s;',1,true),'legacy 5s read timeout still rendered')
print('PASS renderer default proxy_read_timeout 300s')

local d2=v2config();d2.services[1].read_timeout=1200
local r2=R.render(C.validate(d2),providers());assert(r2,'render with read_timeout failed')
assert(r2.configuration:find('proxy_read_timeout 1200s;',1,true),'configured read_timeout not rendered')
assert(r2.configuration:find('proxy_connect_timeout 2s;',1,true),'connect timeout must stay 2s')
print('PASS renderer honors configured read_timeout, keeps connect 2s')

-- 4) Render: temp paths leave the private runtime root.
assert(not r.configuration:find('client_body_temp_path body;',1,true),'relative client_body_temp_path still rendered')
assert(not r.configuration:find('proxy_temp_path proxy;',1,true),'relative proxy_temp_path still rendered')
assert(r.configuration:find('client_body_temp_path /tmp/homepublish-tmp/body;',1,true),'absolute tmp client body path missing')
assert(r.configuration:find('proxy_temp_path /tmp/homepublish-tmp/proxy;',1,true),'absolute tmp proxy path missing')
print('PASS renderer uses absolute /tmp/homepublish-tmp temp paths')

-- 5) Route plan passes read_timeout through for https and http services.
local d3=v2config();d3.services[1].read_timeout=600
local plan=P.compile(C.validate(d3));assert(plan,'plan compile failed')
assert(plan.services[1].read_timeout==600,'plan lost https read_timeout')
local d4=v2config();d4.services[1]={service_id='web',name='web',enabled=true,type='http_proxy',hostname='vmware.innonext.win',upstream_scheme='http',read_timeout=90,backend={addressFamily='ipv4',host='192.168.1.2',port=80,allowed_ranges={'192.168.1.0/24'}},dns={mode='manual'}}
local c4=C.validate(d4);assert(c4,'http_proxy read_timeout rejected')
local plan4=P.compile(c4);assert(plan4,'http plan compile failed')
assert(plan4.http_services[1].read_timeout==90,'http plan lost read_timeout')
print('PASS route plan passes read_timeout through https/http services')

print('REQ013_RED_GREEN')
