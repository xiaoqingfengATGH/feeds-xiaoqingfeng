-- Non-installed two-service TLS fixture; independent backends and certificates.
package.path=arg[1]..'/?.lua;'..package.path
local R=require('direct-renderer')
local root=arg[2];local port=tonumber(arg[3]);local address=arg[4]
local plan={services={},access_profile={listeners={
 {family='ipv4',address='127.0.0.1',internal_port=port,interface='lo',zone='fixture',protocol='tcp'},
 {family='ipv6',address='::1',internal_port=port,interface='lo',zone='fixture',protocol='tcp'}}}}
for i,host in ipairs({'service.home','second.home'}) do
 plan.services[i]={hostname=host,certificate_ref='import:fixture',backend={addressFamily=address:find(':',1,true) and 'ipv6' or 'ipv4',host=address,port=tonumber(arg[4+i]),allowed_ranges={'127.0.0.0/8','::1/128'}}}
end
local providers={authorize_listener=function(l) return l.interface=='lo' and l.zone=='fixture' end,
 authorize_backend=function(a) return a==address end,healthy=function() return true end,
 certificate_snapshot=function(ref,host)
  assert(ref=='import:fixture' and (host=='service.home' or host=='second.home'))
  return {certificate=root..'/'..host..'.pem',key=root..'/'..host..'.key'}
 end}
local result,err=R.render(plan,providers);assert(result,err);assert(result.activation_ready==false)
local f=assert(io.open(root..'/nginx.conf','w'));f:write(result.configuration);f:close()
