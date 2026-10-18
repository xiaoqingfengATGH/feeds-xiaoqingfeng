-- SPDX-License-Identifier: Apache-2.0
-- Private, bounded HTTP/1.0 Unix bridge. No shell, paths or credentials from RPC.
local n=require('nixio')
local source=debug.getinfo(1,'S').source:sub(2):match('^(.*)/')
local J=dofile(source..'/product-json.lua');local M={}
local path='/var/run/ddns-go/local-api.sock'
local function now()
 local f=assert(io.open('/proc/uptime','r'));local v=f:read('*l');f:close();return assert(tonumber(v:match('^[%d.]+')))
end
local function request(method,route,body,deadline)
 local s
 local ok,result=pcall(function()
  deadline=math.min(deadline or now()+0.75,now()+0.75)
  assert(deadline>now(),'timeout')
  local function ready(event)
   local ms=math.floor((deadline-now())*1000);assert(ms>0,'timeout')
   local f={{fd=s,events=n.poll_flags(event)}};assert(n.poll(f,ms)>0 and f[1].revents~=0,'timeout')
  end
  s=assert(n.socket('unix','stream'));assert(s:setblocking(false));assert(s:connect(path))
  local bytes=method..' '..route..' HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n'
  if body then bytes=bytes..'Content-Type: application/json\r\nContent-Length: '..#body..'\r\n' end
  bytes=bytes..'\r\n'..(body or '')
  local sent=0
  while sent<#bytes do ready('out');local count=assert(s:send(bytes:sub(sent+1)));assert(count>0);sent=sent+count end
  local raw=''
  while true do
   ready('in');local chunk=assert(s:recv(4096));if #chunk==0 then break end
   raw=raw..chunk;assert(#raw<=69632,'oversized response')
  end
  local at=assert(raw:find('\r\n\r\n',1,true));assert(at<=4096)
  local header=raw:sub(1,at-1);local status=tonumber(header:match('^HTTP/1%.[01] (%d%d%d) '));assert(status)
  assert(not header:lower():find('transfer%-encoding:'),'unsupported framing')
  local length=header:lower():match('\r\ncontent%-length:%s*(%d+)')
  local data=raw:sub(at+4);assert(#data<=65536 and (not length or tonumber(length)==#data),'invalid length')
  local value=J.decode(data);assert(type(value)=='table')
  return {status=status,value=value}
 end)
 if s then s:close() end
 if ok then return result end
 return nil
end
local errors={
 stale_profile='域名更新账户已变更，请重新选择后保存。',
 ambiguous_profile_name='存在同名域名更新账户，请先在 ddns-go 中修改名称。',
 family_disabled='所选账户未启用需要的地址类型，请检查 ddns-go 设置。',
 save_failed='域名更新设置未能保存，请检查 ddns-go 后重试。'
}
local unavailable='无法连接域名更新服务，请检查 ddns-go 是否运行并启用本地接口。'
local function error_message(response)
 return response and errors[response.value.error] or unavailable
end
local function text(s,max)
 assert(type(s)=='string' and #s<=max and not s:find('[%z\1-\31\127]'));return s
end
function M.profiles()
 local response=request('GET','/v1/profiles')
 local ok,profiles=pcall(function()
  assert(response and response.status==200 and response.value.api_version==1)
  local values=response.value.profiles;assert(type(values)=='table' and #values<=64)
  local out={};local seen={}
  for i,p in ipairs(values) do
   local id=text(p.profile_id,256);assert(#id>0 and not seen[id]);seen[id]=true
   local item={profile_id=id,name=text(p.name,128),provider=text(p.provider,128)}
   for _,family in ipairs({'a','aaaa'}) do
    local v=p[family];assert(type(v)=='table' and type(v.enabled)=='boolean' and type(v.domains)=='table' and #v.domains<=1024)
    item[family]={enabled=v.enabled,domains={}}
    for j,domain in ipairs(v.domains) do item[family].domains[j]=text(domain,253) end
   end
   out[i]=item
  end
  return out
 end)
 if not ok then return {available=false,profiles={},error=error_message(response)} end
 return {available=true,profiles=profiles}
end
function M.ensure(config)
 local out={results={},warnings={}};local deadline=now()+3
 for _,s in ipairs(config.services or {}) do
  if s.enabled==true and (s.type=='http_proxy' or s.type=='https_proxy' or s.type=='tls_passthrough') and s.dns and s.dns.mode=='ddns_go' then
   local response=request('POST','/v1/domains/ensure',J.encode({profile_id=s.dns.profile_id,hostname=s.hostname,record_types=s.dns.record_types}),deadline)
   local value=response and response.value
   local success=response and response.status==200 and value.api_version==1 and type(value.added)=='table' and type(value.already)=='table' and type(value.update_queued)=='boolean' or false
   local item={service_id=s.service_id,hostname=s.hostname,ok=success}
   if success then item.message='已加入自动更新列表' else
    item.error=error_message(response);out.warnings[#out.warnings+1]={service_id=s.service_id,hostname=s.hostname,error=item.error}
   end
   out.results[#out.results+1]=item
  end
 end
 return out
end
return M
