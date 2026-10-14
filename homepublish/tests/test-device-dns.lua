package.path=arg[1]..'/?.lua;/usr/share/homepublish/?.lua;'..package.path
local P=require('product-device-provider')
local c={services={{service_id='fixture',hostname='service.home',certificate_ref='import:fixture',backend={addressFamily='hostname',host='localhost.lan',port=49285,allowed_ranges={'127.0.0.0/8','::1/128'}},authentication_review={authentication='confirmed',management=false}}},access_profile={methods_allowed={'manual_ipv4'},listeners={{family='ipv4',address='192.168.1.2',interface='br-lan',zone='lan',protocol='tcp',internal_port=49284,external_port=49284}}}}
local p,e=P.plan(c);assert(p,e)
assert(p.backends[1].address=='127.0.0.1')
assert(p.configuration:find('proxy_next_upstream off;',1,true))
assert(p.backends[1].resolver=='system-getaddrinfo/poll30-no-dns-ttl')
print('PASS real DNS IPv4 preferred scoped render and request replay disabled')
