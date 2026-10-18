local n=require('nixio');local fs=require('nixio.fs');local J=require('product-json')
local D=dofile(ROOT..'/product-ddns.lua')
local function server(response,verify)
 fs.unlink(ROOT..'/api.sock');local s=assert(n.socket('unix','stream'));assert(s:bind(ROOT..'/api.sock'));assert(s:listen(4))
 local pid=n.fork();assert(pid)
 if pid==0 then
  local c=assert(s:accept());local data=''
  while not data:find('\r\n\r\n',1,true) do data=data..assert(c:recv(4096)) end
  local length=tonumber(data:match('[Cc]ontent%-[Ll]ength: (%d+)')) or 0
  local at=assert(data:find('\r\n\r\n',1,true))+4
  while #data-at+1<length do data=data..assert(c:recv(4096)) end
  if verify then verify(data) end
  if response=='timeout' then n.nanosleep(2) else assert(c:sendall(response)) end
  c:close();s:close();os.exit(0)
 end
 s:close();return pid
end
local function done(pid)local p,why,code=n.waitpid(pid);assert(p==pid and code==0,'fixture child failed');fs.unlink(ROOT..'/api.sock')end
local function http(body,status)return 'HTTP/1.0 '..(status or '200 OK')..'\r\nContent-Length: '..#body..'\r\n\r\n'..body end
local unavailable=D.profiles();assert(unavailable.available==false and #unavailable.profiles==0)
local pid=server(http(J.encode({api_version=1,profiles={{profile_id='p:1',name='Home',provider='DNSPod',a={enabled=true,domains={'old.example.com'}},aaaa={enabled=false,domains={}},secret='NEVER_EXPORT'}}})),function(r)assert(r:find('GET /v1/profiles HTTP/1.0',1,true))end)
local r=D.profiles();done(pid);assert(r.available and r.profiles[1].profile_id=='p:1');assert(not J.encode(r):find('NEVER_EXPORT',1,true))
local config={services={{service_id='web',enabled=true,type='http_proxy',hostname='new.example.com',dns={mode='manual'}}}}
local result=D.ensure(config);assert(#result.results==0 and #result.warnings==0)
config.services[1].dns={mode='ddns_go',profile_id='p:1',record_types={'A'}}
pid=server(http('{"api_version":1,"added":["A"],"already":[],"update_queued":true,"secret":"NEVER_EXPORT"}'),function(r)
 assert(r:find('POST /v1/domains/ensure HTTP/1.0',1,true));local body=J.decode(r:match('\r\n\r\n(.*)'));assert(body.hostname=='new.example.com' and body.profile_id=='p:1' and body.record_types[1]=='A')
end)
result=D.ensure(config);done(pid);assert(#result.results==1 and result.results[1].ok and #result.warnings==0);assert(not J.encode(result):find('NEVER_EXPORT',1,true))
pid=server(http('{"error":"stale_profile","secret":"NEVER_EXPORT"}','409 Conflict'))
result=D.ensure(config);done(pid);assert(#result.warnings==1 and not result.results[1].ok);assert(not J.encode(result):find('NEVER_EXPORT',1,true))
pid=server('timeout');local before=os.time();result=D.ensure(config);assert(os.time()-before<=2 and #result.warnings==1);done(pid)
for _,response in ipairs({http('{}'),http('{"api_version":2,"profiles":[]}'),http('{"api_version":1,"profiles":[]}')..'surplus','HTTP/1.0 200 OK\r\nContent-Length: 999999\r\n\r\n','HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n'}) do
 pid=server(response);r=D.profiles();done(pid);assert(not r.available,'malformed response accepted')
end
-- Ineligible, disabled and manual rules must not even connect to the socket.
local listener=assert(n.socket('unix','stream'));assert(listener:bind(ROOT..'/api.sock'));assert(listener:listen(4))
D.ensure({services={{service_id='manual',enabled=true,type='http_proxy',dns={mode='manual'}},{service_id='off',enabled=false,type='http_proxy',dns={mode='ddns_go'}},{service_id='ssh',enabled=true,type='ssh',dns={mode='ddns_go'}},{service_id='tcp',enabled=true,type='tcp_forward',dns={mode='ddns_go'}}}})
assert(not n.poll({{fd=listener,events=n.poll_flags('in')}},10),'unexpected socket connection');listener:close();fs.unlink(ROOT..'/api.sock')
-- Every connection stalls: the whole 16-service batch still has a three-second cap.
listener=assert(n.socket('unix','stream'));assert(listener:bind(ROOT..'/api.sock'));assert(listener:listen(32))
local child=n.fork();assert(child)
if child==0 then local sockets={};while true do sockets[#sockets+1]=assert(listener:accept());local f=assert(io.open(ROOT..'/connections','w'));f:write(#sockets);f:close() end end
listener:close();local many={services={}};for i=1,16 do many.services[i]=config.services[1] end
local function uptime()local f=assert(io.open('/proc/uptime'));local v=tonumber(f:read('*l'):match('^[%d.]+'));f:close();return v end
local t=uptime();result=D.ensure(many);local elapsed=uptime()-t;n.nanosleep(0,50000000);n.kill(child,15);n.waitpid(child);fs.unlink(ROOT..'/api.sock')
local f=assert(io.open(ROOT..'/connections'));local connects=tonumber(f:read('*a'));f:close();assert(connects<=5,'must not connect after aggregate budget expires')
assert(elapsed<3.5 and #result.warnings==16,'aggregate timeout budget exceeded');print('DDNS_BRIDGE_GREEN '..elapsed)
