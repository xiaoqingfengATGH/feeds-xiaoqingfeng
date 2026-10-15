local root = assert(arg[1], 'fixture root required')
local path = root .. '/network-inventory.lua'
local f = io.open(path, 'r')
assert(f, 'P1 inventory module missing')
f:close()
local inventory = dofile(path)
local live, err = inventory.collect()
assert(live and live.status == 'ok', err and err.error)
assert(type(live.networks) == 'table' and #live.networks > 0)
local found
for _, n in ipairs(live.networks) do
  if n.network == 'lan' then
    found = n
    assert(n.device == 'br-lan' and n.zones[1] == 'lan')
    local binding = {network=n.network, family='ipv4', address='192.168.1.2'}
    local resolved, e = inventory.resolve(binding, live)
    assert(resolved and resolved.zone == 'lan', e and e.error)
  end
end
assert(found, 'real LAN absent')
print('PASS live fixed ubus/UCI inventory and exact LAN resolution')

local function fixture(addresses)
  return {interface={{interface='edge',up=true,l3_device='br-edge',
    ['ipv4-address']=addresses or {{address='192.168.8.1',mask=24}},
    ['ipv6-address']={{address='fd00::1',mask=64},{address='2001:db8::1',mask=64},
      {address='::',mask=0},{address='::1',mask=128},{address='fe80::1',mask=64},
      {address='::ffff:c000:201',mask=128},{address='ff02::1',mask=64}},
    ['ipv6-prefix-assignment']={{['local-address']={address='fd01::1',mask=64}}}}}}
end
local function check_error(value, err, code, field)
  assert(value==nil and err.error_code==code and err.field==field and err.retryable==true)
end
local snap=fixture({{address='192.168.8.1',mask=24},{address='0.0.0.0',mask=0},
  {address='127.0.0.1',mask=8},{address='169.254.1.1',mask=16},{address='224.0.0.1',mask=4}})
local zones={{name='trusted',network={'edge'}},{name='guest',network='edge'}}
local normalized=assert(inventory.normalize(snap,zones))
assert(#normalized.networks[1].addresses==4, 'unsafe address offered or delegated local missing')
local scopes={}
for _,a in ipairs(normalized.networks[1].addresses) do scopes[a.address]=a.scope end
assert(scopes['fd00::1']=='ula' and scopes['fd01::1']=='ula' and scopes['2001:db8::1']=='gua')
local binding={network='edge',family='ipv4',address='192.168.8.1'}
local v,e=inventory.resolve(binding,normalized)
check_error(v,e,'ZONE_AMBIGUOUS','access_profile.listeners.network')
local one=assert(inventory.normalize(snap,{{name='trusted',network={'edge'}}}))
assert(inventory.resolve(binding,one).device=='br-edge')
binding.address='192.168.8.2'
v,e=inventory.resolve(binding,one)
check_error(v,e,'ADDRESS_UNAVAILABLE','access_profile.listeners.address')
binding.network='absent'
v,e=inventory.resolve(binding,one)
check_error(v,e,'NETWORK_UNAVAILABLE','access_profile.listeners.network')
local duplicate=fixture(); duplicate.interface[2]=duplicate.interface[1]
v,e=inventory.resolve({network='edge',family='ipv4',address='192.168.8.1'},assert(inventory.normalize(duplicate,{})))
check_error(v,e,'NETWORK_UNAVAILABLE','access_profile.listeners.network')
local down=fixture(); down.interface[1].up=false
v,e=inventory.resolve({network='edge'},assert(inventory.normalize(down,{})))
check_error(v,e,'NETWORK_UNAVAILABLE','access_profile.listeners.network')
local reversed=assert(inventory.normalize(snap,{zones[2],zones[1]}))
assert(reversed.summary==normalized.summary, 'summary order instability')
for _,bad in ipairs({{}, {interface='bad'}, {interface={[2]={}}}}) do
  v,e=inventory.normalize(bad,{})
  check_error(v,e,'NETWORK_UNAVAILABLE','access_profile.listeners.network')
end
v,e=inventory.normalize(fixture({{address='999.2.3.4',mask=24}}),{})
check_error(v,e,'NETWORK_UNAVAILABLE','access_profile.listeners.network')
print('PASS classification, delegated local IPv6, exclusion, ambiguity, down/missing, malformed, deterministic summary')
local malformed6=fixture()
malformed6.interface[1]['ipv6-address']={{address='2001:::1',mask=64}}
v,e=inventory.normalize(malformed6,{})
check_error(v,e,'NETWORK_UNAVAILABLE','access_profile.listeners.network')
local saved_ubus=package.loaded.ubus
package.loaded.ubus={connect=function() return nil end}
v,e=inventory.collect()
package.loaded.ubus=saved_ubus
check_error(v,e,'NETWORK_UNAVAILABLE','access_profile.listeners.network')
print('PASS malformed IPv6 and real-adapter dependency failure returns structured unknown')

-- Exercise actual canonical normalization, not a manually expanded listener.
local canonical = dofile(root .. '/canonical-v2.lua')
local config = assert(canonical.validate({schema_version=2, services={},
  access_profile={listeners={{listener_id='v6',family='ipv6',network='edge',address='FD00::1',port=18443}}}}))
local canonical_binding = config.access_profile.listeners[1]
assert(canonical_binding.address=='fd00:0:0:0:0:0:0:1')
local resolved, semantic_error = inventory.resolve(canonical_binding, one)
assert(resolved and resolved.address=='fd00::1', 'canonical IPv6 binding must resolve compressed inventory: '..tostring(semantic_error and semantic_error.error_code))
assert(scopes['fd00::1']=='ula', 'inventory must retain readable source addresses')
print('PASS canonical normalized IPv6 binding resolves compressed inventory exactly')

local alternate=fixture()
alternate.interface[1]['ipv6-address'][1].address='FD00:0000:0:0:0000:0:0:0001'
alternate.interface[1]['ipv6-address'][2].address='2001:0DB8:0:0:0:0:0:0001'
local equivalent=assert(inventory.normalize(alternate,{{name='trusted',network={'edge'}}}))
assert(equivalent.summary==one.summary, 'equivalent IPv6 spellings must have identical inventory summary')
alternate.interface[1]['ipv6-address'][#alternate.interface[1]['ipv6-address']+1]={address='fd00::1',mask=64}
local deduped=assert(inventory.normalize(alternate,{{name='trusted',network={'edge'}}}))
assert(#deduped.networks[1].addresses==#one.networks[1].addresses, 'equivalent IPv6 hosts must be deduplicated')
assert(deduped.summary==one.summary, 'duplicate equivalent host must not alter inventory summary')
for _,address in ipairs({'fd00::2','fd00::1/64','fd00::1%br-edge','::ffff:192.168.8.1','0:0:0:0:0:ffff:c0a8:801','fd00:::1'}) do
  local rejected,why=inventory.resolve({network='edge',family='ipv6',address=address},one)
  check_error(rejected,why,'ADDRESS_UNAVAILABLE','access_profile.listeners.address')
end
assert(inventory.resolve({network='edge',family='ipv6',address='2001:DB8:0:0::1'},one))
print('PASS semantic summary, deduplication, GUA/case variants and exact-host no-CIDR/no-mapped rejection')

-- Lua # may point beyond a hole; ipairs then silently drops later records.
local sparse=fixture()
for i=2,4 do sparse.interface[i]=sparse.interface[1] end
sparse.interface[2]=nil
v,e=inventory.normalize(sparse,{})
check_error(v,e,'NETWORK_UNAVAILABLE','access_profile.listeners.network')
print('PASS sparse interior-hole interface array fails closed independently of Lua length')
local function hole(value)
  local values={value,value,value,value}; values[2]=nil; return values
end
for _,field in ipairs({'ipv4-address','ipv6-address','ipv6-prefix-assignment'}) do
  local s=fixture(); s.interface[1][field]=hole(s.interface[1][field][1])
  v,e=inventory.normalize(s,{})
  check_error(v,e,'NETWORK_UNAVAILABLE','access_profile.listeners.network')
end
v,e=inventory.normalize(fixture(),hole({name='trusted',network={'edge'}}))
check_error(v,e,'NETWORK_UNAVAILABLE','access_profile.listeners.network')
v,e=inventory.normalize(fixture(),{{name='trusted',network=hole('edge')}})
check_error(v,e,'NETWORK_UNAVAILABLE','access_profile.listeners.network')
local changed=fixture(); changed.interface[1]['ipv6-address'][1].address='fd00::2'
assert(assert(inventory.normalize(changed,{{name='trusted',network={'edge'}}})).summary~=one.summary)
for _,n in ipairs(live.networks) do
  if n.up and n.device~='' and #n.zones==1 then
    for _,a in ipairs(n.addresses) do
      if a.family=='ipv6' then
        local c=assert(canonical.validate({schema_version=2,services={},access_profile={listeners={
          {listener_id='live6',family='ipv6',network=n.network,address=a.address,port=18443}}}}))
        assert(inventory.resolve(c.access_profile.listeners[1],live))
        print('PASS real IPv6 canonical binding on '..n.network)
      end
    end
  end
end
print('PASS sparse address/prefix/zone/network arrays and genuine-address summary sensitivity')
