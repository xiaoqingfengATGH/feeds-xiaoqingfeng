-- Real public CLI/RPC with fixed Lua store and invocation-local network faults.
local root='/root/homepublish-lua-store/p1'
local source='/usr/share/homepublish'
local scope=dofile(root..'/device-p1-lua-scope.lua')
local J=dofile(source..'/product-json.lua')
local W=dofile(source..'/product-wire.lua')
local function put(path,bytes) local f=assert(io.open(path,'wb'));assert(f:write(bytes));assert(f:close()) end
local function read(path) local f=assert(io.open(path,'rb'));local b=f:read('*a');f:close();return b end
local function call(action,body,mode)
 put(root..'/request.json',body)
 assert(os.execute('lua '..source..'/product-rpc.lua '..action..' < '..root..'/request.json > '..root..'/request.wire')==0)
 local prefix="dofile('"..root.."/device-p1-lua-scope.lua');"
 if mode=='connect' then prefix=prefix.."package.preload.ubus=function() return {connect=function() return nil end} end;"
 elseif mode=='firewall' then prefix=prefix.."package.preload.uci=function() return {cursor=function() return {load=function() return false end,unload=function()end}end}end;"
 elseif mode=='malformed' then prefix=prefix.."package.preload.ubus=function()return {connect=function()return {call=function()return {interface='bad'}end,close=function()end}end}end;" end
 put(root..'/fault-cli.lua',prefix.."arg={};dofile('"..source.."/product-cli.lua')")
 local status=os.execute('lua '..root..'/fault-cli.lua < '..root..'/request.wire > '..root..'/response.wire 2> '..root..'/stderr')
 assert(os.execute('lua '..source..'/product-rpc.lua response < '..root..'/response.wire > '..root..'/response.json')==0)
 local raw=read(root..'/response.json');print('OBSERVE '..(mode or action)..' cli_exit='..status..' '..raw)
 assert(read(root..'/stderr')=='','private stack leaked')
 assert(not raw:find(root,1,true),'private path leaked')
 return J.decode(raw),status
end
for _,mode in ipairs({'connect','firewall','malformed'}) do
 local r,status=call('network_inventory','{}',mode)
 assert(status~=0 and r.error_code=='NETWORK_UNAVAILABLE' and r.retryable==true)
 print('PASS full transport '..mode)
end
assert(scope.store.transaction(function()return 'corrupt journal',true end))
local r,status=call('save','{"expected_revision":0,"config":{"schema_version":2,"services":[],"access_profile":{"listeners":[]},"publication_policy":{"mode":"continuous","boot_restore":false}}}')
assert(status~=0 and r.error_code=='STATE_UNKNOWN' and r.field=='state' and r.retryable==true)
print('PASS actual Lua corrupt journal STATE_UNKNOWN')
assert(os.execute('chmod 755 '..root..'/store')==0)
print('PASS mode-agnostic store directory')
print('TOTAL Lua full transport fault regressions PASS')
