"""Local runtime/controller regressions: uv run --python 3.13 --with lupa <file>."""
import pathlib
import unittest
from lupa.lua51 import LuaRuntime

SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'files/usr/share/homepublish'

class StartupTests(unittest.TestCase):
    def lua(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().source = SOURCE.as_posix()
        lua.execute("package.path=source..'/?.lua;'..package.path")
        return lua

    def test_component_health_never_contacts_targets(self):
        self.lua().execute('''
package.loaded['direct-renderer']={};package.loaded['direct-backend']={};package.loaded['device-integrations']={}
local healthy=true
package.loaded['product-procd-group']={new=function()return {healthy=function()return healthy,'sslh process is not running' end}end}
os.execute=function()error('startup must not execute network probes')end
io.popen=function()error('startup must not execute TLS/HTTP probes')end
package.preload.nixio=function()error('startup must not open sockets')end
local V=require('product-v2-runtime').new({available=function()return true end,probe_address=function()return '192.0.2.1' end})
local p={generation=42,listeners={{address='192.0.2.1',port=443}},services={
 {service_id='web',type='https_proxy',hostname='web.example.test'}, {service_id='tls',type='tls_passthrough',hostname='tls.example.test'},
 {service_id='ssh',type='ssh'}, {service_id='tcp',type='tcp_forward',listen_port=2222}}}
local ok,results=V.readiness(p);assert(ok,'healthy components must start even with unavailable targets')
for _,s in ipairs(p.services) do assert(results[s.service_id].ready and results[s.service_id].generation==42) end
healthy=false
local ok,results,err=V.readiness(p);assert(not ok and err=='sslh process is not running')
for _,s in ipairs(p.services) do assert(not results[s.service_id].ready) end
''')

    def test_controller_preserves_component_failure(self):
        self.lua().execute('''
package.loaded['product-wire']={encode=function(v)return v end,decode=function(v)return v end}
local config={schema_version=2,services={{service_id='web'}},publication_policy={mode='persistent'}}
local state
local function reset() state={saved_revision=1,saved_config=config,intent_revision=0,desired_state={state='disabled'},runtime={phase='stopped',generation=0,cleanup='confirmed'},capabilities={}} end
package.loaded['product-provider']={handle=function()return state end,controller_transaction=function(fn)fn(state);return state end}
local fail_start=true;local stops=0
local p={runtime_plan=function(c)return c end,plan=function(c)return c end,
 start=function()return not fail_start,'nginx configuration test failed' end,
 readiness=function()return false,{web={ready=false,generation=1}},'sslh process is not running' end,
 stop=function()stops=stops+1;return true end}
reset();local c=require('product-controller').new(p)
local s=c.start(1,true);assert(s.runtime.last_error=='nginx configuration test failed',tostring(s.runtime.last_error));assert(s.runtime.stage=='start' and s.runtime.cleanup=='confirmed' and stops==1)
reset();fail_start=false;c=require('product-controller').new(p)
s=c.start(1,true);assert(s.runtime.last_error=='sslh process is not running',tostring(s.runtime.last_error));assert(s.runtime.stage=='readiness' and not s.runtime.services.web.ready)
reset();p.start=function()return false end;c=require('product-controller').new(p)
assert(c.start(1,true).runtime.last_error=='provider start failed')
reset();p.start=function()return false,'nginx: bind failed\\n'..string.rep('x',300) end;c=require('product-controller').new(p)
local reason=c.start(1,true).runtime.last_error
assert(#reason<=128 and not reason:find('[%c]') and reason:find('nginx: bind failed',1,true),'failure must obey existing journal bounds')
''')

    def test_plan_start_renew_keep_address_safety_without_target_probes(self):
        self.lua().execute('''
local resolves=0;local starts=0;local authorized=true
package.loaded['device-integrations']={resolve=function(host)resolves=resolves+1;assert(host=='late.home');return {addresses={'192.168.1.9'},ttl=30,observed_at=100,resolver='fixture'} end}
package.loaded['network-inventory']={collect=function()return {} end,resolve=function(l)return l end}
package.loaded['product-procd-group']={new=function()return {healthy=function()return true end,start=function(p,g)starts=starts+1;p.generation=g;return true end,stop=function()return true end}end}
package.preload.nixio=function()error('must not open target sockets')end
io.popen=function()error('must not run target probes')end
os.execute=function()error('must not run target probes')end
local clock=100;os.time=function()return clock end
local c={schema_version=2,services={},access_profile={listeners={{listener_id='lan4',family='ipv4',network='lan',address='192.168.1.2',port=24443}}},publication_policy={mode='continuous',boot_restore=false}}
for i=1,2 do c.services[i]={service_id='tcp'..i,name='TCP'..i,enabled=true,type='tcp_forward',listen_port=24443+i,backend={addressFamily=i==1 and 'ipv4' or 'hostname',host=i==1 and '192.168.1.8' or 'late.home',port=22,allowed_ranges={'192.168.1.0/24'}},authentication_review={authentication='confirmed',management=false}} end
local V=require('product-v2-runtime').new({available=function()return true end,authorize=function()return true end,authorize_listener=function()return true end,authorize_backend=function()return authorized end,narrow=function(s)return s end,root='/tmp/homepublish-test'})
local p,e=V.plan(c);assert(p,e);assert(p.selected.tcp1.address=='192.168.1.8' and p.selected.tcp2.address=='192.168.1.9')
assert(V.start(p,9) and starts==1);local ok,out=V.readiness(p);assert(ok and out.tcp1.ready and out.tcp2.ready)
clock=131;assert(V.renew(),'target unavailability must not trigger group recovery');assert(resolves>=2)
authorized=false;assert(not V.plan(c),'backend ownership must remain enforced')
authorized=true;c.services[1].backend.host='8.8.8.8';assert(not V.plan(c),'public target must remain rejected')
''')

    def test_existing_backend_and_canonical_regressions(self):
        for name, root_arg in [('test-direct.lua', SOURCE), ('test-canonical.lua', SOURCE.parents[4]), ('test-certificate-model.lua', SOURCE.parents[4]), ('test-certificate-san.lua', SOURCE.parents[4])]:
            with self.subTest(name=name):
                lua = self.lua()
                lua.globals().arg = lua.table_from({1: root_arg.as_posix()})
                lua.execute((SOURCE.parents[3] / 'tests' / name).read_text(encoding='utf-8'))

    def test_runtime_forwards_start_failures(self):
        self.lua().execute('''
package.loaded['direct-renderer']={};package.loaded['direct-backend']={};package.loaded['device-integrations']={}
package.loaded['product-procd-group']={new=function()return {start=function()return false,'procd service registration failed' end}end}
local available=true
local V=require('product-v2-runtime').new({available=function()return available end})
local ok,err=V.start({},1);assert(not ok and err=='procd service registration failed')
available=false;ok,err=V.start({},1);assert(not ok and err=='installed v2 capability unavailable')
''')

    def test_device_readiness_regression_locally(self):
        lua = self.lua()
        lua.execute("package.loaded['direct-renderer']={};package.loaded['direct-backend']={};package.loaded['device-integrations']={}")
        lua.execute((SOURCE.parents[3] / 'tests/device-tcp-p5-readiness.lua').read_text(encoding='utf-8'))

    def test_procd_start_failure_paths(self):
        self.lua().execute('''
local fault;local listing={};local registered=false
local L=require('product-listeners');L.preflight=function()return true end
L.expected=function()return {{component='nginx',address='127.0.0.1',port=19001,label='shared'}} end
package.loaded['product-json']={encode=function()return '{}' end,decode=function(bytes)if bytes=='manifest' then return {{component='nginx'}} end;return listing end}
io.popen=function()if fault=='status' then return nil end;return {read=function()return '{}' end,close=function()return true end}end
io.open=function(path,mode)
 if fault=='write' and mode=='w' then return nil end
 return {write=function()return true end,close=function()return true end,read=function()return '1 sslh' end}
end
os.execute=function(cmd)
 if fault=='directory' and cmd:find('test ! -e ',1,true) then return 1 end
 if fault=='mkdir' and cmd:find('mkdir ',1,true) then return 1 end
 if fault=='copy' and cmd:find('; cp ',1,true) then return 1 end
 if cmd:find('service set',1,true) then registered=true;if fault=='register' then return 1 end end
 return 0
end
local G=require('product-procd-group').new({name='homepublish-test',root='/tmp/homepublish-test',nginx='/nginx',sslh='/sslh'})
for _,case in ipairs({{'status','procd service status unavailable'},{'directory','runtime directory already exists'},{'mkdir','runtime directory creation failed'},{'write','listener manifest write failed'},{'register','procd service registration failed'}}) do
 fault=case[1];local ok,err=G.start({configuration='test'},1);assert(not ok and err==case[2],tostring(err))
end
fault='copy';local ok,err=G.start({configuration='test',snapshots={{certificate='/tmp/homepublish-test/cert1.pem',key='/tmp/homepublish-test/key1.pem',source={certificate='/etc/acme/test.cer',key='/etc/acme/test.key'}}}},1)
assert(not ok and err=='certificate snapshot copy failed',tostring(err))
fault=nil;ok,err=G.start({configuration='test',sslh_configuration='test'},1)
assert(registered and not ok and err=='procd service is missing',tostring(err))
''')

    def test_procd_component_errors(self):
        self.lua().execute('''
local instances={nginx={command={'/nginx','-p','/tmp/homepublish-test/','-c','nginx.conf'},running=true,pid=123},sslh={command={'/sslh','-F','/tmp/homepublish-test/sslh.cfg'},running=true,pid=124}}
local listing={['homepublish-test']={instances=instances}};local generation='1 sslh';local proc=true
local L=require('product-listeners');L.family=function()return {nginx={},sslh={}},{} end;L.rows=function()return {} end;L.verify=function()return true end
package.loaded['product-json']={encode=function()return '{}' end,decode=function(bytes)if bytes=='manifest' then return {{component='nginx'}} end;return listing end}
io.popen=function()return {read=function()return '{}' end,close=function()return true end}end
io.open=function(path)
 if path:find('listeners.json',1,true) then return {read=function()return 'manifest' end,close=function()end} end
 if path:find('/proc/',1,true) then if not proc then return nil end;return {read=function()return 'stat' end,close=function()end} end
 if not generation then return nil end;return {read=function()return generation end,close=function()end}
end
local G=require('product-procd-group').new({name='homepublish-test',root='/tmp/homepublish-test',nginx='/nginx',sslh='/sslh'})
assert(G.healthy())
instances.sslh.running=false;local ok,err=G.healthy();assert(not ok and err=='sslh process is not running',tostring(err))
instances.sslh.running=true;proc=false;ok,err=G.healthy();assert(not ok and err=='nginx process is unavailable',tostring(err))
proc=true;generation=nil;ok,err=G.healthy();assert(not ok and err=='runtime generation is unavailable',tostring(err))
generation='1';instances.nginx.command={'/foreign'};ok,err=G.healthy();assert(not ok and err=='procd component ownership mismatch',tostring(err))
listing={};ok,err=G.healthy();assert(not ok and err=='procd service is missing',tostring(err))
''')

    def test_start_reports_configuration_failure(self):
        self.lua().execute('''
package.loaded['product-json']={encode=function()return '{}' end,decode=function()return {} end}
local L=require('product-listeners');L.preflight=function()return true end;L.expected=function()return {{component='nginx',address='127.0.0.1',port=19001,label='shared'}} end
io.popen=function()return {read=function()return '{}' end,close=function()return true end}end
io.open=function(path,mode)return {write=function()return true end,close=function()return true end,read=function()return 'nginx: [emerg] bind() failed: Address in use' end}end
os.execute=function(cmd)if cmd:find(' -t ',1,true) then return 1 end;return 0 end
local G=require('product-procd-group').new({name='homepublish-test',root='/tmp/homepublish-test',nginx='/nginx',sslh='/sslh'})
local ok,err=G.start({configuration='test'},1)
assert(not ok and type(err)=='string' and err:find('nginx configuration test failed',1,true) and err:find('Address in use',1,true),tostring(err))
''')

if __name__ == '__main__':
    unittest.main(verbosity=2)
