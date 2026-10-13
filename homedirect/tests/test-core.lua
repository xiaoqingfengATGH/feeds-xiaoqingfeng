local source = arg[1] or '.'
local ok, core = pcall(dofile, source .. '/core.lua')
assert(ok, 'HomeDirect core is missing: ' .. tostring(core))
local function config()
 return {listen='127.0.0.1', port=18443, cert='/tmp/homedirect-test/cert.pem', key='/tmp/homedirect-test/key.pem', runtime='/tmp/homedirect-test', hosts={{name='nas-stun-test.innonext.win', upstream='http://127.0.0.1:18081'}, {name='files-stun-test.innonext.win', upstream='http://127.0.0.1:18082'}}}
end
assert(core.validate(config()))
print('ok 1 - accepts isolated explicit configuration')
local cases = {
 {'management port', function(c) c.port=443 end},
 {'port string injection', function(c) c.port='18443;include x' end},
 {'unspecified listener', function(c) c.listen='0.0.0.0' end},
 {'leading-dot wildcard hostname', function(c) c.hosts[1].name='.innonext.win' end},
 {'hostname injection', function(c) c.hosts[1].name='x; return 200;' end},
 {'duplicate hostname', function(c) c.hosts[2].name=c.hosts[1].name end},
 {'public upstream', function(c) c.hosts[1].upstream='http://8.8.8.8:80' end},
 {'management upstream', function(c) c.hosts[1].upstream='http://192.168.1.2:80' end},
 {'credentials upstream', function(c) c.hosts[1].upstream='http://user:pass@127.0.0.1:18081' end},
 {'nginx path injection', function(c) c.cert='/tmp/x; include evil;' end},
 {'unisolated runtime', function(c) c.runtime='/etc/nginx' end},
 {'empty hosts', function(c) c.hosts={} end},
 {'unknown option', function(c) c.udp=true end},
 {'HTTPS upstream without verification', function(c) c.hosts[1].upstream='https://127.0.0.1:18081' end}
}
for i, case in ipairs(cases) do
 local c=config(); case[2](c)
 local valid=core.validate(c)
 assert(not valid, 'must reject ' .. case[1])
 print('ok ' .. (i+1) .. ' - rejects ' .. case[1])
end
local rendered,err=core.render(config())
assert(rendered, err)
for _,fragment in ipairs({'pid /tmp/homedirect-test/nginx.pid;', 'listen 127.0.0.1:18443 ssl default_server;', 'return 444;', 'server_name nas-stun-test.innonext.win;', 'server_name files-stun-test.innonext.win;', 'proxy_pass http://127.0.0.1:18081;', 'proxy_pass http://127.0.0.1:18082;', 'ssl_certificate /tmp/homedirect-test/cert.pem;', 'proxy_set_header Host $host;', 'proxy_set_header X-Forwarded-For $remote_addr;'}) do
 assert(rendered:find(fragment,1,true), 'missing nginx fragment '..fragment)
end
assert(not rendered:find('include ',1,true), 'must not include management nginx')
local bad=config(); bad.port=443
assert(core.render(bad)==nil, 'render must validate before emission')
print('ok ' .. (#cases+2) .. ' - isolated multi-host TLS nginx generation and default deny')
local f=assert(io.open(source .. '/nginx.conf','w')); f:write(rendered); f:close()

