package.path='/usr/share/homepublish/?.lua;'..package.path
package.cpath='/tmp/homepublish-tcp-p3/?.so;'..package.cpath
local J=require('product-json');local P=require('product-provider');local C=require('product-controller').new(require('product-system-provider'))
local q=J.decode(io.read('*a'));local r
if q.action=='start' then r=C.start(q.revision,q.approved) elseif q.action=='stop' then r=C.stop() else r=assert(P.handle(q,true)) end
io.write(J.encode(r),'\n')
