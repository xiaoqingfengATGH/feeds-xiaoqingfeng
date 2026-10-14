#!/bin/sh
set -eu
e=/tmp/homepublish-r5-evidence
mkdir -p "$e"; chmod 700 "$e"
test ! -e /etc/homepublish/device-test
. /usr/share/homevpn/acme-resolve.sh
homevpn_acme_resolve home.iwonderful.top rsa
before=$(sha256sum "$HV_ACME_CRT" "$HV_ACME_KEY"; ls -ln "$HV_ACME_CRT" "$HV_ACME_KEY")
openssl x509 -in "$HV_ACME_CRT" -noout -subject -issuer -dates -ext subjectAltName
/etc/init.d/homepublish stop
cp /etc/homepublish/product/state "$e/state.backup"
cleanup() {
 lua -e "package.path='/usr/share/homepublish/?.lua;'..package.path;assert(require('product-device-provider').stop())" || true
 test -z "${client:-}" || kill "$client" 2>/dev/null || true
 test -z "${backend:-}" || kill "$backend" 2>/dev/null || true
 test -z "${backend2:-}" || kill "$backend2" 2>/dev/null || true
 rm -rf /etc/homepublish/device-test "$e/www" "$e/www2"
 cp "$e/state.backup" /etc/homepublish/product/state; chmod 600 /etc/homepublish/product/state
 /etc/init.d/homepublish start
}
trap cleanup EXIT INT TERM
mkdir -p /etc/homepublish/device-test "$e/www"; chmod 700 /etc/homepublish/device-test
touch /etc/homepublish/device-test/enabled
printf 'HP_R5_BUSINESS_TLS_A\n' >"$e/www/index.html"
/usr/sbin/uhttpd -f -p 127.0.0.1:49285 -h "$e/www" >"$e/backend.log" 2>&1 & backend=$!
mkdir -p "$e/www2"; printf 'HP_R5_BUSINESS_TLS_B\n' >"$e/www2/index.html"
/usr/sbin/uhttpd -f -p 127.0.0.1:49286 -h "$e/www2" >"$e/backend2.log" 2>&1 & backend2=$!
sleep 1
lua - <<'LUA'
package.path='/usr/share/homepublish/?.lua;'..package.path
local P=require('product-provider');local D=require('product-device-provider');local C=require('product-controller').new(D)
local c={schema_version=1,services={{name='Business certificate loopback',service_id='fixture',hostname='home.iwonderful.top',certificate_ref='acme:home_rsa',backend={addressFamily='ipv4',host='127.0.0.1',port=49285,allowed_ranges={'127.0.0.0/8'}},authentication_review={authentication='confirmed',management=false}}},access_profile={methods_allowed={'manual_ipv4'},listeners={{family='ipv4',address='192.168.1.2',interface='br-lan',zone='lan',protocol='tcp',internal_port=49284,external_port=49284}}},publication_policy={mode='continuous',boot_restore=false}}
local base=assert(P.handle({action='status'}));local s=assert(P.handle({action='save',expected_revision=base.saved_revision,config=c}));local r=C.start(s.saved_revision,true);assert(r.runtime.phase=='running',r.runtime.last_error)
local function marker(expected)
 local f=assert(io.popen("env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --connect-timeout 2 --max-time 5 --resolve home.iwonderful.top:49284:127.0.0.1 --fail --silent --show-error https://home.iwonderful.top:49284/"));local text=f:read('*a');f:close();assert(text:find(expected,1,true),text);print('PASS system CA + hostname '..expected)
end
marker('HP_R5_BUSINESS_TLS_A')
assert(os.execute("ls -ld /tmp/homepublish-device/runtime; ls -l /tmp/homepublish-device/runtime/*.pem; ps | grep '[n]ginx'")==0)
c.services[1].name='Pending business certificate';c.services[1].backend.port=49286;s=assert(P.handle({action='save',expected_revision=s.saved_revision,config=c}));assert(C.status().active_revision~=s.saved_revision);marker('HP_R5_BUSINESS_TLS_A');r=C.apply(s.saved_revision,true);assert(r.runtime.phase=='running',r.runtime.last_error);marker('HP_R5_BUSINESS_TLS_B')
print('PASS canonical Start Save-pending Apply business TLS')
LUA
openssl s_client -connect 127.0.0.1:49284 -servername home.iwonderful.top -verify_hostname home.iwonderful.top -verify_return_error -quiet -ign_eof </dev/null >"$e/old-connection.log" 2>&1 & client=$!
sleep 2
kill -0 "$client"
lua - <<'LUA'
package.path='/usr/share/homepublish/?.lua;'..package.path
local C=require('product-controller').new(require('product-device-provider'));assert(C.stop().runtime.cleanup=='confirmed');assert(C.stop().runtime.cleanup=='confirmed');print('PASS duplicate canonical Stop')
LUA
sleep 1
if kill -0 "$client" 2>/dev/null; then echo 'FAIL old TLS connection retained'; exit 1; fi
if curl -q --noproxy '*' --connect-timeout 1 --max-time 2 --resolve home.iwonderful.top:49284:127.0.0.1 --silent https://home.iwonderful.top:49284/; then echo 'FAIL new TLS connection'; exit 1; fi
test ! -e /tmp/homepublish-device/runtime
homevpn_acme_resolve home.iwonderful.top rsa
after=$(sha256sum "$HV_ACME_CRT" "$HV_ACME_KEY"; ls -ln "$HV_ACME_CRT" "$HV_ACME_KEY")
test "$before" = "$after"
echo 'PASS source certificate/key hash + permissions equal (server-only); old connection closed/new refused; private snapshot removed'
