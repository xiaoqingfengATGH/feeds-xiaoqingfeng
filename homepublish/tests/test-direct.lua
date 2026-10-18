local share=arg[1]
package.path=share..'/?.lua;'..package.path
local ok,B=pcall(require,'direct-backend')
assert(ok,'direct typed backend selection missing')
local b={addressFamily='hostname',host='backend.home',port=8080,allowed_ranges={'127.0.0.0/8','fd00::/16'}}
local trust={resolve=function(host) assert(host=='backend.home');return {addresses={'fd00::2','127.0.0.2','127.0.0.1'},ttl=30,observed_at=100,resolver='fixture'} end,authorize_backend=function() return true end,healthy=function() return true end}
local s,e=B.select(b,trust);assert(s,e);assert(s.address=='127.0.0.1' and s.family=='ipv4' and s.ttl==30)
assert(s.resolver=='fixture' and s.observed_at==100)
print('PASS stable IPv4-first frozen backend')
for _,bad in ipairs({'::','::ffff:127.0.0.1','fe80::1','fe80::1%lo','ff02::1','fd00:::1','fd00::1::2','fd00:1:2:3:4:5:6:7:8','169.254.1.1','0.0.0.0','224.0.0.1','127.00.0.1','8.8.8.8','fd01::1;evil'}) do
 trust.resolve=function() return {addresses={'127.0.0.1',bad},ttl=30,observed_at=100,resolver='fixture'} end
 assert(not B.select(b,trust),'accepted unsafe resolver result '..bad)
end
trust.resolve=function() return {addresses={'fd00::2'},ttl=30,observed_at=100,resolver='fixture'} end
assert(B.select(b,trust).family=='ipv6')
trust.authorize_backend=function() return false end
assert(not B.select(b,trust),'accepted management/unowned backend')
trust.authorize_backend=function() return true end
trust.resolve=function() return {addresses={'127.0.0.1'},ttl=0,observed_at=100,resolver='fixture'} end
assert(not B.select(b,trust),'unbounded DNS snapshot')
print('PASS all resolver results checked / scoped IPv6 / role / bounded TTL')
