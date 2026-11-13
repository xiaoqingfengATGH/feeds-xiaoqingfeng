-- SPDX-License-Identifier: Apache-2.0
-- Shared conventional v2 adapter. Options come only from fixed installed code.
local R=require('direct-renderer');local B=require('direct-backend');local I=require('device-integrations');local M={}
local function q(s)return "'"..s:gsub("'","'\\''").."'"end

local function identity(source)
 local f=io.popen('sha256sum '..q(source.certificate)..' '..q(source.key)..' 2>/dev/null');if not f then return nil end
 local s=f:read('*a');f:close();return s~='' and s or nil
end

function M.new(o)
 local G=require('product-procd-group').new(o);local active,next_check,lease_deadline,firewall_retry_at,firewall_retry_delay
 local firewall=o.firewall
 local function lease()
  if not lease_deadline then return 10 end
  local remaining=lease_deadline-os.time();if remaining<=0 then return nil end
  return math.min(10,remaining)
 end
 local V={}
 function V.runtime_plan(c)
  if not o.available() then return nil,'installed v2 capability unavailable' end
  local p,e=require('canonical-v2').validate(c);if not p then return nil,e end
  local enabled={};for _,s in ipairs(p.services) do if s.enabled then
   enabled[#enabled+1]=s
  end end;p.services=enabled
  if #enabled==0 or not o.authorize(p) then return nil,'installed v2 scope denied' end
  return p
 end
 local function verify_bindings(listeners)
  local N=require('network-inventory');local inventory,err=N.collect()
  if not inventory then return nil,err.error end
  for _,l in ipairs(listeners) do
   local resolved,e=N.resolve(l,inventory)
   if not resolved then return nil,e.error end
  end
  return true
 end
 function V.plan(c)
  local p,e=V.runtime_plan(c);if not p then return nil,e end
  local bound,err=verify_bindings(p.access_profile.listeners);if not bound then return nil,err end
  local snapshots={};local bindings={};local backend={}
  local ports=o.mixed_ports
  if type(ports)=='function' then ports=ports(p);if not ports then return nil,'internal ports unavailable' end end
  -- Select only authorized, scoped addresses. The required backend selector
  -- callback is deliberately non-probing: target availability is never a gate.
  local deps={resolve=I.resolve,mixed_ports=ports,authorize_listener=o.authorize_listener,authorize_backend=o.authorize_backend,healthy=function()return true end}
  deps.certificate_snapshot=function(ref,host)
   local key=ref..'|'..host;if bindings[key] then return bindings[key] end
   local source=assert(I.certificate_source(ref,host));local i=#snapshots+1
   local target={certificate=o.root..'/cert'..i..'.pem',key=o.root..'/key'..i..'.pem'}
   snapshots[i]={source=source,certificate=target.certificate,key=target.key,identity=identity(source)};assert(snapshots[i].identity,'certificate identity unavailable');bindings[key]=target;return target
  end
  for _,s in ipairs(p.services) do local b,err=B.select(s.backend,deps);if not b then return nil,err end;backend[s.service_id]=b end
  local r,err=R.render(p,deps);if not r then return nil,err end
  -- Fixed device profile can only narrow exact authorized addresses to loopback.
  r.configuration=o.narrow(r.configuration);if r.sslh_configuration then r.sslh_configuration=o.narrow(r.sslh_configuration) end
  local rules
  if firewall then
   local inventory,e=require('network-inventory').collect();if not inventory then return nil,type(e)=='table' and e.error or e end
   rules,e=require('product-firewall-plan').plan(p,inventory);if not rules then return nil,type(e)=='table' and e.error or e end
  end
  r.services=p.services;r.listeners=p.access_profile.listeners;r.snapshots=snapshots;r.selected=backend;r.firewall_rules=rules
  if G.preflight then local ok,why=G.preflight(r);if not ok then return nil,why end end
  return r
 end
 function V.start(p,g,remaining)
  if not o.available() then return false,'installed v2 capability unavailable' end
  lease_deadline=remaining and remaining>0 and os.time()+math.ceil(remaining/1000) or nil
  local ok,err=G.start(p,g);if ok then active=p;next_check=os.time()+30 end;return ok,err
 end
 function V.readiness(p)
  -- Startup readiness describes our components, not target availability. Targets
  -- may start later or reject HTTP/TLS/SSH without stopping unrelated services.
  local healthy,err=G.healthy();local class;local out={}
  if healthy and firewall then
   local ttl=lease()
   if not ttl then healthy=false;err='firewall publication lease expired'
   else healthy,err,class=firewall.reconcile(p.firewall_rules or {},ttl) end
  end
  for _,s in ipairs(p.services) do out[s.service_id]={ready=healthy==true,generation=p.generation} end
  return healthy==true,out,err,class
 end
 function V.renew()
  if not active then return false,'runtime is not active',{kind='unsafe',code='inactive'} end
  local healthy,health_error=G.healthy()
  if not healthy then return false,health_error or 'component unhealthy',{kind='unsafe',code='listener_unhealthy'} end
  -- Health and identity are safety checks, not lease-refresh work.  Run them
  -- on every grace tick, including ticks where firewall publication is backed
  -- off, so a changed listener/certificate/backend cannot hide behind retry.
  next_check=os.time()+30
  local bound,binding_error=verify_bindings(active.listeners);if not bound then return false,binding_error or 'listener binding verification failed',{kind='unsafe',code='listener_identity'} end
  for _,s in ipairs(active.snapshots) do if identity(s.source)~=s.identity then return false,'certificate identity mismatch',{kind='unsafe',code='certificate_identity'} end end
  for _,s in ipairs(active.services) do
   local b=B.select(s.backend,{resolve=I.resolve,authorize_backend=o.authorize_backend,healthy=function()return true end})
   local old=active.selected[s.service_id];if not b or not old or b.address~=old.address or b.port~=old.port then return false,'backend identity mismatch',{kind='unsafe',code='backend_identity'} end
  end
  if firewall then
   local now=os.time()
   if firewall_retry_at and now<firewall_retry_at then return false,'firewall reconciliation backoff',{kind='transient',code='lock_timeout'} end
   local ttl=lease();if not ttl then return false,'firewall publication lease expired',{kind='unsafe',code='lease_expired'} end
   local ok,err,class=firewall.reconcile(active.firewall_rules or {},ttl)
   if ok then firewall_retry_at=nil;firewall_retry_delay=nil;return true end
   if class and class.kind=='transient' then firewall_retry_delay=math.min(4,(firewall_retry_delay or 1)*2);firewall_retry_at=now+firewall_retry_delay end
   return false,err or 'firewall reconciliation failed',class or {kind='unsafe',code='worker_rejected'}
  end
  return true
 end
 function V.stop()
  -- Always revoke before terminating listeners. Still terminate components on
  -- nft failure, but retain cleanup=unknown so the controller retries removal.
  local revoked=true;if firewall then revoked=firewall.clear() end
  local stopped=G.stop()
  if stopped then active=nil;next_check=nil;lease_deadline=nil;firewall_retry_at=nil;firewall_retry_delay=nil end
  return revoked==true and stopped==true
 end
 function V.firewall_status()return firewall and firewall.status() or {state='unmanaged',rule_count=0} end
 return V
end
return M
