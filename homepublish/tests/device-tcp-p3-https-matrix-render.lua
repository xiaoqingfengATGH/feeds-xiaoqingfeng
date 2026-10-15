-- Device-only task20 HTTPS matrix; installed modules, fixed endpoint narrowing only.
local root=assert(arg[1]);package.path='/usr/share/homepublish/?.lua;'..package.path
local C=require('canonical-v2');local R=require('direct-renderer')
local v6='fd89:878e:a47f:0:0:0:0:2'
for _,family in ipairs({'ipv4','ipv6'}) do
 for _,scheme in ipairs({'http','https'}) do
  local addr=family=='ipv4' and '127.0.0.1' or v6
  local port=scheme=='http' and 49445 or 49446
  local c={schema_version=2,default_certificate_ref='acme:home_rsa',access_profile={listeners={{listener_id='v4',family='ipv4',network='lan',address='192.168.1.2',port=49443},{listener_id='v6',family='ipv6',network='lan',address='fd89:878e:a47f::1',port=49443}}},publication_policy={mode='continuous',boot_restore=false},services={{service_id='matrixweb',name='HTTPS matrix',enabled=true,type='https_proxy',hostname='home.iwonderful.top',certificate_mode='inherit',upstream_scheme=scheme,backend={addressFamily=family,host=addr,port=port,allowed_ranges={family=='ipv4' and '127.0.0.0/8' or 'fd89:878e:a47f::2/128'}},authentication_review={authentication='confirmed',management=false}}}}
  if scheme=='https' then c.services[1].upstream_tls={verify=true,server_name='home.iwonderful.top'} end
  assert(C.validate(c))
  local p={authorize_listener=function(l)return (l.address=='192.168.1.2' or l.address=='fd89:878e:a47f:0:0:0:0:1') and l.internal_port==49443 end,authorize_backend=function(a,n)return a==addr and n==port end,healthy=function()return true end,certificate_snapshot=function(ref,host)assert(ref=='acme:home_rsa' and host=='home.iwonderful.top');return {certificate=root..'/runtime/cert.pem',key=root..'/runtime/key.pem'} end}
  local r,e=R.render(c,p);assert(r,e);assert(r.activation_ready==false)
  local upstream=family=='ipv4' and '127.0.0.1' or '['..v6..']'
  assert(r.configuration:find('proxy_pass '..scheme..'://'..upstream..':'..port..';',1,true))
  if scheme=='https' then assert(r.configuration:find('proxy_ssl_verify on;',1,true));assert(r.configuration:find('proxy_ssl_name home.iwonderful.top;',1,true)) end
  -- Exact canonical fixture addresses only; no production validation override.
  local text,n=r.configuration:gsub('192%.168%.1%.2:49443','127.0.0.1:49443');assert(n==2)
  text,n=text:gsub('%[fd89:878e:a47f:0:0:0:0:1%]:49443','[::1]:49443');assert(n==2)
  if family=='ipv6' then text,n=text:gsub('%[fd89:878e:a47f:0:0:0:0:2%]:'..port,'[::1]:'..port);assert(n==1) end
  local f=assert(io.open(root..'/runtime/matrix-'..family..'-'..scheme..'.conf','w'));assert(f:write(text));assert(f:close())
  c.access_profile.listeners[2].address='::1';assert(not C.validate(c));assert(not R.render(c,p))
 end
end
print('PASS installed renderer HTTPS matrix: dual ingress / both backend families / verified HTTPS upstream; production loopback ingress forbidden')
