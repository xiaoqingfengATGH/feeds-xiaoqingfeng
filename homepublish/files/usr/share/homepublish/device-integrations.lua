-- SPDX-License-Identifier: Apache-2.0
-- Read-only adapters for the local acme.sh certificate store and libc resolver.
-- Certificate inventory scans /etc/acme domain directories (HomeACME semantics:
-- one directory = one certificate; domain RSA and domain_ecc are two certificates).
-- No issuance, provider credentials, DDNS mutations or proxy configuration.
-- The certificate/key resolution logic is HomePublish's own copy of the
-- acme-resolve directory convention (explicit type, pubkey match, no fallback);
-- it does not source other applications' scripts at runtime.
local M={}
local ACME_STATE='/etc/acme'
local function hostname(s)return type(s)=='string' and #s<=253 and s:match('^[a-z0-9][a-z0-9.%-]*$') and not s:find('..',1,true) end
local function dir_domain(s)
 -- A certificate directory name: fqdn, fqdn_ecc or fqdn_rsa (wildcards keep their '*').
 if type(s)~='string' or #s>258 then return nil end
 local base=s:gsub('_ecc$',''):gsub('_rsa$','')
 if base=='' or not base:match('^[a-z0-9*][a-z0-9.*%-]*$') or base:find('..',1,true) then return nil end
 return base
end
-- nixio.fs is always present on OpenWrt (unlike the busybox 'stat' applet).
local FS=require('nixio').fs
local function fs_stat(path)
 local ok,st=pcall(FS.stat,path)
 if not ok or not st then return nil end
 return {kind=st.type,size=tonumber(st.size) or 0}
end
local function is_dir(path)local st=fs_stat(path);return st and st.kind=='dir' end
local function is_file(path)local st=fs_stat(path);return st and st.kind=='reg' and st.size>0 and st.size<=65536 end
local function kind_of(dir)
 -- Directory suffix decides the intended key type; the certificate itself must agree.
 if dir:match('_ecc$') then return 'ecc' end
 if dir:match('_rsa$') then return 'rsa' end
 return 'rsa'
end
-- HomePublish's own resolver copy of the acme-resolve convention:
-- explicit type, certificate/key public keys must match, no cross-type fallback.
local function popen_line(cmd)
 local f=io.popen(cmd)
 if not f then return nil end
 local out=f:read('*a');f:close()
 if not out or #out==0 then return nil end
 return out
end
function M.acme_source(domain,kind)
 if not (hostname(domain) or (type(domain)=='string' and domain:sub(1,2)=='*.' and hostname(domain:sub(3)))) or (kind~='rsa' and kind~='ecc') then return nil,'explicit domain/key type required' end
 local base=os.getenv('HP_ACME_STATE_DIR') or '/etc/acme'
 local link=os.getenv('HP_ACME_LINK_DIR') or '/etc/ssl/acme'
 local cands={}
 if kind=='rsa' then
  cands[#cands+1]=base..'/'..domain
  cands[#cands+1]=base..'/'..domain..'_rsa'
 else
  cands[#cands+1]=base..'/'..domain..'_ecc'
 end
 for _,dir in ipairs(cands) do
  local cert=dir..'/fullchain.cer'
  local key=dir..'/'..domain..'.key'
  if is_file(cert) and is_file(key) then
   local cert_pub=popen_line("openssl x509 -in '"..cert.."' -pubkey -noout 2>/dev/null")
   local key_pub=popen_line("openssl pkey -in '"..key.."' -passin pass: -pubout 2>/dev/null")
   if cert_pub and key_pub and cert_pub==key_pub then
    local alg=kind=='ecc' and 'ec' or 'rsa'
    local ok=popen_line("openssl "..alg.." -in '"..key.."' -passin pass: -noout >/dev/null 2>&1 && echo OK")
    if ok and ok:find('OK',1,true) then return {certificate=cert,key=key,domain=domain,key_type=kind} end
   end
  end
 end
 -- Link-directory convention (/etc/ssl/acme): fullchain.crt + domain key.
 if is_dir(link) then
  local cert=link..'/'..domain..'.fullchain.crt'
  local key=link..'/'..domain..'.key'
  if is_file(cert) and is_file(key) then
   local cert_pub=popen_line("openssl x509 -in '"..cert.."' -pubkey -noout 2>/dev/null")
   local key_pub=popen_line("openssl pkey -in '"..key.."' -passin pass: -pubout 2>/dev/null")
   if cert_pub and key_pub and cert_pub==key_pub then
    local alg=kind=='ecc' and 'ec' or 'rsa'
    local ok=popen_line("openssl "..alg.." -in '"..key.."' -passin pass: -noout >/dev/null 2>&1 && echo OK")
    if ok and ok:find('OK',1,true) then return {certificate=cert,key=key,domain=domain,key_type=kind} end
   end
  end
 end
 return nil,'no valid matching '..kind..' certificate/key for '..domain
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
-- Resolve an acme: certificate reference to {domain,key_type,dir}.
-- Primary identity: the reference names the certificate directory (domain or domain_ecc).
-- Legacy references named a uci 'acme' cert section; map them to their directory.
local function reference(ref)
 if type(ref)~='string' then return nil,'certificate reference required' end
 local id=ref:match('^acme:([a-zA-Z0-9*][a-zA-Z0-9_.%-]*)$')
 if not id then return nil,'ACME certificate reference required' end
 if dir_domain(id) then
  local kind=kind_of(id);local domain=dir_domain(id)
  if M.acme_source(domain,kind) then return {domain=domain,key_type=kind,dir=id} end
 end
 -- Legacy: uci section name -> domains[1] + key_type (unset key_type means ecc, matching acme.sh).
 local section
 require('uci').cursor():foreach('acme','cert',function(s)
  if s['.name']==id then section=s end
 end)
 if not section then return nil,'certificate not found' end
 local domain=type(section.domains)=='table' and section.domains[1] or section.domains
 if type(domain)~='string' then return nil,'certificate identity unavailable' end
 local kt=type(section.key_type)=='string' and section.key_type or 'ec256'
 local kind=kt:match('^ec%d+$') and 'ecc' or kt:match('^rsa%d+$') and 'rsa' or nil
 if not kind then return nil,'certificate identity unavailable' end
 if not M.acme_source(domain,kind) then return nil,'certificate files unavailable' end
 return {domain=domain,key_type=kind,dir=kind=='ecc' and (domain..'_ecc') or domain}
end
-- Certificates actually issued on this device: one row per /etc/acme domain directory.
function M.certificate_inventory()
 local C=require('certificate-metadata')
 local rows={}
 local names={}
 local ok,iter=pcall(FS.dir,ACME_STATE)
 if ok then for name in iter do names[#names+1]=name end end
 table.sort(names)
 for _,name in ipairs(names) do
  local domain=dir_domain(name)
  if domain and is_dir(ACME_STATE..'/'..name) then
   local kind=kind_of(name)
   -- 只列证书与私钥都可读、公钥配对成功的目录（ca/ 等内部目录不进列表）
   local source=M.acme_source(domain,kind)
   if source then
    local metadata=C.read(source.certificate)
    local row={certificate_ref='acme:'..name,domain=domain,key_type=kind,status=metadata and metadata.status or 'unavailable',sans=metadata and metadata.sans or {}}
    if metadata then row.not_before=metadata.not_before;row.not_after=metadata.not_after end
    rows[#rows+1]=row
   end
  end
 end
 return {certificates=rows,scope='local acme.sh certificate directories'}
end
function M.certificate_source(ref,host)
 local identity,e=reference(ref);if not identity then return nil,e end
 local source,err=M.acme_source(identity.domain,identity.key_type);if not source then return nil,err end
 local C=require('certificate-metadata');local metadata,me=C.read(source.certificate)
 if not metadata then return nil,me end
 if metadata.status~='within_validity' or not C.match(metadata.sans,host) then return nil,'certificate expired or DNS SAN mismatch' end
 return source
end
return M
