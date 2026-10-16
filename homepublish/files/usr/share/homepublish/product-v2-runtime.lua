-- SPDX-License-Identifier: Apache-2.0
-- Shared conventional v2 adapter. Options come only from fixed installed code.
local R=require('direct-renderer');local B=require('direct-backend');local I=require('device-integrations');local M={}
local function q(s)return "'"..s:gsub("'","'\\''").."'"end
local function run(s)return os.execute(s)==0 end
local function identity(source)
 local f=io.popen('sha256sum '..q(source.certificate)..' '..q(source.key)..' 2>/dev/null');if not f then return nil end
 local s=f:read('*a');f:close();return s~='' and s or nil
end
local function connected(address,port,banner)
 local n=require('nixio');local s=n.socket(address:find(':',1,true) and 'inet6' or 'inet','stream');if not s then return false end
 s:setopt('socket','rcvtimeo',2);s:setopt('socket','sndtimeo',2)
 local ok=s:connect(address,port)
 if ok and banner then s:send('SSH-2.0-HomePublish_Readiness\r\n');local text=s:recv(256);ok=type(text)=='string' and text:match('^SSH%-2%.0%-')~=nil end
 s:close();return ok==true
end
function M.new(o)
 local G=require('product-procd-group').new(o);local active,next_check
 local V={}
 function V.runtime_plan(c)
  if not o.available() then return nil,'installed v2 capability unavailable' end
  local p,e=require('canonical-v2').validate(c);if not p then return nil,e end
  local enabled={};for _,s in ipairs(p.services) do if s.enabled then
   if s.authentication_review.authentication~='confirmed' or s.authentication_review.management then return nil,'authentication review required' end
   enabled[#enabled+1]=s
  end end;p.services=enabled
  if #enabled==0 or not o.authorize(p) then return nil,'installed v2 scope denied' end
  return p
 end
 local function verify_bindings(listeners)
  local N=require('network-inventory');local inventory,err=N.collect()
  if not inventory then return nil,err.error end
  for _,l in ipairs(listeners) do
   local resolved,e=N.resolve(l,inventory)
   if not resolved then return nil,e.error end
  end
  return true
 end
 function V.plan(c)
  local p,e=V.runtime_plan(c);if not p then return nil,e end
  local bound,err=verify_bindings(p.access_profile.listeners);if not bound then return nil,err end
  local snapshots={};local bindings={};local backend={}
  local ports=o.mixed_ports
  if type(ports)=='function' then ports=ports(p);if not ports then return nil,'internal ports unavailable' end end
  local deps={resolve=I.resolve,mixed_ports=ports,authorize_listener=o.authorize_listener,authorize_backend=o.authorize_backend,healthy=function()return true end}
  deps.certificate_snapshot=function(ref,host)
   local key=ref..'|'..host;if bindings[key] then return bindings[key] end
   local source=assert(I.certificate_source(ref,host));local i=#snapshots+1
   local target={certificate=o.root..'/cert'..i..'.pem',key=o.root..'/key'..i..'.pem'}
   snapshots[i]={source=source,certificate=target.certificate,key=target.key,identity=identity(source)};assert(snapshots[i].identity,'certificate identity unavailable');bindings[key]=target;return target
  end
  for _,s in ipairs(p.services) do local b,err=B.select(s.backend,deps);if not b then return nil,err end;backend[s.service_id]=b end
  local r,err=R.render(p,deps);if not r then return nil,err end
  -- Fixed device profile can only narrow exact authorized addresses to loopback.
  r.configuration=o.narrow(r.configuration);if r.sslh_configuration then r.sslh_configuration=o.narrow(r.sslh_configuration) end
  r.services=p.services;r.listeners=p.access_profile.listeners;r.snapshots=snapshots;r.selected=backend
  return r
 end
 function V.start(p,g)
  if not o.available() then return false end
  local ok=G.start(p,g);if ok then active=p;next_check=os.time()+30 end;return ok
 end
 function V.readiness(p)
  local healthy=G.healthy();local out={}
  local address=o.probe_address(p.listeners[1]);local shared=p.listeners[1].port
  for _,s in ipairs(p.services) do
   local ready=false;local port=s.type=='tcp_forward' and s.listen_port or shared
   for _=1,3 do
    if s.type=='tls_passthrough' and not o.passthrough_trust then
     -- Transport-only probe: SNI routing and TLS handshake, no HTTP or
     -- ingress certificate identity imposed on an opaque backend service.
     local endpoint=address:find(':',1,true) and '['..address..']' or address
     local f=io.popen("timeout 3 openssl s_client -brief -connect "..q(endpoint..':'..port)..' -servername '..q(s.hostname).." </dev/null 2>&1; printf '\\nHP_TLS_EXIT=%s\\n' \"$?\"")
     local text=f and f:read('*a') or '';if f then f:close() end
     local established,protocol,cipher,status=false,false,false,nil
     for line in text:gmatch('[^\r\n]+') do
      if line=='CONNECTION ESTABLISHED' then established=true end
      if line:match('^Protocol version: TLSv1%.[23]$') then protocol=true end
      if line:match('^Ciphersuite: [A-Z0-9_%-]+$') and not line:find('NONE',1,true) then cipher=true end
      local code=line:match('^HP_TLS_EXIT=(%d+)$');if code then status=tonumber(code) end
     end
     ready=established and protocol and cipher and status==0
    elseif s.type=='https_proxy' or s.type=='tls_passthrough' then
     local trust=s.type=='tls_passthrough' and o.passthrough_trust or nil
     local endpoint=address:find(':',1,true) and '['..address..']' or address
     ready=run("env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --connect-timeout 1 --max-time 2 --fail --silent --output /dev/null"..(trust and ' --cacert '..q(trust) or '')..' --resolve '..q(s.hostname..':'..port..':'..endpoint)..' '..q('https://'..s.hostname..':'..port..'/'))
    else
     local b=p.selected[s.service_id]
     ready=connected(b.address,b.port,s.type=='ssh') and connected(address,port,s.type=='ssh')
    end
    if ready then break end;os.execute('sleep 1')
   end
   out[s.service_id]={ready=healthy and ready,generation=p.generation}
  end
  for _,v in pairs(out) do if not v.ready then return false,out end end;return healthy,out
 end
 function V.renew()
  if not active or not G.healthy() then return false end
  if os.time()>=(next_check or 0) then
   next_check=os.time()+30
   if not verify_bindings(active.listeners) then return false end
   for _,s in ipairs(active.snapshots) do if identity(s.source)~=s.identity then return false end end
   for _,s in ipairs(active.services) do
    local b=B.select(s.backend,{resolve=I.resolve,authorize_backend=o.authorize_backend,healthy=function()return true end})
    local old=active.selected[s.service_id];if not b or b.address~=old.address or b.port~=old.port then return false end
   end
  end;return true
 end
 function V.stop()local ok=G.stop();if ok then active=nil;next_check=nil end;return ok end
 return V
end
return M
