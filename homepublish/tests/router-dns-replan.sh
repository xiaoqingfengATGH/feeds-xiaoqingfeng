#!/bin/sh
# Non-installed controlled getaddrinfo feed; installed resolver/selection/provider/controller unchanged.
set -eu
e=/tmp/homepublish-dns-replan-evidence
mkdir -p "$e"; chmod 700 "$e"
test ! -e /etc/homepublish/device-test
test ! -e /tmp/homepublish-device/runtime
if ubus call service list '{"name":"homepublish"}' | grep -q '"homepublish"'; then /etc/init.d/homepublish stop; fi
cp /etc/homepublish/product/state "$e/state.backup"
cleanup() {
 lua -e "package.path='/usr/share/homepublish/?.lua;'..package.path;assert(require('product-device-provider').stop())" || true
 test -z "${backend:-}" || kill "$backend" 2>/dev/null || true
 test -z "${backend2:-}" || kill "$backend2" 2>/dev/null || true
 rm -rf /etc/homepublish/device-test "$e/www4" "$e/www6"
 cp "$e/state.backup" /etc/homepublish/product/state; chmod 600 /etc/homepublish/product/state
}
trap cleanup EXIT INT TERM
mkdir -p /etc/homepublish/device-test "$e/www4/cgi-bin" "$e/www6/cgi-bin"
chmod 700 /etc/homepublish/device-test
touch /etc/homepublish/device-test/enabled
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=service.home -addext subjectAltName=DNS:service.home -keyout /etc/homepublish/device-test/key.pem -out /etc/homepublish/device-test/cert.pem >"$e/openssl.log" 2>&1
chmod 600 /etc/homepublish/device-test/*.pem
for family in 4 6; do
 printf 'HP_DNS_V%s\n' "$family" >"$e/www$family/index.html"
 printf '#!/bin/sh\nprintf "%%s\\n" "$REQUEST_METHOD" >>/tmp/homepublish-dns-replan-evidence/post%s.log\nprintf "Content-Type: text/plain\\n\\nHP_POST_V%s\\n"\n' "$family" "$family" >"$e/www$family/cgi-bin/write"
 chmod 755 "$e/www$family/cgi-bin/write"
done
rm -f "$e/post4.log" "$e/post6.log"
/usr/sbin/uhttpd -f -p 127.0.0.1:49285 -h "$e/www4" -x /cgi-bin >"$e/backend4.log" 2>&1 & backend=$!
/usr/sbin/uhttpd -f -p '[::1]:49285' -h "$e/www6" -x /cgi-bin >"$e/backend6.log" 2>&1 & backend2=$!
sleep 1
lua - <<'LUA'
package.path='/usr/share/homepublish/?.lua;'..package.path
local N=require('nixio');local original=N.getaddrinfo
local feed={{family='inet6',address='::1'},{family='inet',address='127.0.0.1'}};local queries=0
-- Injection exists ONLY in this test process at libc-answer boundary. Actual I.resolve,
-- direct-backend selection, thirty-second refresh and controller recovery execute normally.
N.getaddrinfo=function(host,...) if host=='localhost.lan' then queries=queries+1;return feed end;return original(host,...) end
local I=require('device-integrations');assert(I.resolve('localhost.lan').addresses[1]=='::1')
local P=require('product-provider');local D=require('product-device-provider')
local plan_original=D.plan
-- Canonical rejects ::1 CIDR. Narrow the fixed fixture's approved ULA range
-- to loopback only in this non-installed adapter; do not change the validator.
D.plan=function(config)
 local copy=require('product-wire').decode(require('product-wire').encode(config))
 assert(copy.services[1].backend.allowed_ranges[2]=='fd00::/16')
 copy.services[1].backend.allowed_ranges[2]='::1/128'
 return plan_original(copy)
end
local C=require('product-controller').new(D,{clock=function()return {now=os.time(),boot_id='controlled-dns-test',trusted=true}end})
local c={schema_version=1,services={{name='Controlled DNS',service_id='fixture',hostname='service.home',certificate_ref='import:fixture',backend={addressFamily='hostname',host='localhost.lan',port=49285,allowed_ranges={'127.0.0.0/8','fd00::/16'}},authentication_review={authentication='confirmed',management=false}}},access_profile={methods_allowed={'manual_ipv4'},listeners={{family='ipv4',address='192.168.1.2',interface='br-lan',zone='lan',protocol='tcp',internal_port=49284,external_port=49284}}},publication_policy={mode='temporary',temporary_duration=120,boot_restore=false}}
local function text(path)local f=assert(io.open(path));local t=f:read('*a');f:close();return t end
local function request(marker,post)
 local command="curl -q --noproxy '*' --connect-timeout 2 --max-time 5 --cacert /etc/homepublish/device-test/cert.pem --resolve service.home:49284:127.0.0.1 --fail --silent --show-error "..(post and '-X POST ' or '')..'https://service.home:49284/'..(post and 'cgi-bin/write' or '')
 local f=assert(io.popen(command));local t=f:read('*a');f:close();assert(t:find(marker,1,true),t)
end
local base=P.handle({action='status'});local saved=assert(P.handle({action='save',expected_revision=base.saved_revision,config=c}));local first=C.start(saved.saved_revision,true);assert(first.runtime.phase=='running',first.runtime.last_error)
local gen=first.runtime.generation;local expiry=first.runtime.expires_at
local oldpid=text('/tmp/homepublish-device/runtime/nginx.pid'):match('%d+')
assert(text('/tmp/homepublish-device/runtime/nginx.conf'):find('127.0.0.1:49285',1,true));request('HP_DNS_V4');request('HP_POST_V4',true)
-- Pending port change must NOT be consumed by DNS recovery.
c.services[1].backend.port=49286;saved=assert(P.handle({action='save',expected_revision=saved.saved_revision,config=c}))
feed={{family='inet6',address='::1'}}
local state;local deadline=os.time()+40
repeat os.execute('sleep 1');state=C.tick() until state.runtime.phase=='retry_wait' or os.time()>=deadline
assert(state.runtime.phase=='retry_wait','periodic DNS selection change not observed');assert(state.runtime.cleanup=='confirmed');assert(state.runtime.expires_at==expiry)
assert(os.execute('kill -0 '..oldpid..' 2>/dev/null')~=0,'old generation master retained')
repeat os.execute('sleep 1');state=C.tick() until state.runtime.phase=='running' or os.time()>=deadline
assert(state.runtime.phase=='running',state.runtime.last_error);assert(state.runtime.generation>gen);assert(state.runtime.expires_at==expiry)
assert(state.active_revision==first.active_revision and state.saved_revision==saved.saved_revision and state.pending_config.apply_required)
assert(text('/tmp/homepublish-device/runtime/nginx.conf'):find('[::1]:49285',1,true));request('HP_DNS_V6');request('HP_POST_V6',true)
assert(text('/tmp/homepublish-dns-replan-evidence/post4.log')=='POST\n');assert(text('/tmp/homepublish-dns-replan-evidence/post6.log')=='POST\n');assert(text('/tmp/homepublish-device/runtime/nginx.conf'):find('proxy_next_upstream off;',1,true))
local stop=C.stop();assert(stop.runtime.cleanup=='confirmed' and stop.runtime.phase=='stopped');assert(C.tick(gen).desired_state.manual_stop_latch)
assert(not io.open('/tmp/homepublish-device/runtime/nginx.conf'));assert(queries>=4)
-- Honest scope: canonical multi-service support does not make installed fixed provider multi-service.
local clone=require('product-wire').decode(require('product-wire').encode(c));clone.services[2]=clone.services[1]
local plan,err=D.plan(clone);assert(not plan and err=='device test scope denied')
print('PASS installed r5 controlled getaddrinfo answer A+AAAA -> AAAA; actual 30s renew, stop old PID, bounded recovery new generation, TLS markers v4 -> v6; active not pending; original temporary deadline; POST exactly once each/no replay; Stop snapshots removed; installed multi-service explicitly unsupported; queries='..queries..' generations='..gen..'->'..state.runtime.generation)
LUA
