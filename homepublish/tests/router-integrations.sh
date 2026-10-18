#!/bin/sh
set -eu
p=${1:-/usr/share/homepublish}
e=/tmp/homepublish-r4-evidence
mkdir -p "$e"; chmod 700 "$e"
test ! -e /etc/homepublish/device-test
cleanup() {
 /etc/init.d/homepublish-nginx stop || true
 test -z "${backend:-}" || kill "$backend" 2>/dev/null || true
 rm -rf /etc/homepublish/device-test /tmp/homepublish-device/runtime "$e/www"
}
trap cleanup EXIT INT TERM
mkdir -p /etc/homepublish/device-test "$e/www"
chmod 700 /etc/homepublish/device-test
printf 'HP_R4_DNS_TLS_MARKER\n' >"$e/www/index.html"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=service.home -addext subjectAltName=DNS:service.home -keyout /etc/homepublish/device-test/key.pem -out /etc/homepublish/device-test/cert.pem >"$e/openssl.log" 2>&1
chmod 600 /etc/homepublish/device-test/*.pem
touch /etc/homepublish/device-test/enabled
/usr/sbin/uhttpd -f -p 127.0.0.1:49285 -h "$e/www" >"$e/backend.log" 2>&1 & backend=$!
sleep 1
lua - "$p" <<'LUA'
package.path=arg[1]..'/?.lua;/usr/share/homepublish/?.lua;'..package.path
local P=require('product-device-provider')
local c={services={{service_id='fixture',hostname='service.home',certificate_ref='import:fixture',backend={addressFamily='ipv4',host='127.0.0.1',port=49285,allowed_ranges={'127.0.0.0/8'}},authentication_review={authentication='confirmed',management=false}}},access_profile={methods_allowed={'manual_ipv4'},listeners={{family='ipv4',address='192.168.1.2',interface='br-lan',zone='lan',protocol='tcp',internal_port=49284,external_port=49284}}}}
if os.getenv('HP_TEST_DNS')=='1' then c.services[1].backend={addressFamily='hostname',host='localhost.lan',port=49285,allowed_ranges={'127.0.0.0/8','::1/128'}} end
local plan,e=P.plan(c);assert(plan,e);assert(P.start(plan,1,0));assert(P.readiness())
assert(os.execute("curl -q --noproxy '*' --cacert /etc/homepublish/device-test/cert.pem --resolve service.home:49284:127.0.0.1 --fail --silent https://service.home:49284/")==0)
assert(os.execute('openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=service.home -addext subjectAltName=DNS:service.home -keyout /etc/homepublish/device-test/newkey.pem -out /etc/homepublish/device-test/newcert.pem >/tmp/homepublish-r4-evidence/replace.log 2>&1 && chmod 600 /etc/homepublish/device-test/new*.pem && mv /etc/homepublish/device-test/newkey.pem /etc/homepublish/device-test/key.pem && mv /etc/homepublish/device-test/newcert.pem /etc/homepublish/device-test/cert.pem')==0)
os.execute('sleep 31')
assert(not P.renew(),'certificate refresh failed to invalidate active generation')
assert(P.stop());plan=assert(P.plan(c));assert(P.start(plan,2,0));assert(P.readiness());assert(P.stop())
print('PASS actual TLS and controlled replacement re-readiness/Stop')
LUA
