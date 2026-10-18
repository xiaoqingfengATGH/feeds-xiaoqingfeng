-- Real target canonical behavior; no journal writes or DNS access.
local C=dofile(ROOT..'/canonical-v2.lua')
local J=dofile(ROOT..'/product-json.lua')
local base={schema_version=2,access_profile={listeners={{listener_id='v4',family='ipv4',network='lan',address='192.168.1.2',port=18443}}},services={{service_id='web',name='Web',enabled=true,type='http_proxy',hostname='new.example.com',upstream_scheme='http',backend={addressFamily='ipv4',host='192.168.1.3',port=8080}}}}
local function copy(v)return J.decode(J.encode(v))end
local out=assert(C.validate(base));assert(out.services[1].dns and out.services[1].dns.mode=='manual','legacy services must explicitly default to manual')
local c=copy(base);c.services[1].dns={mode='ddns_go',profile_id='profile:1:abcdef',record_types={'AAAA','A'}}
out=assert(C.validate(c));assert(out.services[1].dns.profile_id==c.services[1].dns.profile_id);assert(out.services[1].dns.record_types[1]=='AAAA')
for _,kind in ipairs({'http_proxy','https_proxy','tls_passthrough'}) do
 local x=copy(c);x.services[1].type=kind
 if kind=='https_proxy' then x.services[1].certificate_mode='inherit' elseif kind=='tls_passthrough' then x.services[1].upstream_scheme=nil end
 assert(C.validate(x),'eligible host type rejected')
end
for _,dns in ipairs({false,{mode='bad'},{mode='ddns_go',profile_id='',record_types={'A'}},{mode='ddns_go',profile_id='x',record_types={}},{mode='ddns_go',profile_id='x',record_types={'A','A'}},{mode='ddns_go',profile_id='x',record_types={'CNAME'}},{mode='manual',unexpected=true}}) do
 c=copy(base);c.services[1].dns=dns;assert(not C.validate(c),'invalid dns accepted')
end
for _,kind in ipairs({'ssh','tcp_forward'}) do
 c=copy(base);local s=c.services[1];s.type=kind;s.hostname=nil;s.upstream_scheme=nil;if kind=='tcp_forward' then s.listen_port=19443 end
 assert(C.validate(c));s.dns={mode='ddns_go',profile_id='x',record_types={'A'}};assert(not C.validate(c),'non-host DDNS rejected')
end
print('DDNS_SCHEMA_GREEN')
