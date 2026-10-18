-- Private journal JSON CLI; provider is the unchanged installed module.
package.path='/usr/share/homepublish/?.lua;'..package.path
dofile('/tmp/homepublish-tcp-p3/device-legacy-lua-scope.lua')
local J=require('product-json');local P=require('product-provider')
local provider=require('product-device-provider')
assert(type(provider.runtime_plan)=='function','installed v2 adapter capability missing')
local readiness=provider.readiness
provider.readiness=function(p)
 local ok,services=readiness(p)
 local marker=io.open('/tmp/homepublish-tcp-p3/controller-stale-generation')
 if marker then marker:close();for _,s in pairs(services or {}) do s.generation=0 end end
 return ok,services
end
local C=require('product-controller').new(provider)
local q=J.decode(io.read('*a'));local r
if q.action=='start' then r=C.start(q.revision,q.approved)
elseif q.action=='stop' then r=C.stop()
elseif q.action=='status' then r=P.handle(q)
else r=P.handle(q,true) end
io.write(J.encode(assert(r)),'\n')
