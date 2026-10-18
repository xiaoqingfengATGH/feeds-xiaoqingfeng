-- Fixed P1 scope: no caller-controlled root and no production store evaluation.
local source='/usr/share/homepublish'
local root='/root/homepublish-lua-store/p1/store'
local f=assert(io.open(source..'/product-provider.lua','rb'));local bytes=f:read('*a');f:close()
assert(bytes:find("local store=dofile(source..'/product-store.lua')",1,true),'production Lua store required')
assert(not package.loaded.homepublish_store,'native store already loaded')
local store=dofile(source..'/product-store-core.lua').new(root)
local original=dofile
_G.dofile=function(path)
 if path==source..'/product-store.lua' then return store end
 return original(path)
end
-- CLI status/stop use a process-local channel adapter, not the live daemon.
package.preload['product-channel']=function()
 local J=original(source..'/product-json.lua')
 return {request=function(raw)
  local response,err=original(source..'/product-provider.lua').handle(J.decode(raw),true)
  return J.encode(response or {error_code='STATE_UNKNOWN',field='state',retryable=true,error='Request rejected or state unavailable'})
 end}
end
package.path=source..'/?.lua;'..package.path
return {store=store,provider=function()return original(source..'/product-provider.lua')end,root=root}
