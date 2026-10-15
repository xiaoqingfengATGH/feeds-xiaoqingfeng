-- Real target nixio sockets. All waits bounded; shell owns backend PID.
local n=require('nixio');local mode=assert(arg[1]);local port=tonumber(assert(arg[2]))
local function send(s,data)
 local at=1;while at<=#data do local k=assert(s:send(data:sub(at)));assert(k>0);at=at+k end
end
local function read(s,count)
 local out='';while #out<count do
  local fds={{fd=s,events=n.poll_flags('in','hup','err')}};assert(n.poll(fds,5000)>0,'read deadline')
  local bytes=assert(s:recv(count-#out));assert(#bytes>0,'early EOF');out=out..bytes
 end;return out
end
local function eof(s)
 assert(n.poll({{fd=s,events=n.poll_flags('in','hup','err')}},5000)>0,'EOF deadline');assert(s:recv(1)=='','expected EOF')
end
local bytes={};for i=0,255 do bytes[#bytes+1]=string.char(i) end
local payload=table.concat(bytes):rep(32)
if mode=='server-first' or mode=='client-first' or mode=='server-half' then
 local l=assert(n.socket('inet','stream'));assert(l:setopt('socket','reuseaddr',1));assert(l:bind('127.0.0.1',port));assert(l:listen(4))
 local s=assert(l:accept());l:close()
 if mode=='server-first' then send(s,'SERVER_FIRST\0\255') end
 if mode=='server-half' then send(s,'SERVER_HALF\0');assert(s:shutdown('wr')) end
 assert(read(s,#payload)==payload,'payload bytes corrupted or PROXY inserted')
 if mode~='server-half' then
  send(s,payload:reverse());assert(read(s,4)=='PING');send(s,'PONG')
  -- A live idle connection survives longer than protocol probe and HTTP timeout.
  n.nanosleep(8);send(s,'HELD8');assert(read(s,5)=='AFTER')
 end
 eof(s)
 if mode~='server-half' then send(s,'TAIL_AFTER_CLIENT_FIN\0');assert(s:shutdown('wr')) end
 s:close();print('PASS backend '..mode..' exact 8192 binary bytes and half-close')
else
 local s=assert(n.socket('inet6','stream'));assert(s:connect('::1',port))
 if mode=='client-server-first' then assert(read(s,14)=='SERVER_FIRST\0\255') end
 if mode=='client-server-half' then
  assert(read(s,12)=='SERVER_HALF\0');eof(s);send(s,payload);assert(s:shutdown('wr'));s:close()
  print('PASS server write-half closed first; client sent 8192 bytes after observed EOF');return
 end
 send(s,payload);assert(read(s,#payload)==payload:reverse(),'reverse byte mismatch')
 send(s,'PING');assert(read(s,4)=='PONG')
 -- read() bound 5s is shorter than intended hold; wait explicitly first.
 n.nanosleep(8);assert(read(s,5)=='HELD8');send(s,'AFTER')
 assert(s:shutdown('wr'));assert(read(s,22)=='TAIL_AFTER_CLIENT_FIN\0');eof(s);s:close()
 print('PASS '..mode..' IPv6 to IPv4; 8192 binary bytes both ways + interleaving + held8s + response after client FIN')
end
