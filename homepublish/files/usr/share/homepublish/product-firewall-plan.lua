-- SPDX-License-Identifier: Apache-2.0
-- Pure INPUT allow-set planner: no discovery, shell, nft, persistence or runtime state.
-- The caller supplies the config being activated, NOT an unsaved draft. Only the
-- lifecycle adapter may reconcile this desired set against its live owned set.
local source=debug.getinfo(1,'S').source:sub(2)
local base=source:match('^(.*)/') or '.'
local C=dofile(base..'/canonical-v2.lua')
local N=dofile(base..'/network-inventory.lua')
local M={}
function M.plan(config,inventory)
 local c,_,detail=C.validate(config)
 if not c then return nil,detail end
 local firewall=c.access_profile.firewall
 -- Legacy records preserve manual firewall ownership; never infer a zone.
 if firewall==nil then return {} end
 local ok,e=N.validate_firewall(firewall,inventory)
 if not ok then return nil,e end
 local ports,shared={},false
 for _,s in ipairs(c.services) do
  if s.enabled then
   if s.type=='tcp_forward' then ports[s.listen_port]=true else shared=true end
  end
 end
 local rules,seen={},{}
 for _,l in ipairs(c.access_profile.listeners) do
  local selected={};for p in pairs(ports) do selected[p]=true end
  if shared then selected[l.port]=true end
  for _,zone in ipairs(firewall[l.family..'_zones']) do
   for port in pairs(selected) do
    local dest_ip=l.bind_mode~='auto' and l.address or nil
    local key=l.family..':'..zone..':'..port..':'..(dest_ip or '')
    if not seen[key] then
     seen[key]=true;rules[#rules+1]={family=l.family,zone=zone,port=port,protocol='tcp',dest_ip=dest_ip}
    end
   end
  end
 end
 table.sort(rules,function(a,b)
  if a.family~=b.family then return a.family<b.family end
  if a.zone~=b.zone then return a.zone<b.zone end
  return a.port<b.port
 end)
 return rules
end
return M
