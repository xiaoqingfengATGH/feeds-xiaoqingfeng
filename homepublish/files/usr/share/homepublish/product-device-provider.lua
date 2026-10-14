-- SPDX-License-Identifier: Apache-2.0
-- Installed, root-only device test profile. Production/public activation denied.
local N=require('homepublish_device');local R=require('direct-renderer');local M={}
function M.plan(c)
 if #c.services~=1 or #c.access_profile.listeners~=1 then return nil,'device test scope denied' end
 local s=c.services[1];local l=c.access_profile.listeners[1]
 if s.service_id~='fixture' or s.hostname~='service.home' or s.certificate_ref~='import:fixture' or s.backend.host~='127.0.0.1' or (s.backend.port~=49285 and s.backend.port~=49286) or s.authentication_review.authentication~='confirmed' or s.authentication_review.management then return nil,'device test service denied' end
 if #c.access_profile.methods_allowed~=1 or c.access_profile.methods_allowed[1]~='manual_ipv4' or l.family~='ipv4' or l.address~='192.168.1.2' or l.interface~='br-lan' or l.zone~='lan' or l.internal_port~=49284 or l.external_port~=49284 then return nil,'device test listener denied' end
 -- Canonical intentionally disallows loopback publication. This server-owned
 -- profile narrows the approved model to loopback; it never broadens it.
 l.address='127.0.0.1';l.interface='lo'
 return R.render(c,{authorize_listener=function(v)return v.address=='127.0.0.1' and v.internal_port==49284 end,authorize_backend=function(v)return v=='127.0.0.1' end,healthy=function()return true end,certificate_snapshot=function()return {certificate='/tmp/homepublish-device/runtime/cert.pem',key='/tmp/homepublish-device/runtime/key.pem'}end})
end
function M.start(plan,g,t)return N.start(plan.configuration,g,t)end
function M.readiness()
 for i=1,30 do
  if not N.renew() then return false end
  local rc=os.execute("/usr/bin/curl -q --noproxy '*' --connect-timeout 0.05 --max-time 0.1 --cacert /etc/homepublish/device-test/cert.pem --resolve service.home:49284:127.0.0.1 --fail --silent --output /dev/null https://service.home:49284/")
  if rc==0 then return true end
 end
 return false
end
function M.renew()return N.renew()end
function M.stop()return N.stop()end
return M
