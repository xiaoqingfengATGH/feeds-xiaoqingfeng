-- Invocation-local parser adversaries against the unchanged installed readiness path.
package.path='/usr/share/homepublish/?.lua;'..package.path
package.loaded['product-procd-group']={new=function()return {healthy=function()return true end} end}
local V=require('product-v2-runtime').new({probe_address=function()return '127.0.0.1' end})
local p={generation=7,listeners={{port=1}},services={{service_id='tls',type='tls_passthrough',hostname='opaque.home.test'}}}
local oldp,olde=io.popen,os.execute
os.execute=function()return 0 end
local cases={
 {'fatal-after-established','CONNECTION ESTABLISHED\nProtocol version: TLSv1.3\nCiphersuite: TLS_AES_256_GCM_SHA384\nerror: handshake failure\nHP_TLS_EXIT=1\n',false},
 {'none-cipher','New, (NONE), Cipher is (NONE)\nHP_TLS_EXIT=0\n',false},
 {'refused','connect:errno=111\nHP_TLS_EXIT=1\n',false},
 {'timeout','CONNECTION ESTABLISHED\nProtocol version: TLSv1.3\nCiphersuite: TLS_AES_256_GCM_SHA384\nHP_TLS_EXIT=124\n',false},
 {'forged-substring','prefix CONNECTION ESTABLISHED suffix\nHP_TLS_EXIT=0\n',false},
 {'missing-status','CONNECTION ESTABLISHED\nProtocol version: TLSv1.3\nCiphersuite: TLS_AES_256_GCM_SHA384\n',false},
 {'success','CONNECTION ESTABLISHED\nProtocol version: TLSv1.3\nCiphersuite: TLS_AES_256_GCM_SHA384\nHP_TLS_EXIT=0\n',true}}
for _,c in ipairs(cases) do
 io.popen=function()return {read=function()return c[2] end,close=function()return true end} end
 local ok,out=V.readiness(p);assert(ok==c[3] and out.tls.ready==c[3],c[1]..' false readiness result: '..tostring(ok));print(c[1]..' GREEN')
end
io.popen,os.execute=oldp,olde
print('P5_READINESS_ADVERSARIES_GREEN')
