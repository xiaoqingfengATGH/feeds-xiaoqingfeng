-- SPDX-License-Identifier: Apache-2.0
local root=arg[1] or '.'
local path=root..'/homepublish/files/usr/share/homepublish/'
local function load(name) local f=loadfile(path..name..'.lua'); return f and f() end
local model=load('canonical')
local function fixture()
 return {schema_version=1,services={{service_id='nas',name='NAS',hostname='nas.example.test',backend={addressFamily='ipv4',host='192.168.1.10',port=8080,allowed_ranges={'192.168.1.0/24'}},certificate_ref='acme:nas',authentication_review={authentication='confirmed',management=false}}},access_profile={methods_allowed={'manual_ipv4'},listeners={{family='ipv4',address='192.168.1.2',interface='wan',zone='wan',protocol='tcp',internal_port=8443,external_port=18443}}}}
end
assert(model and type(model.validate)=='function','canonical authority missing')
local c,e=model.validate(fixture()); assert(c,e)
assert(c.publication_policy.mode=='continuous')
assert(c.publication_policy.boot_restore==false)
assert(c.services[1].backend.addressFamily=='ipv4')
assert(c.services[1].backend.port==8080)
print('PASS canonical defaults and typed service')
local function reject(change, label)
 local bad=fixture(); change(bad)
 local value,err=model.validate(bad)
 assert(value==nil and type(err)=='string', 'must reject '..label)
end
reject(function(c) c.desired_state={enabled=true} end,'client intent')
reject(function(c) c.services[1].token='secret' end,'secret field')
reject(function(c) c.access_profile.listeners[1].command='nft' end,'command')
reject(function(c) c.schema_version=2 end,'unknown schema')
reject(function(c) c.services[1].backend.port='8080' end,'string port')
reject(function(c) c.services[2]=c.services[1] end,'duplicate service')
reject(function(c) c.services[1].certificate_ref='/etc/key.pem' end,'arbitrary certificate path')
reject(function(c) c.services[1].hostname='*.example.test' end,'wildcard hostname')
reject(function(c) c.access_profile.listeners[1].interface='wan;touch /tmp/x' end,'interface injection')
reject(function(c) c.services[1].authentication_review.management='false' end,'boolean coercion')
print('PASS strict known fields, types, references and uniqueness')
reject(function(c) c.services[1].backend.host='999.1.2.3' end,'invalid IPv4')
reject(function(c) c.services[1].backend.host='8.8.8.8' end,'external backend')
reject(function(c) c.services[1].backend.allowed_ranges={'0.0.0.0/0'} end,'broad range')
reject(function(c) c.services[1].backend.host='192.168.2.1' end,'out of allowed range')
reject(function(c) c.services[1].backend.backup={addressFamily='ipv4',host='192.168.2.1',port=80} end,'backup out of range')
reject(function(c) c.access_profile.listeners[1].address='0.0.0.0' end,'wildcard bind')
reject(function(c) c.access_profile.listeners[1].family='ipv6'; c.access_profile.listeners[1].address='::ffff:192.168.1.2' end,'mapped IPv6')
reject(function(c) c.access_profile.methods_allowed={'upnp_ipv4'} end,'missing gateway identity')
reject(function(c) c.access_profile.listeners[2]=c.access_profile.listeners[1] end,'duplicate listener')
reject(function(c) c.publication_policy={mode='temporary',temporary_duration=59} end,'short duration')
reject(function(c) c.publication_policy={mode='temporary',temporary_duration=86401} end,'long duration')
reject(function(c) c.publication_policy={mode='continuous',temporary_duration=1800} end,'continuous fake deadline')
local v6=fixture(); v6.services[1].backend={addressFamily='ipv6',host='fd12:3456::10',port=80,allowed_ranges={'fd12:3456::/64'}}
v6.access_profile={methods_allowed={'direct_ipv6'},listeners={{family='ipv6',address='2001:db8::2',interface='wan6',zone='wan',protocol='tcp',internal_port=8443,external_port=8443}}}
v6.publication_policy={mode='temporary'}
local normalized,ve=model.validate(v6); assert(normalized,ve); assert(normalized.publication_policy.temporary_duration==1800)
for _,addr in ipairs({'::','::1','fe80::1','ff02::1','::ffff:c000:201','1::2::3','gggg::1','2001:db8:1:2:3:4:5:6:7'}) do
 reject(function(c) c.services[1].backend={addressFamily='ipv6',host=addr,port=80,allowed_ranges={'2001:db8::/32'}} end,'unsafe or malformed IPv6 '..addr)
end
local dns=fixture(); dns.services[1].backend.addressFamily='hostname'; dns.services[1].backend.host='nas.lan'
assert(model.validate(dns))
local detached=fixture(); local copy=assert(model.validate(detached)); detached.services[1].name='changed'; assert(copy.services[1].name=='NAS')
print('PASS address scope, IPv6, methods, duration bounds and detached plans')
return {model=model,fixture=fixture,path=path}
