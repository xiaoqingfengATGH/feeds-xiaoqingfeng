-- SPDX-License-Identifier: Apache-2.0
-- Product authority. Never feed this model to the legacy fixed-TTL engine.
local M={}
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
local function address(family,s)
 check(type(s)=='string','address required')
 if family=='ipv4' then
  local a,b,c,d=s:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$'); check(a~=nil,'IPv4 literal required')
  local oct={a,b,c,d}; for i,v in ipairs(oct) do check(#v<=3 and (v=='0' or v:sub(1,1)~='0'),'noncanonical IPv4'); oct[i]=integer(tonumber(v),0,255) end
  check(oct[1]~=0 and oct[1]<224 and not (oct[1]==169 and oct[2]==254),'unsafe IPv4')
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
 check((words[1]>=0x2000 and words[1]<=0x3fff) or (words[1]>=0xfc00 and words[1]<=0xfdff),'unsafe IPv6')
 return words
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
local function endpoint(b,backup)
 object(b,backup and {addressFamily=true,host=true,port=true} or {addressFamily=true,host=true,port=true,backup=true,allowed_ranges=true})
 local family=b.addressFamily or 'ipv4'
 check(family=='ipv4' or family=='ipv6' or family=='hostname','backend family')
 check(type(b.host)=='string' and #b.host<=253 and not b.host:find('[%s/;"\'\\]'),'backend host')
 if family=='hostname' then hostname(b.host) end
 local r={addressFamily=family,host=b.host,port=integer(b.port,1,65535)}
 if not backup then
  array(b.allowed_ranges,1,32); r.allowed_ranges={}; for i,v in ipairs(b.allowed_ranges) do check(type(v)=='string','range required'); r.allowed_ranges[i]=v end
  if b.backup then r.backup=endpoint(b.backup,true) end
  local allowed=ranges(r.allowed_ranges); scoped_endpoint(r,allowed); if r.backup then scoped_endpoint(r.backup,allowed) end
 end
 return r
end
local function validate(c)
 object(c,{schema_version=true,services=true,access_profile=true,publication_policy=true,default_certificate_ref=true})
 check(c.schema_version==1,'unsupported schema')
 array(c.services,1,16)
 local r={schema_version=1,services={}}; local ids,hosts={},{}
 local function certificate(ref)
  check(type(ref)=='string','certificate reference required')
  local provider,id=ref:match('^(%a+):([a-zA-Z0-9_.%-]+)$')
  check(provider=='acme' or provider=='import','certificate reference provider');identifier(id)
  return ref
 end
 if c.default_certificate_ref~=nil then r.default_certificate_ref=certificate(c.default_certificate_ref) end
 for i,s in ipairs(c.services) do
  object(s,{service_id=true,name=true,hostname=true,backend=true,certificate_ref=true,certificate_mode=true,enabled=true,authentication_review=true})
  local id=identifier(s.service_id); local host=hostname(s.hostname)
  check(not ids[id] and not hosts[host],'duplicate service or hostname'); ids[id]=true; hosts[host]=true
  check(type(s.name)=='string' and #s.name>=1 and #s.name<=128 and not s.name:find('[%z\1-\31\127]'),'invalid service name')
  local mode=s.certificate_mode or (s.certificate_ref and 'override' or 'inherit')
  check(mode=='inherit' or mode=='override','certificate binding mode')
  check(s.enabled==nil or type(s.enabled)=='boolean','service enabled boolean')
  local binding=certificate(mode=='inherit' and r.default_certificate_ref or s.certificate_ref)
  object(s.authentication_review,{authentication=true,management=true})
  check(s.authentication_review.authentication=='confirmed' or s.authentication_review.authentication=='unconfirmed','authentication review')
  check(type(s.authentication_review.management)=='boolean','management review')
  r.services[i]={service_id=id,name=s.name,hostname=host,backend=endpoint(s.backend),certificate_ref=binding,certificate_mode=mode,enabled=s.enabled~=false,authentication_review={authentication=s.authentication_review.authentication,management=s.authentication_review.management}}
 end
 local a=c.access_profile
 object(a,{methods_allowed=true,listeners=true,gateway_ref=true})
 array(a.methods_allowed,1,4); array(a.listeners,1,8)
 r.access_profile={methods_allowed={},listeners={}}
 local methods={}
 for i,m in ipairs(a.methods_allowed) do
  check(m=='manual_ipv4' or m=='upnp_ipv4' or m=='direct_ipv6' or m=='stun_experimental','unknown access method')
  check(not methods[m],'duplicate method');methods[m]=true; r.access_profile.methods_allowed[i]=m
 end
 if a.gateway_ref~=nil then r.access_profile.gateway_ref=identifier(a.gateway_ref) end
 check(not methods.upnp_ipv4 or a.gateway_ref~=nil,'gateway reference required')
 local tuples={};local families={}
 for i,l in ipairs(a.listeners) do
  object(l,{family=true,address=true,interface=true,zone=true,protocol=true,internal_port=true,external_port=true})
  check(l.family=='ipv4' or l.family=='ipv6','listener family'); check(l.protocol=='tcp','TCP only')
  check(type(l.address)=='string','explicit listener address')
  local words=address(l.family,l.address); local tuple=l.family..':'..table.concat(words,':')..':'..tostring(l.internal_port)
  check(not tuples[tuple],'duplicate listener');tuples[tuple]=true;families[l.family]=true
  if l.family=='ipv4' then check(math.floor(words[1]/256)~=127,'loopback ingress forbidden')
  else check(l.external_port==l.internal_port,'IPv6 has no DNAT') end
  r.access_profile.listeners[i]={family=l.family,address=l.address,interface=identifier(l.interface),zone=identifier(l.zone),protocol='tcp',internal_port=integer(l.internal_port,1024,65535),external_port=integer(l.external_port,1,65535)}
 end
 check(not families.ipv4 or methods.manual_ipv4 or methods.upnp_ipv4 or methods.stun_experimental,'IPv4 method required')
 check(not families.ipv6 or methods.direct_ipv6,'IPv6 method required')
 check(not methods.direct_ipv6 or families.ipv6,'IPv6 listener required')
 check(not (methods.manual_ipv4 or methods.upnp_ipv4 or methods.stun_experimental) or families.ipv4,'IPv4 listener required')
 local p=c.publication_policy; if p==nil then p={} end
 object(p,{mode=true,temporary_duration=true,boot_restore=true})
 local mode=p.mode or 'continuous'; check(mode=='continuous' or mode=='temporary','policy mode')
 check(p.boot_restore==nil or type(p.boot_restore)=='boolean','boot_restore boolean')
 local policy={mode=mode,boot_restore=p.boot_restore or false}
 if mode=='temporary' then policy.temporary_duration=integer(p.temporary_duration or 1800,60,86400)
 else check(p.temporary_duration==nil,'continuous has no user deadline') end
 r.publication_policy=policy
 return r
end
function M.validate(c)
 local ok,result=pcall(validate,c); if ok then return result end
 return nil,tostring(result)
end
function M.runtime_plan(c)
 local plan,e=M.validate(c);if not plan then return nil,e end
 local services={};for _,s in ipairs(plan.services) do if s.enabled~=false then services[#services+1]=s end end
 if #services==0 then return nil,'no enabled services' end
 plan.services=services;return plan
end
return M
