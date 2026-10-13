-- SPDX-License-Identifier: Apache-2.0
local root,case=arg[1],arg[2]
local fixture=assert(loadfile(root..'/homepublish/tests/test-canonical.lua'))().fixture
local path=root..'/homepublish/files/usr/share/homepublish/'
local model=dofile(path..'canonical.lua')
local provider=dofile(path..'product-provider.lua')
local wire=dofile(path..'product-wire.lua')
local store=require('homepublish_store')
local function sparse(v) return {[1]=v,[2]=v,[4]=v,[100]={secret='SENTINEL_ONLY'}} end
if case=='sparse' then
 for _,field in ipairs({'services','listeners','methods_allowed','allowed_ranges'}) do
  local c=fixture()
  if field=='services' then c.services=sparse(c.services[1]);c.services[2]=fixture().services[1];c.services[2].service_id='other';c.services[2].hostname='other.example.test'
  elseif field=='allowed_ranges' then c.services[1].backend.allowed_ranges=sparse('192.168.1.0/24')
  elseif field=='methods_allowed' then c.access_profile.methods_allowed=sparse('manual_ipv4');c.access_profile.methods_allowed[2]='stun_experimental'
  else c.access_profile.listeners=sparse(c.access_profile.listeners[1]);c.access_profile.listeners[2]=fixture().access_profile.listeners[1];c.access_profile.listeners[2].internal_port=8444 end
  assert(not model.validate(c),'accepted sparse '..field)
  local value=provider.handle({action='save',expected_revision=0,config=c})
  assert(value==nil,'persisted sparse '..field)
 end
elseif case=='journal' then
 for _,field in ipairs({'saved_config','active_config'}) do
  assert(store.transaction(function()
   local c=fixture();c.services[1].backend.backup=false
   -- Accepted false optional backup must never appear in public canonical plans.
   -- Use a sparse array to hide an unvalidated field beyond ipairs as well.
   local hidden=fixture().services[1];hidden.secret='SENTINEL_ONLY'
   c.services[2]=fixture().services[1];c.services[2].service_id='other';c.services[2].hostname='other.example.test'
   c.services[4]=hidden;c.services[100]=hidden
   local s={state_version=1,saved_revision=1,intent_revision=0,saved_config=fixture(),desired_state={state='disabled',manual_stop_latch=false},runtime={phase='unsupported'}}
   s[field]=c
   if field=='active_config' then s.active_revision=1 end
   return wire.encode(s),true
  end))
  local value=provider.handle({action='status'})
  assert(value==nil,'corrupt journal accepted '..field)
  -- Dense unknown fields are rejected too, for either persisted snapshot.
  assert(store.transaction(function()
   local s={state_version=1,saved_revision=1,intent_revision=0,saved_config=fixture(),desired_state={state='disabled',manual_stop_latch=false},runtime={phase='unsupported'}}
   s[field]=fixture();s[field].services[1].secret='SENTINEL_ONLY'
   if field=='active_config' then s.active_revision=1 end
   return wire.encode(s),true
  end))
  assert(provider.handle({action='status'})==nil,'unknown snapshot field accepted '..field)
 end
 -- A valid-but-nonnormalized journal must be exported detached and normalized.
 assert(store.transaction(function()
  local c=fixture();c.services[1].backend.backup=false
  return wire.encode({state_version=1,saved_revision=1,intent_revision=0,saved_config=c,desired_state={state='disabled',manual_stop_latch=false},runtime={phase='unsupported'}}),true
 end))
 local value=assert(provider.handle({action='status'}))
 assert(value.saved_config.services[1].backend.backup==nil,'raw journal exported instead of canonical plan')
 assert(value.saved_config.publication_policy.mode=='continuous')
elseif case=='policy' then
 for _,policy in ipairs({false,'continuous',42}) do
  local c=fixture();c.publication_policy=policy
  assert(not model.validate(c),'accepted nonobject policy '..tostring(policy))
  assert(provider.handle({action='save',expected_revision=0,config=c})==nil)
 end
 assert(model.validate(fixture()).publication_policy.mode=='continuous')
elseif case=='revision' then
 local max=9007199254740990 -- largest accepted persisted revision
 for _,field in ipairs({'saved_revision','intent_revision'}) do
  assert(store.transaction(function()
   local s={state_version=1,saved_revision=1,intent_revision=0,saved_config=fixture(),desired_state={state='disabled',manual_stop_latch=false},runtime={phase='unsupported'}}
   s[field]=max-1;return wire.encode(s),true
  end))
  local request=field=='saved_revision' and {action='save',expected_revision=max-1,config=fixture()} or {action='stop'}
  local value=assert(provider.handle(request));assert(value[field]==max)
  local before=store.transaction(function(bytes) return nil,bytes end)
  if field=='saved_revision' then request.expected_revision=max end
  assert(provider.handle(request)==nil,'overflow committed '..field)
  assert(store.transaction(function(bytes) return nil,bytes end)==before,'overflow wrote disk')
  assert(provider.handle({action='status'})[field]==max,'overflow poisoned journal')
  assert(store.transaction(function(bytes)
   local s=wire.decode(bytes);s[field]=max+1;return wire.encode(s),true
  end))
  local invalid=store.transaction(function(bytes) return nil,bytes end)
  assert(provider.handle({action='status'})==nil,'invalid upper bound accepted '..field)
  assert(store.transaction(function(bytes) return nil,bytes end)==invalid)
 end
end
print('PASS review regression '..case)
