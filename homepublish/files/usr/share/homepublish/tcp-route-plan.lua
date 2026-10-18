-- SPDX-License-Identifier: Apache-2.0
-- Pure task16 route lowering. No I/O, process launch, or activation authority.
-- v2 remains activation-gated by product-provider until the real adapter exists.
local C=require('canonical-v2');local M={}
function M.compile(config)
 local c,e=C.validate(config);if not c then return nil,e end
 local plan={services={},http_services={},access_profile={listeners={}},source_schema=2}
 for i,l in ipairs(c.access_profile.listeners) do
  plan.access_profile.listeners[i]={listener_id=l.listener_id,bind_mode=l.bind_mode,family=l.family,address=l.address,network=l.network,interface=l.network,zone='unresolved',protocol='tcp',internal_port=l.port}
 end
 for _,s in ipairs(c.services) do
  if s.enabled then
  if s.type=='tcp_forward' then
   plan.tcp=plan.tcp or {};plan.tcp[#plan.tcp+1]={service_id=s.service_id,listen_port=s.listen_port,backend=s.backend}
  elseif s.type=='ssh' then
   plan.ssh={service_id=s.service_id,backend=s.backend}
  elseif s.type=='http_proxy' then
   plan.http_services[#plan.http_services+1]={service_id=s.service_id,hostname=s.hostname,backend=s.backend,upstream_scheme=s.upstream_scheme,upstream_tls=s.upstream_tls}
  elseif s.type=='tls_passthrough' then
   plan.passthrough=plan.passthrough or {};plan.passthrough[#plan.passthrough+1]={service_id=s.service_id,hostname=s.hostname,backend=s.backend}
  else
   if s.type~='https_proxy' then return nil,'P3 route type not implemented: '..s.type end
   local ref=s.certificate_mode=='inherit' and c.default_certificate_ref or s.certificate_ref
   if not ref then return nil,'HTTPS certificate binding missing' end
   plan.services[#plan.services+1]={service_id=s.service_id,hostname=s.hostname,certificate_ref=ref,backend=s.backend,upstream_scheme=s.upstream_scheme,upstream_tls=s.upstream_tls}
  end
  end
 end
 if #plan.services==0 and #plan.http_services==0 and not plan.tcp and not plan.ssh and not plan.passthrough then return nil,'no enabled routes' end
 return plan
end
return M
