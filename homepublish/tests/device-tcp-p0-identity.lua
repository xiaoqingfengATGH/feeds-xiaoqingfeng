-- Device-only: real sslh->Nginx stream PROXY v1 and unprivileged exec.
local n=require 'nixio'
local fs=require 'nixio.fs'
local root='/tmp/homepublish-tcp-p0'
local kids,socks={},{}
local function write(name,data) local f=assert(io.open(root..'/'..name,'w'));f:write(data);f:close() end
local function read(path) local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local function fork(fn)
 local p=assert(n.fork());if p==0 then for _,s in ipairs(socks) do s:close() end;local ok,e=xpcall(fn,debug.traceback);if not ok then io.stderr:write(tostring(e)..'\n');io.stderr:flush();os.exit(1) end;os.exit(0) end;kids[#kids+1]=p;return p
end
local function backend(port,expected,marker)
 -- Acquire in child so no listener descriptors leak into other children.
 local p=fork(function()
  local s=assert(n.socket('inet','stream'));assert(s:setopt('socket','reuseaddr',1));assert(s:bind('127.0.0.1',port));assert(s:listen(8))
  write('ready-'..port,'ready')
  while true do local c=s:accept();if c then
   c:setopt('socket','rcvtimeo',3);local b=c:recv(8192) or ''
   if b:sub(1,#expected)==expected then c:send(marker) else c:send('WRONG_BYTES') end;c:close()
  end end
 end)
 return p
end
local function hello()
 local function u16(v)return string.char(math.floor(v/256),v%256)end
 local host='a.fixture.home';local names=string.char(0)..u16(#host)..host
 local ext=string.char(0,0)..u16(#names+2)..u16(#names)..names
 local body=string.char(3,3)..string.rep('x',32)..string.char(0)..u16(2)..string.char(0,47)..string.char(1,0)..u16(#ext)..ext
 local h=string.char(1,0)..u16(#body)..body;return string.char(22,3,1)..u16(#h)..h
end
local function request(bytes,expected)
 local c=assert(n.socket('inet6','stream'));c:setopt('socket','rcvtimeo',4);assert(c:connect('::1',49300));assert(c:send(bytes));local b=c:recv(512);c:close()
 if expected then assert(b==expected,'bad response '..tostring(b)) else assert(not b or b=='','unexpected response '..tostring(b)) end
end
local function unprivileged(binary,...)
 local args={...};assert(n.setgid(65534));assert(n.setuid(65534));n.exec(root..'/'..binary,unpack(args));os.exit(127)
end
local function assert_identity(log)
 local success=0
 for line in log:gmatch('[^\n]+') do
  if line:match('|200$') then
   assert(line=='::1|127.0.0.1|200','wrong current identity '..line);success=success+1
  end
 end
 assert(success==1,'expected exactly one successful identity record')
end
-- Mutation control: stale correct row must never hide a wrong successful row.
assert(not pcall(assert_identity,'::1|127.0.0.1|200\n2001:db8::bad|127.0.0.1|200\n'))
local function run()
 -- This invocation alone owns the identity evidence; never accept appended history.
 write('identity.log',''); assert(fs.chown(root..'/identity.log',65534,65534))
 backend(49301,string.char(22,3,1),'HP_PP_STRIPPED')
 backend(49303,'SSH-2.0-HP_P0\r\n','HP_SSH_UNCHANGED')
 local deny=assert(n.socket('inet','stream'));assert(deny:bind('127.0.0.1',49309));socks[#socks+1]=deny
 write('sslh.cfg',[[foreground: true; numeric: true; transparent: false; timeout: 1;
user: "nobody";
listen: ( { host: "::1"; port: "49300"; } );
protocols: (
 { name: "tls"; host: "127.0.0.1"; port: "49302"; sni_hostnames: [ "a.fixture.home" ]; proxyprotocol: 1; },
 { name: "ssh"; host: "127.0.0.1"; port: "49303"; },
 { name: "anyprot"; host: "127.0.0.1"; port: "49309"; }
);
on-timeout: "anyprot";
]])
 write('nginx.conf',[[daemon off; master_process off;
error_log stderr notice; pid /tmp/homepublish-tcp-p0/nginx.pid;
events { worker_connections 32; }
stream {
 log_format identity '$proxy_protocol_addr|$remote_addr|$status';
 access_log /tmp/homepublish-tcp-p0/identity.log identity;
 server { listen 127.0.0.1:49302 proxy_protocol; proxy_pass 127.0.0.1:49301; proxy_timeout 3s; }
}
]])
 local nginx=fork(function()unprivileged('nginx-stream','-p',root..'/','-c',root..'/nginx.conf')end)
 local sslh=fork(function()unprivileged('sslh-select','-F',root..'/sslh.cfg')end)
 n.nanosleep(1)
 for _,pid in ipairs({nginx,sslh}) do
  local status=read('/proc/'..pid..'/status');local uid=status:match('\nUid:%s*([^\n]+)')
  assert(uid and uid:match('^65534%s+65534%s+65534%s+65534'),'process is not nobody '..pid)
 end
 print('PASS BOTH_PROCESSES_NONROOT')
 request(hello(),'HP_PP_STRIPPED');print('PASS PP_V1_NGINX_CONSUMED_V6_TO_V4')
 request('SSH-2.0-HP_P0\r\n','HP_SSH_UNCHANGED');print('PASS SSH_NO_PROXY_HEADER')
 request('PROXY TCP6 2001:db8::bad ::1 1234 49300\r\n'..hello());print('PASS EXTERNAL_PROXY_HEADER_REJECTED')
 n.nanosleep(1)
 local log=read(root..'/identity.log');assert_identity(log)
 print('PASS NGINX_ORIGINAL_V6_AND_PROXY_PEER '..log:gsub('\n',';'))
end
local ok,e=xpcall(run,debug.traceback)
-- Keep refusal reservation until every child (including ingress) is reaped.
for _,p in ipairs(kids)do n.kill(p,15)end
n.nanosleep(1)
for _,p in ipairs(kids)do
 local done=false
 for i=1,20 do local pid=n.waitpid(p,'nohang');if pid and pid~=0 then done=true;break end;n.nanosleep(0,50000000)end
 if not done then n.kill(p,9);for i=1,20 do local pid=n.waitpid(p,'nohang');if pid and pid~=0 then done=true;break end;n.nanosleep(0,50000000)end end
 if not done then ok=false;e=(e or '')..' child cleanup unknown '..p end
end
for _,s in ipairs(socks)do s:close()end
if not ok then io.stderr:write(tostring(e)..'\n');os.exit(1)end
print('HP_TCP_P0_IDENTITY_PASS (stream metadata, NOT HTTP X-Forwarded-For/TLS authentication acceptance)')
