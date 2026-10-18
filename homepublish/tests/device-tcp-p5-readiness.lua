-- Startup readiness is component-only; target TLS/HTTP failures are irrelevant.
package.path='/usr/share/homepublish/?.lua;'..package.path
local healthy=true
package.loaded['product-procd-group']={new=function()return {healthy=function()return healthy,'sslh process is not running' end} end}
local V=require('product-v2-runtime').new({})
local p={generation=7,services={{service_id='tls',type='tls_passthrough'},
 {service_id='web',type='https_proxy'},{service_id='ssh',type='ssh'},
 {service_id='tcp',type='tcp_forward'}}}
local oldp,olde=io.popen,os.execute
io.popen=function()error('startup must not execute TLS or HTTP probes')end
os.execute=function()error('startup must not execute target probes')end
local ok,out=V.readiness(p)
assert(ok,'healthy components must start regardless of target state')
for _,s in ipairs(p.services) do assert(out[s.service_id].ready and out[s.service_id].generation==7) end
healthy=false
local failed,results,err=V.readiness(p)
assert(not failed and err=='sslh process is not running')
for _,s in ipairs(p.services) do assert(not results[s.service_id].ready) end
io.popen,os.execute=oldp,olde
print('P5_READINESS_ADVERSARIES_GREEN')
