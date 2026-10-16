-- Fixed private RPC transport; never registered as a production rpcd endpoint.
package.path='/usr/share/homepublish/?.lua;'..package.path
package.cpath='/tmp/homepublish-tcp-p3/?.so;'..package.cpath
local n=require('nixio');local fs=require('nixio.fs');local J=require('product-json')
local path='/tmp/homepublish-tcp-p3/controller-fixture/policy.sock'
local function read(s)local b='';while not b:find('\n',1,true) do local p=s:recv(4096);assert(p and #p>0,'closed');b=b..p end;return b:match('^([^\n]*)') end
if arg[1]~='serve' then
 local s=assert(n.socket('unix','stream'));assert(s:connect(path));s:sendall(io.read('*a')..'\n');io.write(read(s),'\n');s:close();return
end
assert(#arg==1)
local P=require('product-provider');local C=require('product-controller').new(require('product-device-provider'))
fs.unlink(path);local server=assert(n.socket('unix','stream'));assert(server:bind(path));assert(fs.chmod(path,'600'));assert(server:listen(4));C.restore()
while true do
 local f={{fd=server,events=n.poll_flags('in')}};n.poll(f,1000)
 if f[1].revents and f[1].revents~=0 then
  local client=assert(server:accept())
  local ok,r=pcall(function()
   local q=J.decode(read(client))
   if q.action=='start' then return C.start(q.revision,q.approved)
   elseif q.action=='apply' then return C.apply(q.revision,q.approved)
   elseif q.action=='stop' then return C.stop()
   elseif q.action=='status' then return C.status()
   elseif q.action=='stale_tick' then return C.tick(q.generation)
   elseif q.action=='restore' then return C.restore()
   else return P.handle(q,true) end
  end)
  client:sendall(J.encode(ok and r or {error=tostring(r)})..'\n');client:close()
 end
 C.tick()
end
