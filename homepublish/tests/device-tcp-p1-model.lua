-- SPDX-License-Identifier: Apache-2.0
local root=assert(arg[1]); local phase=arg[2] or 'all'
local canonical=dofile(root..'/canonical.lua')
local function copy(v) if type(v)~='table' then return v end local r={} for k,x in pairs(v) do r[k]=copy(x) end return r end
local function base()
 return {schema_version=2,services={},access_profile={listeners={{listener_id='lan6',family='ipv6',network='lan',address='FD00:0000:0:0:0:0:0:1',port=8443}}}}
end
local function service(t,id)
 local s={service_id=id or t,name=t,type=t,enabled=true,backend={addressFamily='ipv4',host='192.168.1.10',port=8080,allowed_ranges={'192.168.1.0/24'}},authentication_review={authentication='unconfirmed',management=false}}
 if t=='https_proxy' then s.hostname='WEB.Example.com';s.upstream_scheme='http';s.certificate_mode='inherit'
 elseif t=='tls_passthrough' then s.hostname='tls.example.com'
 elseif t=='tcp_forward' then s.listen_port=9443 end return s
end
local count=0
local function test(name,fn) local ok,e=pcall(fn);if not ok then print('FAIL '..name..': '..tostring(e));os.exit(1) end count=count+1;print('PASS '..name) end
local function valid(c) local r,e=canonical.validate(c);assert(r,e);return r end
local function bad(c,code) local r,e,d=canonical.validate(c);assert(not r,'unexpected acceptance');assert(type(e)=='string');if code then assert(d and d.error_code==code,e) end end
if phase=='core' or phase=='all' then
 test('four types and IPv6 normalization',function() local c=base();for _,t in ipairs({'https_proxy','tls_passthrough','ssh','tcp_forward'}) do c.services[#c.services+1]=service(t) end local r=valid(c);assert(r.access_profile.listeners[1].address=='fd00:0:0:0:0:0:0:1');assert(r.services[1].hostname=='web.example.com');assert(r.services[1].certificate_ref==nil);assert(r.publication_policy.boot_restore==false);assert(c.services[1].hostname=='WEB.Example.com') end)
 test('v2 runtime explicitly refused',function() local p,e=canonical.runtime_plan(base());assert(not p and e:find('P3',1,true),e) end)
 test('unsupported schema structured refusal',function() local c=base();c.schema_version=3;bad(c,'UNSUPPORTED_SCHEMA') end)
 test('strict structures and disabled syntax',function()
 local mutations={function(c)c.extra=true end,function(c)c.services={[2]=service('ssh')} end,function(c)c.access_profile.listeners[1].zone='lan' end,function(c)c.services={service('ssh')};c.services[1].hostname='x.example' end,function(c)c.services={service('tcp_forward')};c.services[1].enabled=false;c.services[1].listen_port=22 end,function(c)c.services={service('https_proxy')};c.services[1].certificate_ref='acme:x' end,function(c)c.services={service('ssh')};c.services[1].backend.addressFamily=nil end,function(c)c.services={service('https_proxy')};c.services[1].upstream_scheme='https';c.services[1].upstream_tls={verify=false,server_name='x.example'} end}
 for _,mutate in ipairs(mutations) do local c=base();mutate(c);bad(c,'INVALID_CONFIG') end end)
 test('malformed service gives secret-free fixed error',function() local c=base();c.services={false};local r,e,d=canonical.validate(c);assert(not r and d.error_code=='INVALID_CONFIG');assert(not e:find('canonical',1,true),e) end)
 test('HTTPS upstream strict verified DNS',function() local c=base();c.services={service('https_proxy')};local s=c.services[1];s.upstream_scheme='https';s.upstream_tls={verify=true,server_name='BACK.Example.com'};assert(valid(c).services[1].upstream_tls.server_name=='back.example.com');s.upstream_tls.ca='/tmp/x';bad(c) end)
 test('listener safety and cardinality',function() for _,address in ipairs({'::','::1','fe80::1','::ffff:c000:201','ff02::1','fd00::1%lan','fd00:::1'}) do local c=base();c.access_profile.listeners[1].address=address;bad(c) end local c=base();c.access_profile.listeners[2]=copy(c.access_profile.listeners[1]);c.access_profile.listeners[2].listener_id='other';bad(c);c=base();c.access_profile.listeners[2]={listener_id='lan4',family='ipv4',network='lan',address='192.168.1.1',port=8443};valid(c);c.access_profile.listeners[2].port=8444;bad(c) end)
end
if phase=='conflicts' or phase=='all' then
 test('disabled normalized domain conflict',function() local c=base();c.services={service('https_proxy'),service('tls_passthrough')};c.services[2].hostname='web.EXAMPLE.com';c.services[2].enabled=false;bad(c,'DOMAIN_CONFLICT') end)
 test('disabled SSH conflict',function() local c=base();c.services={service('ssh','a'),service('ssh','b')};c.services[2].enabled=false;bad(c,'SSH_CONFLICT') end)
 test('disabled TCP and reserved shared port conflicts',function() local c=base();c.services={service('tcp_forward','a'),service('tcp_forward','b')};c.services[2].enabled=false;bad(c,'PORT_CONFLICT');c.services[2]=nil;c.services[1].listen_port=8443;bad(c,'PORT_CONFLICT') end)
 test('duplicate IDs across types',function() local c=base();c.services={service('ssh','x'),service('tls_passthrough','x')};bad(c,'INVALID_CONFIG') end)
 test('equivalent IPv6 family binding rejected',function() local c=base();c.access_profile.listeners[2]=copy(c.access_profile.listeners[1]);c.access_profile.listeners[2].listener_id='second';c.access_profile.listeners[2].address='fd00::1';bad(c,'PORT_CONFLICT') end)
end
if phase=='migration' or phase=='all' then
 local function legacy() local c=base();c.schema_version=1;c.default_certificate_ref='acme:example';local s=service('https_proxy');s.type=nil;s.upstream_scheme=nil;s.certificate_ref='acme:example';c.services={s};c.access_profile={methods_allowed={'manual_ipv4','direct_ipv6'},listeners={{family='ipv4',address='192.168.1.1',interface='br-lan',zone='lan',protocol='tcp',internal_port=8443,external_port=443},{family='ipv6',address='fd00::1',interface='lan',zone='lan',protocol='tcp',internal_port=8443,external_port=8443}}};return c end
 local inventory={networks={{network='lan',device='br-lan'}}}
 test('pure explicit migration preserves all listeners and source',function() assert(type(canonical.migrate_preview)=='function','migration export missing');local c=legacy();local p=canonical.migrate_preview(c,inventory);assert(#p.blocking_issues==0);assert(#p.proposed_config.access_profile.listeners==2);assert(p.proposed_config.services[1].type=='https_proxy');assert(p.proposed_config.services[1].certificate_ref==nil);assert(c.schema_version==1 and c.services[1].certificate_ref=='acme:example');assert(p.original_config.access_profile.listeners[1].external_port==443);p.original_config.services[1].name='changed';assert(c.services[1].name~='changed');assert(#p.warnings>0);valid(p.proposed_config) end)
 test('migration refuses ambiguous missing and unsupported without loss',function() for _,inv in ipairs({{networks={}}, {networks={{network='lan',device='br-lan'},{network='guest',device='br-lan'}}}}) do local c=legacy();local p=canonical.migrate_preview(c,inv);assert(#p.blocking_issues>0 and #p.original_config.access_profile.listeners==2) end local c=legacy();c.access_profile.methods_allowed[#c.access_profile.methods_allowed+1]='stun_experimental';local p=canonical.migrate_preview(c,inventory);assert(#p.blocking_issues>0 and p.original_config.access_profile.methods_allowed[3]=='stun_experimental') end)
 test('migration blocks multiple same-family listeners and differing ports without truncation',function()
  local c=legacy();c.access_profile.listeners[3]=copy(c.access_profile.listeners[1]);c.access_profile.listeners[3].address='192.168.1.2';local p=canonical.migrate_preview(c,inventory);assert(#p.blocking_issues>0 and #p.proposed_config.access_profile.listeners==3 and #p.original_config.access_profile.listeners==3)
  c=legacy();c.access_profile.listeners[1].internal_port=8444;p=canonical.migrate_preview(c,inventory);assert(#p.blocking_issues>0 and #p.proposed_config.access_profile.listeners==2)
 end)
 test('legacy validate and runtime unchanged',function() local c=legacy();local r,e=canonical.validate(c);assert(r,e);assert(r.schema_version==1 and r.services[1].certificate_ref=='acme:example');assert(canonical.runtime_plan(c));c.services={};assert(canonical.validate(c));local r,e=canonical.runtime_plan(c);assert(not r and e=='no enabled services') end)
end
print('TOTAL '..count..' PASS phase='..phase)
