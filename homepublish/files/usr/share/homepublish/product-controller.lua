-- SPDX-License-Identifier: Apache-2.0
-- Internal serialized controller; no production CLI activation or client providers.
local P=require('product-provider');local W=require('product-wire');local M={}
function M.new(provider)
 local C={generation=nil}
 local function status() return assert(P.handle({action='status'})) end
 local function change(fn) return assert(P.controller_transaction(fn)) end
 local function finish(phase,err,cleanup)
  return change(function(s)
   if s.runtime.generation==C.generation then
    s.runtime.phase=phase;s.runtime.last_error=err;s.runtime.cleanup=cleanup
   end
  end)
 end
 function C.stop()
  -- Commit revocation before invoking any provider stop, including cleanup failure.
  local state=change(function(s)
   assert(s.intent_revision<9007199254740990,'intent exhausted')
   s.intent_revision=s.intent_revision+1;s.desired_state={state='disabled',manual_stop_latch=true};s.approval=nil
   s.runtime.phase='stopping';s.runtime.cleanup='unknown'
  end)
  local ok=provider.stop()
  if C.generation==nil then C.generation=state.runtime.generation end
  return finish(ok and 'stopped' or 'blocked',ok and nil or 'cleanup unknown',ok and 'confirmed' or 'unknown')
 end
 function C.start(revision,approved)
  local s=status()
  if approved~=true then return {error='approval required'} end
  if s.saved_revision~=revision or revision==0 then return {error='revision conflict'} end
  if s.runtime.phase=='running' or s.runtime.phase=='starting' or s.runtime.cleanup=='unknown' then return {error='runtime busy or cleanup unknown'} end
  local snapshot=W.decode(W.encode(s.saved_config))
  local plan,err=provider.plan(W.decode(W.encode(snapshot)))
  if not plan then return {error=err or 'scope denied'} end
  s=change(function(v)
   assert(v.saved_revision==revision and v.intent_revision==s.intent_revision,'stale start')
   assert(v.intent_revision<9007199254740990,'intent exhausted')
   v.intent_revision=v.intent_revision+1;C.generation=v.intent_revision
   v.desired_state={state='enabled',manual_stop_latch=false}
   v.active_revision=revision;v.active_config=snapshot;v.approval={revision=revision}
   v.runtime={phase='starting',generation=C.generation,cleanup='unknown'}
   if snapshot.publication_policy.mode=='temporary' then v.runtime.expires_at=os.time()+snapshot.publication_policy.temporary_duration end
  end)
  local remaining=s.runtime.expires_at and math.max(0,s.runtime.expires_at-os.time())*1000 or 0
  if s.runtime.expires_at and remaining==0 then return C.stop() end
  local ok=provider.start(plan,C.generation,remaining)
  if not ok then
   local clean=provider.stop()
   return finish('blocked','provider start failed',clean and 'confirmed' or 'unknown')
  end
  return finish('running',nil,'unknown') -- live resources are not cleanup-confirmed
 end
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
   local clean=provider.stop();return finish('blocked','provider unavailable',clean and 'confirmed' or 'unknown')
  end
  return s
 end
 function C.status() C.tick();return status() end
 return C
end
return M
