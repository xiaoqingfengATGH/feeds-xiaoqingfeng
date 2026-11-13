-- Target Lua, real private journal. Runtime adapter is deliberately non-production.
local root=assert(arg[1]);package.path=root..'/?.lua;'..package.path
local fs=require('nixio.fs');assert(fs.mkdir(root..'/store','700'))
local P=require('product-provider');local W=require('product-wire')
local config={schema_version=2,access_profile={listeners={{listener_id='v4',family='ipv4',network='lan',address='192.168.1.2',port=18443}}},services={{service_id='web',name='Web',enabled=true,type='http_proxy',hostname='old.example.com',upstream_scheme='http',backend={addressFamily='ipv4',host='192.168.1.3',port=8080},dns={mode='ddns_go',profile_id='p:1',record_types={'A'}}}},publication_policy={mode='temporary',temporary_duration=600,boot_restore=false}}
assert(P.handle{action='save',expected_revision=0,config=config})
local now=100;local starts=0;local stops=0;local generation;local seen;local ttl;local dns=0;local fail_start=false
package.loaded['product-ddns']={ensure=function()dns=dns+1;return {results={},warnings={}}end}
local provider={runtime_plan=function(c)return c end,plan=function(c)seen=c;return c end,start=function(p,g,t)starts=starts+1;generation=g;ttl=t;if fail_start then return false,'lock timeout',{kind='transient',code='lock_timeout'} end;return true end,readiness=function()return true,{web={ready=true,generation=generation}}end,stop=function()stops=stops+1;return true end,renew=function()return true end}
local function controller()return require('product-controller').new(provider,{clock=function()return {now=now,boot_id='test',trusted=true}end})end
local C=controller();local s=C.start(1,true);assert(s.runtime.phase=='running');assert(dns==1)
local expiry=s.runtime.expires_at
config.services[1].hostname='pending.example.com';assert(P.handle{action='save',expected_revision=1,config=config})
now=150;s=controller().restore(true)
assert(s.runtime.phase=='running','explicit restart must restore despite boot_restore=false')
assert(s.active_revision==1 and s.saved_revision==2 and seen.services[1].hostname=='old.example.com','restart active not saved')
assert(s.runtime.expires_at==expiry and ttl==(expiry-now)*1000,'restart must not extend deadline')
assert(s.desired_state.state=='enabled' and not s.desired_state.manual_stop_latch and dns==1,'intent and no DDNS')
assert(P.controller_transaction(function(v)v.runtime.attempt_count=3 end))
s=controller().restore(true);assert(s.runtime.phase=='running' and s.runtime.attempt_count<=3,'explicit restart has fresh bounded retry budget')
s=controller().restore();assert(s.runtime.phase=='stopped' and starts==3,'unmarked boot_restore=false remains stopped')
C=controller();C.stop();s=C.restore(true);assert(s.desired_state.manual_stop_latch and s.runtime.phase=='stopped' and starts==3,'manual stop remains stopped')
-- Expired bounded publication must not be resurrected by a valid handoff.
assert(P.controller_transaction(function(v)v.desired_state={state='enabled',manual_stop_latch=false};v.approval={revision=1};v.runtime.expires_at=expiry;v.runtime.clock_at=100;v.runtime.clock_trusted=true;v.runtime.boot_id='test' end))
now=expiry;s=controller().restore(true);assert(s.runtime.phase=='stopped' and s.desired_state.manual_stop_latch and starts==3,'expired deadline denied')
-- Real journal: repeated transient recovery must never exceed schema retry bound.
now=200;C=controller();fail_start=false;s=C.start(2,true);assert(s.runtime.phase=='running')
fail_start=true;provider.renew=function()return false,'bad listener',{kind='transient',code='lock_timeout'}end
for i=1,12 do now=now+10;s=C.tick();assert(not s.error,'retry journal error');assert(s.runtime.attempt_count<=3,'retry bound');end
assert(s.desired_state.state=='enabled' and not s.desired_state.manual_stop_latch,'fault must preserve intent')
fail_start=false;now=now+10;s=C.tick();assert(s.runtime.phase=='running','transient recovery must eventually succeed')
print('RESTART_CONTROLLER_GREEN')
