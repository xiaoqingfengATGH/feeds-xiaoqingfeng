-- Target Lua/nixio contract; SOURCE is the fixed private source bundle.
local C=dofile(SOURCE..'/canonical-v2.lua')
local function config(kind,value)
 local s={service_id='host',name='Host',enabled=true,type=kind or 'http_proxy',hostname='entry.home.test',upstream_scheme='http',backend={addressFamily='ipv4',host='127.0.0.1',port=8080,host_header=value}}
 if s.type=='https_proxy' then s.certificate_mode='inherit' end
 if s.type=='ssh' or s.type=='tcp_forward' or s.type=='tls_passthrough' then s.upstream_scheme=nil;if s.type~='tls_passthrough' then s.hostname=nil end end
 if s.type=='tcp_forward' then s.listen_port=18081 end
 return {schema_version=2,access_profile={listeners={{listener_id='v4',family='ipv4',network='lan',address='192.168.1.2',port=18443}}},services={s}}
end
local n=0
for _,kind in ipairs({'http_proxy','https_proxy'}) do
 for _,value in ipairs({'backend.home.test','Backend.Example:8443','192.168.1.9','192.168.1.9:80','[::1]','[2001:db8::1]:65535','localhost:1'}) do
  local r,e=C.validate(config(kind,value));assert(r,require('luci.jsonc').stringify(e));assert(r.services[1].backend.host_header==value);n=n+1
 end
 for _,value in ipairs({'',false,5,{},'https://host','user@host','host/path','host?x','host#x',' host','host ','host\r\nX: x','host\t','host;return','host"','host\'','host\\x','$host','${host}','host:0','host:65536','host:-1','host:01','host:','host:1:2','[]','[::1','::1','[::::]','[1:2:3]','[::ffff:192.0.2.1]','[fe80::1%eth0]','bad..host','-host','host-','999.1.2.3'}) do
  local r,e,d=C.validate(config(kind,value));if value=='' then assert(r and r.services[1].backend.host_header==nil) else assert(not r,'accepted invalid Host: '..tostring(value));assert(d.error_code=='INVALID_CONFIG') end;n=n+1
 end
 local r=assert(C.validate(config(kind,nil)));assert(r.services[1].backend.host_header==nil)
end
for _,kind in ipairs({'ssh','tcp_forward','tls_passthrough'}) do
 for _,value in ipairs({'backend.home.test',''}) do assert(not C.validate(config(kind,value)),'non-proxy Host accepted') end
 assert(C.validate(config(kind,nil)))
end
local c=config('http_proxy','backend.home.test');c.services[1].backend.backup={addressFamily='ipv4',host='127.0.0.2',port=8080,host_header='backup.test'};assert(not C.validate(c),'backup Host accepted')
local R=require('direct-renderer')
local providers={authorize_listener=function()return true end,authorize_backend=function()return true end,healthy=function()return true end,certificate_snapshot=function()return {certificate='/tmp/fixture.pem',key='/tmp/fixture.key'} end,mixed_ports={http=41002,https=41001,reject=41003}}
for _,kind in ipairs({'http_proxy','https_proxy'}) do
 for _,scheme in ipairs({'http','https'}) do
  for _,value in ipairs({'backend.home.test:8443','[::1]:1234','192.168.1.9',''}) do
   local c=config(kind,value);c.default_certificate_ref='acme:fixture';c.services[1].upstream_scheme=scheme
   if scheme=='https' then c.services[1].upstream_tls={verify=false,server_name='sni.home.test'} end
   local v=assert(C.validate(c));local rendered,e=R.render(v,providers);assert(rendered,e)
   assert(rendered.configuration:find('proxy_set_header Host '..(value~='' and value or 'entry.home.test')..';',1,true))
   assert(not rendered.configuration:find('proxy_set_header X-Forwarded-Host',1,true))
   if scheme=='https' then assert(rendered.configuration:find('proxy_ssl_name sni.home.test;',1,true)) end
  end
 end
 for _,bad in ipairs({'$host','host;return 200','host\r\nX: x','host:65536',false,9}) do
  local c=config(kind,bad);c.default_certificate_ref='acme:fixture'
  assert(not R.render(c,providers),'internal renderer accepted unsafe Host')
 end
end
print('HOST_HEADER_SCHEMA_GREEN '..n)
print('HOST_HEADER_RENDERER_GREEN')
