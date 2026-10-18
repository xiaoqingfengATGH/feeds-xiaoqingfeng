-- Target-only B1 tracer: unchanged installed modules, no test profile/marker.
package.path='/usr/share/homepublish/?.lua;'..package.path
local J=require('product-json')
local c={schema_version=2,default_certificate_ref='acme:home_rsa',access_profile={listeners={{listener_id='p5',family='ipv4',network='lan',address='192.168.1.2',port=50881}}},publication_policy={mode='continuous',boot_restore=false},services={{service_id='p5web',name='P5 retained production test',enabled=true,type='https_proxy',hostname='home.iwonderful.top',certificate_mode='inherit',upstream_scheme='http',backend={addressFamily='ipv4',host='127.0.0.1',port=50882,allowed_ranges={'127.0.0.0/8'}},authentication_review={authentication='confirmed',management=false}}}}
local provider=require('product-system-provider')
if arg[1]=='plan' then
 local p,e=provider.plan(c);assert(p,'B1 real production plan: '..tostring(e))
 assert(p.configuration:find('192.168.1.2:50881',1,true),'exact canonical listener')
 assert(not p.configuration:find('49543',1,true),'fixture port leaked')
 print('PASS real production plan exact LAN nonfixture endpoints');return
end
-- Only native journal is scoped. Provider/modules remain unchanged installed.
package.cpath='/tmp/homepublish-tcp-p3/?.so;'..package.cpath
local P=require('product-provider');local C=require('product-controller').new(provider)
local q=J.decode(io.read('*a'));local result
if q.action=='fixture_config' then result=c
elseif q.action=='start' then result=C.start(q.revision,q.approved)
elseif q.action=='apply' then result=C.apply(q.revision,q.approved)
elseif q.action=='stop' then result=C.stop()
else result=assert(P.handle(q,true)) end
io.write(J.encode(result),'\n')
