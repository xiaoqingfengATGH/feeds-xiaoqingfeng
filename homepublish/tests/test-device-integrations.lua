-- Device adapter behavior regression, executable on installed Lua/nixio.
package.path=arg[1]..'/?.lua;'..package.path
local I=require('device-integrations')
local values={home={domains={'home.iwonderful.top'},enabled='1'},home_rsa={domains={'home.iwonderful.top'},enabled='1',key_type='rsa2048'}}
local function get(s,k) return values[s] and values[s][k] end
local ecc=assert(I.acme_source('acme:home','home.iwonderful.top',get))
assert(ecc.certificate=='/etc/acme/home.iwonderful.top_ecc/fullchain.cer')
local rsa=assert(I.acme_source('acme:home_rsa','home.iwonderful.top',get))
assert(rsa.key=='/etc/acme/home.iwonderful.top/home.iwonderful.top.key')
assert(not I.acme_source('acme:home','other.home',get))
assert(not I.acme_source('acme:../home','home.iwonderful.top',get))
local r=assert(I.resolve('localhost.lan'))
local seen={};for _,a in ipairs(r.addresses) do seen[a]=true end
assert(seen['127.0.0.1'] and seen['::1'])
assert(r.ttl==30 and r.resolver=='system-getaddrinfo/poll30-no-dns-ttl')
print('PASS actual ACME section references and system dual-family resolver')
