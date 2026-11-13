-- Private target-Lua renew classification/recovery contract.
local source=assert(arg[1]);package.path=source..'/?.lua;'..package.path
package.loaded['direct-renderer']={};package.loaded['direct-backend']={};package.loaded['device-integrations']={}
package.loaded['product-procd-group']={new=function()return {healthy=function()return true end,start=function()return true end,stop=function()return true end}end}
local calls=0
local firewall={reconcile=function()calls=calls+1;return false,'fw4 lock wait timed out',{kind='transient',code='lock_timeout'}end,clear=function()return true end,status=function()return {state='open'}end}
local V=require('product-v2-runtime').new({available=function()return true end,firewall=firewall})
local p={generation=7,services={},listeners={},snapshots={},firewall_rules={}}
assert(V.start(p,7,10000));local ok,detail,class=V.renew()
assert(not ok and detail=='fw4 lock wait timed out' and class.kind=='transient' and class.code=='lock_timeout' and calls==1,'runtime classification')

package.loaded['product-wire']={encode=function(v)return v end,decode=function(v)return v end}
local config={schema_version=2,services={{service_id='web'}},publication_policy={mode='continuous'}}
local state={saved_revision=1,saved_config=config,active_revision=1,active_config=config,intent_revision=1,desired_state={state='enabled',manual_stop_latch=false},approval={revision=1},runtime={phase='running',generation=1,cleanup='confirmed',active_verified=true},capabilities={}}
package.loaded['product-provider']={handle=function()return state end,controller_transaction=function(fn)fn(state);return state end}
local stops=0;local now=100
local provider={runtime_plan=function(c)return c end,plan=function(c)return c end,stop=function()stops=stops+1;return true end,renew=function()return false,'lock wait expired',{kind='transient',code='lock_timeout'}end}
local C=require('product-controller').new(provider,{clock=function()return {now=now,boot_id='b',trusted=true}end});C.generation=1
local s=C.tick(1);assert(s.runtime.phase=='running' and stops==0 and s.runtime.next_retry==101,'grace first')
now=101;s=C.tick(1);assert(s.runtime.phase=='running' and s.runtime.next_retry==103,'grace second')
now=103;s=C.tick(1);assert(s.runtime.phase=='running' and s.runtime.next_retry==107,'grace third')
now=107;s=C.tick(1);assert(s.runtime.phase=='retry_wait' and stops==1 and state.desired_state.state=='enabled' and not state.desired_state.manual_stop_latch,'bounded grace preserves intent')

package.loaded['product-json']={encode=function()return '{}' end,decode=function()error('no worker result')end}
package.loaded.nixio={getpid=function()return 321 end,sysinfo=function()return {uptime=100}end}
package.loaded['nixio.fs']={mkdir=function()return true end,lstat=function()return {uid=0,type='dir'}end,chmod=function()return true end,unlink=function()end,rmdir=function()end}
io.open=function(path,mode)
 if path=='/proc/321/stat' then return {read=function()return '321 (lua) S '..string.rep('0 ',18)..'12345' end,close=function()end} end
 if mode=='w' then return {write=function()return true end,close=function()return true end} end
 return nil
end
local command_count=0;os.execute=function(cmd)command_count=command_count+1;return command_count==1 and 0 or 124*256 end
local F=require('product-firewall-system');local fok,fdetail,fclass=F.reconcile({},10)
assert(not fok and fclass.kind=='transient' and fclass.code=='lock_timeout' and fdetail=='firewall lock/worker timeout','firewall classification')
print('DEVICE_RENEW_CLASSIFICATION_GREEN')
