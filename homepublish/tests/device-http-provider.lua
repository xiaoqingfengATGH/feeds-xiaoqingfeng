-- SPDX-License-Identifier: Apache-2.0
-- Provider allocation contract; dependency stubs avoid changing runtime or firewall.
local source=assert(arg[1]);package.path=source..'/?.lua;'..package.path
local options
package.loaded['product-v2-runtime']={new=function(o)options=o;return {runtime_plan=function(c)return c end} end}
package.loaded['product-firewall']={new=function()return {} end}
local old_execute=os.execute;os.execute=function()return 0 end
local next_port=0;local closed=0
-- Collision sequence includes entry, dedicated, primary and backup target ports.
local candidates={8443,9000,8080,8081,41001,41001,41002,41002,41003}
package.loaded.nixio={socket=function(f,k)
 assert(f=='inet' and k=='stream');local chosen
 return {bind=function(_,host,p)assert(host=='127.0.0.1' and p==0);next_port=next_port+1;chosen=candidates[next_port];return chosen~=nil end,
 getsockname=function()return '127.0.0.1',chosen end,close=function()closed=closed+1 end}
end}
require('product-system-provider')
local ports=assert(options.mixed_ports({access_profile={listeners={{port=8443}}},services={{listen_port=9000,backend={port=8080,backup={port=8081}}}}}))
assert(ports.http and ports.https and ports.reject,'HTTP requires its own trusted internal port')
assert(ports.http~=ports.https and ports.http~=ports.reject and ports.https~=ports.reject,'internal ports must be distinct')
for _,p in pairs(ports) do assert(p~=8443 and p~=9000 and p~=8080 and p~=8081,'internal port collides with configured endpoint') end
assert(closed==next_port,'all allocation sockets must close')
os.execute=old_execute
print('HTTP_PROVIDER_PORTS_GREEN')
