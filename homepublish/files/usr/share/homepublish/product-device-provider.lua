-- SPDX-License-Identifier: Apache-2.0
-- Installed, root-only device test profile. Production/public activation denied.
local R=require('direct-renderer');local I=require('device-integrations');local M={}
local active_plan,next_check
local function cert_identity(source)
 local f=io.popen('sha256sum '..(source and ("'"..source.certificate.."'") or '/etc/homepublish/device-test/cert.pem')..' 2>/dev/null');if not f then return nil end
 local v=f:read('*l');f:close();return v and v:match('^(%x+)')
end
local root='/tmp/homepublish-device/runtime'
local function run(s)return os.execute(s)==0 end
local function write(name,bytes)local f=assert(io.open(root..'/'..name,'w'));assert(f:write(bytes));assert(f:close())end
function M.plan(c)
 c=require('product-wire').decode(require('product-wire').encode(c))
 if #c.services<1 or #c.services>2 or #c.access_profile.listeners~=1 then return nil,'device test scope denied' end
 local l=c.access_profile.listeners[1];local services={};local hosts={};local snapshots={}
 for i,s in ipairs(c.services) do
  local business=s.hostname=='home.iwonderful.top' and s.certificate_ref=='acme:home_rsa'
  local fixture=s.hostname=='service.home' and s.certificate_ref=='import:fixture'
  local inventory_fixture=(s.hostname=='a.fixture.home' or s.hostname=='b.fixture.home') and (s.certificate_ref=='acme:fixture_rsa' or s.certificate_ref=='acme:fixture_ecc')
  if (s.service_id~='fixture' and s.service_id~='fixture2') or hosts[s.hostname] or (not business and not fixture and not inventory_fixture) or (s.backend.host~='127.0.0.1' and not (s.backend.addressFamily=='hostname' and s.backend.host=='localhost.lan')) or (s.backend.port~=49285 and s.backend.port~=49286) or s.authentication_review.authentication~='confirmed' or s.authentication_review.management then return nil,'device test service denied' end
  hosts[s.hostname]=true
  local source={certificate='/etc/homepublish/device-test/cert.pem',key='/etc/homepublish/device-test/key.pem'}
  if business or inventory_fixture then local e;source,e=I.certificate_source(s.certificate_ref,s.hostname);if not source then return nil,e end end
  for _,v in ipairs({source.certificate,source.key}) do if not v:match('^/[a-zA-Z0-9_./%*%-]+$') or v:find('..',1,true) then return nil,'trusted HomeVPN source path required' end end
  local binding=source.certificate..'|'..source.key;local slot=snapshots[binding]
  if not slot then slot=i;snapshots[binding]=slot end
  services[i]={service_id=s.service_id,backend=s.backend,hostname=s.hostname,system_trust=business,certificate_source=source,cert_identity=cert_identity(source),certificate=root..'/cert'..slot..'.pem',key=root..'/key'..slot..'.pem'}
 end
 if #c.access_profile.methods_allowed~=1 or c.access_profile.methods_allowed[1]~='manual_ipv4' or l.family~='ipv4' or l.address~='192.168.1.2' or l.interface~='br-lan' or l.zone~='lan' or l.internal_port~=49284 or l.external_port~=49284 then return nil,'device test listener denied' end
 -- Canonical intentionally disallows loopback publication. This server-owned
 -- profile narrows the approved model to loopback; it never broadens it.
 l.address='127.0.0.1';l.interface='lo'
 local plan,e=R.render(c,{resolve=I.resolve,authorize_listener=function(v)return v.address=='127.0.0.1' and v.internal_port==49284 end,authorize_backend=function(v)return v=='127.0.0.1' or v=='::1' end,healthy=function()return true end,certificate_snapshot=function(ref,host)
  for _,v in ipairs(services) do if v.hostname==host then return {certificate=v.certificate,key=v.key} end end
 end})
 if plan then
  plan.services=services
  -- Retain the historical single-service diagnostic fields for consumers.
  for k,v in pairs(services[1]) do plan[k]=v end
 end
 return plan,e
end
function M.start(plan,g,t)
 if not run("test -f /etc/homepublish/device-test/enabled") then return false end
 if not run('umask 077; mkdir -p '..root..' && chmod 0700 '..root) then return false end
 for _,v in ipairs(plan.services) do
  if not run("umask 077; cp '"..v.certificate_source.certificate.."' "..v.certificate.." && cp '"..v.certificate_source.key.."' "..v.key..' && chmod 0600 '..v.certificate..' '..v.key) then return false end
 end
 active_plan=plan
 -- Root master reads the private key; normal Nginx workers are nobody.
 write('nginx.conf','user nobody nogroup;\n'..plan.configuration)
 if not run('/usr/sbin/nginx -t -p '..root..'/ -c nginx.conf >'..root..'/config-test.log 2>&1') then return false end
 local ok=run('/etc/init.d/homepublish-nginx start');if ok then active_plan=plan;next_check=os.time()+30 end;return ok
end
function M.readiness()
 if not active_plan then return false end
 local results={}
 for _,v in ipairs(active_plan.services) do
  local trust=v.system_trust and '' or ' --cacert '..v.certificate
  local ready=false
  for i=1,30 do
   if os.execute("env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR /usr/bin/curl -q --noproxy '*' --connect-timeout 1 --max-time 1"..trust.." --resolve "..v.hostname..":49284:127.0.0.1 --fail --silent --output /dev/null https://"..v.hostname..":49284/")==0 then ready=true;break end
   os.execute('sleep 1')
  end
  results[v.service_id]={ready=ready}
  -- Collect every binding, even when another service fails.
 end
 for _,v in pairs(results) do if not v.ready then return false,results end end
 return true,results
end
function M.renew()
 -- A changed certificate or DNS selection closes this generation; controller
 -- bounded recovery re-plans approved ACTIVE config, never pending saved edits.
 if active_plan and os.time()>=(next_check or 0) then
  next_check=os.time()+30
  for i,v in ipairs(active_plan.services) do
   if not v.cert_identity or cert_identity(v.certificate_source)~=v.cert_identity then return false end
   if v.backend.addressFamily=='hostname' then
    local b=require('direct-backend').select(v.backend,{resolve=I.resolve,authorize_backend=function(a)return a=='127.0.0.1' or a=='::1' end,healthy=function()return true end})
    if not b or b.address~=active_plan.backends[i].address then return false end
   end
  end
 end
 -- Ordinary health observation, not a short capability/authorization heartbeat.
 local f=io.open(root..'/nginx.pid','r');if not f then return false end
 local pid=f:read('*l');f:close();return pid and pid:match('^%d+$') and run('kill -0 '..pid..' 2>/dev/null') or false
end
function M.stop()
 active_plan=nil;next_check=nil
 -- Avoid submitting delete for an absent procd service (normal duplicate Stop).
 local f=io.popen([[ubus call service list '{"name":"homepublish-nginx"}' 2>/dev/null]])
 local registered=f and f:read('*a') or '';if f then f:close() end
 local stopped=true
 if registered:find('"homepublish-nginx"',1,true) then stopped=run('/etc/init.d/homepublish-nginx stop') end
 if not stopped and M.renew() then return false end
 -- procd terminates the master, which terminates its workers and connections.
 for i=1,10 do
  if not M.renew() then
   return run('rm -rf '..root)
  end
  os.execute('sleep 1')
 end
 return false
end
return M
