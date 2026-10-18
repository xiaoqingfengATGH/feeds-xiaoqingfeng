-- Device-only controller public JSON boundary, fixed adapter and private native store.
package.path='/tmp/homepublish-tcp-p3/?.lua;/usr/share/homepublish/?.lua;'..package.path
dofile('/tmp/homepublish-tcp-p3/device-legacy-lua-scope.lua')
local J=require('product-json');local P=require('product-provider')
local C=require('product-controller').new(require('device-tcp-p3-controller-adapter'))
local q=J.decode(io.read('*a'));local r
if q.action=='start' then r=C.start(q.revision,q.approved)
elseif q.action=='stop' then r=C.stop()
elseif q.action=='status' then r=P.handle(q)
else r=P.handle(q,true) end
io.write(J.encode(assert(r)),'\n')
