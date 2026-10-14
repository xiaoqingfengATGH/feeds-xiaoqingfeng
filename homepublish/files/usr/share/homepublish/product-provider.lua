-- SPDX-License-Identifier: Apache-2.0
-- Internal API: callers supply typed requests; storage location is compiled, not client-selected.
local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
local model=dofile(source..'/canonical.lua')
local wire=dofile(source..'/product-wire.lua')
local store=require('homepublish_store')
local M={}
local function initial()
 return {state_version=1,saved_revision=0,intent_revision=0,desired_state={state='disabled',manual_stop_latch=false},runtime={phase='unsupported'}}
end
local function known(t,fields)
 assert(type(t)=='table','journal object')
 for k in pairs(t) do assert(fields[k],'unknown journal field') end
end
local function revision(n) assert(type(n)=='number' and n%1==0 and n>=0 and n<9007199254740991,'journal revision') end
local function validate_state(s)
 known(s,{state_version=true,saved_revision=true,saved_config=true,active_revision=true,active_config=true,intent_revision=true,desired_state=true,runtime=true,approval=true,attempted_revision=true,attempted_config=true,candidate_revision=true,candidate_config=true})
 assert(s.state_version==1,'journal version');revision(s.saved_revision);revision(s.intent_revision)
 if s.saved_revision>0 then s.saved_config=assert(model.validate(s.saved_config),'invalid saved config') else assert(s.saved_config==nil,'unexpected config') end
 if s.active_revision~=nil then
  revision(s.active_revision);assert(s.active_revision>0 and s.active_revision<=s.saved_revision,'invalid active revision')
  s.active_config=assert(model.validate(s.active_config),'invalid active snapshot')
 else assert(s.active_config==nil,'orphan active config') end
 for _,prefix in ipairs({'attempted','candidate'}) do
  local r,c=s[prefix..'_revision'],s[prefix..'_config']
  if r then revision(r);assert(r>0 and r<=s.saved_revision,'invalid attempt revision');s[prefix..'_config']=assert(model.validate(c),'invalid attempt snapshot') else assert(c==nil,'orphan attempt') end
 end
 known(s.desired_state,{state=true,manual_stop_latch=true})
 assert(s.desired_state.state=='disabled' or s.desired_state.state=='enabled','journal desired')
 assert(type(s.desired_state.manual_stop_latch)=='boolean','journal latch')
 assert(not s.desired_state.manual_stop_latch or s.desired_state.state=='disabled','latched enabled intent')
 known(s.runtime,{phase=true,generation=true,last_error=true,cleanup=true,expires_at=true,stage=true,active_verified=true,services=true,attempt_count=true,next_retry=true,reason=true,running_since=true,boot_id=true,clock_at=true,clock_trusted=true})
 local phases={unsupported=true,cleanup_required=true,starting=true,running=true,stopping=true,stopped=true,blocked=true,retry_wait=true}
 assert(phases[s.runtime.phase],'runtime unavailable')
 if s.runtime.generation~=nil then revision(s.runtime.generation) end
 if s.runtime.last_error~=nil then assert(type(s.runtime.last_error)=='string' and #s.runtime.last_error<=128,'runtime error') end
 if s.runtime.cleanup~=nil then assert(s.runtime.cleanup=='confirmed' or s.runtime.cleanup=='unknown','runtime cleanup') end
 if s.runtime.expires_at~=nil then revision(s.runtime.expires_at) end
 if s.runtime.stage then assert(type(s.runtime.stage)=='string' and #s.runtime.stage<=32,'runtime stage') end
 if s.runtime.active_verified~=nil then assert(type(s.runtime.active_verified)=='boolean','runtime verification') end
 for _,k in ipairs({'attempt_count','next_retry','running_since','clock_at'}) do if s.runtime[k]~=nil then revision(s.runtime[k]) end end
 if s.runtime.attempt_count then assert(s.runtime.attempt_count<=3,'retry budget') end
 if s.runtime.reason then assert(type(s.runtime.reason)=='string' and #s.runtime.reason<=128,'retry reason') end
 if s.runtime.boot_id then assert(type(s.runtime.boot_id)=='string' and #s.runtime.boot_id<=128,'boot identity') end
 if s.runtime.clock_trusted~=nil then assert(type(s.runtime.clock_trusted)=='boolean','clock trust') end
 if s.runtime.services then
  local allowed={};for _,service in ipairs((s.attempted_config or s.active_config).services) do allowed[service.service_id]=service.hostname end
  for id,result in pairs(s.runtime.services) do
   assert(allowed[id]==result.hostname,'runtime service identity')
   known(result,{hostname=true,ready=true,generation=true});assert(type(result.ready)=='boolean','service readiness')
   assert(result.generation==s.runtime.generation,'service generation')
  end
 end
 if s.approval then known(s.approval,{revision=true});assert(s.approval.revision==(s.attempted_revision or s.active_revision),'approval revision') end
 return s
end
local function public(state)
 local out=wire.decode(wire.encode(state))
 out.pending_config={saved_revision=state.saved_revision,apply_required=state.saved_revision>0 and state.saved_revision~=state.active_revision}
 return out
end
function M.handle(request)
 if type(request)~='table' or getmetatable(request)~=nil then return nil,'request object required' end
 local allowed=request.action=='save' and {action=true,expected_revision=true,config=true} or request.action=='validate' and {action=true,config=true} or {action=true}
 for k in pairs(request) do if not allowed[k] then return nil,'unknown request field' end end
 if request.action=='validate' then local c,e=model.validate(request.config);return c and {valid=true,config=c} or {valid=false,error=e} end
 if request.action~='save' and request.action~='status' and request.action~='stop' and request.action~='start' and request.action~='apply' then return nil,'unsupported action' end
 if request.action=='start' or request.action=='apply' then return nil,'unsupported: runtime not implemented' end
 return store.transaction(function(bytes)
  local state=validate_state(bytes and wire.decode(bytes) or initial())
  if request.action=='status' then return nil,public(state) end
  if request.action=='stop' then
   state.desired_state={state='disabled',manual_stop_latch=true}
   assert(state.intent_revision<9007199254740990,'intent revision exhausted')
   state.intent_revision=state.intent_revision+1;state.approval=nil
   -- Preserve the owned generation so the internal controller observes revocation.
   state.runtime.active_verified=false
   state.runtime.phase=(state.active_revision or state.attempted_revision) and 'cleanup_required' or 'unsupported'
   if state.active_revision or state.attempted_revision then state.runtime.cleanup='unknown' end
   return wire.encode(state),public(state)
  end
  assert(request.action=='save','unsupported action')
  assert(request.expected_revision==state.saved_revision,'revision conflict')
  local config,err=model.validate(request.config);assert(config,err)
  assert(state.saved_revision<9007199254740990,'saved revision exhausted')
  state.saved_revision=state.saved_revision+1;state.saved_config=config
  return wire.encode(state),public(state)
 end)
end
-- Internal code dependency only; never exposed through the fixed client protocol.
function M.controller_transaction(fn)
 return store.transaction(function(bytes)
  local state=validate_state(bytes and wire.decode(bytes) or initial())
  fn(state)
  validate_state(state)
  return wire.encode(state),public(state)
 end)
end
return M
