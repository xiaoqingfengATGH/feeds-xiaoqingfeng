-- SPDX-License-Identifier: Apache-2.0
-- Internal test-only loader. Never installed by the runtime package.
-- Scope the exact provider dependency without accepting a root from RPC/env.
local source=assert(arg[1], 'source directory required')
local root=assert(arg[2], 'private store root required')
assert(root:match('^/root/homepublish%-lua%-store/provider%-%w+$'), 'unsafe fixture root')
local fs=require('nixio.fs')
assert(fs.mkdir(root,'700') or fs.lstat(root).type=='dir')
local core=dofile(source..'/product-store-core.lua')
local store=core.new(root)
local original=dofile
_G.dofile=function(path)
 if path==source..'/product-store.lua' then return store end
 return original(path)
end
local P=dofile(source..'/product-provider.lua')
_G.dofile=original
local W=dofile(source..'/product-wire.lua')
assert(P.handle{action='status'}.saved_revision==0)
local config={schema_version=2,services={},access_profile={listeners={{listener_id='lan',family='ipv4',network='lan',address='192.168.1.2',port=24443}}},publication_policy={mode='continuous',boot_restore=false}}
local saved=assert(P.handle({action='save',expected_revision=0,config=config},true))
assert(saved.saved_revision==1 and saved.desired_state.state=='disabled')
local before=assert(io.open(root..'/state','rb'));local bytes=before:read('*a');before:close()
local conflict=assert(P.handle({action='save',expected_revision=0,config=config},true))
assert(conflict.error_code=='REVISION_CONFLICT')
local status=assert(P.handle{action='status'})
assert(status.saved_revision==1 and status.active_revision==nil)
local after=assert(io.open(root..'/state','rb'));assert(after:read('*a')==bytes);after:close()
assert(P.controller_transaction(function(s) s.intent_revision=s.intent_revision+1 end).intent_revision==1)
assert(P.handle{action='status'}.saved_revision==1)
assert(package.loaded.homepublish_store==nil, 'native store loaded')
print('PROVIDER_LUA_SAVE_CONFLICT_CONTROLLER_GREEN')
