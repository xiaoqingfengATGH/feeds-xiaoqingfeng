#!/bin/sh
# Run only in an isolated target chroot. Real target UCI/Lua/procd JSON builder;
# ubus transport deliberately replaced, never submit/start a real service.
set -e
. /etc/init.d/homedirect
initscript=/etc/init.d/homedirect
flock() { :; } # Fixture-only lock transport; no host locks.
. /lib/functions/procd.sh
ubus() { printf '%s\n' "$4" > /tmp/registration.json; }
setuci() { uci set "homedirect.main.$1=$2"; uci commit homedirect; }
register() {
 rm -f /tmp/registration.json
 procd_open_service homedirect-uci-fixture
 if start_service; then procd_close_service || return 1; return 0; else return 1; fi
}
reject() {
 if register; then echo "FAIL accepted $1"; exit 1; fi
 [ ! -e /tmp/registration.json ]
 echo "PASS fail before registration: $1"
}
register
[ -z "$(jsonfilter -i /tmp/registration.json -e '@.instances.*.command')" ]
echo 'PASS disabled zero instances'
setuci enabled 1
reject unapproved
setuci exposure_approved 1
setuci publication_enabled 1
setuci router_token_file /etc/homedirect/router.token
# Already set fixed reference in UCI fixture, but no credential yet.
reject missing-token
printf '%s' AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > /etc/homedirect/router.token
chmod 600 /etc/homedirect/router.token
/usr/libexec/homedirect-lease --check-publication /etc/homedirect/router.token
register
command=$(jsonfilter -i /tmp/registration.json -e '@.instances.lease.command[*]')
[ "$command" = "$(printf '%s\n' /usr/libexec/homedirect-lease --provision 60 18444 18443 turn.cloudflare.com example.com publish)" ]
[ -z "$(jsonfilter -i /tmp/registration.json -e '@.instances.lease.respawn')" ]
[ -z "$(jsonfilter -i /tmp/registration.json -e '@.triggers[*]')" ]
[ "$(lua /usr/share/homedirect/config-cli.lua status)" = '{"state":"configured","publication":"configured","mapped":"unknown","reachable":"unverified"}' ]
echo 'PASS opt-in exact native command; bounded TTL; no respawn/triggers; honest status'
mv /usr/bin/curl /usr/bin/curl.save;reject missing-curl;mv /usr/bin/curl.save /usr/bin/curl
mv /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca.save;reject missing-ca;mv /etc/ssl/certs/ca.save /etc/ssl/certs/ca-certificates.crt
mv /usr/libexec/homedirect-publish /usr/libexec/publish.save;reject missing-publisher;mv /usr/libexec/publish.save /usr/libexec/homedirect-publish
chmod 644 /etc/homedirect/router.token;reject public-token;chmod 600 /etc/homedirect/router.token
chown 1000 /etc/homedirect/router.token;reject owner;chown 0 /etc/homedirect/router.token
ln /etc/homedirect/router.token /etc/homedirect/hardlink;reject hardlink;rm /etc/homedirect/hardlink
mv /etc/homedirect/router.token /etc/homedirect/original;ln -s original /etc/homedirect/router.token;reject symlink;rm /etc/homedirect/router.token;mv /etc/homedirect/original /etc/homedirect/router.token
printf '%s' short > /etc/homedirect/router.token;reject short-token
printf '%s\n' AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > /etc/homedirect/router.token;reject newline-token
printf '%0130d' 0 > /etc/homedirect/router.token;reject oversized-token
printf '%s' AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > /etc/homedirect/router.token
chmod 755 /etc/homedirect;reject public-parent;chmod 700 /etc/homedirect
chmod 644 /etc/homedirect/key.pem;reject public-key;chmod 600 /etc/homedirect/key.pem
mv /etc/homedirect/cert.pem /etc/homedirect/cert.save;reject missing-cert;mv /etc/homedirect/cert.save /etc/homedirect/cert.pem
setuci router_token_file /tmp/token;reject wrong-path
setuci router_token_file /etc/homedirect/router.token
setuci ttl 121;reject ttl-overflow;setuci ttl 60
setuci router_token plaintext;reject plaintext;uci delete homedirect.main.router_token;uci commit homedirect
setuci publication_enabled 0
rm /etc/homedirect/router.token
register
[ "$(jsonfilter -i /tmp/registration.json -e '@.instances.lease.command[*]')" = "$(printf '%s\n' /usr/libexec/homedirect-lease --provision 60 18444 18443 turn.cloudflare.com example.com)" ]
echo 'PASS publication disabled legacy command; no secret needed'
uci delete homedirect.main.publication_enabled;uci delete homedirect.main.router_token_file;uci commit homedirect
register
echo 'PASS absent new options legacy registration'
[ ! -e /tmp/engine-ran ]
for d in /tmp/homedirect-service-*; do [ ! -e "$d" ]; done
echo 'PASS registration read-only: no engine/runtime/snapshot/network'
