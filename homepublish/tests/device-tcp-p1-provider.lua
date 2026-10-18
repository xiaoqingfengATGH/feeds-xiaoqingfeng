local root='/root/homepublish-lua-store/p1'
local scope=dofile(root..'/device-p1-lua-scope.lua')
local P=scope.provider()
local W=dofile('/usr/share/homepublish/product-wire.lua')
local S=scope.store
local function copy(v) return W.decode(W.encode(v)) end
local c={schema_version=2,services={{service_id='tcp',name='TCP',enabled=true,type='tcp_forward',listen_port=24444,backend={addressFamily='ipv4',host='192.168.1.8',port=22,allowed_ranges={'192.168.1.0/24'}},authentication_review={authentication='confirmed',management=false}}},access_profile={listeners={{listener_id='lan4',family='ipv4',network='lan',address='192.168.1.2',port=24443}}},publication_policy={mode='continuous',boot_restore=false}}
local inv=assert(P.handle{action='network_inventory'});assert(inv.status=='ok' and #inv.networks>0,'scoped inventory missing')
print('PASS real scoped inventory')
assert(P.handle{action='save',expected_revision=0,config=c}.saved_revision==1)
local status=assert(P.handle{action='status'});assert(status.schema_versions[2]==2 and status.desired_state.state=='disabled' and status.active_config==nil)
local e=assert(P.handle{action='save',expected_revision=0,config=c});assert(e.error_code=='REVISION_CONFLICT')
local f=assert(P.handle{action='preflight',revision=1});assert(f.ready==false and f.inventory_summary==inv.summary)
local dependency=false;for _,b in ipairs(f.blockers) do if b.error_code=='DEPENDENCY_UNAVAILABLE' then dependency=true end end;assert(dependency,'unimplemented runtime reported ready')
assert(#f.endpoints==1 and f.endpoints[1].port==24444 and f.endpoints[1].device=='br-lan')
print('PASS v2 persistence, optimistic revision, Save not Start, truthful preflight and TCP-only endpoint')
assert(P.handle{action='preflight',revision=0}.error_code=='REVISION_CONFLICT')
local bad=copy(c);bad.access_profile.listeners[1].network='absent'
assert(P.handle{action='save',expected_revision=1,config=bad}.saved_revision==2)
f=assert(P.handle{action='preflight',revision=2});assert(f.blockers[1].error_code=='NETWORK_UNAVAILABLE')
bad=copy(c);bad.access_profile.listeners[1].address='192.168.1.250'
assert(P.handle{action='save',expected_revision=2,config=bad}.saved_revision==3)
f=assert(P.handle{action='preflight',revision=3});assert(f.blockers[1].error_code=='ADDRESS_UNAVAILABLE')
print('PASS precise live network/address blockers and stale preflight')
local v1={schema_version=1,services={},access_profile={methods_allowed={'manual_ipv4'},listeners={{family='ipv4',address='192.168.1.2',interface='lan',zone='lan',protocol='tcp',internal_port=24443,external_port=24443}}},publication_policy={mode='continuous',boot_restore=false}}
local state={state_version=1,saved_revision=5,saved_config=v1,active_revision=4,active_config=v1,intent_revision=0,desired_state={state='disabled',manual_stop_latch=false},runtime={phase='stopped'}}
assert(S.transaction(function() return W.encode(state),true end))
local old=S.migration_backup;S.migration_backup=nil
e=assert(P.handle{action='save',expected_revision=5,config=c});assert(e.error_code=='DEPENDENCY_UNAVAILABLE')
status=assert(P.handle{action='status'});assert(status.saved_revision==5 and status.saved_config.schema_version==1 and status.active_config.schema_version==1)
S.migration_backup=old
local value,legacy_error=P.handle{action='save',expected_revision=0,config=v1};assert(value==nil and type(legacy_error)=='string')
if old==true then
 local migrated=assert(P.handle{action='save',expected_revision=5,config=c})
 assert(migrated.saved_revision==6 and migrated.saved_config.schema_version==2 and migrated.active_revision==4 and migrated.active_config.schema_version==1)
 local backup=assert(io.open(root..'/store/migration-v1','rb'));local bytes=backup:read('*a');backup:close();assert(bytes==W.encode(state),'migration backup not exact original journal')
 assert(S.transaction(function() return W.encode(state),true end))
 assert(os.execute('chmod 644 '..root..'/store/migration-v1')==0)
 local rejected,reason=P.handle{action='save',expected_revision=5,config=c};assert(rejected==nil and type(reason)=='string')
 local preserved=assert(P.handle{action='status'});assert(preserved.saved_revision==5 and preserved.saved_config.schema_version==1 and preserved.active_config.schema_version==1)
 assert(os.execute('chmod 600 '..root..'/store/migration-v1')==0)
 assert(P.handle{action='save',expected_revision=5,config=c}.saved_revision==6)
 print('PASS unsafe backup rejects provider transition without state change; equal private backup safely reusable')
 print('PASS transaction-backed migration original backup and active v1 preservation')
end
assert(type(select(2,P.handle{action='status',path='/tmp'}))=='string','legacy nil/string API changed')
print('PASS older-store transition gate preserves saved and active v1; legacy malformed request API')
local function command(cmd)
 local p=assert(io.popen(cmd));local b=p:read('*a');p:close();return b
end
local J=dofile('/usr/share/homepublish/product-json.lua')
local function encode(method,body)
 return command("printf '%s' '"..body.."' | lua "..'/usr/share/homepublish/product-rpc.lua '..method)
end
local encoded=encode('network_inventory','{}');assert(W.decode(encoded).action=='network_inventory','inventory transport unavailable')
assert(W.decode(encode('preflight','{"revision":5}')).revision==5)
local function call(method,body)
 return J.decode(command("printf '%s' '"..body.."' | lua "..'/usr/share/homepublish/product-rpc.lua '..method..' | lua '..root..'/cli.lua | lua /usr/share/homepublish/product-rpc.lua response'))
end
assert(call('preflight','{"revision":0}').error_code=='REVISION_CONFLICT')
assert(call('network_inventory','{"path":"/etc/shadow"}').error_code=='INVALID_CONFIG')
assert(call('preflight','{"revision":"5"}').error_code=='INVALID_CONFIG')
assert(call('validate','{"config":{"schema_version":99}}').error_code=='UNSUPPORTED_SCHEMA')
assert(call('network_inventory','{}').status=='ok')
for _,body in ipairs({'{"expected_revision":"6","config":{}}','{"expected_revision":-1,"config":{}}','{"expected_revision":1.5,"config":{}}','{"config":{}}'}) do
 assert(call('save',body).error_code=='INVALID_CONFIG','save revision type guard failed')
end
print('PASS final save revision transport guards')
print('PASS scoped transport encoding, malformed fields/types, structured errors and real inventory')
