-- SPDX-License-Identifier: Apache-2.0
-- Read-only adapters for actual OpenWrt acme-acmesh and libc resolver.
-- No issuance, provider credentials, DDNS mutations or proxy configuration.
local M={}
local function hostname(s)return type(s)=='string' and #s<=253 and s:match('^[a-z0-9][a-z0-9.%-]*$') and not s:find('..',1,true) end
function M.acme_source(domain,kind)
 -- HomeVPN identity: explicit domain + rsa/ecc, never infer or cross-type fallback.
 -- Call only after explicit certificate choice; resolver reads keys server-side.
 if not (hostname(domain) or (type(domain)=='string' and domain:sub(1,2)=='*.' and hostname(domain:sub(3)))) or (kind~='rsa' and kind~='ecc') then return nil,'explicit HomeVPN domain/key type required' end
 local f=io.popen(". /usr/share/homevpn/acme-resolve.sh; homevpn_acme_resolve '"..domain.."' '"..kind.."' && printf '%s\\n%s\\n' \"$HV_ACME_CRT\" \"$HV_ACME_KEY\"")
 if not f then return nil,'HomeVPN resolver unavailable' end
 local cert=f:read('*l');local key=f:read('*l');f:close()
 if not cert or not key or cert=='' or key=='' then return nil,'HomeVPN resolver rejected certificate' end
 return {certificate=cert,key=key,domain=domain,key_type=kind}
end
function M.resolve(host)
 if not hostname(host) then return nil,'invalid resolver hostname' end
 local answer=require('nixio').getaddrinfo(host)
 if type(answer)~='table' then return nil,'system resolver failed' end
 local out,seen={},{}
 for _,v in ipairs(answer) do
  if (v.family=='inet' or v.family=='inet6') and not seen[v.address] then out[#out+1]=v.address;seen[v.address]=true end
 end
 if #out==0 or #out>64 then return nil,'resolver answer count' end
 -- getaddrinfo exposes no DNS TTL. This is a bounded refresh policy, not TTL.
 return {addresses=out,ttl=30,observed_at=os.time(),resolver='system-getaddrinfo/poll30-no-dns-ttl'}
end
function M.ddns_status()
 local c=require('uci').cursor();local domains={};local f=io.popen("grep -E '^            - [a-z0-9][a-z0-9.-]+$' /etc/ddns-go/config.yaml 2>/dev/null")
 -- Project only exact domain-list records; never return full YAML/credentials.
 if f then for line in f:lines() do local d=line:match('^%s+%-%s+([a-z0-9][a-z0-9.%-]*)%s*$');if d and hostname(d) then domains[d]=true end end;f:close() end
 local list={};for d in pairs(domains) do list[#list+1]=d end;table.sort(list)
 return {enabled=c:get('ddns-go','config','enabled')=='1',domains=list,address_status='not exposed by supported read-only interface',mutation_supported=false}
end
local function selection(ref)
 if type(ref)~='string' or not ref:match('^acme:[a-zA-Z0-9_][a-zA-Z0-9_.%-]*$') then return nil,'ACME section reference required' end
 local result;local id=ref:sub(6)
 require('uci').cursor():foreach('acme','cert',function(s)
  if s['.name']==id then
   local domain=type(s.domains)=='table' and s.domains[1] or s.domains
   local kind=type(s.key_type)=='string' and (s.key_type:match('^ec%d+$') and 'ecc' or s.key_type:match('^rsa%d+$') and 'rsa')
   if domain and kind then result={domain=domain,key_type=kind} end
  end
 end)
 return result,result and nil or 'ACME section identity unavailable'
end
function M.certificate_source(ref,host)
 local identity,e=selection(ref);if not identity then return nil,e end
 local source,err=M.acme_source(identity.domain,identity.key_type);if not source then return nil,err end
 local C=require('certificate-metadata');local metadata,me=C.read(source.certificate)
 if not metadata then return nil,me end
 if metadata.status~='valid' or not C.match(metadata.sans,host) then return nil,'certificate expired or DNS SAN mismatch' end
 return source
end
function M.certificate_inventory()
 local rows={};local C=require('certificate-metadata')
 require('uci').cursor():foreach('acme','cert',function(s)
  if #rows>=32 then return end
  local ref='acme:'..s['.name'];local identity=selection(ref)
  if identity then
   local source=M.acme_source(identity.domain,identity.key_type)
   local metadata=source and C.read(source.certificate)
   local row={certificate_ref=ref,domain=identity.domain,key_type=identity.key_type,status=metadata and metadata.status or 'unavailable',sans=metadata and metadata.sans or {}}
   if metadata then row.not_before=metadata.not_before;row.not_after=metadata.not_after end
   rows[#rows+1]=row
  end
 end)
 return {certificates=rows,scope='configured ACME sections; public metadata only'}
end
return M
