-- SPDX-License-Identifier: Apache-2.0
-- Internal serialized controller; no production CLI activation or client providers.
local P=require('product-provider');local W=require('product-wire');local M={}
function M.new(provider)
 local C={generation=nil}
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
   s.runtime.phase='stopping';s.runtime.cleanup='unknown';s.runtime.active_verified=false
  end)
  local ok=provider.stop()
  C.generation=state.runtime.generation
  local err;if not ok then err='cleanup unknown' end
  return finish(ok and 'stopped' or 'blocked',err,ok and 'confirmed' or 'unknown','stop')
 end
 local function launch(revision,approved,apply)
  local s=status()
  if approved~=true then return {error='approval required'} end
  if s.saved_revision~=revision or revision==0 then return {error='revision conflict'} end
  if apply then
   if s.runtime.phase~='running' or s.desired_state.state~='enabled' or s.desired_state.manual_stop_latch then return {error='not running'} end
  elseif s.runtime.phase=='running' or s.runtime.phase=='starting' or s.runtime.cleanup=='unknown' then return {error='runtime busy or cleanup unknown'} end
  local snapshot=W.decode(W.encode(s.saved_config))
  local plan,err=provider.plan(W.decode(W.encode(snapshot)))
  if not plan then return {error=err or 'scope denied'} end
  local expiry=apply and s.runtime.expires_at or nil
  if expiry and os.time()>=expiry then return C.stop() end
  s=change(function(v)
   assert(v.saved_revision==revision and v.intent_revision==s.intent_revision and v.runtime.generation==s.runtime.generation,'stale launch')
   assert(v.intent_revision<9007199254740990,'intent exhausted')
   v.intent_revision=v.intent_revision+1;C.generation=v.intent_revision
   v.desired_state={state='enabled',manual_stop_latch=false}
   v.attempted_revision=revision;v.attempted_config=snapshot;v.candidate_revision=revision;v.candidate_config=snapshot;v.approval={revision=revision}
   v.runtime={phase='starting',stage=apply and 'replace_cleanup' or 'start',generation=C.generation,cleanup='unknown',active_verified=false}
   v.runtime.expires_at=expiry
   if not apply and snapshot.publication_policy.mode=='temporary' then v.runtime.expires_at=os.time()+snapshot.publication_policy.temporary_duration end
  end)
  if apply and not provider.stop() then return finish('blocked','cleanup unknown','unknown','replace_cleanup') end
  local remaining=s.runtime.expires_at and math.max(0,s.runtime.expires_at-os.time())*1000 or 0
  if s.runtime.expires_at and remaining==0 then return C.stop() end
  local ok=provider.start(plan,C.generation,remaining)
  local stage='start'
  if ok then stage='readiness';ok=provider.readiness and provider.readiness(plan)==true end
  if not ok then
   local clean=provider.stop()
   return finish('blocked','provider '..stage..' failed',clean and 'confirmed' or 'unknown',stage)
  end
  local current=status()
  if current.intent_revision~=C.generation or current.saved_revision~=revision or current.desired_state.state~='enabled' or current.desired_state.manual_stop_latch or (current.runtime.expires_at and os.time()>=current.runtime.expires_at) then return C.stop() end
  return change(function(v)
   assert(v.intent_revision==C.generation and v.saved_revision==revision,'stale readiness')
   v.active_revision=revision;v.active_config=snapshot;v.candidate_revision=nil;v.candidate_config=nil
   v.runtime.phase='running';v.runtime.stage='ready';v.runtime.active_verified=true
  end)
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
  if s.runtime.expires_at and os.time()>=s.runtime.expires_at then return C.stop() end
  if s.runtime.phase=='running' and not provider.renew() then
   local clean=provider.stop();return finish('blocked','provider unavailable',clean and 'confirmed' or 'unknown','renew')
  end
  return s
 end
 function C.status() C.tick();return status() end
 return C
end
return M
