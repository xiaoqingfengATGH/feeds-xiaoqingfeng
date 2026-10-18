-- SPDX-License-Identifier: Apache-2.0
-- Internal API: callers supply typed requests; storage location is fixed, not client-selected.
local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
local model=dofile(source..'/canonical.lua')
local wire=dofile(source..'/product-wire.lua')
local store=dofile(source..'/product-store.lua')
local M={}
local function failure(code,field,message,retryable)
 return {error_code=code,field=field,error=message,retryable=retryable==true}
end
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
 -- r9: 已安装即真实能力；后端权威校验保留（CLI→device-test channel→controller 拒绝路径不动）
 out.schema_versions={1,2}
 local supported=not state.saved_config or state.saved_config.schema_version==1
 out.capabilities={start=supported,apply=supported,stop=true,network_inventory=true,preflight=true,service_types={'http_proxy','https_proxy','tls_passthrough','ssh','tcp_forward'}}
 out.pending_config={saved_revision=state.saved_revision,apply_required=state.saved_revision>0 and state.saved_revision~=state.active_revision}
 return out
end
function M.handle(request,structured)
 if type(request)~='table' or getmetatable(request)~=nil then return nil,'request object required' end
 local allowed=request.action=='migration_preview' and {action=true,expected_revision=true} or request.action=='save' and {action=true,expected_revision=true,config=true} or request.action=='validate' and {action=true,config=true} or request.action=='preflight' and {action=true,revision=true} or {action=true}
 for k in pairs(request) do if not allowed[k] then return nil,'unknown request field' end end
 if request.action=='ddns_profiles' then
  return dofile(source..'/product-ddns.lua').profiles()
 end
 if request.action=='network_inventory' then
  return dofile(source..'/network-inventory.lua').collect()
 end
 if request.action=='certificates' then
  package.path=source..'/?.lua;'..package.path
  return require('device-integrations').certificate_inventory()
 end
 if request.action=='validate' then
  local c,e,detail=model.validate(request.config)
  if c then return {valid=true,config=c} end
  local out=detail or failure('INVALID_CONFIG','config',e,false);out.valid=false;return out
 end
 if request.action~='migration_preview' and request.action~='preflight' and request.action~='save' and request.action~='status' and request.action~='stop' and request.action~='start' and request.action~='apply' then return nil,'unsupported action' end
 -- r9: start/apply 为真实能力，但本地 provider 无 controller 执行通道；
 -- 设备通道（device-test channel）才是权威执行路径，此处保持权威拒绝。
 if request.action=='start' or request.action=='apply' then return nil,'runtime requires the device controller channel' end
 return store.transaction(function(bytes)
  local state=validate_state(bytes and wire.decode(bytes) or initial())
  if request.action=='status' then return nil,public(state) end
  if request.action=='migration_preview' then
   if request.expected_revision~=state.saved_revision then return nil,failure('REVISION_CONFLICT','expected_revision','Saved revision changed',true) end
   if not state.saved_config or state.saved_config.schema_version~=1 then return nil,failure('INVALID_CONFIG','schema_version','A saved v1 configuration is required',false) end
   local inventory,err=dofile(source..'/network-inventory.lua').collect()
   if not inventory then return nil,err end
   return nil,model.migrate_preview(state.saved_config,inventory)
  end
  if request.action=='preflight' then
   if request.revision~=state.saved_revision then return nil,failure('REVISION_CONFLICT','revision','Saved revision changed',true) end
   if not state.saved_config then return nil,failure('INVALID_CONFIG','config','No saved configuration',false) end
   return nil,dofile(source..'/preflight.lua').check(state.saved_config,state.saved_revision)
  end
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
  if request.expected_revision~=state.saved_revision then
   if not structured and type(request.config)=='table' and request.config.schema_version==1 then error('revision conflict') end
   return nil,failure('REVISION_CONFLICT','expected_revision','Saved revision changed',true)
  end
  local config,err,detail=model.validate(request.config)
  if not config then
   if not structured and type(request.config)=='table' and request.config.schema_version==1 then error(err) end
   return nil,detail or failure('INVALID_CONFIG','config',err,false)
  end
  local migrating=state.saved_config and state.saved_config.schema_version==1 and config.schema_version==2
  if migrating and store.migration_backup~=true then
   return nil,failure('DEPENDENCY_UNAVAILABLE','schema_version','Private migration backup support unavailable',false)
  end
  assert(state.saved_revision<9007199254740990,'saved revision exhausted')
  state.saved_revision=state.saved_revision+1;state.saved_config=config
  return wire.encode(state),public(state),migrating==true
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
