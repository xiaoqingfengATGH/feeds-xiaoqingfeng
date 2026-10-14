-- SPDX-License-Identifier: Apache-2.0
-- Internal serialized controller; no production CLI activation or client providers.
local P=require('product-provider');local W=require('product-wire');local M={}
function M.new(provider,options)
 options=options or {}
 local clock=options.clock or function()return {now=os.time(),boot_id='untrusted',trusted=false}end
 local function now()return clock().now end
 local C={generation=nil}
 local schedule
 local function valid_clock(s)
  if not s.runtime.expires_at then return true end
  local t=clock()
  return t.trusted==true and s.runtime.clock_trusted==true and t.boot_id==s.runtime.boot_id and t.now>=s.runtime.clock_at and t.now<s.runtime.expires_at
 end
 local function status() return assert(P.handle({action='status'})) end
 local function change(fn) return assert(P.controller_transaction(fn)) end
 local function finish(phase,err,cleanup,stage)
  return change(function(s)
   if s.runtime.generation==C.generation then
    s.runtime.phase=phase;s.runtime.last_error=err;s.runtime.cleanup=cleanup;s.runtime.stage=stage
    if phase~='running' then s.runtime.active_verified=false end
   end
  end)
 end
 function C.stop()
  local state=change(function(s)
   assert(s.intent_revision<9007199254740990,'intent exhausted')
   s.intent_revision=s.intent_revision+1;s.desired_state={state='disabled',manual_stop_latch=true};s.approval=nil
   s.runtime.next_retry=nil;s.runtime.phase='stopping';s.runtime.cleanup='unknown';s.runtime.active_verified=false
  end)
  local ok=provider.stop()
  C.generation=state.runtime.generation
  local err;if not ok then err='cleanup unknown' end
  return finish(ok and 'stopped' or 'blocked',err,ok and 'confirmed' or 'unknown','stop')
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
  local effective,err=require('canonical').runtime_plan(snapshot)
  local plan;if effective then plan,err=provider.plan(effective) end
  if not plan then
   if recovery then
    change(function(v)v.runtime.attempt_count=(v.runtime.attempt_count or 0)+1 end)
    return schedule(err or 'scope denied')
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
   local n=recovery and (v.runtime.attempt_count or 0)+1 or 0
   local stamp=clock()
   v.runtime={attempt_count=n,boot_id=stamp.boot_id,clock_at=stamp.now,clock_trusted=stamp.trusted==true,phase='starting',stage=apply and 'replace_cleanup' or 'start',generation=C.generation,cleanup='unknown',active_verified=false}
   v.runtime.expires_at=expiry
   if not apply and not recovery and snapshot.publication_policy.mode=='temporary' then v.runtime.expires_at=now()+snapshot.publication_policy.temporary_duration end
  end)
  if apply and not provider.stop() then return finish('blocked','cleanup unknown','unknown','replace_cleanup') end
  local remaining=s.runtime.expires_at and math.max(0,s.runtime.expires_at-now())*1000 or 0
  if s.runtime.expires_at and remaining==0 then return C.stop() end
  local ok=provider.start(plan,C.generation,remaining)
  local stage='start'
  if ok then
   stage='readiness';local results
   if provider.readiness then ok,results=provider.readiness(plan) else ok=false end
   ok=ok==true
   if #effective.services>1 and not results then ok=false end
   if results then
    change(function(v)
     assert(v.runtime.generation==C.generation,'stale service readiness')
     v.runtime.services={}
     for _,service in ipairs(effective.services) do
      local result=results[service.service_id]
      local ready=type(result)=='table' and result.ready==true
      v.runtime.services[service.service_id]={hostname=service.hostname,ready=ready,generation=C.generation}
      if not ready then ok=false end
     end
    end)
   end
  end
  if not ok then
   local clean=provider.stop()
   return finish('blocked','provider '..stage..' failed',clean and 'confirmed' or 'unknown',stage)
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
   if n>=3 then v.runtime.phase='blocked';v.runtime.reason='recovery budget exhausted'
   else v.runtime.phase='retry_wait';v.runtime.next_retry=now()+math.min(4,2^n) end
  end)
 end
 function C.restore()
  local s=status();C.generation=s.runtime.generation
  local clean=provider.stop()
  s=finish(clean and 'stopped' or 'blocked',nil,clean and 'confirmed' or 'unknown','boot_cleanup')
  if not clean or not s.active_config or not s.active_config.publication_policy.boot_restore or s.desired_state.state~='enabled' or s.desired_state.manual_stop_latch then return s end
  return schedule('controller restart')
 end
 function C.start(revision,approved) return launch(revision,approved,false) end
 function C.apply(revision,approved) return launch(revision,approved,true) end
 function C.tick(event_generation)
  local s,err=P.handle({action='status'})
  if not s then return {error=err or 'state unavailable'} end
  if C.generation==nil or (event_generation and event_generation~=C.generation) then return s end
  if s.runtime.generation~=C.generation or s.desired_state.state~='enabled' or s.desired_state.manual_stop_latch then
   if s.runtime.phase=='stopped' then return s end
   return C.stop()
  end
  if s.runtime.expires_at and (now()>=s.runtime.expires_at or (options.clock and not valid_clock(s))) then return C.stop() end
  if s.runtime.phase=='running' and not provider.renew() then
   local clean=provider.stop();s=finish('blocked','provider unavailable',clean and 'confirmed' or 'unknown','renew')
   if not clean then return s end
   return schedule('provider unavailable')
  end
  if s.runtime.phase=='retry_wait' and now()>=s.runtime.next_retry then
   local r=launch(s.active_revision,true,false,true)
   if r.runtime and r.runtime.phase=='blocked' and r.runtime.cleanup=='confirmed' then return schedule(r.runtime.last_error) end
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
