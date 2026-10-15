-- Real socket rejection probes; no backend or journal changes.
local n=require('nixio')
for _,payload in ipairs({'GARBAGE_NOT_TLS\r\n','PROXY TCP6 2001:db8::bad ::1 1234 49543\r\n',''}) do
 local s=assert(n.socket('inet6','stream'));assert(s:connect('::1',49543))
 if payload~='' then assert(s:send(payload)==#payload) end
 local fds={{fd=s,events=n.poll_flags('in','hup','err')}}
 assert(n.poll(fds,4000)>0,'reject socket not closed within bound')
 local bytes,code=s:recv(4096);assert(bytes=='' or (bytes==nil and code~=11),'unexpected business response or pending read')
 s:close()
end
print('PASS raw garbage/client-PROXY/idle EOF within 4 seconds')
