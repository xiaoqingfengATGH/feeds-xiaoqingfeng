-- Real-device non-idempotent POST regression (existing noReplay behavior).
local root=assert(arg[1]);package.path=root..'/?.lua;/usr/share/homepublish/?.lua;'..package.path
local R=require('direct-renderer');local I=require('device-integrations');local nx=require('nixio')
local c={schema_version=2,default_certificate_ref='acme:fixture',access_profile={listeners={{listener_id='v6',family='ipv6',network='lan',address='fd89:878e:a47f::1',port=49556}}},publication_policy={mode='continuous',boot_restore=false},services={{service_id='post',name='post',enabled=true,type='https_proxy',hostname='tls.fixture.home',certificate_mode='inherit',upstream_scheme='http',backend={addressFamily='hostname',host='controlled.fixture.home',port=49557,allowed_ranges={'127.0.0.0/8'}},authentication_review={authentication='confirmed',management=false}}}}
local original=nx.getaddrinfo
nx.getaddrinfo=function(host)assert(host=='controlled.fixture.home');return {{family='inet',address='127.0.0.2'},{family='inet',address='127.0.0.1'}} end
local r,e=R.render(c,{resolve=I.resolve,authorize_listener=function(l)return l.internal_port==49556 end,authorize_backend=function(a,p)return (a=='127.0.0.1' or a=='127.0.0.2') and p==49557 end,healthy=function()return true end,certificate_snapshot=function()return {certificate=root..'/matrix-runtime/tls.pem',key=root..'/matrix-runtime/tls.key'}end});assert(r,e)
nx.getaddrinfo=original
assert(r.backends[1].address=='127.0.0.1');assert(r.configuration:find('proxy_next_upstream off;',1,true))
local text,n=r.configuration:gsub('fd89:878e:a47f:0:0:0:0:1','::1');assert(n==2)
local f=assert(io.open(root..'/matrix-runtime/post.conf','w'));assert(f:write(text));assert(f:close())
print('PASS controlled libc dual answer uses exactly one deterministic IPv4 backend; HTTP noReplay existing behavior')
