-- Fixed test-only dependency scope. Refuse native providers before any lifecycle call.
local source='/usr/share/homepublish'
package.path=source..'/?.lua;'..package.path
local f=assert(io.open(source..'/product-provider.lua','rb'))
local bytes=assert(f:read('*a'));assert(f:close())
assert(bytes:find("local store=dofile(source..'/product-store.lua')",1,true),'production Lua store required; refusing native fallback')
assert(not package.loaded['product-provider'],'provider already loaded before isolation')
local store=dofile(source..'/product-store-core.lua').new('/root/homepublish-lua-store/legacy-controller-store')
local original=dofile
_G.dofile=function(path)
 if path==source..'/product-store.lua' then return store end
 return original(path)
end
local ok,result=pcall(require,'product-provider')
_G.dofile=original
assert(ok,result)
assert(package.loaded.homepublish_store==nil,'native store loaded')
return result
