-- SPDX-License-Identifier: Apache-2.0
-- Read-only adapters for actual OpenWrt acme-acmesh and libc resolver.
-- No issuance, provider credentials, DDNS mutations or proxy configuration.
local M={}
local function hostname(s)return type(s)=='string' and #s<=253 and s:match('^[a-z0-9][a-z0-9.%-]*$') and not s:find('..',1,true) end
function M.acme_source(domain,kind)
 -- HomeVPN identity: explicit domain + rsa/ecc, never infer or cross-type fallback.
 -- Call only after explicit certificate choice; resolver reads keys server-side.
 if not hostname(domain) or (kind~='rsa' and kind~='ecc') then return nil,'explicit HomeVPN domain/key type required' end
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
return M
