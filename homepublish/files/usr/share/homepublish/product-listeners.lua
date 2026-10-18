-- SPDX-License-Identifier: Apache-2.0
-- Local TCP LISTEN inspection only; never connects to a backend.
local M={}
local function words(s)
 local a,b=s:match('^(.-)::(.-)$');local t={}
 local function add(v)for x in v:gmatch('[%da-fA-F]+') do t[#t+1]=tonumber(x,16) end end
 if a then
  add(a);local tail={};for x in b:gmatch('[%da-fA-F]+') do tail[#tail+1]=tonumber(x,16) end
  while #t+#tail<8 do t[#t+1]=0 end;for _,x in ipairs(tail) do t[#t+1]=x end
 else add(s) end
 return t
end
function M.same_address(a,b,f)
 if f=='ipv4' then return a==b end
 local x,y=words(a),words(b);if #x~=8 or #y~=8 then return false end
 for i=1,8 do if x[i]~=y[i] then return false end end;return true
end
local function wildcard(a,f)return M.same_address(a,f=='ipv4' and '0.0.0.0' or '::',f) end
function M.conflicts(a,b)
 return a.family==b.family and a.port==b.port and (wildcard(a.address,a.family) or wildcard(b.address,b.family) or M.same_address(a.address,b.address,a.family))
end
function M.endpoint(e)return (e.family=='ipv6' and '['..e.address..']' or e.address)..':'..e.port end
function M.reason(e,why)return e.component..' '..M.endpoint(e)..' '..why..' ('..e.label..')' end
function M.expected(p)
 local out,seen={},{}
 local function add(component,address,port)
  port=tonumber(port);local f=address:find(':',1,true) and 'ipv6' or 'ipv4'
  local key=component..'|'..address..'|'..port;if seen[key] then return end;seen[key]=true
  local label=component=='sslh' and 'shared entry' or 'internal/shared'
  for _,s in ipairs(p.services or {}) do if s.type=='tcp_forward' and s.listen_port==port then label=s.name or s.service_id end end
  out[#out+1]={component=component,address=address,port=port,family=f,label=label}
 end
 for socket in (p.configuration or ''):gmatch('listen%s+([^;%s]+)[^;]*;') do
  local a,n=socket:match('^%[([^%]]+)%]:(%d+)$');if not a then a,n=socket:match('^([%d.]+):(%d+)$') end
  assert(a and n,'unsupported rendered nginx listener');add('nginx',a,n)
 end
 -- Restrict parsing to listen, not sslh backend protocol destinations.
 local section=(p.sslh_configuration or ''):match('listen:%s*%((.-)%);') or ''
 for a,n in section:gmatch('host:%s*"([^"]+)";%s*port:%s*"(%d+)"') do add('sslh',a,n) end
 return out
end
function M.parse(text,family)
 local out={}
 for line in text:gmatch('[^\n]+') do
  local t={};for x in line:gmatch('%S+') do t[#t+1]=x end
  if t[4]=='0A' then
   local hex,port=t[2]:match('^(%x+):(%x+)$');local bytes={}
   if hex and t[10] then
    for word in hex:gmatch('%x%x%x%x%x%x%x%x') do
     local reversed=word:sub(7,8)..word:sub(5,6)..word:sub(3,4)..word:sub(1,2)
     bytes[#bytes+1]=reversed
    end
    local address
    if family=='ipv4' then local b={};for x in table.concat(bytes):gmatch('%x%x') do b[#b+1]=tonumber(x,16) end;address=table.concat(b,'.')
    else local b={};for x in table.concat(bytes):gmatch('%x%x%x%x') do b[#b+1]=x:lower() end;address=table.concat(b,':') end
    out[#out+1]={family=family,address=address,port=tonumber(port,16),inode=t[10]}
   end
  end
 end;return out
end
function M.verify(expected,rows,owners)
 for _,e in ipairs(expected) do
  local found,foreign=false,false
  for _,r in ipairs(rows) do
   if r.family==e.family and r.port==e.port and M.same_address(r.address,e.address,e.family) then
    if (owners[e.component] or {})[r.inode] then found=true else foreign=true end
   end
  end
  if not found then return false,M.reason(e,foreign and 'foreign listener' or 'not listening') end
 end;return true
end
local function read(path)local f=io.open(path);if not f then return nil end;local s=f:read('*a');f:close();return s end
function M.rows()
 local out={};for _,f in ipairs({'ipv4','ipv6'}) do
  local s=read(f=='ipv4' and '/proc/net/tcp' or '/proc/net/tcp6');if not s then return nil,'TCP listener inventory unavailable' end
  for _,r in ipairs(M.parse(s,f)) do out[#out+1]=r end
 end;return out
end
function M.identity(pid)
 local s=read('/proc/'..pid..'/stat');local rest=s and s:match('^%d+ %b() (.*)');local t={}
 for x in (rest or ''):gmatch('%S+') do t[#t+1]=x end
 if not t[20] then return nil end;return {pid=tonumber(pid),parent=tonumber(t[2]),start=t[20]}
end
function M.family(roots)
 local fs=require('nixio.fs');local all,owned={},{}
 local iter=fs.dir('/proc');if not iter then return nil,'process inventory unavailable' end
 for pid in iter do if pid:match('^%d+$') then local id=M.identity(pid);if id then all[id.pid]=id end end end
 for component,pid in pairs(roots) do local id=all[pid];if id then id.component=component;owned[pid]=id end end
 local changed=true;while changed do changed=false;for pid,id in pairs(all) do if not owned[pid] and owned[id.parent] then id.component=owned[id.parent].component;owned[pid]=id;changed=true end end end
 local sockets={nginx={},sslh={}}
 for pid,id in pairs(owned) do
  local fd=fs.dir('/proc/'..pid..'/fd');if fd then for n in fd do
   local target=fs.readlink('/proc/'..pid..'/fd/'..n);local inode=target and target:match('^socket:%[(%d+)%]$')
   if inode then sockets[id.component][inode]=true end
  end end
  local now=M.identity(pid);if not now or now.start~=id.start then return nil,'process identity changed during listener inspection' end
 end
 return sockets,owned
end
function M.preflight(expected,ignore)
 local rows,err=M.rows();if not rows then return false,err end
 for _,e in ipairs(expected) do
  local own_overlap=false
  for _,r in ipairs(rows) do
   if M.conflicts(e,r) then
    if ignore and ignore[r.inode] then own_overlap=true else return false,M.reason(e,'address in use') end
   end
  end
  -- /proc does not expose IPV6_V6ONLY. Ask the kernel for cross-family
  -- wildcard cases, rather than treating every IPv6 wildcard as dual stack.
  local ambiguous=false
  for _,r in ipairs(rows) do if r.family~=e.family and r.port==e.port and (wildcard(r.address,r.family) or wildcard(e.address,e.family)) and not (ignore and ignore[r.inode]) then ambiguous=true end end
  -- An old owned socket would make this local bind fail against ourselves.
  -- Defer only that ambiguous check to start's repeated preflight after stop;
  -- post-start owned LISTEN verification remains mandatory in every case.
  if ambiguous and not own_overlap then
   local n=require('nixio');local s=n.socket(e.family=='ipv6' and 'inet6' or 'inet','stream')
   if not s then return false,M.reason(e,'bind check unavailable') end
   if e.family=='ipv6' and not s:setopt('ipv6','v6only',1) then s:close();return false,M.reason(e,'IPv6-only bind check unavailable') end
   local ok,msg,errno=s:bind(e.address,e.port);s:close()
   if not ok then return false,M.reason(e,'bind failed '..tostring(errno)..' '..tostring(msg)) end
  end
 end;return true
end
return M
