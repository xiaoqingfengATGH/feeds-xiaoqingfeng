-- SPDX-License-Identifier: Apache-2.0
-- Product authority. Never feed this model to the legacy fixed-TTL engine.
local M={}
local function fail(code,field,msg,id) error({error=msg,error_code=code,field=field,service_id=id,retryable=false},0) end
local function check(ok,msg) if not ok then error(msg,0) end end
local function object(t,keys)
 check(type(t)=='table' and getmetatable(t)==nil,'object required')
 for k in pairs(t) do check(type(k)=='string' and keys[k],'unknown field') end
end
local function array(t,lo,hi)
 check(type(t)=='table' and getmetatable(t)==nil,'array required')
 local n=0; for k in pairs(t) do check(type(k)=='number' and k%1==0 and k>=1,'array key'); n=n+1 end
 check(n>=lo and n<=hi,'array size')
 for i=1,n do check(rawget(t,i)~=nil,'sparse array') end
 return n
end
local function integer(v,lo,hi) check(type(v)=='number' and v%1==0 and v>=lo and v<=hi,'integer range'); return v end
local function identifier(s)
 check(type(s)=='string' and #s>=1 and #s<=64 and s:match('^[a-zA-Z0-9_][a-zA-Z0-9_.%-]*$'),'invalid identifier'); return s
end
local function hostname(s)
 if type(s)=='string' then s=s:lower() end -- ASCII DNS / IDNA A-labels; no guessed Unicode conversion.
 check(type(s)=='string' and #s<=253 and #s>0 and not s:find('[^a-z0-9.%-]') and not s:find('..',1,true) and s:sub(1,1)~='.' and s:sub(-1)~='.','invalid hostname')
 for label in s:gmatch('[^.]+') do check(#label<=63 and label:match('^[a-z0-9]') and label:match('[a-z0-9]$'),'invalid hostname label') end
 return s
end
-- Address words use 16-bit arithmetic (exact in Lua 5.1 doubles).
local function address(family,s,syntax_only)
 check(type(s)=='string','address required'); s=s:lower()
 if family=='ipv4' then
  local a,b,c,d=s:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$'); check(a~=nil,'IPv4 literal required')
  local oct={a,b,c,d}; for i,v in ipairs(oct) do check(#v<=3 and (v=='0' or v:sub(1,1)~='0'),'noncanonical IPv4'); oct[i]=integer(tonumber(v),0,255) end
  check(syntax_only or oct[1]~=0 and oct[1]<224 and not (oct[1]==169 and oct[2]==254),'unsafe IPv4')
  return {oct[1]*256+oct[2],oct[3]*256+oct[4]}
 end
 check(family=='ipv6' and #s<=39 and #s>=2 and not s:find('[^0-9a-f:]'),'IPv6 literal required')
 local at=s:find('::',1,true); local words={}
 local function parts(t)
  local r={}; if t=='' then return r end
  check(t:sub(1,1)~=':' and t:sub(-1)~=':','IPv6 empty group')
  for w in t:gmatch('[^:]+') do check(#w<=4,'IPv6 group'); r[#r+1]=tonumber(w,16) end
  return r
 end
 if at then
  check(not s:find('::',at+2,true),'IPv6 multiple compression')
  local left,right=parts(s:sub(1,at-1)),parts(s:sub(at+2)); check(#left+#right<8,'IPv6 compression size')
  for _,v in ipairs(left) do words[#words+1]=v end
  for _=1,8-#left-#right do words[#words+1]=0 end
  for _,v in ipairs(right) do words[#words+1]=v end
 else words=parts(s); check(#words==8,'IPv6 group count') end
 -- Only ULA and explicitly scoped global unicast. No unspecified, loopback,
 -- link-local, multicast, compatible/mapped IPv4 or zone-id addresses.
 check(syntax_only or (words[1]>=0x2000 and words[1]<=0x3fff) or (words[1]>=0xfc00 and words[1]<=0xfdff),'unsafe IPv6')
 return words
end
-- HTTP authority only, never an address authorization or an upstream TLS name.
-- Share the exact parser with the renderer, which can receive internal plans.
function M.host_header(s)
 check(type(s)=='string','backend Host string required')
 if s=='' then return nil end
 check(#s<=261 and not s:find('[^a-zA-Z0-9.:%[%]%-]'),'invalid backend Host')
 local host,tail
 if s:sub(1,1)=='[' then
  host,tail=s:match('^%[([^%]]+)%](.*)$');check(host~=nil,'bracketed IPv6 required');address('ipv6',host,true)
 else
  host,tail=s:match('^([^:]+)(.*)$');check(host~=nil,'backend Host required')
  if host:match('^%d+%.%d+%.%d+%.%d+$') then address('ipv4',host,true) else hostname(host) end
 end
 if tail~='' then
  local p=tail:match('^:([1-9]%d*)$');check(p~=nil and #p<=5,'invalid backend Host port');integer(tonumber(p),1,65535)
 end
 return s
end
local function in_range(words,base,prefix)
 if #words~=#base then return false end
 for i=1,#words do
  local bits=math.min(16,prefix); if bits<=0 then return true end
  local divisor=2^(16-bits)
  if math.floor(words[i]/divisor)~=math.floor(base[i]/divisor) then return false end
  prefix=prefix-bits
 end
 return true
end
local function ranges(values)
 local r={}; array(values,1,32)
 for i,s in ipairs(values) do
  check(type(s)=='string','CIDR required'); local host,p=s:match('^([^/]+)/(%d+)$'); check(host~=nil,'CIDR required')
  local family=host:find(':',1,true) and 'ipv6' or 'ipv4'; local bits=integer(tonumber(p),family=='ipv4' and 8 or 16,family=='ipv4' and 32 or 128)
  r[i]={base=address(family,host),prefix=bits}
 end
 return r
end
local function scoped_endpoint(b,allowed)
 if b.addressFamily=='hostname' then return end -- resolve ALL A/AAAA at Start; never resolve on Save.
 local words=address(b.addressFamily,b.host)
 if b.addressFamily=='ipv4' then
  local a=math.floor(words[1]/256);local second=words[1]%256
  check(a==10 or a==127 or (a==172 and second>=16 and second<=31) or (a==192 and second==168),'backend must be household IPv4')
 end
 local found=false;for _,range in ipairs(allowed) do if in_range(words,range.base,range.prefix) then found=true end end
 check(found,'backend outside allowed ranges')
end
local function normalized_address(family,s)
 local words=address(family,s)
 if family=='ipv4' then return table.concat({math.floor(words[1]/256),words[1]%256,math.floor(words[2]/256),words[2]%256},'.') end
 local parts={};for i,w in ipairs(words) do parts[i]=string.format('%x',w) end
 return table.concat(parts,':')
end
local function endpoint(b,backup)
 object(b,backup and {addressFamily=true,host=true,port=true} or {addressFamily=true,host=true,port=true,backup=true,allowed_ranges=true,host_header=true})
 local family=b.addressFamily
 check(family=='ipv4' or family=='ipv6' or family=='hostname','backend family')
 check(type(b.host)=='string' and #b.host<=253 and not b.host:find('[%s/;"\'\\]'),'backend host')
 if family=='hostname' then hostname(b.host) end
 local r={addressFamily=family,host=family=='hostname' and hostname(b.host) or normalized_address(family,b.host),port=integer(b.port,1,65535)}
 if not backup then
  if b.allowed_ranges~=nil then
   array(b.allowed_ranges,1,32); r.allowed_ranges={}; for i,v in ipairs(b.allowed_ranges) do check(type(v)=='string','range required'); r.allowed_ranges[i]=v end
  end
  if b.backup then r.backup=endpoint(b.backup,true) end
  if r.allowed_ranges then
   local allowed=ranges(r.allowed_ranges); scoped_endpoint(r,allowed); if r.backup then scoped_endpoint(r.backup,allowed) end
  else
   -- canonical is also loaded by the read-only RPC CLI, whose default Lua
   -- search path does not include this product directory. Resolve the fixed
   -- sibling dependency independently of the caller's package.path/cwd.
   local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
   local A=dofile(source..'/direct-address.lua')
   for _,target in ipairs({r,r.backup}) do if target.addressFamily~='hostname' then check(A.backend_allowed(target.host),'backend must be household address') end end
  end
 end
 return r
end
local function certificate(ref)
 check(type(ref)=='string','certificate reference required')
 local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
 local provider=dofile(source..'/certificate-reference.lua').parse(ref)
 check(provider~=nil,'invalid certificate reference');return ref
end
local field='config'
local function validate(c)
 field='config';object(c,{schema_version=true,services=true,access_profile=true,publication_policy=true,default_certificate_ref=true});check(c.schema_version==2,'unsupported schema')
 local r={schema_version=2,services={},access_profile={listeners={}}}
 field='default_certificate_ref';if c.default_certificate_ref~=nil then r.default_certificate_ref=certificate(c.default_certificate_ref) end
 field='access_profile';object(c.access_profile,{listeners=true,firewall=true});array(c.access_profile.listeners,1,2)
 local families,ids={},{};local shared
 for i,l in ipairs(c.access_profile.listeners) do
  field='access_profile.listeners['..i..']'
  object(l,{listener_id=true,family=true,network=true,address=true,port=true,bind_mode=true})
  local id=identifier(l.listener_id);check(not ids[id],'duplicate listener identity');ids[id]=true
  check(l.family=='ipv4' or l.family=='ipv6','listener family')
  check(l.bind_mode==nil or l.bind_mode=='address' or l.bind_mode=='auto','listener bind_mode')
  local a,network
  if l.bind_mode=='auto' then
   a=l.family=='ipv4' and '0.0.0.0' or '::'
   check(l.address==a and l.network=='','auto listener requires wildcard address and empty network');network=''
  else a=normalized_address(l.family,l.address);network=identifier(l.network) end
  if families[l.family] then fail('PORT_CONFLICT',field,'one binding per family') end;families[l.family]=true
  check(l.family~='ipv4' or not a:match('^127%.'),'loopback ingress forbidden')
  local p=integer(l.port,1024,65535);check(shared==nil or shared==p,'shared ports must agree');shared=p
  r.access_profile.listeners[i]={listener_id=id,family=l.family,network=network,address=a,port=p}
  if l.bind_mode~=nil then r.access_profile.listeners[i].bind_mode=l.bind_mode end
 end
 -- Optional extension inside schema v2: absence means legacy/manual firewall ownership.
 if c.access_profile.firewall~=nil then
  field='access_profile.firewall';object(c.access_profile.firewall,{ipv4_zones=true,ipv6_zones=true})
  local f={};r.access_profile.firewall=f
  for _,family in ipairs({'ipv4','ipv6'}) do
   local key=family..'_zones';field='access_profile.firewall.'..key
   local zones=c.access_profile.firewall[key];array(zones,families[family] and 1 or 0,families[family] and 64 or 0)
   f[key]={};local seen={}
   for i,z in ipairs(zones) do
    check(type(z)=='string' and #z>=1 and #z<=64 and z:match('^[a-zA-Z0-9_][a-zA-Z0-9_%-]*$'),'invalid firewall zone')
    check(not seen[z],'duplicate firewall zone');seen[z]=true;f[key][i]=z
   end
  end
 end
 field='services';array(c.services,0,16)
 local service_ids,domains,ports={}, {}, {};local ssh,rdp=false,false
 for i,s in ipairs(c.services) do
  field='services['..i..']'
  check(type(s)=='table' and getmetatable(s)==nil,'service object required')
  local keys={service_id=true,name=true,enabled=true,type=true,backend=true,authentication_review=true,dns=true}
  if s.type=='https_proxy' then keys.hostname=true;keys.upstream_scheme=true;keys.certificate_mode=true;keys.certificate_ref=true;keys.upstream_tls=true
  elseif s.type=='http_proxy' then keys.hostname=true;keys.upstream_scheme=true;keys.upstream_tls=true
  elseif s.type=='tls_passthrough' then keys.hostname=true
  elseif s.type=='tcp_forward' then keys.listen_port=true
  else check(s.type=='ssh' or s.type=='rdp','unknown service type') end
  object(s,keys);check(type(s.enabled)=='boolean','service enabled boolean')
  check(type(s.name)=='string' and #s.name>=1 and #s.name<=128 and not s.name:find('[%z\1-\31\127]'),'invalid service name')
  local t={service_id=identifier(s.service_id),name=s.name,enabled=s.enabled,type=s.type,backend=endpoint(s.backend)}
  if s.backend.host_header~=nil then
   check(s.type=='http_proxy' or s.type=='https_proxy','backend Host only supports HTTP reverse proxies')
   t.backend.host_header=M.host_header(s.backend.host_header)
  end
  -- Legacy declarations are round-tripped, not authentication or startup gates.
  if s.authentication_review~=nil then
   object(s.authentication_review,{authentication=true,management=true})
   check(s.authentication_review.authentication=='confirmed' or s.authentication_review.authentication=='unconfirmed','authentication review')
   check(type(s.authentication_review.management)=='boolean','management review')
   t.authentication_review={authentication=s.authentication_review.authentication,management=s.authentication_review.management}
  end
  if s.type=='https_proxy' or s.type=='http_proxy' or s.type=='tls_passthrough' then t.hostname=hostname(s.hostname) end
  field='services['..i..'].dns'
  local dns=s.dns
  if dns==nil then dns={mode='manual'} end
  object(dns,{mode=true,profile_id=true,record_types=true})
  check(dns.mode=='manual' or dns.mode=='ddns_go','请选择域名解析方式')
  t.dns={mode=dns.mode}
  if dns.mode=='ddns_go' then
   check(t.hostname~=nil,'此接入方式不支持自动域名更新')
   check(not t.hostname:match('^%d+%.%d+%.%d+%.%d+$'),'自动域名更新需要有效域名')
   check(type(dns.profile_id)=='string' and #dns.profile_id>=1 and #dns.profile_id<=256 and not dns.profile_id:find('[%z\1-\32\127]'),'请选择域名更新账户')
   array(dns.record_types,1,2);local seen={};t.dns.record_types={}
   for j,v in ipairs(dns.record_types) do check((v=='A' or v=='AAAA') and not seen[v],'请选择不重复的 IPv4 或 IPv6 记录');seen[v]=true;t.dns.record_types[j]=v end
   t.dns.profile_id=dns.profile_id
  else
   -- Ignore stale editor selections when switching back to manual mode.
   check(dns.profile_id==nil or type(dns.profile_id)=='string','域名更新账户无效')
   if dns.record_types~=nil then array(dns.record_types,0,2);for _,v in ipairs(dns.record_types) do check(v=='A' or v=='AAAA','域名记录类型无效') end end
  end
  field='services['..i..']'
  if s.type=='https_proxy' or s.type=='http_proxy' then
   check(s.upstream_scheme=='http' or s.upstream_scheme=='https','upstream scheme');t.upstream_scheme=s.upstream_scheme
   if s.type=='https_proxy' then
    check(s.certificate_mode=='inherit' or s.certificate_mode=='override','certificate mode');t.certificate_mode=s.certificate_mode
    if s.certificate_mode=='inherit' then check(s.certificate_ref==nil,'inherit must not contain resolved certificate')
    elseif s.certificate_ref~=nil then t.certificate_ref=certificate(s.certificate_ref) end
   end
   if s.upstream_scheme=='https' then
    object(s.upstream_tls,{verify=true,server_name=true})
    local verify=s.upstream_tls.verify
    if verify==nil then verify=true end
    check(type(verify)=='boolean','upstream TLS verify boolean required')
    t.upstream_tls={verify=verify}
    if verify or s.upstream_tls.server_name~=nil and s.upstream_tls.server_name~='' then t.upstream_tls.server_name=hostname(s.upstream_tls.server_name) end
   else check(s.upstream_tls==nil,'HTTP has no upstream TLS') end
  elseif s.type=='tcp_forward' then t.listen_port=integer(s.listen_port,1024,65535) end
  check(not service_ids[t.service_id],'duplicate service identity');service_ids[t.service_id]=true
  if t.hostname then
   local domain_key=(t.type=='http_proxy' and 'http:' or 'tls:')..t.hostname
   if domains[domain_key] then fail('DOMAIN_CONFLICT',field..'.hostname','duplicate domain',t.service_id) end
   domains[domain_key]=true
  end
  if t.type=='ssh' then
   if ssh then fail('SSH_CONFLICT',field..'.type','only one SSH per ingress',t.service_id) end;ssh=true
  end
  if t.type=='rdp' then
   if rdp then fail('RDP_CONFLICT',field..'.type','only one RDP per ingress',t.service_id) end;rdp=true
  end
  if t.listen_port then
   if t.listen_port==shared or ports[t.listen_port] then fail('PORT_CONFLICT',field..'.listen_port','TCP port conflicts with shared or independent listener',t.service_id) end
   ports[t.listen_port]=true
  end
  r.services[i]=t
 end
 field='publication_policy';local p=c.publication_policy or {};object(p,{mode=true,temporary_duration=true,boot_restore=true})
 local mode=p.mode or 'continuous';check(mode=='continuous' or mode=='temporary','policy mode');check(p.boot_restore==nil or type(p.boot_restore)=='boolean','boot_restore boolean')
 r.publication_policy={mode=mode,boot_restore=p.boot_restore or false}
 if mode=='temporary' then r.publication_policy.temporary_duration=integer(p.temporary_duration or 1800,60,86400) else check(p.temporary_duration==nil,'continuous has no deadline') end
 return r
end
function M.validate(c)
 local ok,r=pcall(validate,c);if ok then return r end
 local d=type(r)=='table' and r or {error=tostring(r),error_code='INVALID_CONFIG',field=field,retryable=false}
 return nil,d.error,d
end
local function clone(v)
 if type(v)~='table' then return v end
 local r={};for k,x in pairs(v) do r[k]=clone(x) end;return r
end
-- Pure preview. Inventory shape: {networks={{network='lan',device='br-lan'},...}}.
-- No discovery, persistence, backup creation, DNS or runtime side effects here.
function M.migrate_preview(c,inventory,legacy_validate)
 local preview={original_config=clone(c),warnings={},blocking_issues={}}
 local function issue(code,path,message)
  preview.blocking_issues[#preview.blocking_issues+1]={error_code=code,field=path,error=message,retryable=false}
 end
 local source,e=legacy_validate(c)
 if not source then issue('INVALID_CONFIG','config',e);return preview end
 local proposed={schema_version=2,services={},access_profile={listeners={}},publication_policy=clone(source.publication_policy),default_certificate_ref=source.default_certificate_ref}
 preview.proposed_config=proposed
 for i,s in ipairs(source.services) do
  local t=clone(s);t.type='https_proxy';t.upstream_scheme='http'
  if t.certificate_mode=='inherit' then t.certificate_ref=nil end
  proposed.services[i]=t
 end
 for _,method in ipairs(source.access_profile.methods_allowed) do
  if method~='manual_ipv4' and method~='direct_ipv6' then issue('INVALID_CONFIG','access_profile.methods_allowed','legacy access mechanism requires explicit reselection: '..method) end
 end
 if source.access_profile.gateway_ref then issue('INVALID_CONFIG','access_profile.gateway_ref','legacy gateway configuration retained in original_config; explicit reselection required') end
 local inventory_ok=pcall(function()
  check(type(inventory)=='table','inventory required');array(inventory.networks,0,256)
  for _,n in ipairs(inventory.networks) do identifier(n.network);identifier(n.device) end
 end)
 for i,l in ipairs(source.access_profile.listeners) do
  local matches={};local path='access_profile.listeners['..i..']'
  if inventory_ok then
   for _,n in ipairs(inventory.networks) do
    if n.network==l.interface or n.device==l.interface then matches[n.network]=true end
   end
  end
  local network,n=nil,0;for name in pairs(matches) do network=name;n=n+1 end
  if n~=1 then issue('NETWORK_UNAVAILABLE',path..'.interface','legacy interface has no unique inventory network');network=nil end
  -- Every original listener is represented, even a blocked/unresolved candidate.
  proposed.access_profile.listeners[i]={listener_id='legacy_'..i,family=l.family,network=network,address=l.address,port=l.internal_port}
  preview.warnings[#preview.warnings+1]={field=path..'.external_port',message='external_port retained only in original_config; no upstream mapping changed',value=l.external_port}
 end
 local normalized,ve,detail=M.validate(proposed)
 if normalized then preview.proposed_config=normalized
 else issue(detail.error_code,detail.field,ve) end
 return preview
end
return M
