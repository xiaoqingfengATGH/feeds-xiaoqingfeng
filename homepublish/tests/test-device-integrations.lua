-- Device adapter behavior regression, executable on installed Lua/nixio.
package.path=arg[1]..'/?.lua;'..package.path
local I=require('device-integrations')
assert(not I.acme_source('home.iwonderful.top',nil))
assert(not I.acme_source('../domain','rsa'))
local r=assert(I.resolve('localhost.lan'))
local seen={};for _,a in ipairs(r.addresses) do seen[a]=true end
assert(seen['127.0.0.1'] and seen['::1'])
assert(r.ttl==30 and r.resolver=='system-getaddrinfo/poll30-no-dns-ttl')
print('PASS actual ACME section references and system dual-family resolver')
