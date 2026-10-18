package.path='/usr/share/homepublish/?.lua;'..package.path
local J=require('product-json')
local c={schema_version=2,default_certificate_ref='acme:home_rsa',access_profile={listeners={{listener_id='p5',family='ipv4',network='lan',address='192.168.1.2',port=50881}}},publication_policy={mode='continuous',boot_restore=false},services={}}
local function add(id,t,port)
 local s={service_id=id,name=id,enabled=true,type=t,backend={addressFamily='ipv4',host='127.0.0.1',port=port,allowed_ranges={'127.0.0.0/8'}},authentication_review={authentication='confirmed',management=false}}
 if t=='https_proxy' then s.hostname='home.iwonderful.top';s.certificate_mode='inherit';s.upstream_scheme='http' end
 if t=='tls_passthrough' then s.hostname='opaque.home.test' end
 if t=='tcp_forward' then s.listen_port=50885 end
 c.services[#c.services+1]=s
end
add('web','https_proxy',50882);add('tls','tls_passthrough',50886);add('ssh','ssh',50887);add('tcp','tcp_forward',50888)
local provider=require('product-system-provider')
if arg[1]=='plan' then local p,e=provider.plan(c);assert(p,'four protocol production plan: '..tostring(e));assert(p.sslh_configuration);assert(#p.services==4);print('FOUR_PROTOCOL_PRODUCTION_PLAN_GREEN');return end
package.cpath='/tmp/homepublish-tcp-p3/?.so;'..package.cpath
local P=require('product-provider');local C=require('product-controller').new(provider)
local q=J.decode(io.read('*a'));local r
if q.action=='fixture_config' then r=c elseif q.action=='start' then r=C.start(q.revision,q.approved) elseif q.action=='stop' then r=C.stop() else r=assert(P.handle(q,true)) end
io.write(J.encode(r),'\n')
