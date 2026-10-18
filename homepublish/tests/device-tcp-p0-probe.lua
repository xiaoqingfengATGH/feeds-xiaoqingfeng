-- Device-only P0 probe. No real credentials/certificates or management backends.
local nixio = require 'nixio'
local root = '/tmp/homepublish-tcp-p0'
local children, sockets = {}, {}
local function file(name, value)
 local f=assert(io.open(root..'/'..name,'w')); f:write(value); f:close()
end
local function fork(fn)
 local pid=assert(nixio.fork())
 if pid==0 then fn(); os.exit(0) end
 children[#children+1]=pid; return pid
end
local function backend(port, marker, server_first)
 local s=assert(nixio.socket('inet','stream')); assert(s:bind('127.0.0.1',port)); assert(s:listen(8))
 sockets[#sockets+1]=s
 fork(function() while true do local c=s:accept(); if c then c:setopt('socket','rcvtimeo',3); if not server_first then c:recv(8192) end; c:send(marker); c:close() end end end)
end
local function connect(port, bytes, expected, fragmented)
 local c=assert(nixio.socket('inet6','stream')); c:setopt('socket','rcvtimeo',5)
 assert(c:connect('::1',port),'IPv6 connect failed '..port)
 if bytes then
  if fragmented then
   assert(c:send(bytes:sub(1,8))); nixio.nanosleep(0,100000000); assert(c:send(bytes:sub(9)))
  else assert(c:send(bytes)) end
 end
 local value=c:recv(512); c:close()
 if expected then assert(value==expected,'route mismatch: '..tostring(value)..' != '..expected)
 else assert(not value or value=='','unexpected business response '..tostring(value)) end
end
local function u16(n) return string.char(math.floor(n/256),n%256) end
local function hello(host)
 host=host or ''
 local names=string.char(0)..u16(#host)..host
 local ext=host~='' and (string.char(0,0)..u16(#names+2)..u16(#names)..names) or ''
 local body=string.char(3,3)..string.rep('x',32)..string.char(0)..u16(2)..string.char(0,47)..string.char(1,0)..u16(#ext)..ext
 local handshake=string.char(1,0)..u16(#body)..body
 return string.char(22,3,1)..u16(#handshake)..handshake
end
local function run()
 local fs=require 'nixio.fs'; if not fs.stat(root..'/logs') then assert(fs.mkdir(root..'/logs','700')) end
 -- Bound but deliberately non-listening endpoint: reserved refusal, never a foreign service.
 local deny=assert(nixio.socket('inet','stream')); assert(deny:bind('127.0.0.1',49309)); sockets[#sockets+1]=deny
 backend(49301,'HP_TLS_A'); backend(49302,'HP_TLS_B'); backend(49303,'HP_SSH'); backend(49304,'HP_TCP',true)
 file('sslh.cfg', [[foreground: true;
inetd: false;
numeric: true;
transparent: false;
timeout: 1;
user: "root";
pidfile: "/tmp/homepublish-tcp-p0/sslh.pid";
listen: ( { host: "::1"; port: "49300"; } );
protocols: (
 { name: "tls"; host: "127.0.0.1"; port: "49301"; sni_hostnames: [ "a.fixture.home" ]; },
 { name: "tls"; host: "127.0.0.1"; port: "49302"; sni_hostnames: [ "b.fixture.home" ]; },
 { name: "ssh"; host: "127.0.0.1"; port: "49303"; },
 { name: "anyprot"; host: "127.0.0.1"; port: "49309"; }
);
on-timeout: "anyprot";
]])
 file('nginx.conf', [[daemon off;
master_process off;
error_log stderr notice;
pid /tmp/homepublish-tcp-p0/nginx.pid;
events { worker_connections 32; }
stream { server { listen [::1]:49305 ipv6only=on; proxy_pass 127.0.0.1:49304; proxy_timeout 5s; } }
]])
 fork(function() nixio.exec(root..'/sslh-select','-F',root..'/sslh.cfg'); os.exit(127) end)
 fork(function() nixio.exec(root..'/nginx-stream','-p',root..'/','-c',root..'/nginx.conf'); os.exit(127) end)
 nixio.nanosleep(1)
 connect(49300,hello('a.fixture.home'),'HP_TLS_A'); print('PASS SNI_A_V6_TO_V4')
 connect(49300,hello('b.fixture.home'),'HP_TLS_B'); print('PASS SNI_B_V6_TO_V4')
 connect(49300,'SSH-2.0-HP_P0\r\n','HP_SSH'); print('PASS SSH_PROBE_V6_TO_V4')
 connect(49305,nil,'HP_TCP'); print('PASS NGINX_STREAM_V6_TO_V4_SERVER_FIRST')
 connect(49300,hello('a.fixture.home'),'HP_TLS_A',true); print('PASS FRAGMENTED_CLIENT_HELLO')
 connect(49300,hello(nil)); print('PASS NO_SNI_NO_BUSINESS')
 connect(49300,hello('unknown.fixture.home')); print('PASS UNKNOWN_SNI_NO_BUSINESS')
 connect(49300,'UNKNOWN_PROTOCOL\r\n'); print('PASS UNKNOWN_PROTOCOL_NO_BUSINESS')
 connect(49300,nil); print('PASS SILENT_TIMEOUT_NO_BUSINESS')
end
local ok,err=xpcall(run,debug.traceback)
for _,pid in ipairs(children) do nixio.kill(pid,15) end
nixio.nanosleep(1)
for _,pid in ipairs(children) do
 local found=nixio.waitpid(pid,'nohang')
 if not found or found==0 then nixio.kill(pid,9); nixio.waitpid(pid) end
end
for _,s in ipairs(sockets) do s:close() end
if not ok then io.stderr:write(tostring(err)..'\n'); os.exit(1) end
print('HP_TCP_P0_PROBES_PASS (probe routing only; no real TLS/SSH authentication/public acceptance)')
