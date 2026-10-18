local fs=require('nixio.fs');assert(fs.mkdir(ROOT..'/store','700'))
local store=dofile(ROOT..'/product-store-core.lua').new(ROOT..'/store')
local original=dofile
_G.dofile=function(path)if path==ROOT..'/product-store.lua' then return store end;return original(path)end
local P=dofile(ROOT..'/product-provider.lua');_G.dofile=original;package.loaded['product-provider']=P
local count=0;local fail=false
package.loaded['product-ddns']={ensure=function(config)
 count=count+1;assert(P.handle{action='status'}.runtime.phase=='running','DNS must follow forwarding readiness')
 assert(config.services[1].dns.profile_id=='p:1','snapshot preserved');if fail then error('NEVER_EXPORT') end
 return {results={{service_id='web',ok=true}},warnings={}}
end}
local config={schema_version=2,access_profile={listeners={{listener_id='v4',family='ipv4',network='lan',address='192.168.1.2',port=18443}}},services={{service_id='web',name='Web',enabled=true,type='http_proxy',hostname='new.example.com',upstream_scheme='http',backend={addressFamily='ipv4',host='192.168.1.3',port=8080},dns={mode='ddns_go',profile_id='p:1',record_types={'A'}}}}}
assert(P.handle{action='validate',config=config});local saved=assert(P.handle{action='save',expected_revision=0,config=config});assert(saved.saved_revision==1 and count==0)
local runtime={runtime_plan=function(c)return c end,plan=function(c)return c end,start=function()return true end,readiness=function()return true,{web={ready=true,generation=1}} end,stop=function()return true end,renew=function()return true end}
local C=dofile(ROOT..'/product-controller.lua').new(runtime,{clock=function()return {now=100,boot_id='test',trusted=true}end})
local r=C.start(1,true);assert(r.runtime.phase=='running');assert(count==1 and r.ddns and #r.ddns.results==1,'explicit start must ensure DNS')
assert(r.active_config.services[1].dns.mode=='ddns_go');C.status();C.tick();assert(count==1,'polling must not ensure')
fail=true;runtime.readiness=function()return true,{web={ready=true,generation=2}} end
r=C.apply(1,true);assert(r.runtime.phase=='running' and count==2 and #r.ddns.warnings==1,'DNS errors must not fail forwarding')
assert(not require('product-json').encode(r.ddns):find('NEVER_EXPORT',1,true))
C.stop();assert(count==2);C.restore();assert(count==2)
local after=P.handle{action='status'};assert(after.saved_config.services[1].dns.profile_id=='p:1' and after.active_config.services[1].dns.record_types[1]=='A')
print('DDNS_LIFECYCLE_GREEN')
