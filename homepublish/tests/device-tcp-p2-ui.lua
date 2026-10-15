-- Device only. Fixed private journal; no installed store or runtime activation.
local root='/tmp/homepublish-p2-ui'
package.path=root..'/?.lua;'..package.path
package.cpath=root..'/?.so;'..package.cpath
local P=dofile(root..'/product-provider.lua')
local W=dofile(root..'/product-wire.lua')
local J=dofile(root..'/product-json.lua')
if arg[1]=='seed-v1' then
 local c={schema_version=1,services={},access_profile={methods_allowed={'manual_ipv4'},listeners={{family='ipv4',address='192.168.1.2',interface='lan',zone='lan',protocol='tcp',internal_port=24443,external_port=24444}}},publication_policy={mode='continuous',boot_restore=false}}
 local s={state_version=1,saved_revision=1,saved_config=c,intent_revision=0,desired_state={state='disabled',manual_stop_latch=false},runtime={phase='stopped',cleanup='confirmed'}}
 assert(require('homepublish_store').transaction(function()return W.encode(s),true end));print('seeded private v1');return
end
if arg[1]=='test-preview' then
 local before=assert(P.handle{action='status'})
 local p=assert(P.handle{action='migration_preview',expected_revision=before.saved_revision})
 assert(p.proposed_config and p.proposed_config.schema_version==2,'missing read-only migration preview')
 assert(P.handle{action='status'}.saved_revision==before.saved_revision)
 assert(P.handle{action='migration_preview',expected_revision=0}.error_code=='REVISION_CONFLICT')
 print('PASS preview read-only, complete proposed model and stale revision');return
end
local req=J.decode(io.read('*a'));req.action=arg[1]
assert(({status=true,certificates=true,network_inventory=true,validate=true,save=true,migration_preview=true})[req.action],'method rejected')
local value,err=P.handle(req,true)
if not value then value=type(err)=='table' and err or {error='Private target request failed',error_code='STATE_UNKNOWN'} end
io.write(J.encode(value))
