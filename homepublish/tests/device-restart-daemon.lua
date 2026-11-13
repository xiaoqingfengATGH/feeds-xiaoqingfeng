local root=assert(arg[1]);local runtime=assert(arg[2]);package.path=root..'/?.lua;'..package.path
local fs=require('nixio.fs');local n=require('nixio');local J=require('product-json');assert(fs.mkdir(root..'/store','700'))
local function put(name,b)local f=assert(io.open(root..'/'..name,'w'));f:write(b);f:close()end
put('product-system-provider.lua',[[local generation
return {runtime_plan=function(c)return c end,plan=function(c)return c end,start=function(p,g,t)generation=g;return true end,readiness=function()return true,{web={ready=true,generation=generation}}end,stop=function()return true end,renew=function()return true end}
]])
put('product-ddns.lua',"return {ensure=function()local f=assert(io.open('"..root.."/dns','a'));f:write('ensure\\n');f:close();return {results={},warnings={}}end}")
local P=require('product-provider')
local config={schema_version=2,access_profile={listeners={{listener_id='v4',family='ipv4',network='lan',address='192.168.1.2',port=18443}}},services={{service_id='web',name='Web',enabled=true,type='http_proxy',hostname='old.example.com',upstream_scheme='http',backend={addressFamily='ipv4',host='192.168.1.3',port=8080},dns={mode='ddns_go',profile_id='p:1',record_types={'A'}}}},publication_policy={mode='temporary',temporary_duration=600,boot_restore=false}}
assert(P.handle{action='save',expected_revision=0,config=config})
put('driver',[[#!/bin/sh
# rc.common's default restart does manual stop/start unless overridden.
restart() { echo rc.common-default-restart-would-stop >&2; return 1; }
start() { start_service; }
. ']]..root..[[/init'
procd_lock() { :; }
procd_open_instance() { :; }
procd_set_param() { :; }
procd_close_instance() {
 if test -f ']]..root..[[/pid'; then
  old=$(cat ']]..root..[[/pid')
  if test -e /proc/$old/stat && ! grep -q ') Z ' /proc/$old/stat; then echo old-daemon-still-alive >&2; return 1; fi
 fi
 /usr/bin/lua ']]..root..[[/product-daemon.lua' >']]..root..[[/daemon.log' 2>&1 < /dev/null &
 echo $! > ']]..root..[[/pid'
}
procd_kill() { kill "$(cat ']]..root..[[/pid')"; }
case "$1" in start) start;; restart) restart;; stop) stop_service;procd_kill homepublish;; esac
]])
local private_init
if arg[3]=='procd' then
 local f=assert(io.open(root..'/init'));local init=f:read('*a');f:close()
 local name='homepublish-restart-'..root:match('restart%-(%w+)$')
 private_init=root..'/'..name
 put(name,(init:gsub('procd_kill homepublish','procd_kill '..name)))
 put('driver',"#!/bin/sh\nexec /bin/sh /etc/rc.common '"..private_init.."' \"$1\"\n")
end
local function shell(action)local rc=os.execute("sh '"..root.."/driver' "..action);assert(rc==0,'init '..action..' failed')end
local function request(q)return J.decode(require('product-channel').request(J.encode(q)))end
local function await()
 for i=1,15 do if fs.lstat(runtime..'/control.sock') then local ok,s=pcall(request,{action='status'});if ok and s.runtime then return s end end;n.nanosleep(1) end
 error('private daemon unavailable')
end
local function cleanup()
 if private_init then os.execute("sh '"..root.."/driver' shutdown");n.nanosleep(2)
 else os.execute("test ! -f '"..root.."/pid' || kill $(cat '"..root.."/pid') 2>/dev/null");n.nanosleep(1) end
 fs.unlink(runtime..'/control.sock');require('product-restart').clear();assert(fs.rmdir(runtime),'private runtime cleanup')
end
local ok,err=pcall(function()
 shell('start');await();local s=request{action='start',revision=1,approved=true};assert(s.runtime.phase=='running');local expiry=s.runtime.expires_at
 config.services[1].hostname='pending.example.com';local saved
 for i=1,10 do saved=P.handle{action='save',expected_revision=1,config=config};if saved then break end;n.nanosleep(1) end
 assert(saved,'private concurrent save unavailable')
 shell('restart');s=await()
 assert(s.runtime.phase=='running','private daemon init restart must recover boot_restore=false')
 assert(s.active_revision==1 and s.saved_revision==2 and s.active_config.services[1].hostname=='old.example.com' and s.runtime.expires_at==expiry,'active snapshot and deadline preserved')
 assert(not fs.lstat(runtime..'/restart'),'marker consumed')
 local f=assert(io.open(root..'/dns'));local dns=f:read('*a');f:close();assert(dns=='ensure\n','restart must not perform DDNS')
 if private_init then
  -- A later ordinary start must not inherit even a valid armed abandoned marker.
  shell('shutdown');n.nanosleep(2)
  local R=require('product-restart');assert(R.prepare(assert(P.handle{action='status'})))
  local f=assert(io.open(runtime..'/restart'));local t=J.decode(f:read('*a'));f:close();t.ready=true;t.pid=4194304
  f=assert(io.open(runtime..'/restart','w'));f:write(J.encode(t));f:close()
  shell('start');s=await();assert(s.runtime.phase=='stopped' and s.desired_state.state=='enabled' and not fs.lstat(runtime..'/restart'),'ordinary start discards abandoned capability')
 end
 shell('stop');n.nanosleep(1);shell('start');s=await();assert(s.desired_state.manual_stop_latch and s.runtime.phase=='stopped','manual init stop unchanged')
 shell('restart');s=await();assert(s.desired_state.manual_stop_latch and s.runtime.phase=='stopped','restart must preserve manual disabled')
end)
cleanup();assert(ok,err);print('RESTART_DAEMON_GREEN')
