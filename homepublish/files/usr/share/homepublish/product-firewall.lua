-- SPDX-License-Identifier: Apache-2.0
-- Own only tagged INPUT rules and expiring TCP-port sets in inet fw4.
-- No persisted allow-list is consumed by fw4. A live controller reconciles
-- after reload; kernel timeouts close allowances even after SIGKILL.
local M={};local OWNER='homepublish:input:v1';local MAX_LEASE=10
local function zone(s)return type(s)=='string' and #s<=64 and s:match('^[a-zA-Z0-9_][a-zA-Z0-9_%-]*$') end
local function integer(n,max)return type(n)=='number' and n==math.floor(n) and n>=1 and n<=max end
local A=require('direct-address')
local function setname(r)
 local suffix=r.dest_ip and ('_a'..r.dest_ip:gsub('.',function(c)return string.format('%02x',c:byte())end)) or ''
 return 'homepublish_in'..(r.family=='ipv4' and '4_' or '6_')..r.zone..suffix
end
local function ownedset(s)return type(s)=='string' and s:match('^homepublish_in[46]_[a-zA-Z0-9_][a-zA-Z0-9_%-]*$') end
local function validate(rules)
 if type(rules)~='table' or #rules>512 then return nil,'invalid firewall rules' end
 local count=0;for k in pairs(rules) do count=count+1;if not integer(k,#rules) then return nil,'invalid firewall rule list' end end
 if count~=#rules then return nil,'invalid firewall rule list' end
 local groups={}
 for _,r in ipairs(rules) do
  if type(r)~='table' or (r.family~='ipv4' and r.family~='ipv6') or not zone(r.zone) or r.protocol~='tcp' or not integer(r.port,65535) then return nil,'invalid firewall tuple' end
  for k in pairs(r) do if k~='family' and k~='zone' and k~='protocol' and k~='port' and k~='dest_ip' then return nil,'invalid firewall tuple field' end end
  if r.dest_ip~=nil then
   local ok,_,family=pcall(A.parse,r.dest_ip)
   if not ok or family~=r.family then return nil,'invalid firewall destination' end
  end
  local name=setname(r)
  if groups[name] and (groups[name].zone~=r.zone or groups[name].dest_ip~=r.dest_ip) then return nil,'firewall group collision' end
  groups[name]=groups[name] or {zone=r.zone,family=r.family,dest_ip=r.dest_ip,ports={}};groups[name].ports[r.port]=true
 end
 return groups
end
local function sorted(t)local keys={};for k in pairs(t)do keys[#keys+1]=k end;table.sort(keys);return keys end
-- fw4's final zone action is an unconditional jump to *_from_ZONE. Only
-- insert immediately before that last non-owned rule: all user filters stay first.
local function terminal(snapshot,z)
 local last;local targets={}
 for _,entry in ipairs(snapshot.nftables) do
  local c,r=entry.chain,entry.rule
  if c and c.family=='inet' and c.table=='fw4' then targets[c.name]=true end
  if r and r.family=='inet' and r.table=='fw4' and r.chain=='input_'..z and r.comment~=OWNER then last=r end
 end
 local expr=last and last.expr;local jump=type(expr)=='table' and #expr==1 and expr[1].jump
 local target=type(jump)=='table' and jump.target
 if not target or not targets[target] or not integer(last.handle,9007199254740990) then return nil end
 for _,action in ipairs({'accept','drop','reject'}) do if target==action..'_from_'..z then return last.handle end end
end
local function same(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not same(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local function expression(name,g)
 local expr={{match={op='==',left={meta={key='nfproto'}},right=g.family}}}
 if g.dest_ip then expr[#expr+1]={match={op='==',left={payload={protocol=g.family=='ipv4' and 'ip' or 'ip6',field='daddr'}},right=g.dest_ip}} end
 expr[#expr+1]={match={op='==',left={payload={protocol='tcp',field='dport'}},right='@'..name}}
 expr[#expr+1]={accept={}};return expr
end
local function matches(name,g,r)
 local expected=expression(name,g)
 if g.dest_ip then
  -- nft drops redundant nfproto when an exact ip/ip6 destination already
  -- constrains the family. Accept only these two exact expression shapes.
  local index=type(r.expr)=='table' and #r.expr==3 and 1 or 2
  local m=type(r.expr)=='table' and type(r.expr[index])=='table' and r.expr[index].match
  local ok,words,family=pcall(A.parse,type(m)=='table' and m.right or nil)
  if not ok or family~=g.family or not same(words,A.parse(g.dest_ip)) then return false end
  expected[2].match.right=m.right -- nft compresses IPv6; compare address words above.
  if index==1 then table.remove(expected,1) end
 end
 return same(r.expr,expected)
end
-- Verify exact owned set/port contents and finite leases under the fw4 lock.
-- nft 1.1.6 src/json.c divides kernel milliseconds by 1000 for JSON timeout
-- and expires. Do not accept millisecond-shaped fixtures as seconds here.
function M.verify(rules,snapshot,lease)
 local groups=validate(rules)
 if not groups or not integer(lease,MAX_LEASE) or type(snapshot)~='table' or type(snapshot.nftables)~='table' then return false end
 local seen,chains,matched={},{},{}
 local anchors,started,ended={},{},{}
 for _,g in pairs(groups) do anchors[g.zone]=terminal(snapshot,g.zone);if not anchors[g.zone] then return false end end
 for _,entry in ipairs(snapshot.nftables) do
  local s,r=entry.set,entry.rule
  if s and s.family=='inet' and s.table=='fw4' and ownedset(s.name) then
   local g=groups[s.name];if not g or seen[s.name] or s.comment~=OWNER then return false end
   if s.type~='inet_service' or not same(s.flags,{'timeout'}) or not integer(s.timeout,lease) or type(s.elem)~='table' then return false end
   local ports={}
   for _,element in ipairs(s.elem) do
    local e=type(element)=='table' and element.elem
    -- nft omits element timeout when equal to the finite set default. A
    -- wrapped element with positive bounded expires still proves live expiry;
    -- bare values and absent expires remain rejected.
    if type(e)~='table' then return false end
    local timeout=e.timeout==nil and s.timeout or e.timeout
    if not integer(timeout,lease) or not integer(e.expires,timeout) then return false end
    local value=e.val
    if not integer(value,65535) or not g.ports[value] or ports[value] then return false end;ports[value]=true
   end
   for port in pairs(g.ports) do if not ports[port] then return false end end
   seen[s.name]=true
  end
  if r and r.family=='inet' and r.table=='fw4' then
   if r.comment==OWNER then
    if ended[r.chain] then return false end
    local found
    for name,g in pairs(groups) do
     if r.chain=='input_'..g.zone and not matched[name] and matches(name,g,r) then found=name;break end
    end
    if not found then return false end
    matched[found]=true;started[r.chain]=true;chains[r.chain]=(chains[r.chain] or 0)+1
   else
    local z=r.chain:match('^input_(.+)$')
    if started[r.chain] and r.handle~=anchors[z] then return false end
    if z and anchors[z] and r.handle==anchors[z] then ended[r.chain]=true end
   end
  end
 end
 local expected={}
 for name,g in pairs(groups) do if not seen[name] then return false end;local chain='input_'..g.zone;expected[chain]=(expected[chain] or 0)+1 end
 for chain,count in pairs(expected) do if chains[chain]~=count then return false end end
 for chain in pairs(chains) do if not expected[chain] then return false end end
 return true
end
function M.new(deps)
 deps=deps or {};local state={state='closed',rule_count=0,lease_seconds=MAX_LEASE};local F={}
 function F.status()return {state=state.state,error=state.error,rule_count=state.rule_count,lease_seconds=state.lease_seconds} end
 function F.reconcile(rules,lease)
  lease=lease or MAX_LEASE
  local groups,err=validate(rules)
  if not groups or not integer(lease,MAX_LEASE) then state.state='update_failed';state.error=err or 'invalid firewall lease';return false,state.error end
  local ok
  if not deps.snapshot then
   ok,err=require('product-firewall-system').reconcile(rules,lease)
  else
   local snapshot=deps.snapshot();local batch={};local present=false
   if type(snapshot)~='table' or type(snapshot.nftables)~='table' then err='firewall status unavailable'
   else
    local sets={};local table_exists=false
    for _,entry in ipairs(snapshot.nftables) do
     if entry.table and entry.table.family=='inet' and entry.table.name=='fw4' then table_exists=true end
     local r=entry.rule;local s=entry.set
     if s and s.family=='inet' and s.table=='fw4' and s.name=='homepublish_input_guard' then present=true end
     if r and r.family=='inet' and r.table=='fw4' and r.comment==OWNER then
      local z=type(r.chain)=='string' and r.chain:match('^input_(.+)$')
      if not zone(z) or not integer(r.handle,9007199254740990) then err='firewall ownership mismatch';break end
      batch[#batch+1]='delete rule inet fw4 '..r.chain..' handle '..string.format('%.0f',r.handle)
     end
     if s and s.family=='inet' and s.table=='fw4' and ownedset(s.name) then
      if s.comment~=OWNER then err='firewall namespace collision';break end
      sets[s.name]=true
     end
    end
    if not err and next(groups) and not present then
     if deps.bootstrap==true and table_exists then
      batch[#batch+1]='add set inet fw4 homepublish_input_guard { type inet_service; comment "'..OWNER..'"; }'
     else err='firewall fw4 include unavailable' end
    end
    local anchors={}
    if not err then for _,g in pairs(groups) do
     anchors[g.zone]=terminal(snapshot,g.zone)
     if not anchors[g.zone] then err='firewall safe rule ordering unavailable';break end
    end end
    if not err then
     for _,name in ipairs(sorted(sets))do batch[#batch+1]='delete set inet fw4 '..name end
     for _,name in ipairs(sorted(groups)) do
      local g=groups[name];local elements={}
      for _,port in ipairs(sorted(g.ports)) do elements[#elements+1]=port..' timeout '..lease..'s' end
      batch[#batch+1]='add set inet fw4 '..name..' { type inet_service; flags timeout; timeout '..lease..'s; comment "'..OWNER..'"; elements = { '..table.concat(elements,', ')..' }; }'
      batch[#batch+1]='insert rule inet fw4 input_'..g.zone..' position '..string.format('%.0f',anchors[g.zone])..' meta nfproto '..g.family..(g.dest_ip and (' '..(g.family=='ipv4' and 'ip' or 'ip6')..' daddr '..g.dest_ip) or '')..' tcp dport @'..name..' accept comment "'..OWNER..'"'
     end
     ok=#batch==0 or deps.apply(table.concat(batch,'\n')..'\n')==true
     if not ok then err='firewall atomic update failed' end
    end
   end
  end
  if not ok then state.state='update_failed';state.error=err or 'firewall update failed';return false,state.error end
  state={state=#rules>0 and 'open' or 'closed',rule_count=#rules,lease_seconds=lease};return true
 end
 function F.clear()local ok,err=F.reconcile({});if not ok then state.state='cleanup_failed' end;return ok,err end
 return F
end
return M
