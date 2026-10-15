-- Device-only task16 tracer; never writes the live product journal.
local root=assert(arg[1]);package.path=root..'/?.lua;/usr/share/homepublish/?.lua;'..package.path
local C=require('canonical-v2');local R=require('direct-renderer')
local c={schema_version=2,default_certificate_ref='acme:home_rsa',access_profile={listeners={{listener_id='v6',family='ipv6',network='lan',address='fd89:878e:a47f::1',port=49443}}},publication_policy={mode='continuous',boot_restore=false},services={{service_id='p3web',name='P3 private vertical',enabled=true,type='https_proxy',hostname='home.iwonderful.top',certificate_mode='inherit',upstream_scheme='http',backend={addressFamily='ipv4',host='127.0.0.1',port=49445,allowed_ranges={'127.0.0.0/8'}},authentication_review={authentication='confirmed',management=false}}}}
assert(C.validate(c))
local p={authorize_listener=function(l)return l.address=='fd89:878e:a47f:0:0:0:0:1' and l.internal_port==49443 end,authorize_backend=function(a,port)return a=='127.0.0.1' and (port==49445 or port==49446 or port==49447) end,healthy=function()return true end,certificate_snapshot=function(ref,host)assert(ref=='acme:home_rsa' and host=='home.iwonderful.top');return {certificate=root..'/runtime/cert.pem',key=root..'/runtime/key.pem'} end}
local r,e=R.render(c,p);assert(r,'v2 HTTPS render rejected: '..tostring(e));assert(r.activation_ready==false)
assert(r.configuration:find('proxy_pass http://127.0.0.1:49445;',1,true))
print('PASS v2 canonical to HTTPS IPv6 route plan/render')
local function write(name,bytes)local f=assert(io.open(root..'/'..name,'w'));assert(f:write(bytes));assert(f:close()) end
local function narrowed(r)
 -- FIXED HARNESS ONLY: replace this one canonical ULA listener with ::1.
 -- Production validation above remains strict. This is not public-v6 evidence.
 local text,n=r.configuration:gsub('%[fd89:878e:a47f:0:0:0:0:1%]:49443','[::1]:49443');assert(n==2,'fixed binding narrowing mismatch');return text
end
write('runtime/http.conf',narrowed(r))
c.services[1].upstream_scheme='https';c.services[1].upstream_tls={verify=true,server_name='home.iwonderful.top'};c.services[1].backend.port=49446
r,e=R.render(c,p);assert(r,e);assert(r.configuration:find('proxy_ssl_verify on;',1,true));assert(r.configuration:find('proxy_ssl_name home.iwonderful.top;',1,true));write('runtime/https.conf',narrowed(r))
c.services[1].upstream_tls.server_name='wrong.fixture.home';r,e=R.render(c,p);assert(r,e);write('runtime/wrong-name.conf',narrowed(r))
c.services[1].upstream_tls.server_name='home.iwonderful.top';c.services[1].backend.port=49447;r,e=R.render(c,p);assert(r,e);write('runtime/untrusted.conf',narrowed(r))
c.services[1].upstream_tls.verify=false;assert(not C.validate(c));assert(not R.render(c,p));print('PASS upstream verify=false rejected')
c.services[1].upstream_tls.verify=true;c.access_profile.listeners[1].address='::1';assert(not C.validate(c));assert(not R.render(c,p));print('PASS production loopback ingress remains forbidden')
-- Appended regression coverage, not independently claimed RED cases.
c.access_profile.listeners[1].address='fd89:878e:a47f::1'
local q=assert(C.validate(c));q.services[1].upstream_tls.server_name='home.iwonderful.top';q.services[1].backend.port=49446
local first=assert(R.render(q,p));local second=assert(R.render(q,p));assert(first.configuration==second.configuration,'non-deterministic renderer')
q.default_certificate_ref='acme:must_not_be_selected';q.services[1].certificate_mode='override';q.services[1].certificate_ref='acme:home_rsa';assert(R.render(q,p),'override lost')
q.services[2]={service_id='future',name='not implemented yet',enabled=false,type='ssh',backend=q.services[1].backend,authentication_review=q.services[1].authentication_review}
assert(R.render(q,p),'disabled unsupported route should not create sockets')
q.services[2].enabled=true;assert(not R.render(q,p),'unsupported active route must fail closed')
q.services[2]=nil;q.services[1].enabled=false;assert(not R.render(q,p),'empty enabled route graph accepted')
print('PASS deterministic/override/disabled/unsupported/empty route regressions')
print('P3_RENDER_GREEN')
