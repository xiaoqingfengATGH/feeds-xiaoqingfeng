-- Explicit bounded host-test scope; never installed, no production enable switch.
package.path=arg[1]..'/?.lua;'..package.path
local root=arg[2];local port=tonumber(arg[3]);local backend=tonumber(arg[4])
local native=require('homepublish_controller_test');local renderer=require('direct-renderer');local wire=require('product-wire')
local p={};local fault=nil
function p.plan(c)
 if #c.services~=1 or #c.access_profile.listeners~=1 or #c.access_profile.methods_allowed~=1 or c.access_profile.methods_allowed[1]~='manual_ipv4' then return nil,'fixture scope denied' end
 local s=c.services[1];local l=c.access_profile.listeners[1]
 if s.service_id~='fixture' or s.hostname~='service.home' or s.certificate_ref~='import:fixture' or s.backend.host~='127.0.0.1' or (s.backend.port~=backend and s.backend.port~=tonumber(arg[5])) or s.authentication_review.authentication~='confirmed' or s.authentication_review.management or l.family~='ipv4' or l.address~='192.168.1.2' or l.interface~='fixture' or l.zone~='fixture' or l.internal_port~=port or l.external_port~=port then return nil,'fixture scope denied' end
 -- Canonical ingress deliberately cannot be loopback. This fixed host fixture
 -- maps only its exact declared private scope to isolated loopback sockets.
 l.address='127.0.0.1';l.interface='lo'
 local r,e=renderer.render(c,{authorize_listener=function(v)return v.address=='127.0.0.1' and v.internal_port==port end,authorize_backend=function(v)return v=='127.0.0.1' end,healthy=function()return true end,certificate_snapshot=function()return {certificate=root..'/runtime/cert.pem',key=root..'/runtime/key.pem'} end})
 if not r then return nil,e end
 r.configuration=r.configuration:gsub('proxy_next_upstream off;','proxy_next_upstream off; proxy_buffering off;')
 return r
end
function p.start(plan,gen,remaining)if fault=='start' then return false end;return native.start(plan.configuration,gen,remaining)end
function p.readiness()
 if fault=='readiness' then return false end
 return os.execute('python3 '..arg[1]..'/../../../../tests/controller-health.py '..root..' '..port)==0
end
function p.renew()return native.renew()end
function p.stop()local ok=native.stop();return ok and fault~='cleanup'end
local c=require('product-controller').new(p)
io.stdout:setvbuf('no');io.stdin:setvbuf('no')
while true do
 if native.ready() then
  local line=io.stdin:read('*l');if not line then c.stop();break end
  local req=wire.decode(line);local response
  if req.action=='fault' then fault=req.stage;response=c.status()
  elseif req.action=='start' then response=c.start(req.revision,req.approved)
  elseif req.action=='apply' then response=c.apply(req.revision,req.approved)
  elseif req.action=='stop' then response=c.stop()
  elseif req.action=='event' then response=c.tick(req.generation)
  elseif req.action=='exit' then response=c.stop()
  else response=c.status() end
  io.stdout:write(wire.encode(response),'\n')
  if req.action=='exit' then break end
 else c.tick() end
end
