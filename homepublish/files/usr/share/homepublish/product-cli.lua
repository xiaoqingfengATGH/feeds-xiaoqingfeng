-- SPDX-License-Identifier: Apache-2.0
-- Fixed stdin protocol only; never accepts paths, commands or Lua source.
local wire
local function fail(message,code)
 if wire then io.stdout:write(wire.encode({error='Request rejected or state unavailable',error_code=code or 'INVALID_CONFIG',field=code=='STATE_UNKNOWN' and 'state' or 'request',retryable=code=='STATE_UNKNOWN'}),'\n') else io.stderr:write('Request rejected\n') end
 os.exit(1)
end
if #arg~=0 then fail('unsupported arguments') end
local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
wire=dofile(source..'/product-wire.lua')
local provider=dofile(source..'/product-provider.lua')
local bytes=io.stdin:read(262145)
local decoded,request=pcall(wire.decode,bytes)
if not decoded then fail('invalid request wire') end
local handled,response,err
if ({start=true,apply=true,stop=true,status=true})[request.action] then
 package.path=source..'/?.lua;'..package.path
 local J=require('product-json')
 handled,response=pcall(function()return J.decode(require('product-channel').request(J.encode(request)))end)
else
 handled,response,err=pcall(provider.handle,request,true)
end
if not handled then fail('invalid request') end
if not response then
 -- Inventory failures are already typed. Never call string methods on them,
 -- and export only the fixed public shape (not arbitrary internal metadata).
 if type(err)=='table' and err.error_code=='NETWORK_UNAVAILABLE' then
  io.stdout:write(wire.encode({error_code='NETWORK_UNAVAILABLE',field='access_profile.listeners.network',error='Network inventory unavailable or malformed',retryable=err.retryable==true}),'\n')
  os.exit(1)
 end
 -- Exact native-store vocabulary, not substring heuristics: notably a failed
 -- directory fsync happens AFTER rename and must direct the caller to readback.
 local store_errors={
  ['store failure']=true,['unsafe store directory']=true,
  ['unsafe store lock']=true,['store busy']=true,
  ['unsafe store state']=true,['unsafe store candidate']=true,
  ['invalid stored state or request']=true,
  ['invalid migration backup request']=true,
  ['candidate close failed']=true,['migration backup failed']=true,
  ['commit durability unknown; read status']=true
 }
 fail('request failed',type(err)=='string' and store_errors[err] and 'STATE_UNKNOWN' or 'INVALID_CONFIG')
end
io.stdout:write(wire.encode(response),'\n')
