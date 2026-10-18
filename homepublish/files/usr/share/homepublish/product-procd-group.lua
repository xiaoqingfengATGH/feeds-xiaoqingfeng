-- SPDX-License-Identifier: Apache-2.0
-- Standard procd group. Options are trusted server code, never RPC input.
local J=require('product-json');local L=require('product-listeners');local M={}
local function quote(s)return "'"..s:gsub("'","'\\''").."'"end
local function run(s)return os.execute(s)==0 end
function M.new(o)
 assert(o.name:match('^homepublish[%w%-]*$') and o.root:match('^/tmp/homepublish[%w%p]*$') and not o.root:find('..',1,true))
 local function read()
  local f=io.popen('ubus call service list '..quote(J.encode({name=o.name}))..' 2>/dev/null');if not f then return nil end
  local bytes=f:read('*a');local closed=f:close();local ok,r=pcall(J.decode,bytes);if not ok or not closed then return nil end;return r
 end
 local function write(n,s)
  local f=io.open(o.root..'/'..n,'w');if not f then return false end
  local ok=f:write(s);local closed=f:close();return ok and closed
 end
 local function command(kind)
  if kind=='nginx' then return {o.nginx,'-p',o.root..'/','-c','nginx.conf'} end
  return {o.sslh,'-F',o.root..'/sslh.cfg'}
 end
 local function owned(instances)
  for k,v in pairs(instances or {}) do
   if k~='nginx' and k~='sslh' then return false end
   local expect=command(k);if type(v.command)~='table' or #v.command~=#expect then return false end
   for i,s in ipairs(expect) do if v.command[i]~=s then return false end end
  end;return true
 end
 local function process(pid)
  local f=io.open('/proc/'..pid..'/stat');if not f then return nil end;local s=f:read('*a');f:close();return s
 end
 local G={};local expected;local tracked={};local tracked_sockets={}
 local function capture(instances)
  local roots={};for k,v in pairs(instances or {}) do if v.pid then roots[k]=tonumber(v.pid) end end
  local sockets,ids=L.family(roots);if not sockets then return nil,ids end
  for pid,id in pairs(ids) do tracked[pid]=id end
  for _,set in pairs(sockets) do for inode in pairs(set) do tracked_sockets[inode]=true end end
  return sockets
 end
 function G.preflight(plan)
  local r=read();if not r then return false,'procd service status unavailable' end
  local ignore={}
  if r[o.name] then
   if not owned(r[o.name].instances) then return false,'procd component ownership mismatch' end
   local sockets,err=capture(r[o.name].instances);if not sockets then return false,err end
   for _,set in pairs(sockets) do for inode in pairs(set) do ignore[inode]=true end end
  end
  return L.preflight(L.expected(plan),ignore)
 end
 function G.healthy()
  local r=read();if not r then return false,'procd service status unavailable' end
  if not r[o.name] then return false,'procd service is missing' end
  if not owned(r[o.name].instances) then return false,'procd component ownership mismatch' end
  local f=io.open(o.root..'/generation');if not f then return false,'runtime generation is unavailable' end;local gen=f:read('*a');f:close()
  local components=gen:match('sslh') and {'nginx','sslh'} or {'nginx'}
  for _,k in ipairs(components) do
   local v=(r[o.name].instances or {})[k]
   if not v or not v.running then return false,k..' process is not running' end
   if not v.pid or not process(v.pid) then return false,k..' process is unavailable' end
  end
  if not expected then
   local manifest=io.open(o.root..'/listeners.json');if not manifest then return false,'listener manifest unavailable' end
   local bytes=manifest:read('*a');manifest:close();local ok,value=pcall(J.decode,bytes)
   if not ok or type(value)~='table' or #value==0 then return false,'listener manifest invalid' end;expected=value
  end
  local sockets,err=capture(r[o.name].instances);if not sockets then return false,err end
  local rows;rows,err=L.rows();if not rows then return false,err end
  return L.verify(expected,rows,sockets)
 end
 function G.start(plan,g)
  local checked,conflict=G.preflight(plan);if not checked then return false,conflict end
  local before=read();if not before then return false,'procd service status unavailable' end
  if before[o.name] then return false,'procd service already exists' end
  if not run('test ! -e '..quote(o.root)) then return false,'runtime directory already exists' end
  if not run('umask 077; mkdir '..quote(o.root)) then return false,'runtime directory creation failed' end
  expected=L.expected(plan);if #expected==0 then return false,'rendered listener plan is empty' end
  if not write('listeners.json',J.encode(expected)) then return false,'listener manifest write failed' end
  plan.generation=g;if not write('generation',tostring(g)..(plan.sslh_configuration and ' sslh' or '')) then return false,'runtime generation write failed' end
  -- Snapshot only trusted resolver bindings inside this newly owned runtime.
  for _,s in ipairs(plan.snapshots or {}) do
   for _,k in ipairs({'certificate','key'}) do
    local target=s[k];if type(target)~='string' or not target:match('^'..o.root:gsub('([^%w])','%%%1')..'/[a-z0-9]+%.pem$') then return false,'invalid '..k..' snapshot target' end
    local source=s.source[k];if type(source)~='string' or not source:match('^/[a-zA-Z0-9_./%*%-]+$') or source:find('..',1,true) then return false,'invalid '..k..' snapshot source' end
    if not run('umask 077; cp '..quote(source)..' '..quote(target)..' && chmod 0600 '..quote(target)) then return false,k..' snapshot copy failed' end
   end
  end
  if not write('nginx.conf',(plan.configuration:gsub('error_log stderr error;', 'error_log '..o.root..'/error.log error;'))) then return false,'nginx configuration write failed' end
  if plan.sslh_configuration and not write('sslh.cfg',plan.sslh_configuration) then return false,'sslh configuration write failed' end
  if not run('OPENSSL_CONF=/dev/null '..quote(o.nginx)..' -t -p '..quote(o.root..'/')..' -c nginx.conf >'..quote(o.root..'/config-test.log')..' 2>&1') then
   local f=io.open(o.root..'/config-test.log');local detail=f and f:read(1024) or '';if f then f:close() end
   detail=(detail or ''):gsub('[%c]',' ')
   if detail:find('bind',1,true) then
    local chosen=expected[1];for _,e in ipairs(expected) do if detail:find(tostring(e.port),1,true) then chosen=e;break end end
    local errno=detail:match('%((%d+):');local reason=detail:match('[Aa]ddress.*[Ii]n use') and 'address in use' or 'bind failed'
    return false,L.reason(chosen,reason..(errno and ' errno '..errno or ''))..': nginx configuration test failed: '..detail
   end
   return false,'nginx configuration test failed'..(detail~='' and ': '..detail or '')
  end
  local instances={nginx={command=command('nginx'),env={OPENSSL_CONF='/dev/null'},stdout=true,stderr=true,term_timeout=2}}
  if plan.sslh_configuration then instances.sslh={command=command('sslh'),stdout=true,stderr=true,term_timeout=2} end
  -- No respawn: recovery and manual Stop remain controller-owned.
  if not run('ubus call service set '..quote(J.encode({name=o.name,instances=instances}))..' >/dev/null') then return false,'procd service registration failed' end
  local err
  for _=1,5 do local ok;ok,err=G.healthy();if ok then return true end;os.execute('sleep 1') end
  -- Retain endpoint first: controller journal errors have a 128-byte bound.
  local detail=''
  local f=io.open(o.root..'/error.log');if f then local bytes=f:read('*a') or '';f:close();detail=bytes:match('([^\n]*bind%(%) failed[^\n]*)') or bytes:match('([^\n]*bind%([^\n]*)') or '' end
  if detail=='' and plan.sslh_configuration then
   local log=io.popen('logread -l 40 -e '..quote(o.name)..' 2>/dev/null')
   if log then local bytes=log:read('*a') or '';log:close();detail=bytes:match('([^\n]*[Bb]ind[^\n]*)') or bytes:match('([^\n]*[Aa]ddress already in use[^\n]*)') or '' end
  end
  if detail~='' then
   local chosen=expected[1]
   for _,e in ipairs(expected) do if detail:find(tostring(e.port),1,true) then chosen=e;break end end
   local errno=detail:match('%((%d+):')
   local reason=detail:match('[Aa]ddress already in use') and 'address in use' or detail:match('[Cc]annot assign requested address') and 'address unavailable' or 'bind failed'
   return false,L.reason(chosen,reason..(errno and ' errno '..errno or ''))..': '..detail:gsub('[%c]',' ')
  end
  if expected and expected[1] and err and err:find('process',1,true) then
   for _,e in ipairs(expected) do if err:find(e.component,1,true) then return false,L.reason(e,err) end end
  end
  return false,err or 'runtime components did not start'
 end
 function G.stop()
  local r=read();if not r then return false end
  local service=r[o.name];if service and not owned(service.instances) then return false end
  local inventory_ok=true
  if service then
   local sockets=capture(service.instances);if not sockets then inventory_ok=false end
   if not run('ubus call service delete '..quote(J.encode({name=o.name}))..' >/dev/null') then return false,'procd service deletion failed' end
  end
  for _=1,8 do
   local after=read();local absent=inventory_ok and after and not after[o.name]
   for pid,id in pairs(tracked) do
    local now=L.identity(pid)
    if now and now.start==id.start then
     absent=false
     -- Include children created during shutdown before their parent exits.
     local roots={[id.component]=pid};local sockets,ids=L.family(roots)
     if sockets then
      for child,identity in pairs(ids) do tracked[child]=identity end
      for _,set in pairs(sockets) do for inode in pairs(set) do tracked_sockets[inode]=true end end
     end
    end
   end
   local rows=L.rows();if not rows then absent=false else
    for _,row in ipairs(rows) do if tracked_sockets[row.inode] then absent=false end end
   end
   if absent then
    local removed=run('rm -rf '..quote(o.root));if removed then expected=nil;tracked={};tracked_sockets={} end
    return removed,removed and nil or 'runtime directory cleanup failed'
   end
   os.execute('sleep 1')
  end
  return false,'owned process or TCP listener cleanup incomplete'
 end
 return G
end
return M
