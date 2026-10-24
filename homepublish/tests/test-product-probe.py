"""Host-only Lua probe contract tests; no device writes or network calls."""
import pathlib, unittest
from lupa.lua51 import LuaRuntime
ROOT=pathlib.Path(__file__).resolve().parents[1]/'files/usr/share/homepublish'
class ProbeTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.globals().module_path=str(ROOT/'product-probe.lua').replace('\\','/')
 def test_saved_service_success_and_no_active_claim(self):
  self.lua.execute('''
   local M=dofile(module_path)
   local r=M.probe({service_id='web'}, {
    snapshot=function()return {saved_revision=7,active_revision=6,saved_config={services={{service_id='web',backend={host='192.168.1.2',port=80,addressFamily='ipv4',allowed_ranges={'192.168.1.0/24'}}}}}} end,
    bounded=function(phase,ms,fn) assert(phase=='connect' and ms==3000);return fn() end,
    connect=function(host,port,family)assert(host=='192.168.1.2' and port==80 and family=='ipv4');return {ok=true} end
   })
   assert(r.ok==true and r.saved_revision==7 and r.active_revision==6)
   assert(r.config_source=='saved' and r.origin=='router' and r.public_reachability=='unverified')
   assert(r.phase=='complete' and r.reason=='TCP_CONNECTED' and r.application_health=='unverified')
  ''')
 def test_validation_scope_and_failure_phases(self):
  self.lua.execute('''
   local M=dofile(module_path)
   local touched=0
   for _,id in ipairs({'x;id','../state','a b',string.rep('x',65),''}) do
    local r=M.probe({service_id=id},{snapshot=function()touched=touched+1 end})
    assert(not r.ok and r.reason=='INVALID_REQUEST')
   end
   assert(touched==0)
   local state={saved_revision=2,active_revision=1,saved_config={services={{service_id='web',backend={host='host.example',port=443,addressFamily='hostname',allowed_ranges={'192.168.1.0/24'}}}}}}
   local calls=0
   local d={snapshot=function()return state end, bounded=function(phase,ms,fn)assert(ms==(phase=='resolve' and 2000 or 3000));return fn() end,
    resolve=function()return {ok=true,addresses={'192.168.1.2'}} end,
    connect=function()calls=calls+1;return {ok=false,reason='CONNECTION_REFUSED'} end}
   local r=M.probe({service_id='web'},d);assert(r.phase=='connect' and r.reason=='CONNECTION_REFUSED' and calls==1)
   d.resolve=function()return {ok=true,addresses={'192.168.1.2','8.8.8.8'}} end
   r=M.probe({service_id='web'},d);assert(r.phase=='scope' and calls==1)
   d.resolve=function()return {ok=false,reason='TIMEOUT'} end
   r=M.probe({service_id='web'},d);assert(r.phase=='resolve' and r.reason=='TIMEOUT')
   r=M.probe({service_id='missing'},d);assert(r.reason=='SERVICE_NOT_FOUND')
   state.saved_config.services[1].enabled=false
   r=M.probe({service_id='web'},d);assert(r.reason=='SERVICE_DISABLED' and calls==1)
   state.saved_config=nil
   r=M.probe({service_id='web'},d);assert(r.reason=='NO_SAVED_CONFIG')
   d.snapshot=function()error('private path must not escape')end
   r=M.probe({service_id='web'},d);assert(r.reason=='STATE_UNAVAILABLE' and not r.summary:find('private'))
  ''')
 def test_device_adapter_exists_and_uses_readonly_snapshot(self):
  adapter=ROOT/'product-probe-device.lua'
  self.assertTrue(adapter.exists(), 'missing bounded device adapter')
  self.lua.globals().adapter_path=str(adapter).replace('\\','/')
  self.lua.execute('''
   local M=dofile(adapter_path)
   local d=M.new()
   assert(type(d.snapshot)=='function' and type(d.bounded)=='function')
  ''')
 def test_rpc_route_and_read_acl(self):
  import json
  repo=ROOT.parents[4]
  rpc=(repo/'luci-app-homepublish/root/usr/libexec/rpcd/homepublish').read_text()
  acl=json.loads((repo/'luci-app-homepublish/root/usr/share/rpcd/acl.d/luci-app-homepublish.json').read_text())['luci-app-homepublish']
  self.assertIn('"probe":{"service_id":""}',rpc)
  self.assertIn('call:probe)',rpc)
  self.assertIn('product-probe-rpc.lua',rpc)
  self.assertIn('probe',acl['read']['ubus']['homepublish'])
  self.assertNotIn('probe',acl['write']['ubus']['homepublish'])
 def test_rpc_rejects_injected_fields_and_session(self):
  rpc=ROOT/'product-probe-rpc.lua'
  self.assertTrue(rpc.exists(), 'missing RPC entrypoint')
  self.lua.globals().rpc_path=str(rpc).replace('\\','/')
  self.lua.execute('''
   local input='{"service_id":"web","command":"touch /tmp/no"}'
   local output=''
   io.stdin={read=function()return input end}
   io.stdout={write=function(self,...)for _,v in ipairs({...})do output=output..v end end}
   arg={};dofile(rpc_path)
   local J=dofile(module_path:gsub('product%-probe.lua$','product-json.lua'))
   local r=J.decode(output);assert(not r.ok and r.phase=='request' and r.reason=='INVALID_REQUEST')
   output='';input='{"service_id":"web","ubus_rpc_session":"bad"}';dofile(rpc_path)
   r=J.decode(output);assert(not r.ok and r.reason=='INVALID_REQUEST')
  ''')
 def test_bounded_worker_timeout_is_killed_and_reaped(self):
  self.lua.globals().adapter_path=str(ROOT/'product-probe-device.lua').replace('\\','/')
  self.lua.execute('''
   local closed,killed,reaped=0,false,false
   local n={pipe=function()return {close=function()closed=closed+1 end}, {close=function()closed=closed+1 end} end,
    fork=function()return 42 end,poll_flags=function()return 1 end,
    poll=function(fds,ms)assert(ms==2000);return false end,
    kill=function(pid,sig)assert(pid==42 and sig==9);killed=true end,
    waitpid=function(pid)assert(pid==42 and killed);reaped=true end}
   package.loaded.nixio=n
   local d=dofile(adapter_path).new()
   local r=d.bounded('resolve',2000,function()error('parent must not execute worker')end)
   assert(r.reason=='TIMEOUT' and not r.ok and killed and reaped and closed==2)
  ''')
 def test_resolver_uses_nixio_signature_and_deduplicates(self):
  self.lua.globals().adapter_path=str(ROOT/'product-probe-device.lua').replace('\\','/')
  self.lua.execute('''
   package.loaded.nixio={getaddrinfo=function(host,...)
    assert(host=='backend.example' and select('#',...)==0,'nixio resolver signature')
    return {{family='inet',address='192.168.1.2'},{family='inet',address='192.168.1.2'},{family='inet6',address='fd00::2'}}
   end}
   local r=dofile(adapter_path).new().resolve('backend.example')
   assert(r.ok and #r.addresses==2)
  ''')
 def test_connection_error_summary_is_specific(self):
  self.lua.execute('''
   local r=dofile(module_path).probe({service_id='web'},{
    snapshot=function()return {saved_revision=1,saved_config={services={{service_id='web',backend={host='192.168.1.2',port=80,addressFamily='ipv4',allowed_ranges={'192.168.1.0/24'}}}}}} end,
    bounded=function(_,_,fn)return fn() end,
    connect=function()return {ok=false,reason='CONNECTION_REFUSED'} end})
   assert(r.summary:lower():find('refused',1,true))
  ''')
 def test_snapshot_is_readonly_and_does_not_take_controller_lock(self):
  self.lua.globals().adapter_path=str(ROOT/'product-probe-device.lua').replace('\\','/')
  self.lua.execute('''
   local dir={type='dir',uid=0,modedec=700}
   local state={state_version=1,saved_revision=0}
   local W=dofile(module_path:gsub('product%-probe.lua$','product-wire.lua'))
   local bytes=W.encode(state)
   local st={type='reg',uid=0,modedec=600,size=#bytes}
   local opened=0
   package.loaded['nixio.fs']={lstat=function(path)
    assert(path=='/etc/homepublish/product' or path=='/etc/homepublish/product/state')
    return path:sub(-6)=='/state' and st or dir
   end}
   package.loaded.nixio=setmetatable({}, {__index=function()error('snapshot must not call process/lock APIs')end})
   io.open=function(path,mode)
    assert(path=='/etc/homepublish/product/state' and mode=='rb');opened=opened+1
    return {read=function(_,n)assert(n==262145);return bytes end,close=function()return true end}
   end
   local d=dofile(adapter_path).new()
   assert(d.snapshot().saved_revision==0 and opened==1)
   st.type='lnk';assert(not pcall(d.snapshot));assert(opened==1)
   st.type='reg';st.modedec=644;assert(not pcall(d.snapshot));assert(opened==1)
   st.modedec=600;st.size=262145;assert(not pcall(d.snapshot));assert(opened==1)
   st.size=#bytes;dir.uid=1000;assert(not pcall(d.snapshot));assert(opened==1)
  ''')
 def test_worker_success_failure_and_fork_cleanup(self):
  self.lua.globals().adapter_path=str(ROOT/'product-probe-device.lua').replace('\\','/')
  self.lua.execute('''
   local payload='{"ok":true}'
   local closed,killed,reaped=0,0,0
   local n={pipe=function()return {close=function()closed=closed+1 end,read=function()return payload end}, {close=function()closed=closed+1 end} end,
    fork=function()return 42 end,poll_flags=function()return 1 end,poll=function()return 1 end,
    kill=function()killed=killed+1 end,waitpid=function()reaped=reaped+1 end}
   package.loaded.nixio=n
   local d=dofile(adapter_path).new()
   assert(d.bounded('connect',3000,function()end).ok)
   payload='broken';assert(d.bounded('connect',3000,function()end).reason=='PROBE_FAILED')
   n.poll=function()return nil end
   assert(d.bounded('connect',3000,function()end).reason=='PROBE_UNAVAILABLE')
   assert(closed==6 and killed==3 and reaped==3)
   n.fork=function()return nil end
   assert(d.bounded('connect',3000,function()end).reason=='PROBE_UNAVAILABLE')
   assert(closed==8 and killed==3 and reaped==3)
  ''')
 def test_connect_errno_and_no_application_payload(self):
  self.lua.globals().adapter_path=str(ROOT/'product-probe-device.lua').replace('\\','/')
  self.lua.execute('''
   local code,closed=111,0
   package.loaded.nixio={const={ECONNREFUSED=111,ETIMEDOUT=110,ENETUNREACH=101,EHOSTUNREACH=113,EACCES=13},socket=function(family,kind)
    assert(family=='inet6' and kind=='stream')
    return {connect=function(_,address,port)assert(address=='fd00::2' and port==22);return nil,code end,close=function()closed=closed+1 end}
   end}
   local d=dofile(adapter_path).new()
   for errno,reason in pairs({[111]='CONNECTION_REFUSED',[110]='TIMEOUT',[101]='NETWORK_UNREACHABLE',[113]='HOST_UNREACHABLE',[13]='PERMISSION_DENIED',[999]='CONNECT_FAILED'})do
    code=errno;assert(d.connect('fd00::2',22,'ipv6').reason==reason)
   end
   assert(closed==6)
  ''')
 def test_real_saved_config_validation_and_ipv6_probe(self):
  self.lua.globals().adapter_path=str(ROOT/'product-probe-device.lua').replace('\\','/')
  self.lua.execute('''
   local model=dofile(module_path:gsub('product%-probe.lua$','canonical.lua'))
   local c={schema_version=1,services={{service_id='nas',name='NAS',hostname='nas.example.test',backend={addressFamily='ipv6',host='fd00::10',port=8080,allowed_ranges={'fd00::/64'}},certificate_ref='acme:nas',authentication_review={authentication='confirmed',management=false}}},access_profile={methods_allowed={'manual_ipv4'},listeners={{family='ipv4',address='192.168.1.2',interface='wan',zone='wan',protocol='tcp',internal_port=8443,external_port=18443}}}}
   local config=assert(model.validate(c))
   local r=dofile(module_path).probe({service_id='nas'},{snapshot=function()return {saved_revision=3,saved_config=config}end,
    bounded=function(_,_,fn)return fn()end,connect=function(host,port,family)assert(host=='fd00::10' and family=='ipv6' and port==8080);return {ok=true}end})
   assert(r.ok and r.backend.family=='ipv6' and r.addresses_tested==1 and r.backup_tested==false)
  ''')
 def test_missing_snapshot_and_stat_errors_are_distinct(self):
  self.lua.globals().adapter_path=str(ROOT/'product-probe-device.lua').replace('\\','/')
  self.lua.execute('''
   package.loaded['nixio.fs']={lstat=function()return nil,2 end}
   local d=dofile(adapter_path).new()
   assert(d.snapshot().saved_revision==0)
   package.loaded['nixio.fs'].lstat=function(path)
    if path=='/etc/homepublish/product' then return {type='dir',uid=65534,modedec=493} end
    return nil,13
   end
   assert(not pcall(d.snapshot),'permission failure is not absence')
  ''')
 def test_rpc_valid_session_and_size_limit(self):
  self.lua.globals().rpc_path=str(ROOT/'product-probe-rpc.lua').replace('\\','/')
  self.lua.execute('''
   local input='{"service_id":"web","ubus_rpc_session":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
   local output=''
   package.loaded['nixio.fs']={lstat=function()return nil,2 end}
   io.stdin={read=function(_,n)assert(n==4097);return input end}
   io.stdout={write=function(self,...)for _,v in ipairs({...})do output=output..v end end}
   arg={};dofile(rpc_path)
   local J=dofile(module_path:gsub('product%-probe.lua$','product-json.lua'))
   local r=J.decode(output)
   assert(r.reason=='NO_SAVED_CONFIG' and r.saved_revision==0 and r.service_id=='web')
   assert(not r.ubus_rpc_session)
   input=string.rep('x',4097);output='';dofile(rpc_path)
   r=J.decode(output);assert(r.reason=='INVALID_REQUEST' and r.phase=='request')
   input='{';output='';dofile(rpc_path)
   r=J.decode(output);assert(r.reason=='INVALID_REQUEST')
  ''')
 def test_connect_uses_portable_errno_not_x86_numbers(self):
  self.lua.globals().adapter_path=str(ROOT/'product-probe-device.lua').replace('\\','/')
  self.lua.execute('''
   package.loaded.nixio={const={ENETUNREACH=128,EACCES=13},socket=function()
    return {connect=function()return nil,146,'Connection refused' end,close=function()end}
   end}
   local d=dofile(adapter_path).new()
   assert(d.connect('192.168.1.2',80,'ipv4').reason=='CONNECTION_REFUSED')
  ''')
if __name__=='__main__':unittest.main(verbosity=2)
