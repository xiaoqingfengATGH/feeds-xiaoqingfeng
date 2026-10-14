-- Fixed scope provider plan contract; actual certificate/TLS tested separately.
package.path=arg[1]..'/?.lua;'..package.path
local I=require('device-integrations');local calls={}
I.certificate_source=function(ref,host)
 calls[#calls+1]={ref,host};return {certificate='/fixture/'..ref:sub(6)..'.pem',key='/fixture/'..ref:sub(6)..'.key',domain='*.fixture.home',key_type='rsa'}
end
local P=require('product-device-provider')
local function service(id,host,ref)return {service_id=id,hostname=host,certificate_ref=ref,backend={addressFamily='ipv4',host='127.0.0.1',port=49285,allowed_ranges={'127.0.0.0/8'}},authentication_review={authentication='confirmed',management=false}}end
local c={services={service('fixture','a.fixture.home','acme:fixture_rsa'),service('fixture2','b.fixture.home','acme:fixture_rsa')},access_profile={methods_allowed={'manual_ipv4'},listeners={{protocol='tcp',family='ipv4',address='192.168.1.2',interface='br-lan',zone='lan',internal_port=49284,external_port=49284}}}}
local p,e=P.plan(c);assert(p,e);assert(#calls==2);assert(p.services[1].certificate==p.services[2].certificate,'shared snapshot');assert(p.services[1].hostname~=p.services[2].hostname)
c.services[2].certificate_ref='acme:fixture_ecc';p,e=P.plan(c);assert(p,e);assert(p.services[1].certificate~=p.services[2].certificate,'independent snapshot')
c.services[1].hostname='arbitrary.fixture.home';assert(not P.plan(c),'scope must not expand')
print('PASS fixed wildcard hosts shared and independent snapshot mapping')
