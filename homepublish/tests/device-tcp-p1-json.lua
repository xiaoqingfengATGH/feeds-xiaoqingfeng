-- Public JSON shape assertions run on device; inspect bytes, not Lua #table.
local root=assert(arg[1]);local J=dofile(root..'/product-json.lua')
local W=dofile(root..'/product-wire.lua')
local N=dofile(root..'/network-inventory.lua')
local P=dofile(root..'/preflight.lua')
local config={schema_version=2,services={},access_profile={listeners={}}}
local pre=P.check(config,7)
local inventory=assert(N.normalize({interface={{interface='empty',up=false,device='eth9'}}},{}))
local function public(value) return J.encode(W.decode(W.encode(value))) end
local bytes=public(pre)
for _,key in ipairs({'services','endpoints','warnings'}) do assert(bytes:find('"'..key..'":%[%]'),'public empty array became object: '..key) end
bytes=public(inventory)
for _,key in ipairs({'addresses','zones'}) do assert(bytes:find('"'..key..'":%[%]'),'inventory empty array became object: '..key) end
assert(public(assert(N.normalize({interface={}},{}))):find('"networks":%[%]'))
assert(J.encode({runtime={services={}}}):find('"services":{}'),'runtime service map became array')
for _,bad in ipairs({{[1]='a',[3]='b'},{[1]='a',named='b'}}) do
 assert(not pcall(J.encode,{warnings=bad}),'sparse or mixed array silently truncated')
end
print('PASS actual preflight/inventory empty JSON arrays, runtime service object, sparse/mixed refusal')
print('PUBLIC_PREFLIGHT '..public(pre))
print('PUBLIC_INVENTORY '..public(inventory))
