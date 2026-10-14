-- SPDX-License-Identifier: Apache-2.0
-- Installed, root-only device test profile. Production/public activation denied.
local R=require('direct-renderer');local I=require('device-integrations');local M={}
local active_plan,next_check
local function cert_identity()
 local f=io.popen('sha256sum /etc/homepublish/device-test/cert.pem 2>/dev/null');if not f then return nil end
 local v=f:read('*l');f:close();return v and v:match('^(%x+)')
end
local root='/tmp/homepublish-device/runtime'
local function run(s)return os.execute(s)==0 end
local function write(name,bytes)local f=assert(io.open(root..'/'..name,'w'));assert(f:write(bytes));assert(f:close())end
function M.plan(c)
 c=require('product-wire').decode(require('product-wire').encode(c))
 if #c.services~=1 or #c.access_profile.listeners~=1 then return nil,'device test scope denied' end
 local s=c.services[1];local l=c.access_profile.listeners[1]
 if s.service_id~='fixture' or s.hostname~='service.home' or s.certificate_ref~='import:fixture' or (s.backend.host~='127.0.0.1' and not (s.backend.addressFamily=='hostname' and s.backend.host=='localhost.lan')) or (s.backend.port~=49285 and s.backend.port~=49286) or s.authentication_review.authentication~='confirmed' or s.authentication_review.management then return nil,'device test service denied' end
 if #c.access_profile.methods_allowed~=1 or c.access_profile.methods_allowed[1]~='manual_ipv4' or l.family~='ipv4' or l.address~='192.168.1.2' or l.interface~='br-lan' or l.zone~='lan' or l.internal_port~=49284 or l.external_port~=49284 then return nil,'device test listener denied' end
 -- Canonical intentionally disallows loopback publication. This server-owned
 -- profile narrows the approved model to loopback; it never broadens it.
 l.address='127.0.0.1';l.interface='lo'
 local plan,e=R.render(c,{resolve=I.resolve,authorize_listener=function(v)return v.address=='127.0.0.1' and v.internal_port==49284 end,authorize_backend=function(v)return v=='127.0.0.1' or v=='::1' end,healthy=function()return true end,certificate_snapshot=function()return {certificate='/tmp/homepublish-device/runtime/cert.pem',key='/tmp/homepublish-device/runtime/key.pem'}end})
 if plan then plan.backend=s.backend;plan.cert_identity=cert_identity() end
 return plan,e
end
function M.start(plan,g,t)
 if not run("test -f /etc/homepublish/device-test/enabled") then return false end
 if not run("mkdir -p "..root.." && chmod 0700 "..root.." && cp /etc/homepublish/device-test/cert.pem /etc/homepublish/device-test/key.pem "..root.."/ && chmod 0600 "..root.."/*.pem") then return false end
 -- Root master reads the private key; normal Nginx workers are nobody.
 write('nginx.conf','user nobody nogroup;\n'..plan.configuration)
 if not run('/usr/sbin/nginx -t -p '..root..'/ -c nginx.conf >'..root..'/config-test.log 2>&1') then return false end
 local ok=run('/etc/init.d/homepublish-nginx start');if ok then active_plan=plan;next_check=os.time()+30 end;return ok
end
function M.readiness()
 for i=1,30 do
  if os.execute("/usr/bin/curl -q --noproxy '*' --connect-timeout 1 --max-time 1 --cacert /etc/homepublish/device-test/cert.pem --resolve service.home:49284:127.0.0.1 --fail --silent --output /dev/null https://service.home:49284/")==0 then return true end
  os.execute('sleep 1')
 end
 return false
end
function M.renew()
 -- A changed certificate or DNS selection closes this generation; controller
 -- bounded recovery re-plans approved ACTIVE config, never pending saved edits.
 if active_plan and os.time()>=(next_check or 0) then
  next_check=os.time()+30
  if not active_plan.cert_identity or cert_identity()~=active_plan.cert_identity then return false end
  if active_plan.backend.addressFamily=='hostname' then
   local b=require('direct-backend').select(active_plan.backend,{resolve=I.resolve,authorize_backend=function(a)return a=='127.0.0.1' or a=='::1' end,healthy=function()return true end})
   if not b or b.address~=active_plan.backends[1].address then return false end
  end
 end
 -- Ordinary health observation, not a short capability/authorization heartbeat.
 return run("test -f "..root.."/nginx.pid && kill -0 $(cat "..root.."/nginx.pid)")
end
function M.stop()
 active_plan=nil;next_check=nil
 local stopped=run('/etc/init.d/homepublish-nginx stop')
 if not stopped and M.renew() then return false end
 -- procd terminates the master, which terminates its workers and connections.
 for i=1,10 do
  if not M.renew() then
   return run('rm -rf '..root)
  end
  os.execute('sleep 1')
 end
 return false
end
return M
