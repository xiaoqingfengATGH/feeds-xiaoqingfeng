"""INPUT firewall adapter regressions; uv run --python 3.13 --with lupa this-file."""
import pathlib
import unittest
from lupa.lua51 import LuaRuntime

SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'files/usr/share/homepublish'

class FirewallTests(unittest.TestCase):
    def lua(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().source = SOURCE.as_posix()
        lua.execute("package.path=source..'/?.lua;'..package.path")
        lua.execute("""
function policy(snapshot)
 for _,z in ipairs({'wan','lan'}) do
  local t='reject_from_'..z
  table.insert(snapshot.nftables,{chain={family='inet',table='fw4',name=t}})
  table.insert(snapshot.nftables,{rule={family='inet',table='fw4',chain='input_'..z,handle=z=='wan' and 100 or 101,expr={{jump={target=t}}}}})
 end
 return snapshot
end
""")
        return lua

    def test_destination_scope_grouping_and_policy_order(self):
        self.lua().execute('''
local snapshot={nftables={
 {set={family='inet',table='fw4',name='homepublish_input_guard'}},
 {chain={family='inet',table='fw4',name='reject_from_wan'}},
 {rule={family='inet',table='fw4',chain='input_wan',handle=10,comment='user deny',expr={{drop={}}}}},
 {rule={family='inet',table='fw4',chain='input_wan',handle=20,expr={{jump={target='reject_from_wan'}}}}}}}
local batch;local F=require('product-firewall').new({snapshot=function()return snapshot end,apply=function(b)batch=b;return true end})
assert(F.reconcile({{family='ipv4',zone='wan',protocol='tcp',port=443,dest_ip='192.168.1.2'},
 {family='ipv4',zone='wan',protocol='tcp',port=443,dest_ip='192.168.1.3'}}))
assert(batch:find('position 20 meta nfproto ipv4 ip daddr 192.168.1.2 tcp dport',1,true),'must scope address after user deny, before terminal')
assert(batch:find('ip daddr 192.168.1.3',1,true),'same port on distinct destinations must not merge')
assert(not batch:find('handle 10',1,true),'must not touch user deny')
snapshot.nftables[4]=nil;batch=nil
assert(not F.reconcile({{family='ipv4',zone='wan',protocol='tcp',port=443}}) and batch==nil,'unknown terminal ordering must fail closed')
for _,ip in ipairs({'192.168.1.2; accept','::','192.168.1.2/24'}) do
 assert(not F.reconcile({{family='ipv4',zone='wan',protocol='tcp',port=443,dest_ip=ip}}))
end
''')

    def test_verify_rejects_broadened_destination_and_pre_user_filter_order(self):
        self.lua().execute('''
local F=require('product-firewall')
local rules={{family='ipv4',zone='wan',protocol='tcp',port=443,dest_ip='192.168.1.2'}}
local name='homepublish_in4_wan_a3139322e3136382e312e32'
local owned={family='inet',table='fw4',chain='input_wan',handle=15,comment='homepublish:input:v1',expr={
 {match={op='==',left={meta={key='nfproto'}},right='ipv4'}},
 {match={op='==',left={payload={protocol='ip',field='daddr'}},right='192.168.1.2'}},
 {match={op='==',left={payload={protocol='tcp',field='dport'}},right='@'..name}}, {accept={}}}}
local deny={rule={family='inet',table='fw4',chain='input_wan',handle=10,expr={{reject={}}}}}
local live={nftables={
 {chain={family='inet',table='fw4',name='reject_from_wan'}},
 {set={family='inet',table='fw4',name=name,comment='homepublish:input:v1',type='inet_service',flags={'timeout'},timeout=10,elem={{elem={val=443,timeout=10,expires=9}}}}},
 deny,{rule=owned},
 {rule={family='inet',table='fw4',chain='input_wan',handle=20,expr={{jump={target='reject_from_wan'}}}}}}}
assert(F.verify(rules,live,10))
owned.expr[2].match.right='192.168.1.3';assert(not F.verify(rules,live,10),'wrong destination readback must fail')
owned.expr[2].match.right='192.168.1.2';table.remove(owned.expr,2)
assert(not F.verify(rules,live,10),'port-only broadened rule must fail readback')
owned.expr[2]={match={op='==',left={payload={protocol='ip',field='daddr'}},right='192.168.1.2'}}
owned.expr[3]={match={op='==',left={payload={protocol='tcp',field='dport'}},right='@'..name}};owned.expr[4]={accept={}}
live.nftables[3],live.nftables[4]=live.nftables[4],deny
assert(not F.verify(rules,live,10),'accept before existing user rejection must fail readback')
live.nftables[3],live.nftables[4],live.nftables[5]=deny,live.nftables[5],live.nftables[3]
assert(not F.verify(rules,live,10),'accept after zone terminal is ineffective')
local v6={{family='ipv6',zone='wan',protocol='tcp',port=443,dest_ip='fd00:0:0:0:0:0:0:1'}}
local n6='homepublish_in6_wan_a'..v6[1].dest_ip:gsub('.',function(c)return string.format('%02x',c:byte())end)
owned.expr[1].match.right='ipv6';owned.expr[2].match.left.payload.protocol='ip6';owned.expr[2].match.right='fd00::1';owned.expr[3].match.right='@'..n6
live.nftables[2].set.name=n6;live.nftables[4],live.nftables[5]=live.nftables[5],live.nftables[4]
assert(F.verify(v6,live,10),'compressed nft IPv6 readback must match explicit expanded bind')
''')

    def test_real_nft_normalizes_redundant_family_and_default_element_timeout(self):
        self.lua().execute('''
local F=require('product-firewall')
for _,family in ipairs({'ipv4','ipv6'}) do
 local ip=family=='ipv4' and '192.168.1.2' or 'fd89:878e:a47f::1'
 local name='homepublish_in'..(family=='ipv4' and '4' or '6')..'_lan_a'..ip:gsub('.',function(c)return string.format('%02x',c:byte())end)
 local rules={{family=family,zone='lan',protocol='tcp',port=62171,dest_ip=ip}}
 local s={family='inet',table='fw4',name=name,comment='homepublish:input:v1',type='inet_service',flags={'timeout'},timeout=10,elem={{elem={val=62171,expires=9}}}}
 local r={family='inet',table='fw4',chain='input_lan',comment='homepublish:input:v1',expr={
  {match={op='==',left={payload={protocol=family=='ipv4' and 'ip' or 'ip6',field='daddr'}},right=ip}},
  {match={op='==',left={payload={protocol='tcp',field='dport'}},right='@'..name}},{accept={}}}}
 local live=policy({nftables={{set=s},{rule=r}}})
 assert(F.verify(rules,live,10),'real nft omits redundant nfproto and element timeout equal to set default')
 r.expr[1].match.left.payload.protocol=family=='ipv4' and 'ip6' or 'ip'
 assert(not F.verify(rules,live,10),'destination payload protocol must still constrain family')
 r.expr[1].match.left.payload.protocol=family=='ipv4' and 'ip' or 'ip6'
 s.elem[1].elem.expires=nil;assert(not F.verify(rules,live,10),'default timeout alone cannot prove live expiry')
end
''')

    def test_verify_enforces_kernel_lease_metadata(self):
        cases = {
            'permanent_set': "s.flags=nil;s.timeout=nil;s.elem={443}",
            'bare_element': "s.elem={443}",
            'missing_set_timeout': "s.timeout=nil",
            'oversized_set_timeout': "s.timeout=4",
            'wrong_type': "s.type='integer'",
            'missing_type': "s.type=nil",
            'missing_flags': "s.flags=nil",
            'wrong_flags': "s.flags={'constant'}",
            'extra_flags': "s.flags={'timeout','interval'}",
            'bare_flags': "s.flags='timeout'",
            'missing_element_timeout_and_expiry': "s.elem[1].elem.timeout=nil;s.elem[1].elem.expires=nil",
            'missing_expiry': "s.elem[1].elem.expires=nil",
            'zero_timeout': "s.elem[1].elem.timeout=0",
            'zero_expiry': "s.elem[1].elem.expires=0",
            'negative_expiry': "s.elem[1].elem.expires=-1",
            'oversized_element_timeout': "s.elem[1].elem.timeout=4",
            'oversized_expiry': "s.elem[1].elem.expires=4",
            'expiry_exceeds_timeout': "s.elem[1].elem.timeout=1;s.elem[1].elem.expires=2",
            'string_timeout': "s.elem[1].elem.timeout='3'",
            'fractional_expiry': "s.elem[1].elem.expires=1.5",
            'millisecond_units_not_json_seconds': "s.timeout=3000;s.elem[1].elem.timeout=3000;s.elem[1].elem.expires=2990",
            'duplicate_element': "s.elem[2]=s.elem[1]",
            'duplicate_set': "table.insert(live.nftables,1,{set=s})",
            'missing_elements': "s.elem=nil",
            'unwrapped_element': "s.elem={{val=443,timeout=3,expires=2}}",
            'duplicate_timeout_flag': "s.flags={'timeout','timeout'}",
            'missing_lease': "lease=nil",
            'oversized_lease': "lease=11",
            'zero_lease': "lease=0",
            'fractional_lease': "lease=2.5",
        }
        for label, mutation in cases.items():
            with self.subTest(label=label):
                self.lua().execute('''
local F=require('product-firewall')
local rules={{family='ipv4',zone='wan',protocol='tcp',port=443}}
local s={family='inet',table='fw4',name='homepublish_in4_wan',comment='homepublish:input:v1',
 type='inet_service',flags={'timeout'},timeout=3,elem={{elem={val=443,timeout=3,expires=2}}}}
local live=policy({nftables={{set=s},{rule={family='inet',table='fw4',chain='input_wan',
 comment='homepublish:input:v1',expr={
 {match={op='==',left={meta={key='nfproto'}},right='ipv4'}},
 {match={op='==',left={payload={protocol='tcp',field='dport'}},right='@homepublish_in4_wan'}},{accept={}}}}}}})
local lease=3
assert(F.verify(rules,live,lease),'valid live JSON seconds with elapsed expiry must verify')
s.elem[1].elem.expires=3;assert(F.verify(rules,live,lease),'immediate readback may have full expiry')
s.elem[1].elem.expires=1;assert(F.verify(rules,live,lease),'positive near-expiry readback must verify')
s.elem[1].elem.expires=2
''' + mutation + "\nassert(not F.verify(rules,live,lease),'must reject " + label + "')")

    def test_required_tool_providers_and_capability_failure(self):
        makefile=(SOURCE.parents[3]/'Makefile').read_text()
        self.assertIn('+coreutils-timeout',makefile)
        self.assertIn('+flock',makefile)
        self.lua().execute('''
package.loaded.nixio={};package.loaded['nixio.fs']={mkdir=function()error('must preflight before request creation')end}
os.execute=function(cmd)assert(cmd:find('flock',1,true) and cmd:find('timeout',1,true));return 256 end
local ok,e=require('product-firewall-system').reconcile({},10)
assert(not ok and e=='firewall timeout/flock capability unavailable')
''')

    def test_owned_input_atomic_reconcile(self):
        self.lua().execute('''
local snapshot=policy({nftables={{set={family='inet',table='fw4',name='homepublish_input_guard'}}}})
local batches={};local fail=false
local F=require('product-firewall').new({snapshot=function()return snapshot end,apply=function(s)batches[#batches+1]=s;return not fail end})
local rules={{family='ipv4',zone='wan',port=24443,protocol='tcp'},{family='ipv6',zone='lan',port=2222,protocol='tcp'}}
assert(F.reconcile(rules))
local b=batches[1];assert(b:find('insert rule inet fw4 input_wan',1,true));assert(b:find('meta nfproto ipv4 tcp dport @homepublish_in4_wan accept',1,true))
assert(b:find('24443 timeout 10s',1,true));assert(b:find('input_lan',1,true))
for _,bad in ipairs({'forward','dnat','output','policy','flush table','commit'}) do assert(not b:lower():find(bad,1,true),bad) end
snapshot.nftables[#snapshot.nftables+1]={rule={family='inet',table='fw4',chain='input_wan',handle=7,comment='homepublish:input:v1'}}
table.insert(snapshot.nftables,1,{rule={family='inet',table='fw4',chain='input_wan',handle=9,comment='user-owned'}})
snapshot.nftables[#snapshot.nftables+1]={set={family='inet',table='fw4',name='homepublish_in4_wan',comment='homepublish:input:v1'}}
assert(F.reconcile(rules));b=batches[#batches]
assert(b:find('delete rule inet fw4 input_wan handle 7',1,true));assert(not b:find('handle 9',1,true))
assert(b:find('delete set inet fw4 homepublish_in4_wan',1,true))
fail=true;local ok,err=F.reconcile(rules);assert(not ok and err=='firewall atomic update failed')
assert(F.status().state=='update_failed')
fail=false;assert(F.clear());assert(F.status().state=='closed')
''')

    def test_validation_reload_and_kernel_lease_contract(self):
        self.lua().execute('''
local count=0;local live=policy({nftables={{set={family='inet',table='fw4',name='homepublish_input_guard'}}}})
local F=require('product-firewall').new({snapshot=function()return live end,apply=function(b)count=count+1;assert(b:find('timeout 10s',1,true));return true end})
for _,r in ipairs({{family='ipv4',zone='wan; drop',port=80,protocol='tcp'},{family='ipv4',zone='wan',port=0,protocol='tcp'},{family='ipv4',zone='wan',port=80,protocol='udp'},{family='ipv4',zone='wan',port=80,protocol='tcp',chain='forward'}}) do assert(not F.reconcile({r})) end
assert(count==0)
local r={{family='ipv4',zone='wan',port=80,protocol='tcp'}}
assert(F.reconcile(r));assert(F.reconcile(r));assert(count==2,'repeat hook/reload convergence')
live={nftables={}};assert(not F.reconcile(r));assert(F.clear(),'missing fw4 must permit idempotent cleanup')
live={nftables={{set={family='inet',table='fw4',name='homepublish_in4_wan',comment='foreign'}}}};assert(not F.clear());assert(F.status().state=='cleanup_failed')
''')

    def test_runtime_opens_only_after_health_and_revokes_before_stop(self):
        self.lua().execute('''
package.loaded['direct-renderer']={};package.loaded['direct-backend']={};package.loaded['device-integrations']={}
local events={};local healthy=true;local clear=true;local update=true
package.loaded['product-procd-group']={new=function()return {
 start=function(p,g)p.generation=g;events[#events+1]='start';return true end,
 healthy=function()events[#events+1]='healthy';return healthy end,
 stop=function()events[#events+1]='stop';return true end}end}
local firewall={reconcile=function(r,lease)events[#events+1]='open';assert(lease<=10);return update,'firewall error' end,
 clear=function()events[#events+1]='clear';return clear end,status=function()return {state='open'}end}
local V=require('product-v2-runtime').new({available=function()return true end,firewall=firewall})
local p={services={},listeners={},snapshots={},firewall_rules={{family='ipv4',zone='wan',protocol='tcp',port=443}}}
assert(V.start(p,1,3000));assert(table.concat(events,',')=='start')
assert(V.readiness(p));assert(table.concat(events,',')=='start,healthy,open')
assert(V.stop());assert(events[#events-1]=='clear' and events[#events]=='stop')
events={};assert(V.start(p,2));healthy=false;assert(not V.readiness(p));assert(events[#events]~='open')
healthy=true;update=false;assert(not V.readiness(p),'firewall failure must fail startup')
clear=false;assert(not V.stop(),'cleanup failure must not be reported clean');assert(events[#events]=='stop','components still stop on firewall failure')
''')

    def test_controller_retries_failed_cleanup_and_reports_firewall(self):
        self.lua().execute('''
package.loaded['product-wire']={encode=function(v)return v end,decode=function(v)return v end}
local config={schema_version=2,services={{service_id='web'}},publication_policy={mode='continuous'}}
local state={saved_revision=1,saved_config=config,intent_revision=0,desired_state={state='disabled'},runtime={phase='stopped',generation=0,cleanup='confirmed'},capabilities={}}
package.loaded['product-provider']={handle=function()return state end,controller_transaction=function(fn)fn(state);return state end}
local clean=false;local stops=0
local p={runtime_plan=function(c)return c end,plan=function(c)return c end,start=function()return true end,
 readiness=function()return false,{web={ready=false,generation=1}},'firewall atomic update failed' end,
 stop=function()stops=stops+1;return clean end,firewall_status=function()return {state=clean and 'closed' or 'cleanup_failed'}end}
local C=require('product-controller').new(p)
local s=C.start(1,true);assert(s.runtime.phase=='blocked' and s.runtime.cleanup=='unknown')
clean=true;s=C.tick();assert(stops==2 and s.runtime.cleanup=='confirmed','failed-start firewall cleanup must retry without another Start')
assert(C.status().firewall.state=='closed','derived firewall state must not be saved to journal')
''')

    def test_live_worker_rejects_stale_or_dead_controller(self):
        for stale, identity in [(True, 'same'), (False, 'different')]:
            with self.subTest(stale=stale, identity=identity):
                lua=self.lua()
                lua.globals().age=6 if stale else 0
                lua.globals().identity=identity
                lua.execute('''
local request={rules={{family='ipv4',zone='wan',protocol='tcp',port=443}},lease=10,pid=123,identity='same',uptime=100}
local result;local exit
arg={[0]='product-firewall-apply.lua','/var/run/homepublish-firewall/123-1'}
package.loaded['luci.jsonc']={}
package.loaded.nixio={sysinfo=function()return {uptime=100+age}end}
package.loaded['nixio.fs']={lstat=function()return {type='dir',uid=0,modedec=700}end,stat=function()return 'reg' end}
package.loaded['product-firewall-system']={identity=function()return identity end}
package.loaded['product-json']={decode=function()return request end,encode=function(r)result=r;return '{}' end}
io.open=function(path,mode)return {read=function()return '{}' end,write=function()return true end,close=function()return true end}end
io.popen=function()error('stale controller must never reach nft')end
os.execute=function()error('stale controller must never execute nft')end
os.exit=function(code)exit=code end
dofile(source..'/product-firewall-apply.lua')
assert(exit==1 and result.ok==false and result.error=='firewall controller lease stale')
''')

    def test_expiry_renew_health_reload_and_legacy_empty_rules(self):
        self.lua().execute('''
package.loaded['direct-renderer']={};package.loaded['direct-backend']={};package.loaded['device-integrations']={}
local now=100;os.time=function()return now end
local healthy=true;local batches={};local cleared=0
package.loaded['product-procd-group']={new=function()return {start=function(p,g)p.generation=g;return true end,healthy=function()return healthy end,stop=function()return true end}end}
local firewall={reconcile=function(r,lease)batches[#batches+1]={rules=r,lease=lease};return true end,clear=function()cleared=cleared+1;return true end,status=function()return {}end}
local V=require('product-v2-runtime').new({available=function()return true end,firewall=firewall})
local p={services={},listeners={},snapshots={}}
assert(V.start(p,1,3000));assert(V.readiness(p));assert(#batches[1].rules==0 and batches[1].lease==3,'legacy config must never gain openings')
now=101;assert(V.renew());assert(batches[#batches].lease==2,'lease must not exceed publication remaining time')
healthy=false;local n=#batches;assert(not V.renew());assert(#batches==n,'component crash must never refresh allowances')
healthy=true;now=103;assert(not V.renew(),'expired publication must not refresh allowances')
assert(V.stop() and cleared==1)
''')

    def test_system_transport_private_paths_and_error_propagation(self):
        self.lua().execute('''
local directories={};local files={};local commands={};local mode='ok'
package.loaded.nixio={getpid=function()return 321 end,sysinfo=function()return {uptime=100}end}
package.loaded['nixio.fs']={mkdir=function(p,m)assert(m=='700','nixio parses octal notation, not decimal POSIX 448');directories[p]=true;return true end,
 lstat=function()return {uid=mode=='unsafe' and 1000 or 0,type='dir',modedec=700}end,chmod=function(p,m)assert(m=='700','nixio parses octal notation, not decimal POSIX 448');return true end,
 unlink=function(p)files[p]=nil end,rmdir=function(p)directories[p]=nil end}
package.loaded['product-json']={encode=function(v)assert(v.pid==321 and v.identity=='12345');return 'request' end,
 decode=function(s)if s=='success' then return {ok=true} elseif s=='failed' then return {ok=false,error='firewall atomic update failed'} else error('bad JSON') end end}
io.open=function(path,access)
 if path=='/proc/321/stat' then return {read=function()return '321 (lua daemon) S '..string.rep('0 ',18)..'12345' end,close=function()return true end}end
 if access=='w' then return {write=function(_,s)files[path]=s;return true end,close=function()return true end}end
 if not files[path] then return nil end
 return {read=function()return files[path]end,close=function()return true end}
end
os.execute=function(cmd)
 if cmd=='timeout 1 flock -xn /dev/null /bin/true >/dev/null 2>&1' then return 0 end
 commands[#commands+1]=cmd;assert(cmd:find('timeout 5 flock -x /var/run/fw4.lock',1,true))
 local d=cmd:match('(/var/run/homepublish%-firewall/%d+%-%d+)');assert(d)
 assert(files[d..'/request.json']=='request');files[d..'/result.json']=mode=='fail' and 'failed' or 'success';return mode=='fail' and 256 or 0
end
local F=require('product-firewall-system');assert(F.identity(321)=='12345')
assert(F.reconcile({},10));assert(not directories['/var/run/homepublish-firewall/321-1'])
mode='fail';local ok,e=F.reconcile({},10);assert(not ok and e=='firewall atomic update failed')
mode='unsafe';assert(not F.reconcile({},10));assert(#commands==2)
''')

    def test_worker_reads_nft_json_and_checks_status_after_apply(self):
        for readback_timeout in (3, 4, 10):
            lua = self.lua()
            lua.globals().readback_timeout = readback_timeout
            lua.execute('''
local request={rules={{family='ipv4',zone='wan',protocol='tcp',port=443}},lease=3,pid=123,identity='same',uptime=100}
local result;local exit;local written={};local calls={};local applied=false
arg={[0]='product-firewall-apply.lua','/var/run/homepublish-firewall/123-1'}
package.loaded.nixio={sysinfo=function()return {uptime=100}end}
package.loaded['nixio.fs']={lstat=function()return {type='dir',uid=0,modedec=700}end,stat=function()return 'reg' end}
package.loaded['product-firewall-system']={identity=function()return 'same' end}
package.loaded['product-json']={decode=function(s)assert(s=='request');return request end,encode=function(r)result=r;return '{}' end}
package.loaded['luci.jsonc']={parse=function(s)
 if s=='tables' then return {nftables={{table={family='inet',name='fw4'}}}} end
 assert(s=='rules-with-null-verdicts {"accept":{}}','null ACCEPT must survive jsonc parsing for exact readback')
 if applied then return policy({nftables={
  {set={family='inet',table='fw4',name='homepublish_in4_wan',comment='homepublish:input:v1',type='inet_service',flags={'timeout'},timeout=3,elem={{elem={val=443,timeout=readback_timeout,expires=2}}}}},
  {rule={family='inet',table='fw4',chain='input_wan',comment='homepublish:input:v1',expr={
   {match={op='==',left={meta={key='nfproto'}},right='ipv4'}},
   {match={op='==',left={payload={protocol='tcp',field='dport'}},right='@homepublish_in4_wan'}},{accept={}}}}}}}) end
 return policy({nftables={{set={family='inet',table='fw4',name='homepublish_input_guard'}}}})
end}
io.open=function(path,mode)return {read=function()return 'request' end,write=function(_,s)written[path]=s;return true end,close=function()return true end}end
io.popen=function(cmd)calls[#calls+1]=cmd;return {read=function()return (cmd:find('list tables',1,true) and 'tables' or 'rules-with-null-verdicts {"accept":null}')..'\\nHOMEPUBLISH_OK\\n' end,close=function()return true end}end
os.execute=function(cmd)assert(cmd=='nft -f /var/run/homepublish-firewall/123-1/batch.nft >/dev/null 2>&1');applied=true;return 0 end
os.exit=function(code)exit=code end
dofile(source..'/product-firewall-apply.lua')
assert(applied and #calls==4,'snapshot and exact-target readback must both run')
if readback_timeout==3 then assert(exit==0 and result.ok)
else assert(exit==1 and not result.ok and result.error=='firewall verification failed','worker must verify requested lease, not MAX_LEASE') end
assert(written['/var/run/homepublish-firewall/123-1/batch.nft']:find('input_wan',1,true))
''')

    def test_controller_apply_and_expiry_use_same_cleanup_path(self):
        self.lua().execute('''
package.loaded['product-wire']={encode=function(v)return v end,decode=function(v)return v end}
local config={schema_version=2,services={{service_id='web'}},publication_policy={mode='temporary',temporary_duration=30}}
local state={saved_revision=1,saved_config=config,intent_revision=0,desired_state={state='disabled'},runtime={phase='stopped',generation=0,cleanup='confirmed'},capabilities={}}
package.loaded['product-provider']={handle=function()return state end,controller_transaction=function(fn)fn(state);return state end}
local events={};local generation;local now=100;local clean=true
local p={runtime_plan=function(c)return c end,plan=function(c)return c end,
 start=function(_,g)generation=g;events[#events+1]='start';return true end,
 readiness=function()events[#events+1]='ready';return true,{web={ready=true,generation=generation}} end,
 stop=function()events[#events+1]='stop';return clean end,renew=function()return true end}
local C=require('product-controller').new(p,{clock=function()return {now=now,boot_id='test',trusted=true}end})
assert(C.start(1,true).runtime.phase=='running');assert(state.runtime.expires_at==130)
state.saved_revision=2;events={};assert(C.apply(2,true).runtime.phase=='running');assert(table.concat(events,',')=='stop,start,ready')
assert(state.runtime.expires_at==130,'Apply must not renew temporary publication lifetime')
now=130;events={};local stopped=C.tick();assert(table.concat(events,',')=='stop' and stopped.runtime.phase=='stopped')
assert(stopped.runtime.cleanup=='confirmed' and stopped.desired_state.manual_stop_latch)
''')

    def test_first_activation_bootstraps_only_inert_marker_without_fw4_reload(self):
        self.lua().execute('''
local snapshot=policy({nftables={{table={family='inet',name='fw4'}}}});local batch
local F=require('product-firewall').new({bootstrap=true,snapshot=function()return snapshot end,apply=function(s)batch=s;return true end})
assert(F.reconcile({{family='ipv4',zone='wan',port=443,protocol='tcp'}}),'new package must not need reload of unrelated firewall config')
assert(batch:find('add set inet fw4 homepublish_input_guard',1,true))
assert(not batch:find('flush table',1,true))
snapshot={nftables={}};assert(not F.reconcile({{family='ipv4',zone='wan',port=443,protocol='tcp'}}),'cannot create fw4 table or change global policy')
''')

if __name__ == '__main__':
    unittest.main()
