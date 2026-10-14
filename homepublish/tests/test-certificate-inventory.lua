package.path=arg[1]..'/homepublish/files/usr/share/homepublish/?.lua;'..package.path
local sections={{['.name']='shared',domains={'*.example.test','example.test'},key_type='rsa2048'},{['.name']='ecc',domains={'other.example.test'},key_type='ec256'}}
package.preload.uci=function()return {cursor=function()return {foreach=function(self,config,kind,fn)assert(config=='acme' and kind=='cert');for _,s in ipairs(sections)do fn(s)end end}end}end
local I=require('device-integrations');local C=require('certificate-metadata')
local real=I.acme_source;local popen=io.popen;local observed
io.popen=function(cmd)observed=cmd;local values={'/fixture/cert.pem','/fixture/key.pem'};return {read=function()return table.remove(values,1)end,close=function()end}end
assert(real('*.example.test','rsa'),'wildcard inventory identity must reach existing resolver')
assert(observed:find("'*.example.test' 'rsa'",1,true))
io.popen=popen
I.acme_source=function(domain,kind)return {certificate='/fixture/cert.pem',key='/fixture/key.pem',domain=domain,key_type=kind}end
C.read=function()return {sans={'*.example.test','example.test'},status='within_validity',not_after='fixture date'}end
local source,e=I.certificate_source('acme:shared','photos.example.test');assert(source,e);assert(source.domain=='*.example.test' and source.key_type=='rsa')
assert(not I.certificate_source('acme:shared','a.b.example.test'))
assert(not I.certificate_source('acme:shared','unrelated.test'))
assert(require('product-json').encode({certificates={}}):find('\"certificates\":%[%]'),'empty inventory must be JSON array')
local rows=I.certificate_inventory().certificates;assert(#rows==2 and rows[1].certificate_ref=='acme:shared')
assert(rows[1].domain=='*.example.test' and rows[1].key_type=='rsa' and #rows[1].sans==2)
local json=require('product-json').encode(rows);assert(not json:find('/fixture',1,true) and not json:find('key.pem',1,true))
print('PASS section reference uses inventory domain/algorithm independently of service SAN; metadata projection excludes paths')
