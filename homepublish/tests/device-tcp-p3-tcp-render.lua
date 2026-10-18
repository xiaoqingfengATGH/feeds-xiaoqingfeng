-- Device-only raw TCP rendering test: independent ports, no shared protocol probe.
local root=assert(arg[1]);package.path=root..'/?.lua;/usr/share/homepublish/?.lua;'..package.path
local R=require('direct-renderer')
local c={schema_version=2,access_profile={listeners={{listener_id='v6',family='ipv6',network='lan',address='fd89:878e:a47f::1',port=49543}}},publication_policy={mode='continuous',boot_restore=false},services={}}
for i,pair in ipairs({{49550,49551},{49552,49553},{49554,49555}}) do
 c.services[i]={service_id='tcp'..i,name='tcp'..i,type='tcp_forward',enabled=true,listen_port=pair[1],backend={addressFamily='ipv4',host='127.0.0.1',port=pair[2],allowed_ranges={'127.0.0.0/8'}},authentication_review={authentication='confirmed',management=false}}
end
local p={authorize_listener=function(l)return l.address=='fd89:878e:a47f:0:0:0:0:1' and (l.internal_port==49550 or l.internal_port==49552 or l.internal_port==49554) end,authorize_backend=function(a,port)return a=='127.0.0.1' and (port==49551 or port==49553 or port==49555) end,healthy=function()return true end,certificate_snapshot=function()error('raw TCP must not request certificates') end}
local r,e=R.render(c,p);assert(r,'independent TCP unsupported: '..tostring(e));assert(r.activation_ready==false and not r.sslh_configuration)
assert(not r.configuration:find('49543',1,true),'unused shared entry must not listen')
assert(not r.configuration:find('proxy_protocol',1,true),'raw backend must receive no PROXY')
assert(r.configuration:find('proxy_half_close on;',1,true),'half close support required')
assert(r.configuration:find('proxy_next_upstream off;',1,true),'no byte-stream replay')
local text,n=r.configuration:gsub('fd89:878e:a47f:0:0:0:0:1','::1');assert(n==3,'exact harness narrowing count')
local f=assert(io.open(root..'/tcp-runtime/front.conf','w'));assert(f:write(text));assert(f:close())
assert(R.render(c,p).configuration==r.configuration)
print('P3_TASK19_RENDER_GREEN')
