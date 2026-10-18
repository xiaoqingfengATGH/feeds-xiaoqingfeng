-- Private journal JSON CLI; provider is the unchanged installed module.
package.path='/usr/share/homepublish/?.lua;'..package.path
dofile('/tmp/homepublish-tcp-p3/device-legacy-lua-scope.lua')
local J=require('product-json');local P=require('product-provider')
local provider=require('product-device-provider')
assert(type(provider.runtime_plan)=='function','installed v2 adapter capability missing')
local C=require('product-controller').new(provider)
local q=J.decode(io.read('*a'));local r
if q.action=='start' then r=C.start(q.revision,q.approved)
elseif q.action=='apply' then r=C.apply(q.revision,q.approved)
elseif q.action=='stop' then r=C.stop()
elseif q.action=='status' then r=P.handle(q)
else r=P.handle(q,true) end
io.write(J.encode(assert(r)),'\n')
