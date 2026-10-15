-- Read-only inventory. No caller-controlled paths, commands, or ubus methods.
local M = {}
local function failure(code, field, message)
  return nil, {error_code=code, field=field, error=message, retryable=true}
end
local function array(t)
  if type(t) ~= 'table' or getmetatable(t) ~= nil then return false end
  local n=0
  for k in pairs(t) do
    if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 then return false end
    n=n+1
  end
  for i=1,n do if rawget(t,i)==nil then return false end end
  return true
end
local function text(s) return type(s)=='string' and #s>0 and not s:find('[%c%s]') end
local function classify(family, address)
  if type(address) ~= 'string' then return end
  if family == 'ipv4' then
    local a,b,c,d = address:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
    if not a then return nil, 'invalid' end
    local parts={a,b,c,d}
    for _,p in ipairs(parts) do if #p>3 or tonumber(p)>255 or (#p>1 and p:sub(1,1)=='0') then return nil, 'invalid' end end
    a,b,c,d=tonumber(a),tonumber(b),tonumber(c),tonumber(d)
    if a==0 or a==127 or a>=224 or (a==169 and b==254) then return end
    if a==10 or (a==172 and b>=16 and b<=31) or (a==192 and b==168) then return 'private', nil, address end
    return 'global', nil, address
  end
  if family ~= 'ipv6' then return nil, 'invalid' end
  -- Dotted IPv4-mapped notation is valid input but never eligible.
  if address:lower():match('^::ffff:%d+%.%d+%.%d+%.%d+$') then return end
  if address:find('[^%x:]') then return nil, 'invalid' end
  local s=address:lower()
  local left,right=s:match('^(.-)::(.-)$')
  local words={}
  local function parse(part)
    local out={}
    if part=='' then return out end
    if part:sub(1,1)==':' or part:sub(-1)==':' then return end
    for p in part:gmatch('[^:]+') do
      if #p>4 then return end
      out[#out+1]=tonumber(p,16)
    end
    return out
  end
  if left then
    if right:find('::',1,true) then return nil, 'invalid' end
    local l,r=parse(left),parse(right)
    if not l or not r or #l+#r>=8 then return nil, 'invalid' end
    for _,v in ipairs(l) do words[#words+1]=v end
    for _=1,8-#l-#r do words[#words+1]=0 end
    for _,v in ipairs(r) do words[#words+1]=v end
  else words=parse(s); if not words or #words~=8 then return nil, 'invalid' end end
  -- Only ULA fc00::/7 and GUA 2000::/3: excludes wildcard, loopback,
  -- multicast, link-local, IPv4-mapped (including hexadecimal spelling).
  local parts={}; for i,w in ipairs(words) do parts[i]=string.format('%x',w) end
  local key=table.concat(parts,':')
  if words[1]>=0xfc00 and words[1]<=0xfdff then return 'ula', nil, key end
  if words[1]>=0x2000 and words[1]<=0x3fff then return 'gua', nil, key end
end
-- Exact full-host identity, never prefix membership; presentation stays unchanged.
-- Reuse the eligibility parser to exclude mapped/unsafe/malformed literals.
local function identity(family,address)
  local _,_,key=classify(family,address)
  return key
end
local function bad() return failure('NETWORK_UNAVAILABLE','access_profile.listeners.network','Network inventory unavailable or malformed') end
function M.normalize(snapshot, zones)
  if type(snapshot)~='table' or not array(snapshot.interface) or not array(zones) then return bad() end
  local mapping={}
  for _,z in ipairs(zones) do
    if type(z)~='table' or not text(z.name) then return bad() end
    local nets=z.network or {}
    if type(nets)=='string' then
      local list={}; for n in nets:gmatch('%S+') do list[#list+1]=n end; nets=list
    end
    if not array(nets) then return bad() end
    for _,n in ipairs(nets) do
      if not text(n) then return bad() end
      mapping[n]=mapping[n] or {}; mapping[n][z.name]=true
    end
  end
  local result={status='ok', networks={}}
  for _,iface in ipairs(snapshot.interface) do
    if type(iface)~='table' or not text(iface.interface) or type(iface.up)~='boolean' then return bad() end
    local device=iface.l3_device or iface.device
    if device~=nil and not text(device) then return bad() end
    local n={network=iface.interface, device=device or '', up=iface.up, addresses={}, zones={}}
    for zone in pairs(mapping[n.network] or {}) do n.zones[#n.zones+1]=zone end
    table.sort(n.zones)
    local seen={}
    local function add(a,family)
      if type(a)~='table' or type(a.address)~='string' then return false end
      if a.mask~=nil and (type(a.mask)~='number' or a.mask%1~=0 or a.mask<0 or a.mask>(family=='ipv4' and 32 or 128)) then return false end
      local scope, invalid, host=classify(family,a.address)
      if invalid then return false end
      local key=family..':'..(host or '')
      if scope and not seen[key] then
        seen[key]=true
        n.addresses[#n.addresses+1]={family=family,address=a.address,prefix=a.mask,scope=scope,internal=(scope=='private' or scope=='ula')}
      end
      return true
    end
    for _,spec in ipairs({{'ipv4-address','ipv4'},{'ipv6-address','ipv6'}}) do
      local values=iface[spec[1]] or {}
      if not array(values) then return bad() end
      for _,a in ipairs(values) do if not add(a,spec[2]) then return bad() end end
    end
    local prefixes=iface['ipv6-prefix-assignment'] or {}
    if not array(prefixes) then return bad() end
    for _,p in ipairs(prefixes) do
      if type(p)~='table' then return bad() end
      if p['local-address'] and not add(p['local-address'],'ipv6') then return bad() end
    end
    table.sort(n.addresses,function(a,b) return a.family..':'..identity(a.family,a.address) < b.family..':'..identity(b.family,b.address) end)
    result.networks[#result.networks+1]=n
  end
  local function token(v) v=tostring(v); return #v..':'..v end
  local function signature(n)
    local out={token(n.network),token(n.device),token(n.up)}
    for _,z in ipairs(n.zones) do out[#out+1]='z'..token(z) end
    for _,a in ipairs(n.addresses) do out[#out+1]='a'..token(a.family)..token(identity(a.family,a.address))..token(a.prefix or '')..token(a.scope) end
    return table.concat(out,'|')
  end
  table.sort(result.networks,function(a,b) return signature(a)<signature(b) end)
  local summaries={}
  for _,n in ipairs(result.networks) do summaries[#summaries+1]=token(signature(n)) end
  -- Collision-free canonical summary, not a cryptographic digest.
  result.summary=table.concat(summaries,'|')
  return result
end
function M.collect()
  local ok, value = pcall(function()
    local conn=assert(require('ubus').connect())
    local success,snapshot=pcall(conn.call,conn,'network.interface','dump',{})
    conn:close()
    if not success or type(snapshot)~='table' then error('ubus unavailable') end
    local cursor=assert(require('uci').cursor())
    local zones={}
    local loaded=cursor:load('firewall')
    if not loaded then cursor:unload('firewall'); error('firewall unavailable') end
    local iterated=cursor:foreach('firewall','zone',function(z)
      zones[#zones+1]={name=z.name,network=z.network}
    end)
    cursor:unload('firewall')
    if iterated==false then error('firewall unavailable') end
    return {snapshot=snapshot,zones=zones}
  end)
  if not ok then return bad() end
  return M.normalize(value.snapshot,value.zones)
end
function M.resolve(binding, inventory)
  if type(binding)~='table' or type(inventory)~='table' or inventory.status~='ok' or not array(inventory.networks) then return bad() end
  local matches={}
  for _,n in ipairs(inventory.networks) do if n.network==binding.network then matches[#matches+1]=n end end
  if #matches~=1 or not matches[1].up or matches[1].device=='' then
    return failure('NETWORK_UNAVAILABLE','access_profile.listeners.network','Selected network is unavailable or ambiguous')
  end
  local n=matches[1]
  local found
  local selected=identity(binding.family,binding.address)
  for _,a in ipairs(n.addresses) do
    if selected and a.family==binding.family and identity(a.family,a.address)==selected then found=a end
  end
  if not found then return failure('ADDRESS_UNAVAILABLE','access_profile.listeners.address','Selected address is unavailable on this network') end
  if #n.zones~=1 then return failure('ZONE_AMBIGUOUS','access_profile.listeners.network','Selected network must map to exactly one firewall zone') end
  return {network=n.network,device=n.device,zone=n.zones[1],family=found.family,address=found.address,scope=found.scope,internal=found.internal,inventory_summary=inventory.summary}
end
return M
