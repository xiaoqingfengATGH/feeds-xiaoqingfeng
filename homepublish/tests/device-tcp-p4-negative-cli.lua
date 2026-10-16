-- Fixed test-only inventory faults; unchanged installed provider/preflight code.
-- Does not alter system interfaces, firewall, UCI files or session authorization.
local mode=arg[1]
local late=mode=='late-addressgone'
if late then mode='addressgone' end
local fault=not late
assert(mode=='addressgone' or mode=='zonegone' or mode=='readfail')
local ubus=require('ubus');local uci=require('uci')
local connect=ubus.connect
ubus.connect=function(...)
 local conn=assert(connect(...))
 return {close=function() return conn:close() end,call=function(_,object,method,args)
  if object=='network.interface' and method=='dump' then
   if fault and mode=='readfail' then error('fixed inventory read failure') end
   local snapshot=conn:call(object,method,args)
   if fault and mode=='addressgone' then
    for _,n in ipairs(snapshot.interface) do
     if n.interface=='lan' then n['ipv6-address']={};n['ipv6-prefix-assignment']={} end
    end
   end
   return snapshot
  end
  return conn:call(object,method,args)
 end}
end
local cursor=uci.cursor
uci.cursor=function(...)
 local c=cursor(...)
 return {load=function(_,...)return c:load(...)end,unload=function(_,...)return c:unload(...)end,
 foreach=function(_,config,kind,callback)
  return c:foreach(config,kind,function(z)
   if fault and mode=='zonegone' and config=='firewall' and kind=='zone' then return end
   return callback(z)
  end)
 end}
end
if late then
 package.path='/usr/share/homepublish/?.lua;'..package.path
 package.cpath='/tmp/homepublish-tcp-p3/?.so;'..package.cpath
 local J=require('product-json');local C=require('product-controller').new(require('product-device-provider'))
 local q=J.decode(io.read('*a'));assert(q.action=='start' and q.revision==1 and q.approved==true)
 local before=C.start(1,true);assert(before.runtime.phase=='running')
 fault=true;require('nixio').nanosleep(31)
 local after=C.tick(before.runtime.generation)
 io.write(J.encode({before=before,after=after}),'\n')
else
 dofile('/tmp/homepublish-tcp-p3/device-tcp-p4-installed-cli.lua')
end
