-- SPDX-License-Identifier: Apache-2.0
-- Standard root-private Unix socket; fixed small JSON requests, no exec broker.
local n=require('nixio');local fs=require('nixio.fs');local M={}
local path='/var/run/homepublish/control.sock'
local function ready(s,ms)return n.poll({{fd=s,events=n.poll_flags('in')}},ms)>0 end
local function read(s)
 local out=''
 while #out<262145 do
  if not ready(s,45000) then return nil end
  local b=s:recv(4096);if not b or #b==0 then return nil end
  out=out..b
  if out:find('\n',1,true) then return out:match('^([^\n]*)\n$') end
 end
end
function M.listen()
 assert(fs.mkdir('/var/run/homepublish',448) or fs.stat('/var/run/homepublish','type')=='dir')
 assert(fs.chmod('/var/run/homepublish',448));fs.unlink(path)
 local s=assert(n.socket('unix','stream'));assert(s:bind(path));assert(fs.chmod(path,384));assert(s:listen(8));return s
end
function M.receive(server)
 if not ready(server,1000) then return nil end
 local s=server:accept();if not s then return nil end
 local b=read(s);if not b then s:close();return nil end
 return b,s
end
function M.reply(s,b)s:sendall(b..'\n');s:close()end
function M.request(b)
 local s=assert(n.socket('unix','stream'));assert(s:connect(path));assert(s:sendall(b..'\n'));local out=read(s);s:close();return assert(out,'controller response unavailable')
end
return M
