-- Device only. Fixed private journal; no installed store or runtime activation.
local root='/usr/share/homepublish'
package.path=root..'/?.lua;'..package.path
local function hash(path)
 local p=assert(io.popen('sha256sum '..path));local h=p:read('*l');assert(p:close());return assert(h):match('^(%x+)')
end
local baseline='19234e3e06d55ebde10f2b64fd0517c3b0a02c0dee976ccc681d71989ceb58b9'
assert(hash('/etc/homepublish/product/state')==baseline,'live journal baseline changed')
local f=assert(io.open(root..'/product-provider.lua','rb'));local bytes=f:read('*a');f:close()
assert(bytes:find("local store=dofile(source..'/product-store.lua')",1,true),'production Lua store required')
local store=dofile(root..'/product-store-core.lua').new('/root/homepublish-lua-store/p2-ui-store')
local original=dofile
_G.dofile=function(path) if path==root..'/product-store.lua' then return store end return original(path) end
local ok,P=pcall(original,root..'/product-provider.lua');_G.dofile=original;assert(ok,P)
assert(package.loaded.homepublish_store==nil,'native store loaded')
local W=dofile(root..'/product-wire.lua')
local J=dofile(root..'/product-json.lua')
if arg[1]=='seed-v1' then
 local c={schema_version=1,services={},access_profile={methods_allowed={'manual_ipv4'},listeners={{family='ipv4',address='192.168.1.2',interface='lan',zone='lan',protocol='tcp',internal_port=24443,external_port=24444}}},publication_policy={mode='continuous',boot_restore=false}}
 local s={state_version=1,saved_revision=1,saved_config=c,intent_revision=0,desired_state={state='disabled',manual_stop_latch=false},runtime={phase='stopped',cleanup='confirmed'}}
 assert(store.transaction(function()return W.encode(s),true end));assert(hash('/etc/homepublish/product/state')==baseline);print('seeded private Lua v1');return
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
assert(hash('/etc/homepublish/product/state')==baseline,'live journal changed during private request')
io.write(J.encode(value))
