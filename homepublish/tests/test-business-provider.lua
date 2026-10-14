-- Scoped HomeVPN provider regression; no business key access in this test.
package.path=arg[1]..'/?.lua;'..package.path
local I=require('device-integrations');local calls=0
I.acme_source=function(d,k) assert(d=='home.iwonderful.top' and k=='rsa');calls=calls+1;return {certificate='/etc/acme/home.iwonderful.top/fullchain.cer',key='/etc/acme/home.iwonderful.top/home.iwonderful.top.key'} end
local P=require('product-device-provider')
local c={services={{service_id='fixture',hostname='home.iwonderful.top',certificate_ref='acme:home_rsa',backend={addressFamily='ipv4',host='127.0.0.1',port=49285,allowed_ranges={'127.0.0.0/8'}},authentication_review={authentication='confirmed',management=false}}},access_profile={methods_allowed={'manual_ipv4'},listeners={{family='ipv4',address='192.168.1.2',interface='br-lan',zone='lan',protocol='tcp',internal_port=49284,external_port=49284}}}}
local p,e=P.plan(c);assert(p,e);assert(calls==1);assert(p.hostname=='home.iwonderful.top' and p.system_trust==true);assert(p.certificate_source.key=='/etc/acme/home.iwonderful.top/home.iwonderful.top.key')
c.services[1].hostname='other.example';assert(not P.plan(c));assert(calls==1)
print('PASS scoped explicit HomeVPN RSA business certificate plan')
