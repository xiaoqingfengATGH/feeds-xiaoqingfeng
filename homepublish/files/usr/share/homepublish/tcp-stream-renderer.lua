-- SPDX-License-Identifier: Apache-2.0
-- Independent raw TCP sockets: no sniffing, TLS termination or PROXY injection.
-- Pure trusted-provider compiler; production activation remains separately gated.
local A=require('direct-address');local B=require('direct-backend');local M={}
local function render(plan,p)
 local shared={};for k,v in pairs(plan) do if k~='tcp' then shared[k]=v end end
 local r
 if #plan.services>0 or plan.passthrough or plan.ssh then
  local e;r,e=require('direct-renderer').render(shared,p);assert(r,e)
 else
  r={configuration='worker_processes 1;\ndaemon off;\npid nginx.pid;\nerror_log stderr error;\nevents { worker_connections 64; }\n',backends={},activation_ready=false,blocker='fixed runtime provider and authoritative DNS/ownership readiness required'}
 end
 local servers={};local seen={}
 for _,s in ipairs(plan.tcp) do
  assert(type(s.listen_port)=='number' and s.listen_port%1==0 and s.listen_port>=1024 and s.listen_port<=65535,'independent TCP port')
  local b,e=B.select(s.backend,p);assert(b,e);r.backends[#r.backends+1]=b
  local target=b.family=='ipv6' and '['..b.address..']' or b.address
  local listens={}
  for _,base in ipairs(plan.access_profile.listeners) do
   local l={};for k,v in pairs(base) do l[k]=v end;l.internal_port=s.listen_port;l.service_id=s.service_id
   local words,f=A.parse(l.address);assert(f==l.family and l.protocol=='tcp','TCP listener family/protocol')
   assert(type(p.authorize_listener)=='function' and p.authorize_listener(l)==true,'TCP listener denied')
   local key=f..':'..table.concat(words,':')..':'..s.listen_port;assert(not seen[key],'duplicate TCP socket');seen[key]=true
   local host=f=='ipv6' and '['..l.address..']' or l.address
   listens[#listens+1]='listen '..host..':'..s.listen_port..(f=='ipv6' and ' ipv6only=on' or '')..';'
  end
  assert(#listens>0,'TCP listener required')
  servers[#servers+1]='server { '..table.concat(listens,' ')..' proxy_pass '..target..':'..b.port..'; proxy_connect_timeout 2s; proxy_timeout 1h; proxy_half_close on; proxy_next_upstream off; }'
 end
 local body=table.concat(servers,'\n')..'\n'
 -- The mixed renderer already owns one stream context for rejection. Extend it,
 -- never emit duplicate stream contexts or change its rejection endpoint.
 if r.sslh_configuration then
  local count;r.configuration,count=r.configuration:gsub('stream {',function()return 'stream {\n'..body end,1);assert(count==1,'mixed stream context missing')
 else r.configuration=r.configuration..'stream {\n'..body..'}\n' end
 return r
end
function M.render(plan,p)local ok,r=pcall(render,plan,p);if ok then return r end;return nil,tostring(r) end
return M
