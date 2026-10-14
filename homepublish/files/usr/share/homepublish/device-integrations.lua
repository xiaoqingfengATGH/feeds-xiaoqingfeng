-- SPDX-License-Identifier: Apache-2.0
-- Read-only adapters for actual OpenWrt acme-acmesh and libc resolver.
-- No issuance, provider credentials, DDNS mutations or proxy configuration.
local M={}
local function hostname(s)return type(s)=='string' and #s<=253 and s:match('^[a-z0-9][a-z0-9.%-]*$') and not s:find('..',1,true) end
function M.acme_source(ref,host,get)
 local section=type(ref)=='string' and ref:match('^acme:([a-zA-Z0-9_][a-zA-Z0-9_%-]*)$')
 if not section or not hostname(host) then return nil,'invalid ACME reference' end
 get=get or function(s,k)return require('uci').cursor():get('acme',s,k)end
 if get(section,'enabled')=='0' then return nil,'ACME section disabled' end
 local domains=get(section,'domains');if type(domains)=='string' then local a={};for d in domains:gmatch('%S+') do a[#a+1]=d end;domains=a end
 if type(domains)~='table' or not hostname(domains[1]) then return nil,'ACME domains unavailable' end
 local match=false;for _,d in ipairs(domains) do if d==host then match=true end end
 if not match then return nil,'hostname not in ACME section' end
 local kind=get(section,'key_type');local old=get(section,'keylength')
 if not kind then kind=old and (old:match('^ec%-') and old:gsub('ec%-','ec') or 'rsa'..old) or 'ec256' end
 if not kind:match('^ec%d+$') and not kind:match('^rsa%d+$') then return nil,'unsupported ACME key type' end
 local dir='/etc/acme'
 if not get or type(get)~='function' then return nil,'ACME reader' end
 -- Current device uses default state_dir; refuse rather than guess custom roots.
 local global=require('uci').cursor();local custom
 global:foreach('acme','acme',function(s)custom=custom or s.state_dir end)
 if custom and custom~='/etc/acme' then return nil,'custom ACME state_dir unsupported' end
 dir=dir..'/'..domains[1]..(kind:match('^ec') and '_ecc' or '')
 return {certificate=dir..'/fullchain.cer',key=dir..'/'..domains[1]..'.key',reference=ref,hostname=host}
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
