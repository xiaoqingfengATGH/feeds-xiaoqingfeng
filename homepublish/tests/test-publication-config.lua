local root=arg[1]
local adapter=dofile(root..'/config.lua')
local c={enabled='1',exposure_approved='1',listen='127.0.0.1',port='18443',bind_port='18444',ttl='60',stun_server='example.com',http_server='example.com',cert='/etc/homepublish/cert.pem',key='/etc/homepublish/key.pem',publication_enabled='1',router_token_file='/etc/homepublish/router.token'}
local hosts={{name='nas-stun-test.innonext.win',upstream='http://127.0.0.1:18081'}}
local v,e=adapter.validate(c,hosts);assert(v,e)
assert(v.publication=='configured' and v.router_token_file==c.router_token_file)
c.publication_enabled=nil;c.router_token_file=nil
assert(adapter.validate(c,hosts).publication=='disabled','legacy defaults off')
c.publication_enabled='0';c.router_token_file='/etc/homepublish/router.token'
assert(adapter.validate(c,hosts).publication=='disabled')
c.publication_enabled='1';c.router_token_file=nil
assert(not adapter.validate(c,hosts),'opt-in requires reference')
for _,value in ipairs({'/tmp/token','/etc/homepublish/../router.token','/etc/homepublish/router.token\n','secret-value'}) do
 c.router_token_file=value;assert(not adapter.validate(c,hosts),'unsafe path accepted')
end
c.router_token_file='/etc/homepublish/router.token'
for _,value in ipairs({'yes','2','true',''}) do c.publication_enabled=value;assert(not adapter.validate(c,hosts)) end
c.publication_enabled='1';c.router_token='plaintext';assert(not adapter.validate(c,hosts))
c.router_token=nil
for _,ttl in ipairs({'0','121','1e2'}) do c.ttl=ttl;assert(not adapter.validate(c,hosts)) end
c.ttl='120';assert(adapter.validate(c,hosts).ttl==120)
c.ttl='1';assert(adapter.validate(c,hosts).ttl==1)
print('PASS publication UCI opt-in/defaults/reference/secret rejection/shared TTL')
