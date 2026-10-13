#!/bin/sh
# Run only in an isolated target chroot. Real target UCI/Lua/procd JSON builder;
# ubus transport deliberately replaced, never submit/start a real service.
set -e
. /etc/init.d/homestun
initscript=/etc/init.d/homestun
flock() { :; } # Fixture-only lock transport; no host locks.
. /lib/functions/procd.sh
ubus() { printf '%s\n' "$4" > /tmp/registration.json; }
setuci() { uci set "homestun.main.$1=$2"; uci commit homestun; }
register() {
 rm -f /tmp/registration.json
 procd_open_service homestun-uci-fixture
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
setuci router_token_file /etc/homestun/router.token
# Already set fixed reference in UCI fixture, but no credential yet.
reject missing-token
printf '%s' AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > /etc/homestun/router.token
chmod 600 /etc/homestun/router.token
/usr/libexec/homestun-lease --check-publication /etc/homestun/router.token
register
command=$(jsonfilter -i /tmp/registration.json -e '@.instances.lease.command[*]')
[ "$command" = "$(printf '%s\n' /usr/libexec/homestun-lease --provision 60 18444 18443 turn.cloudflare.com example.com publish)" ]
[ -z "$(jsonfilter -i /tmp/registration.json -e '@.instances.lease.respawn')" ]
[ -z "$(jsonfilter -i /tmp/registration.json -e '@.triggers[*]')" ]
[ "$(lua /usr/share/homestun/config-cli.lua status)" = '{"state":"configured","publication":"configured","mapped":"unknown","reachable":"unverified"}' ]
echo 'PASS opt-in exact native command; bounded TTL; no respawn/triggers; honest status'
mv /usr/bin/curl /usr/bin/curl.save;reject missing-curl;mv /usr/bin/curl.save /usr/bin/curl
mv /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca.save;reject missing-ca;mv /etc/ssl/certs/ca.save /etc/ssl/certs/ca-certificates.crt
mv /usr/libexec/homestun-publish /usr/libexec/publish.save;reject missing-publisher;mv /usr/libexec/publish.save /usr/libexec/homestun-publish
chmod 644 /etc/homestun/router.token;reject public-token;chmod 600 /etc/homestun/router.token
chown 1000 /etc/homestun/router.token;reject owner;chown 0 /etc/homestun/router.token
ln /etc/homestun/router.token /etc/homestun/hardlink;reject hardlink;rm /etc/homestun/hardlink
mv /etc/homestun/router.token /etc/homestun/original;ln -s original /etc/homestun/router.token;reject symlink;rm /etc/homestun/router.token;mv /etc/homestun/original /etc/homestun/router.token
printf '%s' short > /etc/homestun/router.token;reject short-token
printf '%s\n' AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > /etc/homestun/router.token;reject newline-token
printf '%0130d' 0 > /etc/homestun/router.token;reject oversized-token
printf '%s' AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > /etc/homestun/router.token
chmod 755 /etc/homestun;reject public-parent;chmod 700 /etc/homestun
chmod 644 /etc/homestun/key.pem;reject public-key;chmod 600 /etc/homestun/key.pem
mv /etc/homestun/cert.pem /etc/homestun/cert.save;reject missing-cert;mv /etc/homestun/cert.save /etc/homestun/cert.pem
setuci router_token_file /tmp/token;reject wrong-path
setuci router_token_file /etc/homestun/router.token
setuci ttl 121;reject ttl-overflow;setuci ttl 60
setuci router_token plaintext;reject plaintext;uci delete homestun.main.router_token;uci commit homestun
setuci publication_enabled 0
rm /etc/homestun/router.token
register
[ "$(jsonfilter -i /tmp/registration.json -e '@.instances.lease.command[*]')" = "$(printf '%s\n' /usr/libexec/homestun-lease --provision 60 18444 18443 turn.cloudflare.com example.com)" ]
echo 'PASS publication disabled legacy command; no secret needed'
uci delete homestun.main.publication_enabled;uci delete homestun.main.router_token_file;uci commit homestun
register
echo 'PASS absent new options legacy registration'
[ ! -e /tmp/engine-ran ]
for d in /tmp/homestun-service-*; do [ ! -e "$d" ]; done
echo 'PASS registration read-only: no engine/runtime/snapshot/network'
