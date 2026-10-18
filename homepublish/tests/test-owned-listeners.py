"""Owned listener contract regressions (Lua 5.1, no target traffic)."""
import pathlib
import unittest
from lupa.lua51 import LuaRuntime
SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'files/usr/share/homepublish'

class ListenerTests(unittest.TestCase):
    def test_contract(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().source = SOURCE.as_posix()
        lua.execute("package.path=source..'/?.lua;'..package.path")
        lua.execute('''
local L=require('product-listeners')
local p={configuration='http { server { listen 127.0.0.1:19001 ssl; listen [::]:19002 ipv6only=on; } }',sslh_configuration='listen: ( { host: "0.0.0.0"; port: "19003"; } ); protocols: ( { host: "127.0.0.1"; port: "22"; } );',services={{name='database',type='tcp_forward',listen_port=19001}}}
local e=L.expected(p);assert(#e==3 and e[1].label=='database');assert(e[3].component=='sslh')
local rows=L.parse(' 0: 0100007F:4A39 00000000:0000 0A 0:0 0:0 0 0 0 777 1', 'ipv4')
assert(#rows==1 and rows[1].address=='127.0.0.1' and rows[1].port==19001 and rows[1].inode=='777')
assert(L.conflicts({family='ipv4',address='0.0.0.0',port=19001}, rows[1]))
assert(not L.conflicts({family='ipv4',address='127.0.0.2',port=19001},rows[1]))
assert(not L.conflicts({family='ipv6',address='::',port=19001},rows[1]),'IPv6-only must not claim IPv4')
local ok,err=L.verify(e,rows,{nginx={['777']=true},sslh={}});assert(not ok and err:find('19002',1,true))
local only={e[1]};assert(L.verify(only,rows,{nginx={['777']=true}}))
ok,err=L.verify(only,rows,{nginx={}});assert(not ok and err:find('foreign listener',1,true))
ok,err=L.verify(only,{}, {nginx={['777']=true}});assert(not ok and err:find('not listening',1,true))
local v6=L.parse('0: 00000000000000000000000001000000:4A3A 00000000000000000000000000000000:0000 0A 0:0 0:0 0 0 0 778 1','ipv6');assert(v6[1].address=='0000:0000:0000:0000:0000:0000:0000:0001')
assert(L.same_address('::1',v6[1].address,'ipv6'))
assert(#L.parse('0: 0100007F:4A39 00000000:0000 06 0:0 0:0 0 0 0 777 1','ipv4')==0)
''')

    def test_group_readiness_apply_and_stop(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().source = SOURCE.as_posix()
        lua.execute("package.path=source..'/?.lua;'..package.path")
        lua.execute(r'''
local L=require('product-listeners')
local mode='owned';local service;local alive=true;local generation;local files={};local rows={};local encoded={};local seq=0
package.loaded['product-json']={encode=function(t)seq=seq+1;local k='json'..seq;encoded[k]=t;return k end,decode=function(s)if s=='status' then return service and {['homepublish-test']=service} or {} end;return encoded[s] end}
io.popen=function()return {read=function()return 'status' end,close=function()return true end}end
io.open=function(path,flag)
 if flag=='w' then return {write=function(_,s)files[path]=s;return true end,close=function()return true end} end
 if path:find('/proc/',1,true) then if not alive then return nil end;return {read=function()return 'stat' end,close=function()end} end
 if not files[path] then return nil end;return {read=function()return files[path] end,close=function()end}
end
L.identity=function(pid)return alive and {pid=pid,start='123',component='nginx'} or nil end
L.family=function(roots)
 local ids={};for k,pid in pairs(roots) do if alive then ids[pid]={pid=pid,start='123',component=k} end end
 return {nginx=mode=='foreign' and {} or {['777']=true},sslh={}},ids
end
L.rows=function()return rows end
os.execute=function(cmd)
 if cmd:find('service set',1,true) then
  alive=true;service={instances={nginx={command={'/nginx','-p','/tmp/homepublish-test/','-c','nginx.conf'},running=true,pid=100}}}
  rows=mode=='missing' and {} or {{family='ipv4',address='127.0.0.1',port=19001,inode='777'}}
 elseif cmd:find('service delete',1,true) then
  service=nil;alive=false
  rows=mode=='leaked' and {{family='ipv4',address='127.0.0.1',port=19001,inode='777'}} or {{family='ipv4',address='127.0.0.1',port=19001,inode='888'}}
 end;return 0
end
local new=require('product-procd-group').new
local function group()return new({name='homepublish-test',root='/tmp/homepublish-test',nginx='/nginx',sslh='/sslh'}) end
local p={configuration='error_log stderr error; stream { server { listen 127.0.0.1:19001; } }',services={{type='tcp_forward',name='database',listen_port=19001}}}
for _,case in ipairs({'missing','foreign'}) do
 service=nil;rows={};mode=case;local G=group();local ok,err=G.start(p,1)
 assert(not ok and err:find('19001',1,true) and err:find(case=='missing' and 'not listening' or 'foreign listener',1,true),tostring(err))
 assert(G.stop(),'failed startup rollback must terminate components, ignoring foreign rebind')
end
mode='owned';rows={};service=nil;local G=group();assert(G.start(p,2))
assert(G.preflight(p),'apply preflight must ignore this generation sockets')
local changed={configuration='stream { server { listen 127.0.0.1:19002; } }'}
rows[#rows+1]={family='ipv4',address='127.0.0.1',port=19002,inode='999'}
local ok,err=G.preflight(changed);assert(not ok and err:find('19002',1,true))
assert(service and alive,'preflight failure must preserve running old generation')
assert(G.stop(),'foreign process rebinding same port must not block cleanup')
mode='owned';rows={};service=nil;G=group();assert(G.start(p,3));mode='leaked'
ok,err=G.stop();assert(not ok and err:find('cleanup incomplete',1,true),'old socket inode must block cleanup')
''')

if __name__ == '__main__': unittest.main(verbosity=2)
