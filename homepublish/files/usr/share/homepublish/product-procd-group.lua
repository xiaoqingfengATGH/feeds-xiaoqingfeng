-- SPDX-License-Identifier: Apache-2.0
-- Standard procd group. Options are trusted server code, never RPC input.
local J=require('product-json');local M={}
local function quote(s)return "'"..s:gsub("'","'\\''").."'"end
local function run(s)return os.execute(s)==0 end
function M.new(o)
 assert(o.name:match('^homepublish[%w%-]*$') and o.root:match('^/tmp/homepublish[%w%p]*$') and not o.root:find('..',1,true))
 local function read()
  local f=io.popen('ubus call service list '..quote(J.encode({name=o.name}))..' 2>/dev/null');if not f then return nil end
  local bytes=f:read('*a');local closed=f:close();local ok,r=pcall(J.decode,bytes);if not ok or not closed then return nil end;return r
 end
 local function write(n,s)local f=assert(io.open(o.root..'/'..n,'w'));assert(f:write(s));assert(f:close())end
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
 local G={}
 function G.healthy()
  local r=read();if not r or not r[o.name] or not owned(r[o.name].instances) then return false end
  local f=io.open(o.root..'/generation');if not f then return false end;local gen=f:read('*a');f:close()
  local expected=gen:match('sslh') and {'nginx','sslh'} or {'nginx'}
  for _,k in ipairs(expected) do local v=r[o.name].instances[k];if not v or not v.running or not v.pid or not process(v.pid) then return false end end
  return true
 end
 function G.start(plan,g)
  local before=read();if not before or before[o.name] or not run('test ! -e '..quote(o.root)) then return false end
  if not run('umask 077; mkdir '..quote(o.root)) then return false end
  plan.generation=g;write('generation',tostring(g)..(plan.sslh_configuration and ' sslh' or ''))
  -- Snapshot only trusted resolver bindings inside this newly owned runtime.
  for _,s in ipairs(plan.snapshots or {}) do
   for _,k in ipairs({'certificate','key'}) do
    local target=s[k];if type(target)~='string' or not target:match('^'..o.root:gsub('([^%w])','%%%1')..'/[a-z0-9]+%.pem$') then return false end
    local source=s.source[k];if type(source)~='string' or not source:match('^/[a-zA-Z0-9_./%*%-]+$') or source:find('..',1,true) then return false end
    if not run('umask 077; cp '..quote(source)..' '..quote(target)..' && chmod 0600 '..quote(target)) then return false end
   end
  end
  write('nginx.conf',plan.configuration)
  if plan.sslh_configuration then write('sslh.cfg',plan.sslh_configuration) end
  if not run('OPENSSL_CONF=/dev/null '..quote(o.nginx)..' -t -p '..quote(o.root..'/')..' -c nginx.conf >'..quote(o.root..'/config-test.log')..' 2>&1') then return false end
  local instances={nginx={command=command('nginx'),env={OPENSSL_CONF='/dev/null'},stdout=true,stderr=true,term_timeout=2}}
  if plan.sslh_configuration then instances.sslh={command=command('sslh'),stdout=true,stderr=true,term_timeout=2} end
  -- No respawn: recovery and manual Stop remain controller-owned.
  if not run('ubus call service set '..quote(J.encode({name=o.name,instances=instances}))..' >/dev/null') then return false end
  for _=1,5 do if G.healthy() then return true end;os.execute('sleep 1') end
  return false
 end
 function G.stop()
  local r=read();if not r then return false end
  local service=r[o.name];if service and not owned(service.instances) then return false end
  local identities={}
  if service then
   for _,v in pairs(service.instances or {}) do if v.pid then identities[v.pid]=process(v.pid) end end
   -- Record workers/children before terminating masters, not only procd PIDs.
   local f=io.popen('ls /proc');local all=f and f:read('*a') or '';if f then f:close() end
   for pid in all:gmatch('%d+') do local s=process(pid);local parent=s and tonumber(s:match('^%d+ %b() %S+ (%d+)'));if parent and identities[parent] then identities[tonumber(pid)]=s end end
   if not run('ubus call service delete '..quote(J.encode({name=o.name}))..' >/dev/null') then return false end
  end
  for _=1,8 do
   local after=read();local absent=after and not after[o.name]
   for pid,identity in pairs(identities) do
    local current=process(pid)
    local function starttime(stat)
     local rest=stat and stat:match('^%d+ %b() (.*)');local n=0
     for value in (rest or ''):gmatch('%S+') do n=n+1;if n==20 then return value end end
    end
    if current and starttime(current)==starttime(identity) then absent=false end
   end
   if absent then return run('rm -rf '..quote(o.root)) end
   os.execute('sleep 1')
  end
  return false
 end
 return G
end
return M
