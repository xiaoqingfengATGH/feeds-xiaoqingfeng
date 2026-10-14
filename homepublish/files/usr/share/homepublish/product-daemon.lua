-- SPDX-License-Identifier: Apache-2.0
-- Fixed procd controller, canonical journal authority, root-local test channel.
assert(#arg==0,'no daemon arguments')
package.path='/usr/share/homepublish/?.lua;'..package.path
local N=require('product-channel');local W=require('product-json')
local C=require('product-controller').new(require('product-device-provider'))
local server=N.listen();C.restore()
while true do
 local bytes,client=N.receive(server)
 if bytes then
  local ok,response=pcall(function()
   local q=W.decode(bytes);assert(type(q)=='table','request')
   for k in pairs(q)do assert(k=='action' or k=='revision' or k=='approved','unknown field')end
   if q.action=='start' then return C.start(q.revision,q.approved)
   elseif q.action=='apply' then return C.apply(q.revision,q.approved)
   elseif q.action=='stop' then return C.stop()
   elseif q.action=='status' then local s=C.status();s.device_test=true;return s
   else return {error='unsupported device-test operation'}end
  end)
  N.reply(client,W.encode(ok and response or {error='device-test request rejected'}))
 end
 C.tick()
end
