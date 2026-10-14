-- Two independent server-owned host/certificate bindings; no secret access.
package.path=arg[1]..'/?.lua;'..package.path
local I=require('device-integrations')
I.acme_source=function(d,k) assert(d=='home.iwonderful.top' and k=='rsa');return {certificate='/etc/acme/home.iwonderful.top/fullchain.cer',key='/etc/acme/home.iwonderful.top/home.iwonderful.top.key'} end
local P=require('product-device-provider')
local function service(id,host,ref,port)return {service_id=id,hostname=host,certificate_ref=ref,backend={addressFamily='ipv4',host='127.0.0.1',port=port,allowed_ranges={'127.0.0.0/8'}},authentication_review={authentication='confirmed',management=false}}end
local c={services={service('fixture','home.iwonderful.top','acme:home_rsa',49285),service('fixture2','service.home','import:fixture',49286)},access_profile={methods_allowed={'manual_ipv4'},listeners={{family='ipv4',address='192.168.1.2',interface='br-lan',zone='lan',protocol='tcp',internal_port=49284,external_port=49284}}}}
local p,e=P.plan(c);assert(p,e);assert(#p.services==2 and #p.backends==2)
assert(p.services[1].system_trust and not p.services[2].system_trust)
assert(p.configuration:find('/cert1.pem',1,true) and p.configuration:find('/cert2.pem',1,true))
c.services[2].certificate_ref='acme:home_rsa';assert(not P.plan(c));c.services[2].certificate_ref='import:fixture'
c.services[2].hostname='other.example';assert(not P.plan(c))
-- Every service must be checked; one successful curl cannot activate the set.
local execute=os.execute;local seen={};os.execute=function(s)
 if s:find('curl',1,true) then seen[#seen+1]=s;return s:find('service.home',1,true) and 1 or 0 end
 return 0
end
local open=io.open;io.open=function()return {write=function()return true end,close=function()return true end}end
assert(P.start(p,1,{}));assert(not P.readiness());assert(#seen>=2)
os.execute=function()return 0 end
local ok,results=P.readiness();assert(ok and results and results.fixture.ready and results.fixture2.ready,'per-service readiness results required')
io.open=open
os.execute=execute
print('PASS simplified device multi-plan exact bindings and all-service readiness')
