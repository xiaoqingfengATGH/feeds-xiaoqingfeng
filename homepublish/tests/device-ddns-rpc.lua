-- Execute actual staged transport/CLI/response pipeline, default Lua search path.
local J=require('product-json')
local last_raw
local function cli(action,body)
 local f=assert(io.open(ROOT..'/request.json','w'));f:write(J.encode(body or {}));f:close()
 local p=assert(io.popen('lua '..ROOT..'/product-rpc.lua '..action..' < '..ROOT..'/request.json | lua '..ROOT..'/product-cli.lua | lua '..ROOT..'/product-rpc.lua response'))
 local raw=p:read('*a');p:close();last_raw=raw;return assert(J.decode(raw))
end
local r=cli('ddns_profiles');assert(r.available==false and type(r.profiles)=='table' and type(r.error)=='string','ddns_profiles must traverse actual CLI')
assert(last_raw:find('"profiles":[]',1,true),'empty profiles must be JSON array')
assert(J.encode({ddns={results={},warnings={}}}):find('"results":[]',1,true),'empty DNS results must be JSON array')
assert(J.encode({profiles={{a={domains={}}}}}):find('"domains":[]',1,true),'empty domains must be JSON array')
local c={schema_version=2,access_profile={listeners={{listener_id='v4',family='ipv4',network='lan',address='192.168.1.2',port=18443}}},services={{service_id='web',name='Web',enabled=true,type='http_proxy',hostname='new.example.com',upstream_scheme='http',backend={addressFamily='ipv4',host='192.168.1.3',port=8080},dns={mode='ddns_go',profile_id='p:1',record_types={'A'}}}}}
r=cli('validate',{config=c});assert(not r.error,'native validate failed')
assert(r.config and r.config.services[1].dns.profile_id=='p:1','CLI preserves selected DNS')
local f=assert(io.open(ROOT..'/acl.json'));local acl=J.decode(f:read('*a'));f:close()
local function contains(values,key)for _,v in ipairs(values)do if v==key then return true end end;return false end
assert(contains(acl['luci-app-homepublish'].read.ubus.homepublish,'ddns_profiles'))
assert(not contains(acl['luci-app-homepublish'].write.ubus.homepublish,'ddns_profiles'))
local p=assert(io.popen('sh '..ROOT..'/rpcd-homepublish list'));local methods=J.decode(p:read('*a'));p:close();assert(methods.ddns_profiles)
f=assert(io.open(ROOT..'/request.json','w'));f:write('{}');f:close()
p=assert(io.popen('sh '..ROOT..'/rpcd-homepublish call ddns_profiles < '..ROOT..'/request.json'));local native=J.decode(p:read('*a'));p:close();assert(native.available==false and native.profiles)
print('DDNS_RPC_GREEN')
