-- Read-only saved-revision preflight. Never invokes a runtime or creates exposure.
local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
local network=dofile(source..'/network-inventory.lua')
local M={}
function M.check(config,revision)
 local out={revision=revision,ready=false,blockers={},warnings={},endpoints={},services={},source_address_policy={http_proxy='trusted_internal_proxy_only',https_proxy='trusted_internal_proxy_only',tls_passthrough='proxy_address',ssh='proxy_address',rdp='proxy_address',tcp_forward='proxy_address'}}
 local inv,err=network.collect()
 if inv then out.inventory_summary=inv.summary else out.blockers[#out.blockers+1]=err end
 local enabled,shared=0,false
 for _,s in ipairs(config.services) do
  if s.enabled~=false then
   enabled=enabled+1;out.services[#out.services+1]={service_id=s.service_id,type=s.type or 'https_proxy'}
   if s.type~='tcp_forward' then shared=true end
  end
 end
 for _,l in ipairs(config.access_profile.listeners) do
  local binding=l
  if config.schema_version==1 then
   local matches={}
   if inv then for _,n in ipairs(inv.networks) do if n.network==l.interface or n.device==l.interface then matches[#matches+1]=n end end end
   binding={network=#matches==1 and matches[1].network or '',family=l.family,address=l.address,port=l.internal_port}
  end
  if inv then
   local resolved,e=network.resolve(binding,inv)
   if not resolved then out.blockers[#out.blockers+1]=e
   else
    if resolved.internal then out.warnings[#out.warnings+1]={field='access_profile.listeners.address',warning='Private or ULA address; public reachability unverified'} end
    local function endpoint(port,id)
     out.endpoints[#out.endpoints+1]={listener_id=l.listener_id,service_id=id,network=resolved.network,device=resolved.device,zone=resolved.zone,family=resolved.family,address=resolved.address,port=port,ipv6only=resolved.family=='ipv6'}
    end
    if shared then endpoint(binding.port) end
    for _,s in ipairs(config.services) do if s.enabled~=false and s.type=='tcp_forward' then endpoint(s.listen_port,s.service_id) end end
   end
  end
 end
 if enabled==0 then out.blockers[#out.blockers+1]={error_code='NO_ENABLED_SERVICES',field='services',error='No enabled services',retryable=false} end
 -- Network resolution is implemented; certificates/backends/port ownership and
 -- the v2 P3 execution chain are not yet verified by this read-only adapter.
 out.blockers[#out.blockers+1]={error_code='DEPENDENCY_UNAVAILABLE',field='schema_version',error=config.schema_version==2 and 'V2 runtime preflight unavailable until P3' or 'Full runtime dependency preflight unavailable',retryable=false}
 return out
end
return M
