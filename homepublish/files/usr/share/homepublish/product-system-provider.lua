-- SPDX-License-Identifier: Apache-2.0
-- Fixed production dependency: no fixture engine, trust or authorization marker.
local A=require('direct-address');local N=require('network-inventory')
local function executable(p)return os.execute("test -x '"..p.."'")==0 end
local nginx=executable('/usr/libexec/homepublish/nginx') and '/usr/libexec/homepublish/nginx' or '/usr/sbin/nginx'
local function available()
 if not executable(nginx) then return false end
 local f=io.popen(nginx..' -V 2>&1');if not f then return false end
 local s=f:read('*a');f:close();return s:find('--with-http_ssl_module',1,true)~=nil
end
local function allocate(c)
 local n=require('nixio');local held,used,out={},{},{}
 for _,l in ipairs(c.access_profile.listeners) do used[l.port]=true end
 for _,s in ipairs(c.services) do used[s.backend.port]=true;if s.listen_port then used[s.listen_port]=true end end
 for _,key in ipairs({'https','reject'}) do
  for _=1,32 do
   local sock=n.socket('inet','stream');if not sock then break end
   if sock:bind('127.0.0.1',0) then
    local _,p=sock:getsockname()
    if p and not used[p] then out[key]=p;used[p]=true;held[#held+1]=sock;break end
   end;sock:close()
  end
 end
 for _,s in ipairs(held) do s:close() end
 if out.https and out.reject then return out end
end
local V=require('product-v2-runtime').new({
 name='homepublish-runtime',root='/tmp/homepublish-runtime',nginx=nginx,
 sslh='/usr/libexec/homepublish/sslh-select',available=available,mixed_ports=allocate,
 authorize=function()return true end,
 authorize_listener=function(l)
  local inventory=N.collect();return inventory~=nil and N.resolve(l,inventory)~=nil
 end,
 -- direct-backend separately enforces canonical family/port/allowed_ranges.
 authorize_backend=function(address)return A.household(address)==true end,
 narrow=function(s)return s end,probe_address=function(l)return l.address end
})
local M={}
function M.runtime_plan(c)
 if c.schema_version~=2 then return nil,'production provider requires canonical v2' end
 for _,s in ipairs(c.services or {}) do
  if s.enabled and s.type~='https_proxy' then
   if nginx~='/usr/libexec/homepublish/nginx' or not executable('/usr/libexec/homepublish/sslh-select') then return nil,'production stream/multiplex capability unavailable' end
   local f=io.popen(nginx..' -V 2>&1');local flags=f and f:read('*a') or '';if f then f:close() end
   if not flags:find('--with-stream_ssl_preread_module',1,true) or not flags:find('--with-http_realip_module',1,true) then return nil,'production stream/multiplex capability unavailable' end
  end
 end
 return V.runtime_plan(c)
end
function M.plan(c)local p,e=M.runtime_plan(c);if not p then return nil,e end;return V.plan(p)end
M.start=V.start;M.readiness=V.readiness;M.renew=V.renew;M.stop=V.stop
return M
