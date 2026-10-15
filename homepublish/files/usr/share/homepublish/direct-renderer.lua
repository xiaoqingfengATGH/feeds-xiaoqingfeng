-- SPDX-License-Identifier: Apache-2.0
-- Pure internal render: no process/network/filesystem changes. Activation gated.
-- Providers must be fixed trusted code, NEVER client-derived functions/paths.
-- Certificate provider supplies snapshot paths; runtime adapters own SAN/chain/
-- key readiness, private snapshot lifecycle and ordinary procd supervision.
local A=require('direct-address');local B=require('direct-backend');local M={}
local function dense(t,lo,hi)
 assert(type(t)=='table' and getmetatable(t)==nil,'array');local n=0
 for k in pairs(t) do assert(type(k)=='number' and k%1==0 and k>=1,'array key');n=n+1 end
 assert(n>=lo and n<=hi,'array size');for i=1,n do assert(rawget(t,i)~=nil,'sparse array') end;return n
end
local function port(v) assert(type(v)=='number' and v%1==0 and v>=1024 and v<=65535,'listener port');return v end
local function path(s) assert(type(s)=='string' and s:match('^/[a-zA-Z0-9_./%-]+$') and not s:find('..',1,true),'trusted snapshot path');return s end
local function render(plan,p)
 assert(type(plan)=='table' and type(p)=='table','typed plan/providers');dense(plan.services,1,16);dense(plan.access_profile.listeners,1,8)
 local listens,seen={},{}
 for _,l in ipairs(plan.access_profile.listeners) do
  local words,f=A.parse(l.address);assert(f==l.family and l.protocol=='tcp','listener family/protocol');port(l.internal_port)
  assert(type(l.interface)=='string' and type(l.zone)=='string','listener scope')
  assert(type(p.authorize_listener)=='function' and p.authorize_listener(l)==true,'listener ownership/approval/management denied')
  local key=f..':'..table.concat(words,':')..':'..l.internal_port;assert(not seen[key],'duplicate listener');seen[key]=true
  local bind=f=='ipv6' and '['..l.address..']' or l.address
  listens[#listens+1]='listen '..bind..':'..l.internal_port..' ssl'..(f=='ipv6' and ' ipv6only=on' or '')..';'
 end
 local out={'worker_processes 1;','daemon off;','pid nginx.pid;','error_log stderr error;','events { worker_connections 64; }','http {','access_log off;','client_body_temp_path body;','proxy_temp_path proxy;','fastcgi_temp_path fastcgi;','uwsgi_temp_path uwsgi;','scgi_temp_path scgi;'}
 local default={};for _,l in ipairs(listens) do default[#default+1]=l:gsub(';$',' default_server;') end
 out[#out+1]='server { '..table.concat(default,' ')..' ssl_reject_handshake on; return 444; }'
 local hosts={};local snapshots={}
 for _,s in ipairs(plan.services) do
  B.hostname(s.hostname);assert(not hosts[s.hostname],'duplicate hostname');hosts[s.hostname]=true
  assert(type(s.certificate_ref)=='string' and s.certificate_ref:match('^%a+:[a-zA-Z0-9_.%-]+$'),'certificate reference')
  local provider=s.certificate_ref:match('^(%a+):');assert(provider=='acme' or provider=='import','certificate provider')
  assert(type(p.certificate_snapshot)=='function','trusted certificate provider required')
  local cert=p.certificate_snapshot(s.certificate_ref,s.hostname);assert(type(cert)=='table','certificate snapshot unavailable')
  local backend,e=B.select(s.backend,p);assert(backend,e);snapshots[#snapshots+1]=backend
  local host=backend.family=='ipv6' and '['..backend.address..']' or backend.address
  local service_listens={};for i,l in ipairs(listens) do service_listens[i]=l:gsub(' ipv6only=on','') end
  -- Match the raw Host, not $host (which discards ports and can fall back).
  -- Only absent port or the canonical decimal port of this actual socket is valid.
  -- Quoted Nginx regex uses [.] instead of backslash escaping; no client regex.
  local hostname_pattern=s.hostname:gsub('%.','[.]')
  local host_guard='homepublish_host_'..#snapshots
  out[#out+1]='map "$http_host:$server_port" $'..host_guard..' { default 0;'
  local ports={}
  for _,l in ipairs(plan.access_profile.listeners) do
   local number=tostring(l.public_port or l.internal_port)
   if not ports[number] then
    ports[number]=true
    out[#out+1]='"~*^'..hostname_pattern..'(:'..number..')?:'..tostring(l.internal_port)..'$" 1;'
   end
  end
  out[#out+1]='}'
  out[#out+1]='server { '..table.concat(service_listens,' ')..' server_name '..s.hostname..'; ssl_certificate '..path(cert.certificate)..'; ssl_certificate_key '..path(cert.key)..';'
  -- Reverse proxy accepts origin-form only; $host prefers absolute URI authority.
  out[#out+1]='if ($request !~ "^[^ ]+ /") { return 444; }'
  out[#out+1]='if ($ssl_server_name !~* "^'..hostname_pattern..'$") { return 444; }'
  out[#out+1]='if ($'..host_guard..' != 1) { return 444; }'
  out[#out+1]='if ($host != "'..s.hostname..'") { return 444; }'
 local scheme=s.upstream_scheme or 'http';assert(scheme=='http' or scheme=='https','upstream scheme')
  local tls=''
  if scheme=='https' then
   assert(type(s.upstream_tls)=='table' and s.upstream_tls.verify==true,'upstream TLS verification required')
   B.hostname(s.upstream_tls.server_name)
   tls=' proxy_ssl_server_name on; proxy_ssl_name '..s.upstream_tls.server_name..'; proxy_ssl_verify on; proxy_ssl_verify_depth 5; proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;'
  else assert(s.upstream_tls==nil,'HTTP has no upstream TLS') end
  out[#out+1]='location / { proxy_pass '..scheme..'://'..host..':'..backend.port..'; proxy_next_upstream off; proxy_set_header Host '..s.hostname..'; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $remote_addr; proxy_set_header Forwarded "";'..tls..' proxy_connect_timeout 2s; proxy_read_timeout 5s; } }'
 end
 out[#out+1]='}';return {configuration=table.concat(out,'\n')..'\n',backends=snapshots,activation_ready=false,blocker='fixed runtime provider and authoritative TLS/DNS/ownership readiness required'}
end
function M.render(plan,p)
 if type(plan)=='table' and plan.schema_version==2 then
  local lowered,e=require('tcp-route-plan').compile(plan);if not lowered then return nil,e end
  plan=lowered
 end
 if plan.tcp then return require('tcp-stream-renderer').render(plan,p) end
 if plan.passthrough or plan.ssh then return require('sslh-renderer').render(plan,p) end
 local ok,r=pcall(render,plan,p);if ok then return r end;return nil,tostring(r)
end
return M
