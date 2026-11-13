-- SPDX-License-Identifier: Apache-2.0
-- Internal serialized controller; no production CLI activation or client providers.
local P=require('product-provider');local W=require('product-wire');local M={}
function M.new(provider,options)
 options=options or {}
 local clock=options.clock or function()
  local f=io.open('/proc/sys/kernel/random/boot_id','r')
  local boot=f and f:read('*l');if f then f:close() end
  return {now=os.time(),boot_id=boot or 'untrusted',trusted=type(boot)=='string' and #boot>0}
 end
 local function now()return clock().now end
 local C={generation=nil}
 local schedule
 local function valid_clock(s)
  if not s.runtime.expires_at then return true end
  local t=clock()
  return t.trusted==true and s.runtime.clock_trusted==true and t.boot_id==s.runtime.boot_id and t.now>=s.runtime.clock_at and t.now<s.runtime.expires_at
 end
 local function decorate(s)
  -- Endpoint capability is scope-validated, never a global production switch.
  if s.saved_config and s.saved_config.schema_version==2 and type(provider.runtime_plan)=='function' then
   local ok,effective=pcall(provider.runtime_plan,s.saved_config)
   local supported=ok and type(effective)=='table'
   s.capabilities.start=supported;s.capabilities.apply=supported
  end
  if type(provider.firewall_status)=='function' then
   local ok,f=pcall(provider.firewall_status)
   s.firewall=ok and f or {state='update_failed',error='firewall status unavailable'}
  end
  return s
 end
 local function status() return decorate(assert(P.handle({action='status'}))) end
 local function change(fn) return decorate(assert(P.controller_transaction(fn))) end
 local function finish(phase,err,cleanup,stage)
  return change(function(s)
   if s.runtime.generation==C.generation then
    s.runtime.phase=phase;s.runtime.last_error=err;s.runtime.cleanup=cleanup;s.runtime.stage=stage
    if phase~='running' then s.runtime.active_verified=false end
   end
  end)
 end
 local function transient_class(class)
  return type(class)=='table' and class.kind=='transient' and (class.code=='lock_timeout' or class.code=='worker_unavailable')
 end
 local function bounded_error(value,fallback)
  local text=type(value)=='string' and value~='' and value or fallback
  return text:gsub('[%c]',' '):sub(1,128)
 end
 function C.stop(reason,stage)
  local state=change(function(s)
   assert(s.intent_revision<9007199254740990,'intent exhausted')
   s.intent_revision=s.intent_revision+1;s.desired_state={state='disabled',manual_stop_latch=true};s.approval=nil
   s.runtime.next_retry=nil;s.runtime.phase='stopping';s.runtime.cleanup='unknown';s.runtime.active_verified=false
  end)
  local ok=provider.stop()
  C.generation=state.runtime.generation
  local err;if not ok then err='cleanup unknown' end
  return finish(ok and 'stopped' or 'blocked',reason or err,ok and 'confirmed' or 'unknown',stage or 'stop')
 end
 local function launch(revision,approved,apply,recovery)
  local s=status()
  if approved~=true then return {error='approval required'} end
  if (not recovery and s.saved_revision~=revision) or revision==0 then return {error='revision conflict'} end
  if recovery then
   if s.runtime.cleanup~='confirmed' or not s.approval or s.approval.revision~=revision or s.active_revision~=revision or s.desired_state.state~='enabled' or s.desired_state.manual_stop_latch then return {error='recovery denied'} end
   if not valid_clock(s) then return C.stop() end
  elseif apply then
   if s.runtime.phase~='running' or s.desired_state.state~='enabled' or s.desired_state.manual_stop_latch then return {error='not running'} end
  elseif s.runtime.phase=='running' or s.runtime.phase=='starting' or s.runtime.cleanup=='unknown' then return {error='runtime busy or cleanup unknown'} end
  local snapshot=W.decode(W.encode(recovery and s.active_config or s.saved_config))
  local effective,err
  -- A trusted server-owned provider must opt in; the installed canonical guard
  -- remains closed for all providers without the implemented v2 capability.
  if snapshot.schema_version==2 and type(provider.runtime_plan)=='function' then
   effective,err=provider.runtime_plan(snapshot)
  else effective,err=require('canonical').runtime_plan(snapshot) end
  local plan;if effective then plan,err=provider.plan(effective) end
  if not plan then
   if recovery then
    change(function(v)v.runtime.attempt_count=(v.runtime.attempt_count or 0)+1 end)
    return finish('blocked',err or 'scope denied','confirmed','recovery_plan')
   end
   return {error=err or 'scope denied'}
  end
  local expiry=(apply or recovery) and s.runtime.expires_at or nil
  if expiry and now()>=expiry then return C.stop() end
  s=change(function(v)
   assert((recovery or v.saved_revision==revision) and v.intent_revision==s.intent_revision and v.runtime.generation==s.runtime.generation,'stale launch')
   assert(v.intent_revision<9007199254740990,'intent exhausted')
   v.intent_revision=v.intent_revision+1;C.generation=v.intent_revision
   v.desired_state={state='enabled',manual_stop_latch=false}
   v.attempted_revision=revision;v.attempted_config=snapshot;v.candidate_revision=revision;v.candidate_config=snapshot;v.approval={revision=revision}
   local n=recovery and math.min(3,(v.runtime.attempt_count or 0)+1) or 0
   local stamp=clock()
   v.runtime={attempt_count=n,boot_id=stamp.boot_id,clock_at=stamp.now,clock_trusted=stamp.trusted==true,phase='starting',stage=apply and 'replace_cleanup' or 'start',generation=C.generation,cleanup='unknown',active_verified=false}
   v.runtime.expires_at=expiry
   if not apply and not recovery and snapshot.publication_policy.mode=='temporary' then v.runtime.expires_at=now()+snapshot.publication_policy.temporary_duration end
  end)
  if apply and not provider.stop() then return finish('blocked','cleanup unknown','unknown','replace_cleanup') end
  local remaining=s.runtime.expires_at and math.max(0,s.runtime.expires_at-now())*1000 or 0
  if s.runtime.expires_at and remaining==0 then return C.stop() end
  local ok,failure,failure_class=provider.start(plan,C.generation,remaining)
  local stage='start'
  if ok then
   stage='readiness';local results
   if provider.readiness then ok,results,failure,failure_class=provider.readiness(plan) else ok=false;failure=nil end
   ok=ok==true
   if #effective.services>1 and not results then ok=false end
   if results then
    change(function(v)
     assert(v.runtime.generation==C.generation,'stale service readiness')
     v.runtime.services={}
     for _,service in ipairs(effective.services) do
      local result=results[service.service_id]
      local ready=type(result)=='table' and result.ready==true and (snapshot.schema_version~=2 or result.generation==C.generation)
      v.runtime.services[service.service_id]={hostname=service.hostname,ready=ready,generation=C.generation}
      if not ready then ok=false end
     end
    end)
   end
  end
  if not ok then
   local clean=provider.stop()
   -- Preserve the journal's 128-byte error contract, including recovery reason.
   local reason=bounded_error(failure,'provider '..stage..' failed')
   local result=finish('blocked',reason,clean and 'confirmed' or 'unknown',stage)
   if failure_class then
    result=change(function(v)v.runtime.failure_class=failure_class;return v end)
   end
   return result
  end
  local current=status()
  if current.intent_revision~=C.generation or (not recovery and current.saved_revision~=revision) or current.desired_state.state~='enabled' or current.desired_state.manual_stop_latch or (current.runtime.expires_at and now()>=current.runtime.expires_at) then return C.stop() end
  return change(function(v)
   assert(v.intent_revision==C.generation and (recovery or v.saved_revision==revision),'stale readiness')
   v.active_revision=revision;v.active_config=snapshot;v.candidate_revision=nil;v.candidate_config=nil
   v.runtime.running_since=now();v.runtime.phase='running';v.runtime.stage='ready';v.runtime.active_verified=true
  end)
 end
 schedule=function(reason)
  local s=status()
  if not valid_clock(s) then return C.stop() end
  return change(function(v)
   local n=v.runtime.attempt_count or 0
   v.runtime.reason=reason;v.runtime.next_retry=nil
   v.runtime.attempt_count=math.min(3,n+1)
   v.runtime.phase='retry_wait';v.runtime.next_retry=now()+math.min(4,2^math.min(n,2))
   if n>=3 then v.runtime.reason='recovery budget exhausted' end
  end)
 end
 local function automatic_failure(reason,class,stage)
  local s=change(function(v)
   v.runtime.phase='stopping';v.runtime.stage=stage or 'renew';v.runtime.cleanup='unknown';v.runtime.active_verified=false
   v.runtime.next_retry=nil
  end)
  C.generation=s.runtime.generation
  local clean=provider.stop()
  local result=finish('blocked',bounded_error(reason,'automatic recovery failed'),clean and 'confirmed' or 'unknown',stage or 'renew')
  result=change(function(v)
   v.runtime.failure_class=class
   v.runtime.last_error=bounded_error(reason,'automatic recovery failed')
   return v
  end)
  if clean and transient_class(class) then return schedule(result.runtime.last_error) end
  return result
 end
 function C.restore(explicit_restart)
  -- Only the daemon's consumed, identity-bound handoff may bypass boot policy.
  local s=status();C.generation=s.runtime.generation
  local clean=provider.stop()
  s=finish(clean and 'stopped' or 'blocked',nil,clean and 'confirmed' or 'unknown',explicit_restart==true and 'restart_cleanup' or 'boot_cleanup')
  if not clean or not s.active_config or s.desired_state.state~='enabled' or s.desired_state.manual_stop_latch then return s end
  if explicit_restart==true then
   -- A new operator restart gets a bounded recovery budget, never attempt 4.
   s=change(function(v)v.runtime.attempt_count=0;v.runtime.next_retry=nil end)
   -- Recovery uses the approved active snapshot and original deadline, and
   -- deliberately bypasses explicit_launch (which performs optional DDNS).
   return launch(s.active_revision,true,false,true)
  end
  if not s.active_config.publication_policy.boot_restore then return s end
  return schedule('controller restart')
 end
 local function explicit_launch(revision,approved,apply)
  local result=launch(revision,approved,apply)
  if not result.error and result.runtime and result.runtime.phase=='running' and result.runtime.active_verified==true then
   local config=result.active_config
   local needed=false
   for _,s in ipairs(config and config.services or {}) do
    if s.enabled==true and s.dns and s.dns.mode=='ddns_go' and (s.type=='http_proxy' or s.type=='https_proxy' or s.type=='tls_passthrough') then needed=true end
   end
   result.ddns={results={},warnings={}}
   if needed then
    -- Forwarding is already accepted. DNS is best-effort, never a lifecycle gate.
    -- Never call this from recovery/tick/status or while holding a store lock.
    local ok,dns=pcall(function()return require('product-ddns').ensure(config)end)
    result.ddns=ok and dns or {results={},warnings={{error='域名自动更新未完成，请检查 ddns-go 后重试。'}}}
   end
  end
  return result
 end
 function C.start(revision,approved) return explicit_launch(revision,approved,false) end
 function C.apply(revision,approved) return explicit_launch(revision,approved,true) end
 function C.tick(event_generation)
  local s,err=P.handle({action='status'})
  if not s then return {error=err or 'state unavailable'} end
  if C.generation==nil or (event_generation and event_generation~=C.generation) then return s end
  if s.runtime.generation~=C.generation or s.desired_state.state~='enabled' or s.desired_state.manual_stop_latch then
   if s.runtime.phase=='stopped' then return s end
   return C.stop()
  end
  if s.runtime.expires_at and (now()>=s.runtime.expires_at or (options.clock and not valid_clock(s))) then return C.stop() end
  if s.runtime.phase=='blocked' and s.runtime.cleanup=='unknown' then
   local clean=provider.stop()
   return finish('blocked',s.runtime.last_error,clean and 'confirmed' or 'unknown','cleanup_retry')
  end
  if s.runtime.phase=='blocked' and s.runtime.cleanup=='confirmed' and transient_class(s.runtime.failure_class) then
   return schedule(s.runtime.last_error)
  end
  if s.runtime.phase=='running' then
   local renewed,detail,class=provider.renew()
   if not renewed then
    local transient=transient_class(class)
    if transient and s.runtime.next_retry and now()<s.runtime.next_retry then return s end
    if transient then
     local failures=(s.runtime.renew_failures or 0)+1
     if failures<=3 then
      return change(function(v)
       v.runtime.last_error=bounded_error(detail,'provider renewal failed');v.runtime.failure_class=class
       v.runtime.renew_failures=failures;v.runtime.next_retry=now()+math.min(4,2^(failures-1))
      end)
     end
    end
    return automatic_failure(detail,class,'renew')
   end
   if s.runtime.renew_failures then
    return change(function(v)v.runtime.renew_failures=nil;v.runtime.next_retry=nil;v.runtime.failure_class=nil;v.runtime.last_error=nil end)
   end
  end
  if s.runtime.phase=='retry_wait' and now()>=s.runtime.next_retry then
   local r=launch(s.active_revision,true,false,true)
   if r.runtime and r.runtime.phase=='blocked' and r.runtime.cleanup=='confirmed' and transient_class(r.runtime.failure_class) then return schedule(r.runtime.last_error) end
   return r
  end
  if s.runtime.phase=='running' and s.runtime.running_since and now()-s.runtime.running_since>=30 and (s.runtime.attempt_count or 0)>0 then
   return change(function(v)v.runtime.attempt_count=0 end)
  end
  return s
 end
 function C.status() C.tick();return status() end
 return C
end
return M
