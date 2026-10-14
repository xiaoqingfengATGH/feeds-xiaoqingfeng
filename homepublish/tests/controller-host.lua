-- Explicit bounded host-test scope; never installed, no production enable switch.
package.path=arg[1]..'/?.lua;'..package.path
local root=arg[2];local port=tonumber(arg[3]);local backend=tonumber(arg[4]);local alternate=tonumber(arg[5])
local native=require('homepublish_controller_test');local renderer=require('direct-renderer');local wire=require('product-wire')
local p={};local fault=nil
function p.plan(c)
 if #c.services<1 or #c.services>2 or #c.access_profile.listeners<1 or #c.access_profile.listeners>2 then return nil,'fixture scope denied' end
 local methods={};for _,m in ipairs(c.access_profile.methods_allowed) do if m~='manual_ipv4' and m~='direct_ipv6' then return nil,'fixture scope denied' end;methods[m]=true end
 for _,s in ipairs(c.services) do
  local first=s.service_id=='fixture' and s.hostname=='service.home' and s.certificate_ref=='import:fixture'
  local second=s.service_id=='second' and s.hostname=='second.home' and s.certificate_ref=='import:second'
  if not (first or second) or not (s.backend.host=='127.0.0.1' or s.backend.host=='fd00::3') or (s.backend.port~=backend and s.backend.port~=alternate) or s.authentication_review.authentication~='confirmed' or s.authentication_review.management then return nil,'fixture scope denied' end
  if s.backend.host=='fd00::3' then s.backend.host='::1';s.backend.allowed_ranges={'::1/128'} end
 end
 for _,l in ipairs(c.access_profile.listeners) do
  if l.interface~='fixture' or l.zone~='fixture' or l.internal_port~=port or l.external_port~=port or not ((l.family=='ipv4' and l.address=='192.168.1.2' and methods.manual_ipv4) or (l.family=='ipv6' and l.address=='fd00::2' and methods.direct_ipv6)) then return nil,'fixture scope denied' end
  l.address=l.family=='ipv4' and '127.0.0.1' or '::1';l.interface='lo'
 end
 local r,e=renderer.render(c,{authorize_listener=function(v)return (v.address=='127.0.0.1' or v.address=='::1') and v.internal_port==port end,authorize_backend=function(v)return v=='127.0.0.1' or v=='::1' end,healthy=function()return true end,certificate_snapshot=function(ref)return {certificate=root..'/runtime/'..(ref=='import:second' and 'cert2.pem' or 'cert.pem'),key=root..'/runtime/'..(ref=='import:second' and 'key2.pem' or 'key.pem')} end})
 if not r then return nil,e end
 r.configuration=r.configuration:gsub('proxy_next_upstream off;','proxy_next_upstream off; proxy_buffering off;')
 r.services={};for _,s in ipairs(c.services) do r.services[#r.services+1]={service_id=s.service_id,hostname=s.hostname,certificate=s.certificate_ref=='import:second' and 'cert2.pem' or 'cert.pem'} end
 r.listeners=c.access_profile.listeners
 return r
end
function p.start(plan,gen,remaining)if fault=='start' then return false end;return native.start(plan.configuration,gen,remaining)end
function p.readiness(plan)
 local results={};local all=true
 for _,s in ipairs(plan.services) do
  local ready=fault~='readiness' and not (fault=='second-readiness' and s.service_id=='second')
  for _,l in ipairs(plan.listeners) do
   if ready then ready=os.execute('python3 '..arg[1]..'/../../../../tests/controller-health.py '..root..' '..port..' '..s.hostname..' '..s.certificate..' '..l.address)==0 end
  end
  results[s.service_id]={hostname=s.hostname,ready=ready};all=all and ready
 end
 return all,results
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
