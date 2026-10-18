package.path='/usr/share/homepublish/?.lua;'..package.path
-- Test-only dependency injection: fixed private root, never selected by RPC.
local source='/usr/share/homepublish'
local provider_file=assert(io.open(source..'/product-provider.lua','rb'))
local provider_bytes=assert(provider_file:read('*a'));assert(provider_file:close())
assert(provider_bytes:find("local store=dofile(source..'/product-store.lua')",1,true),'Lua provider must be deployed before matrix fixture; refusing native fallback')
local core=dofile(source..'/product-store-core.lua')
local store=core.new('/root/homepublish-lua-store/matrix-store')
local original_dofile=dofile
_G.dofile=function(path)
 if path==source..'/product-store.lua' then return store end
 return original_dofile(path)
end
local J=require('product-json');local P=require('product-provider');local C=require('product-controller').new(require('product-system-provider'))
_G.dofile=original_dofile
assert(package.loaded.homepublish_store==nil,'native store must not load')
local q=J.decode(io.read('*a'));local r
if q.action=='start' then r=C.start(q.revision,q.approved) elseif q.action=='stop' then r=C.stop() else r=assert(P.handle(q,true)) end
io.write(J.encode(r),'\n')
