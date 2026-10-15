-- Device-only full JSON -> RPC wire -> public CLI -> RPC JSON fault regressions.
-- Stage sources + scoped SDK-built homepublish_store.so + fault.so in this fixed
-- private root. Never run this against installed paths. No listeners/config writes.
-- Build fault.so with SDK gcc -shared -fPIC -x c (extract FAULT_C below).
-- Build product-store.c with -DPRODUCT_ROOT='"/tmp/homepublish-tcp-p1-errors/store"'.
-- Run: lua /tmp/homepublish-tcp-p1-errors/device-tcp-p1-errors.lua [network|store|all]
local FAULT_C = [=[
#define _GNU_SOURCE
#include <unistd.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <errno.h>
#include <stdlib.h>
/* Only this process, only a directory descriptor whose identity matches the
 * private compiled store. File fsync and other directories remain real. */
int fsync(int fd) {
 struct stat a,b;
 if(getenv("HP_ERRORS_DIRSYNC") && fstat(fd,&a)==0 && S_ISDIR(a.st_mode) &&
    stat("/tmp/homepublish-tcp-p1-errors/store",&b)==0 && a.st_dev==b.st_dev && a.st_ino==b.st_ino) {
  errno=EIO;return -1;
 }
 return syscall(SYS_fsync,fd);
}
]=]
local root='/tmp/homepublish-tcp-p1-errors'
assert(debug.getinfo(1,'S').source=='@'..root..'/device-tcp-p1-errors.lua','fixed private fixture only')
package.path=root..'/?.lua;'..package.path
local J=dofile(root..'/product-json.lua')
local W=dofile(root..'/product-wire.lua')
local function write(name,s) local f=assert(io.open(root..'/'..name,'wb'));assert(f:write(s));assert(f:close()) end
local function quote(s) return "'"..s:gsub("'","'\\''").."'" end
local function read(name) local f=assert(io.open(root..'/'..name,'rb'));local s=f:read('*a');f:close();return s end
local function run(s) assert(os.execute(s)==0,s) end
write('preload.lua',[[
local root='/tmp/homepublish-tcp-p1-errors'
local mode=assert(os.getenv('HP_ERRORS_MODE'))
local function marker(s) local f=assert(io.open(root..'/injected','w'));f:write(s);f:close() end
if mode=='connect' then
 package.preload.ubus=function() return {connect=function() marker('ubus connect failure');return nil end} end
elseif mode=='firewall' then
 package.preload.uci=function() return {cursor=function() return {load=function() marker('firewall load failure');return false end,unload=function() end} end} end
elseif mode=='malformed' then
 package.preload.ubus=function() return {connect=function() return {call=function() marker('malformed ubus inventory');return {interface='not an array'} end,close=function() end} end} end
else error('unknown fixture fault') end
arg={};dofile(root..'/product-cli.lua')
]])
local function call(method,body,mode)
 write('request.json',body);os.remove(root..'/injected')
 run('lua '..root..'/product-rpc.lua '..method..' < '..root..'/request.json > '..root..'/request.wire')
 local env='LUA_CPATH='..quote(root..'/?.so;;')..' '
 local cli=root..'/product-cli.lua'
 if mode=='dirsync' then env=env..'LD_PRELOAD='..root..'/fault.so HP_ERRORS_DIRSYNC=1 '
 elseif mode then env=env..'HP_ERRORS_MODE='..quote(mode)..' ';cli=root..'/preload.lua' end
 local status=os.execute(env..'lua '..cli..' < '..root..'/request.wire > '..root..'/response.wire 2> '..root..'/stderr')
 local raw=read('response.wire');local err=read('stderr')
 print('OBSERVE '..(mode or method)..' cli_exit='..tostring(status)..' wire_bytes='..#raw..' stderr_bytes='..#err)
 if #err>0 then print(err) end
 run('lua '..root..'/product-rpc.lua response < '..root..'/response.wire > '..root..'/response.json')
 local response=read('response.json');print(response)
 return J.decode(response),raw,err,status
end
local function safe_error(r,raw,stderr,status,code,field)
 assert(r.error_code==code,'expected '..code..', got '..tostring(r.error_code))
 assert(r.field==field and r.retryable==true,'structured field/retryable lost')
 assert(type(r.error)=='string' and #r.error>0,'missing message')
 assert(status~=0,'failure CLI returned success')
 assert(stderr=='' and not raw:find(root,1,true) and not raw:find('stack traceback',1,true),'path/stack leaked')
end
local mode=arg[1] or 'all'
if mode=='all' or mode=='network' then
 for _,fault in ipairs({'connect','firewall','malformed'}) do
  local r,raw,err,status=call('network_inventory','{}',fault)
  assert(#read('injected')>0,'fault not reached')
  safe_error(r,raw,err,status,'NETWORK_UNAVAILABLE','access_profile.listeners.network')
  assert(r.error=='Network inventory unavailable or malformed','safe structured message lost')
  print('PASS full transport '..fault)
 end
end
if mode=='all' or mode=='store' then
 -- Invocation-local journal; only fixed files owned by this private harness.
 for _,name in ipairs({'state','lock','candidate','migration-v1'}) do os.remove(root..'/store/'..name) end
 local config={schema_version=2,services={},access_profile={listeners={{listener_id='lan',family='ipv4',network='lan',address='192.168.1.2',port=24443}}},publication_policy={mode='continuous',boot_restore=false}}
 local s=call('status','{}');local revision=s.saved_revision
 assert(type(revision)=='number','status unavailable before fault')
 local r,raw,err,status=call('save',J.encode({expected_revision=revision,config=config}),'dirsync')
 safe_error(r,raw,err,status,'STATE_UNKNOWN','state')
 local after=call('status','{}');assert(after.saved_revision==revision+1,'rename not committed before directory fsync failure')
 assert(after.saved_config.schema_version==2,'readback config missing')
 print('PASS actual post-rename directory fsync EIO, STATE_UNKNOWN, revision '..revision..' -> '..after.saved_revision)
 run('chmod 755 '..root..'/store')
 r,raw,err,status=call('status','{}');run('chmod 700 '..root..'/store')
 safe_error(r,raw,err,status,'STATE_UNKNOWN','state')
 print('PASS unsafe store directory classified STATE_UNKNOWN')
 -- Force a real C migration_backup failure, not a fabricated provider response.
 local v1={schema_version=1,services={},access_profile={methods_allowed={'manual_ipv4'},listeners={{family='ipv4',address='192.168.1.2',interface='lan',zone='lan',protocol='tcp',internal_port=24443,external_port=24443}}},publication_policy={mode='continuous',boot_restore=false}}
 local seed={state_version=1,saved_revision=after.saved_revision,saved_config=v1,intent_revision=0,desired_state={state='disabled',manual_stop_latch=false},runtime={phase='stopped'}}
 write('seed.wire',W.encode(seed))
 write('seed.lua',"local f=assert(io.open('"..root.."/seed.wire','rb'));local b=f:read('*a');f:close();assert(require('homepublish_store').transaction(function() return b,true end))")
 run('LUA_CPATH='..quote(root..'/?.so;;')..' lua '..root..'/seed.lua')
 write('store/migration-v1','unsafe fixture');run('chmod 644 '..root..'/store/migration-v1')
 r,raw,err,status=call('save',J.encode({expected_revision=after.saved_revision,config=config}))
 safe_error(r,raw,err,status,'STATE_UNKNOWN','state')
 local preserved=call('status','{}');assert(preserved.saved_revision==after.saved_revision and preserved.saved_config.schema_version==1,'failed migration changed state')
 assert(read('store/migration-v1')=='unsafe fixture','foreign backup changed')
 os.remove(root..'/store/migration-v1')
 print('PASS native migration backup failure classified STATE_UNKNOWN; old journal and unsafe backup preserved')
end
print('TOTAL '..mode..' full transport fault regressions PASS')
