-- Duplicate Stop must not submit a delete for absent procd registration.
package.path=arg[1]..'/?.lua;'..package.path
local original=io.popen
io.popen=function(command)
 if command:find('ubus call service list',1,true) then return {read=function()return '{}' end,close=function()return true end} end
 return original(command)
end
local commands={};os.execute=function(s)commands[#commands+1]=s;return 0 end
local P=arg[2] and dofile(arg[2]) or require('product-device-provider')
assert(P.stop());assert(P.stop())
for _,s in ipairs(commands) do assert(not s:find('/etc/init.d/homepublish-nginx stop',1,true),'absent service delete submitted');assert(not s:find('$(cat',1,true),'racy PID shell read') end
print('PASS idempotent absent-service Stop without PID shell race')
