-- Device-only mixed-route tracer. No live journal/provider activation.
local root=assert(arg[1]);package.path=root..'/?.lua;/usr/share/homepublish/?.lua;'..package.path
local R=require('direct-renderer')
local c={schema_version=2,default_certificate_ref='acme:home_rsa',access_profile={listeners={{listener_id='v6',family='ipv6',network='lan',address='fd89:878e:a47f::1',port=49543}}},publication_policy={mode='continuous',boot_restore=false},services={}}
local function service(id,kind,host,port)
 return {service_id=id,name=id,enabled=true,type=kind,hostname=host,backend={addressFamily='ipv4',host='127.0.0.1',port=port,allowed_ranges={'127.0.0.0/8'}},authentication_review={authentication='confirmed',management=false}}
end
c.services[1]=service('web','https_proxy','home.iwonderful.top',49545);c.services[1].certificate_mode='inherit';c.services[1].upstream_scheme='http'
c.services[2]=service('tls','tls_passthrough','tls.fixture.home',49546)
local p={mixed_ports={https=49544,reject=49549},authorize_listener=function(l)return (l.address=='fd89:878e:a47f:0:0:0:0:1' and l.internal_port==49543) end,authorize_backend=function(a,port)return a=='127.0.0.1' and (port==49545 or port==49546) end,healthy=function()return true end,certificate_snapshot=function(ref,host)assert(ref=='acme:home_rsa' and host=='home.iwonderful.top','passthrough must not request certificate');return {certificate=root..'/mixed-runtime/cert.pem',key=root..'/mixed-runtime/key.pem'} end}
local r,e=R.render(c,p);assert(r,'mixed exact-SNI route unsupported: '..tostring(e));assert(r.sslh_configuration and r.activation_ready==false)
local text,n=r.sslh_configuration:gsub('fd89:878e:a47f:0:0:0:0:1','::1');assert(n==1,'fixed harness binding narrowing mismatch')
local function write(name,s)local f=assert(io.open(root..'/mixed-runtime/'..name,'w'));assert(f:write(s));assert(f:close()) end
write('sslh.cfg',text);write('front.conf',r.configuration)
assert(R.render(c,p).configuration==r.configuration)
print('P3_TASK17_RENDER_GREEN')
