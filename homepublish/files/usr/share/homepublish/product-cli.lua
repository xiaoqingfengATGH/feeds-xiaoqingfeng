-- SPDX-License-Identifier: Apache-2.0
-- Fixed stdin protocol only; never accepts paths, commands or Lua source.
local function fail(message)
 io.stderr:write(message..'\n'); os.exit(1)
end
if #arg~=0 then fail('unsupported arguments') end
local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
local wire=dofile(source..'/product-wire.lua')
local provider=dofile(source..'/product-provider.lua')
local bytes=io.stdin:read(262145)
local decoded,request=pcall(wire.decode,bytes)
if not decoded then fail('invalid request wire') end
local handled,response,err
local enabled=io.open('/etc/homepublish/device-test/enabled','r')
if enabled and ({start=true,apply=true,stop=true,status=true})[request.action] then
 enabled:close()
 package.path=source..'/?.lua;'..package.path
 local J=require('product-json')
 handled,response=pcall(function()return J.decode(require('product-channel').request(J.encode(request)))end)
else
 if enabled then enabled:close() end
 handled,response,err=pcall(provider.handle,request)
end
if not handled then fail('invalid request') end
if not response then fail(err or 'request failed') end
io.stdout:write(wire.encode(response),'\n')
