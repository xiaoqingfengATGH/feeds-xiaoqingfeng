-- SPDX-License-Identifier: Apache-2.0
-- Fixed read-only store snapshot and killed/reaped, per-phase network workers.
local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
local J=dofile(source..'/product-json.lua')
local W=dofile(source..'/product-wire.lua')
local model=dofile(source..'/canonical.lua')
local M={}
local function revision(r)return type(r)=='number' and r%1==0 and r>=0 and r<9007199254740991 end
function M.new()
 local d={}
 function d.snapshot()
  local fs=require('nixio.fs');local root='/etc/homepublish/product'
  local dir,code=fs.lstat(root)
  if not dir then assert(code==2);return {saved_revision=0} end
  assert(dir.type=='dir' and dir.uid==0 and dir.modedec==700)
  local st,err=fs.lstat(root..'/state')
  if not st then assert(err==2);return {saved_revision=0} end
  assert(st.type=='reg' and st.uid==0 and st.modedec==600 and st.size>0 and st.size<=262144)
  local f=assert(io.open(root..'/state','rb'));local bytes=f:read(262145);local closed=f:close()
  assert(closed and bytes and #bytes>0 and #bytes<=262144)
  -- Atomic store rename gives one complete saved snapshot, without taking the
  -- controller lock. No transaction/lock creation even on an unconfigured router.
  local s=W.decode(bytes)
  assert(s.state_version==1 and revision(s.saved_revision))
  if s.active_revision~=nil then assert(revision(s.active_revision) and s.active_revision<=s.saved_revision) end
  if s.saved_revision>0 then s.saved_config=assert(model.validate(s.saved_config)) else assert(s.saved_config==nil) end
  return s
 end
 function d.bounded(phase,ms,fn)
  local n=require('nixio')
  local r,w=n.pipe();if not r then return {ok=false,reason='PROBE_UNAVAILABLE'} end
  local pid=n.fork()
  if not pid then r:close();w:close();return {ok=false,reason='PROBE_UNAVAILABLE'} end
  if pid==0 then
   r:close()
   local ok,res=pcall(fn)
   local bytes=J.encode(ok and res or {ok=false,reason='PROBE_FAILED'})
   if #bytes<=8192 then w:write(bytes) end
   w:close();os.exit(0)
  end
  w:close()
  local fds={{fd=r,events=n.poll_flags('in')}}
  local ready=n.poll(fds,ms)
  local bytes
  if ready and ready>0 then bytes=r:read(8193) end
  r:close()
  -- Reap on every parent path; a stuck resolver/connect cannot outlive its RPC.
  n.kill(pid,9);n.waitpid(pid)
  if not ready or ready<=0 then return {ok=false,reason=(ready==false or ready==0) and 'TIMEOUT' or 'PROBE_UNAVAILABLE'} end
  if type(bytes)~='string' or #bytes==0 or #bytes>8192 then return {ok=false,reason='PROBE_FAILED'} end
  local ok,res=pcall(J.decode,bytes)
  if not ok or type(res)~='table' then return {ok=false,reason='PROBE_FAILED'} end
  return res
 end
 function d.resolve(host)
  local n=require('nixio');local answer=n.getaddrinfo(host)
  if type(answer)~='table' then return {ok=false,reason='RESOLVE_FAILED'} end
  local addresses,seen={},{}
  for _,v in ipairs(answer) do
   if (v.family=='inet' or v.family=='inet6') and not seen[v.address] then
    seen[v.address]=true;addresses[#addresses+1]=v.address
   end
  end
  if #addresses==0 or #addresses>64 then return {ok=false,reason='RESOLVE_FAILED'} end
  return {ok=true,addresses=addresses}
 end
 function d.connect(address,port,family)
  local n=require('nixio');local s=n.socket(family=='ipv6' and 'inet6' or 'inet','stream')
  if not s then return {ok=false,reason='SOCKET_UNAVAILABLE'} end
  local ok,code,message=s:connect(address,port);s:close()
  if ok then return {ok=true} end
  -- Linux MIPS socket errno values differ from x86/ARM. Prefer exported
  -- constants; old nixio omits some, so recognize only fixed libc messages.
  local constants=n.const or {}
  local names={ECONNREFUSED='CONNECTION_REFUSED',ETIMEDOUT='TIMEOUT',ENETUNREACH='NETWORK_UNREACHABLE',EHOSTUNREACH='HOST_UNREACHABLE',EACCES='PERMISSION_DENIED',EPERM='PERMISSION_DENIED'}
  for name,reason in pairs(names) do if constants[name] and code==constants[name] then return {ok=false,reason=reason} end end
  local messages={['Connection refused']='CONNECTION_REFUSED',['Connection timed out']='TIMEOUT',['Operation timed out']='TIMEOUT',['Network is unreachable']='NETWORK_UNREACHABLE',['No route to host']='HOST_UNREACHABLE',['Permission denied']='PERMISSION_DENIED',['Operation not permitted']='PERMISSION_DENIED'}
  return {ok=false,reason=messages[message] or 'CONNECT_FAILED'}
 end
 return d
end
return M
