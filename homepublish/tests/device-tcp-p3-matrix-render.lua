-- Device-only task20: exact fixture bindings; never installed.
local root=assert(arg[1]);local family=arg[2] or 'ipv4'
package.path=root..'/?.lua;/usr/share/homepublish/?.lua;'..package.path
local R=require('direct-renderer');local nx=require('nixio');local I=require('device-integrations');local B=require('direct-backend')
local addr=family=='ipv4' and '127.0.0.1' or 'fd89:878e:a47f:0:0:0:0:2'
local c={schema_version=2,access_profile={listeners={{listener_id='v4',family='ipv4',network='lan',address='192.168.1.2',port=49543},{listener_id='v6',family='ipv6',network='lan',address='fd89:878e:a47f::1',port=49543}}},publication_policy={mode='continuous',boot_restore=false},services={}}
local function service(id,kind,host,port)
 return {service_id=id,name=id,enabled=true,type=kind,hostname=host,backend={addressFamily=family,host=addr,port=port,allowed_ranges={family=='ipv4' and '127.0.0.0/8' or 'fd89:878e:a47f::2/128'}},authentication_review={authentication='confirmed',management=false}}
end
c.services={service('tls','tls_passthrough','tls.fixture.home',49546),service('shell','ssh',nil,49547),service('raw','tcp_forward',nil,49546)};c.services[3].listen_port=49550
local p={mixed_ports={reject=49549},authorize_listener=function(l)return (l.address=='192.168.1.2' or l.address=='fd89:878e:a47f:0:0:0:0:1') and (l.internal_port==49543 or l.internal_port==49550) end,authorize_backend=function(a,port)return a==addr and (port==49546 or port==49547) end,healthy=function()return true end,certificate_snapshot=function()error('nonHTTPS must never request certificate')end}
local original=nx.getaddrinfo
local feed={{family=family=='ipv4' and 'inet' or 'inet6',address=addr}}
nx.getaddrinfo=function(host)assert(host=='controlled.fixture.home');return feed end
p.resolve=I.resolve
c.services[1].backend={addressFamily='hostname',host='controlled.fixture.home',port=49546,allowed_ranges={'127.0.0.0/8','fd89:878e:a47f::2/128'}}
local r,e=R.render(c,p);assert(r,'nonHTTPS graph: '..tostring(e));assert(r.sslh_configuration and r.activation_ready==false)
feed={{family='inet',address='192.168.77.9'}}
local denied,why=R.render(c,p);assert(not denied and why:find('backend outside scope',1,true),tostring(why))
feed={{family=family=='ipv4' and 'inet' or 'inet6',address=addr}}
local all=c.services
c.services={all[1]};assert(R.render(c,p),'TLS-only without certificate failed')
c.services={all[2]};assert(R.render(c,p),'SSH-only without certificate failed')
c.services=all
nx.getaddrinfo=original
assert(not r.configuration:find('ssl_certificate',1,true));assert(not r.configuration:find('49544',1,true))
local function narrow(text)
 return (text:gsub('192%.168%.1%.2','127.0.0.1'):gsub('fd89:878e:a47f:0:0:0:0:1','::1'):gsub('fd89:878e:a47f:0:0:0:0:2','::1'))
end
local function write(name,s)local f=assert(io.open(root..'/matrix-runtime/'..name,'w'));assert(f:write(s));assert(f:close())end
write('front.conf',narrow(r.configuration));write('sslh.cfg',narrow(r.sslh_configuration))
-- Controlled libc answer boundary, unchanged production normalization + selector.
local original=nx.getaddrinfo;local answer
nx.getaddrinfo=function(host)assert(host=='controlled.fixture.home');return answer end
local dp={resolve=I.resolve,healthy=function()return true end,authorize_backend=function()return true end}
local b={addressFamily='hostname',host='controlled.fixture.home',port=49546,allowed_ranges={'127.0.0.0/8','::1/128'}}
answer={{family='inet6',address='::1'},{family='inet',address='127.0.0.1'},{family='inet',address='127.0.0.1'}}
local a=assert(B.select(b,dp));assert(a.family=='ipv4' and a.address=='127.0.0.1' and a.ttl==30)
answer={{family='inet6',address='::1'}};a=assert(B.select(b,dp));assert(a.family=='ipv6')
answer={{family='inet',address='127.0.0.1'},{family='inet',address='192.168.77.9'}}
local bad,why=B.select(b,dp);assert(not bad and why:find('backend outside scope',1,true),tostring(why))
answer={{family='inet',address='8.8.8.8'}};assert(not B.select(b,dp))
nx.getaddrinfo=original
print('PASS controlled libc answer feed: dedup IPv4 preference, changed IPv6 answer, mixed outside-range and public answer reject; not real DNS mutation')
print('P3_TASK20_NONHTTPS_RENDER_GREEN '..family)
