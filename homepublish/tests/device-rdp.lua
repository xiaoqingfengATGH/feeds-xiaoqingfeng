-- Device-only RDP contracts; no live journal or listener changes.
local source=assert(arg[1]);package.path=source..'/?.lua;'..package.path
local C=require('canonical-v2');local R=require('direct-renderer')
local function config()
 return {schema_version=2,access_profile={listeners={{listener_id='lan4',family='ipv4',network='lan',address='192.168.1.2',port=24443}}},publication_policy={mode='continuous',boot_restore=false},services={{service_id='desktop',name='Desktop',enabled=true,type='rdp',backend={addressFamily='ipv4',host='192.168.1.5',port=3389,allowed_ranges={'192.168.1.0/24'}}}}}
end
local providers={authorize_listener=function()return true end,authorize_backend=function()return true end,healthy=function()return true end,mixed_ports={https=41001,http=41002,reject=41003},certificate_snapshot=function()error('RDP must not request an ingress certificate')end}
local tests={}
function tests.rdp_only()
 local c,e=C.validate(config());assert(c,'RDP canonical rejected: '..tostring(e))
 local p,e=R.render(c,providers);assert(p,e)
 assert(p.sslh_configuration:find('name: "regex"',1,true),'RDP regex absent')
 assert(p.sslh_configuration:find('^\\\\x03\\\\x00[\\\\s\\\\S]{3}\\\\xe0',1,true),'wrong RDP byte offsets or escaping')
 assert(p.sslh_configuration:find('host: "192.168.1.5"; port: "3389";',1,true),'RDP target absent')
 assert(not p.sslh_configuration:find('proxyprotocol:',1,true),'RDP must not receive PROXY header')
 assert(p.sslh_configuration:find('name: "regex"',1,true)<p.sslh_configuration:find('name: "anyprot"',1,true),'RDP follows catchall')
 assert(not p.configuration:find('ssl_certificate',1,true),'RDP unnecessarily requires certificate')
 local f=assert(io.open(assert(arg[2]),'w'));f:write(p.sslh_configuration);f:close()
end
function tests.conflict()
 local c=config();c.services[2]=config().services[1];c.services[2].service_id='second';c.services[2].enabled=false
 local v,e,d=C.validate(c);assert(not v and d.error_code=='RDP_CONFLICT','duplicate RDP including disabled draft must conflict')
end
function tests.ssh_and_tcp()
 local c=config();c.services[2]={service_id='ssh',name='SSH',enabled=true,type='ssh',backend=c.services[1].backend}
 c.services[3]={service_id='tcp',name='TCP',enabled=true,type='tcp_forward',listen_port=24444,backend=c.services[1].backend}
 local p,e=R.render(c,providers);assert(p,e)
 assert(p.sslh_configuration:find('name: "ssh"',1,true) and p.sslh_configuration:find('name: "regex"',1,true),'SSH/RDP coexistence absent')
 assert(p.configuration:find('192.168.1.2:24444',1,true),'independent TCP lost')
end
function tests.disabled()
 local c=config();c.services[1].enabled=false;assert(C.validate(c));assert(not R.render(c,providers),'disabled RDP creates route')
end
function tests.no_custom_regex()
 local c=config();c.services[1].regex_patterns={'anything'};assert(not C.validate(c),'client regex accepted')
 c=config();c.services[1].hostname='desktop.example.test';assert(not C.validate(c),'RDP domain selector accepted')
 c=config();c.services[1].certificate_ref='acme:desktop';assert(not C.validate(c),'RDP ingress certificate accepted')
end
function tests.ipv6()
 local c=config();c.access_profile.listeners[2]={listener_id='lan6',family='ipv6',network='lan',address='fd89:878e:a47f::1',port=24443}
 c.services[1].backend={addressFamily='ipv6',host='fd89:878e:a47f::5',port=3389,allowed_ranges={'fd89:878e:a47f::/64'}}
 local p,e=R.render(c,providers);assert(p,e);assert(p.sslh_configuration:find('fd89:878e:a47f:0:0:0:0:5',1,true),'IPv6 RDP target lost')
end
local failed=0
for _,name in ipairs({'rdp_only','conflict','ssh_and_tcp','disabled','no_custom_regex','ipv6'}) do local ok,e=pcall(tests[name]);print((ok and 'PASS ' or 'FAIL ')..name..(ok and '' or ': '..tostring(e)));if not ok then failed=failed+1 end end
os.exit(failed==0 and 0 or 1)
