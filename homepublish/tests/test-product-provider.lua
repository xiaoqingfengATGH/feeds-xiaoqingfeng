-- SPDX-License-Identifier: Apache-2.0
local root='/root/homepublish-lua-store/p1'
local scope=dofile(root..'/device-p1-lua-scope.lua')
local fixture=function()
 return {schema_version=1,services={{service_id='nas',name='NAS',hostname='nas.example.test',backend={addressFamily='ipv4',host='192.168.1.10',port=8080,allowed_ranges={'192.168.1.0/24'}},certificate_ref='acme:nas',authentication_review={authentication='confirmed',management=false}}},access_profile={methods_allowed={'manual_ipv4'},listeners={{family='ipv4',address='192.168.1.2',interface='wan',zone='wan',protocol='tcp',internal_port=8443,external_port=18443}}}}
end
local path='/usr/share/homepublish/'
local f=loadfile(path..'product-provider.lua')
assert(f,'persistent canonical provider missing')
local provider=f()
local saved,err=provider.handle({action='save',expected_revision=0,config=fixture()}); assert(saved,err)
assert(saved.saved_revision==1 and saved.active_revision==nil)
assert(saved.desired_state.state=='disabled' and saved.desired_state.manual_stop_latch==false)
assert(saved.pending_config.apply_required==true and saved.runtime.phase=='unsupported')
local again=assert(provider.handle({action='status'}))
assert(again.saved_revision==1 and again.saved_config.services[1].hostname=='nas.example.test')
assert(again.approval==nil)
print('PASS real scoped persistence, readback, initial disabled intent')
local wire=dofile(path..'product-wire.lua');local store=scope.store
local before=wire.encode(again)
for _,request in ipairs({
 {action='save',expected_revision=1,config=fixture(),desired_state={state='enabled'}},
 {action='save',expected_revision=1,config=fixture(),approval=true},
 {action='save',expected_revision=1,config=fixture(),active_revision=1},
 {action='save',expected_revision=1,config=fixture(),path='/etc/config/firewall'},
 {action='save',expected_revision=0,config=fixture()},
 {action='status',config='firewall'}
}) do local value,error=provider.handle(request);assert(value==nil and type(error)=='string','client authority must be rejected');assert(wire.encode(assert(provider.handle({action='status'})))==before) end
print('PASS revision compare-and-save, fixed scope and server-owned fields')
-- Privileged fixture only: an existing immutable snapshot from a future controller.
-- This is not a running process or an implemented Start path.
assert(store.transaction(function(bytes)
 local state=wire.decode(bytes);state.active_revision=1;state.active_config=state.saved_config
 state.desired_state={state='enabled',manual_stop_latch=false};state.approval={revision=1}
 return wire.encode(state),true
end))
local update=fixture();update.services[1].name='NAS pending'
local pending=assert(provider.handle({action='save',expected_revision=1,config=update}))
assert(pending.saved_revision==2 and pending.active_revision==1)
assert(pending.active_config.services[1].name=='NAS' and pending.saved_config.services[1].name=='NAS pending')
pending.active_config.services[1].name='client mutation'
assert(assert(provider.handle({action='status'})).active_config.services[1].name=='NAS')
local stopped=assert(provider.handle({action='stop'}))
assert(stopped.desired_state.state=='disabled' and stopped.desired_state.manual_stop_latch==true)
assert(stopped.intent_revision==1 and stopped.approval==nil)
assert(stopped.active_revision==1 and stopped.runtime.phase=='cleanup_required')
local later=assert(provider.handle({action='save',expected_revision=2,config=fixture()}))
assert(later.saved_revision==3 and later.active_revision==1 and later.desired_state.manual_stop_latch==true)
for _,action in ipairs({'start','apply'}) do
 local value,error=provider.handle({action=action});assert(value==nil and error=='runtime requires the device controller channel')
end
assert(assert(provider.handle({action='status'})).desired_state.state=='disabled')
print('PASS immutable active/pending split, persistent Stop latch, unsupported Start/Apply')
assert(store.transaction(function(bytes) local s=wire.decode(bytes);s.secret='must not leak';return wire.encode(s),true end))
local corrupt,error=provider.handle({action='status'});assert(corrupt==nil and type(error)=='string','corrupt journal must fail closed')
print('PASS corrupt journal rejected before status export')
