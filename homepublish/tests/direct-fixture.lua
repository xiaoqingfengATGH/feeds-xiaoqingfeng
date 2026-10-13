-- Test-only internal provider. Not installed; not product readiness authority.
package.path=arg[1]..'/?.lua;'..package.path
local ok,R=pcall(require,'direct-renderer');assert(ok,'direct renderer missing')
local root=arg[2];local port=tonumber(arg[3]);local backend=arg[4];local bp=tonumber(arg[5])
local plan={services={{hostname='service.home',certificate_ref='import:fixture',backend={addressFamily=backend:find(':',1,true) and 'ipv6' or 'ipv4',host=backend,port=bp,allowed_ranges={'127.0.0.0/8','::1/128'}}}},access_profile={listeners={{family='ipv4',address='127.0.0.1',internal_port=port,interface='lo',zone='fixture',protocol='tcp'},{family='ipv6',address='::1',internal_port=port,interface='lo',zone='fixture',protocol='tcp'}}}}
local p={authorize_listener=function(l) return l.interface=='lo' and l.zone=='fixture' end,authorize_backend=function(s) return s=='127.0.0.1' or s=='::1' end,healthy=function() return true end,certificate_snapshot=function(ref,host) assert(ref=='import:fixture' and host=='service.home');return {certificate=root..'/cert.pem',key=root..'/key.pem'} end}
if arg[6]=='hostname' then
 plan.services[1].backend.addressFamily='hostname';plan.services[1].backend.host='backend.home'
 p.resolve=function(h) assert(h=='backend.home');return {addresses={'::1','127.0.0.1'},ttl=30,observed_at=100,resolver='controlled-fixture'} end
end
local c,e=R.render(plan,p);assert(c,e)
if arg[6]=='hostname' then assert(c.backends[1].address=='127.0.0.1' and c.backends[1].resolver=='controlled-fixture');assert(not c.configuration:find('backend.home',1,true),'runtime DNS emitted') end
local f=assert(io.open(root..'/nginx.conf','w'));assert(c.activation_ready==false);f:write(c.configuration);f:close()
plan.access_profile.listeners[1].address='0.0.0.0';assert(not R.render(plan,p),'wildcard accepted');plan.access_profile.listeners[1].address='127.0.0.1'
p.authorize_listener=function() return false end;assert(not R.render(plan,p),'management/unapproved listener accepted')
p.authorize_listener=function() return true end
plan.services[1].certificate_ref='/tmp/client.pem';assert(not R.render(plan,p),'client certificate path accepted')
plan.services[1].certificate_ref='import:fixture'
p.certificate_snapshot=function() return {certificate=root..'/cert.pem;evil',key=root..'/key.pem'} end;assert(not R.render(plan,p),'snapshot injection accepted')
print('PASS renderer approval and literal scope')
