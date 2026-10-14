-- SPDX-License-Identifier: Apache-2.0
-- Fixed procd controller, canonical journal authority, root-local test channel.
assert(#arg==0,'no daemon arguments')
package.path='/usr/share/homepublish/?.lua;'..package.path
local N=require('homepublish_device');local W=require('product-wire')
local C=require('product-controller').new(require('product-device-provider'))
N.listen();C.restore()
while true do
 local bytes=N.receive()
 if bytes then
  local ok,response=pcall(function()
   local q=W.decode(bytes);assert(type(q)=='table','request')
   for k in pairs(q)do assert(k=='action' or k=='revision' or k=='approved','unknown field')end
   if q.action=='start' then return C.start(q.revision,q.approved)
   elseif q.action=='apply' then return C.apply(q.revision,q.approved)
   elseif q.action=='stop' then return C.stop()
   elseif q.action=='status' then return C.status()
   else return {error='unsupported device-test operation'}end
  end)
  N.reply(W.encode(ok and response or {error='device-test request rejected'}))
 end
 C.tick()
end
