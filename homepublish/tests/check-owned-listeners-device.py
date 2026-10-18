"""Read-only source injection + private loopback sockets; never deploy modules.
Run: python homepublish/tests/check-owned-listeners-device.py
"""
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'homepublish/files/usr/share/homepublish'
script = "local L=(assert(loadstring([====[" + (SOURCE / 'product-listeners.lua').read_text(encoding='utf-8') + "]====])))()\n"
script += "package.path='/usr/share/homepublish/?.lua;'..package.path;package.loaded['product-listeners']=L\nlocal Group=(assert(loadstring([====[" + (SOURCE / 'product-procd-group.lua').read_text(encoding='utf-8') + "]====])))()\n"
script += r'''
local n=require('nixio')
local sockets={}
local function socket(f,a,only)
 local s=assert(n.socket(f,'stream'));sockets[#sockets+1]=s
 if only~=nil then assert(s:setopt('ipv6','v6only',only and 1 or 0)) end
 assert(s:bind(a,0));assert(s:listen(4));local address,port=s:getsockname();assert(type(port)=='number');return s,port
end
local function endpoint(f,a,p)return {component='nginx',family=f,address=a,port=p,label='private fixture'} end
local name='homepublish-listener-check-'..n.getpid();local root='/tmp/'..name
local G=Group.new({name=name,root=root,nginx='/usr/libexec/homepublish/nginx',sslh='/usr/libexec/homepublish/sslh-select'})
local started=false
local ok,err=pcall(function()
 local s,p=socket('inet','127.0.0.1')
 local e=endpoint('ipv4','127.0.0.1',p)
 local clear,reason=L.preflight({e});assert(not clear and reason:find('address in use',1,true),reason)
 print('LIVE_OCCUPIED_PORT_GREEN '..p)
 assert(L.preflight({endpoint('ipv4','127.0.0.2',p)}))
 local own,ids=assert(L.family({nginx=n.getpid()}));local rows=assert(L.rows())
 assert(L.verify({e},rows,own))
 local ready,why=L.verify({e},rows,{nginx={}});assert(not ready and why:find('foreign listener',1,true))
 local missing=endpoint('ipv4','127.0.0.2',p)
 ready,why=L.verify({missing},rows,own);assert(not ready and why:find('not listening',1,true))
 print('OWNED_FOREIGN_WRONG_LISTENER_GREEN')
 local s6,p6=socket('inet6','::',true)
 assert(L.preflight({endpoint('ipv4','127.0.0.1',p6)}),'IPv6-only wildcard must not conflict with IPv4')
 clear,reason=L.preflight({endpoint('ipv6','::1',p6)});assert(not clear and reason:find('address in use',1,true))
 local dual,pdual=socket('inet6','::',false)
 clear,reason=L.preflight({endpoint('ipv4','127.0.0.1',pdual)});assert(not clear and reason:find('bind failed',1,true),reason)
 print('V6_ONLY_AND_DUAL_STACK_WILDCARD_GREEN')
 local inode
 for _,row in ipairs(rows) do if row.port==p and row.family=='ipv4' then inode=row.inode end end
 assert(inode);s:close()
 local replacement=assert(n.socket('inet','stream'));sockets[#sockets+1]=replacement
 assert(replacement:bind('127.0.0.1',p));assert(replacement:listen(4))
 for _,row in ipairs(assert(L.rows())) do assert(row.inode~=inode,'old listener inode remained') end
 print('REBOUND_PORT_NOT_OLD_LISTENER_GREEN')
 replacement:close()
 local plan={configuration='worker_processes 1; daemon off; pid nginx.pid; error_log stderr error; events { worker_connections 16; } stream { server { listen 127.0.0.1:'..p..'; return ""; } }',services={{name='private real nginx',type='tcp_forward',listen_port=p}}}
 local occupied=assert(n.socket('inet','stream'));sockets[#sockets+1]=occupied;assert(occupied:bind('127.0.0.1',p));assert(occupied:listen(4))
 clear,reason=G.start(plan,1);assert(not clear and reason:find('address in use',1,true),reason);occupied:close()
 started=true;local running,why=G.start(plan,2);assert(running,why);assert(G.healthy());assert(G.preflight(plan))
 assert(G.stop(),'real procd/nginx stop must confirm own inode removal');started=false
 print('REAL_PROCD_NGINX_START_HEALTH_STOP_GREEN')
 local reservation,inner=socket('inet','127.0.0.1');reservation:close()
 local mixed={configuration='worker_processes 1; daemon off; pid nginx.pid; error_log stderr error; events { worker_connections 16; } stream { server { listen 127.0.0.1:'..inner..'; return ""; } }',sslh_configuration='foreground: true; numeric: true; transparent: false; timeout: 1; listen: ( { host: "127.0.0.1"; port: "'..p..'"; } ); protocols: ( { name: "anyprot"; host: "127.0.0.1"; port: "'..inner..'"; } ); on-timeout: "anyprot";'}
 started=true;running,why=G.start(mixed,3);assert(running,why);assert(G.healthy());assert(G.preflight(mixed));assert(G.stop());started=false
 print('REAL_PROCD_SSLH_NGINX_INNER_LISTENERS_GREEN')
end)
if started then assert(G.stop(),'private procd cleanup failed') end
for _,s in ipairs(sockets) do pcall(function()s:close()end) end
assert(ok,err)
print('OWNED_LISTENERS_DEVICE_GREEN')
'''
cmd = ['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o','ConnectTimeout=8','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2','lua -']
r = subprocess.run(cmd, input=script.encode(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=40)
print(r.stdout.decode(errors='replace'))
raise SystemExit(r.returncode)
