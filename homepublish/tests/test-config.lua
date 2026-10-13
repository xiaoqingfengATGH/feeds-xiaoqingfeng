local root=arg[1]
local ok, adapter=pcall(dofile, root..'/config.lua')
assert(ok, 'missing UCI validation adapter')
local c={enabled='0', exposure_approved='0', listen='127.0.0.1', port='18443',bind_port='18444',ttl='60',stun_server='turn.cloudflare.com',http_server='example.com',cert='/etc/homepublish/cert.pem',key='/etc/homepublish/key.pem'}
assert(adapter.validate(c,{}).state=='disabled')
c.enabled='1'
assert(not adapter.validate(c,{}), 'approval required')
c.exposure_approved='1'
local hosts={{name='nas-stun-test.innonext.win',upstream='http://127.0.0.1:18081'}}
local v,e=adapter.validate(c,hosts); assert(v,e)
assert(v.ttl==60 and v.bind_port==18444 and v.nginx.runtime=='/tmp/homepublish-service')
for _,item in ipairs({{'ttl','121'},{'ttl','0'},{'ttl','1e2'},{'bind_port','22'},{'bind_port','18443'},{'stun_server','x;id'},{'http_server','-x'},{'cert','/tmp/a.pem'},{'key','/etc/homepublish/../key.pem'},{'enabled','yes'},{'udp','1'}}) do
 local copy={};for k,x in pairs(c) do copy[k]=x end;copy[item[1]]=item[2]
 assert(not adapter.validate(copy,hosts),'reject '..item[1]..'='..item[2])
end
assert(not adapter.validate(c,{{name='.bad.example',upstream='http://127.0.0.1:18081'}}))
print('PASS UCI disabled/approval/bounds/injection/hosts')
