#!/bin/sh
# Run only in an isolated target chroot. Real target UCI/Lua/procd JSON builder;
# ubus transport deliberately replaced, never submit/start a real service.
set -e
. /etc/init.d/homepublish
initscript=/etc/init.d/homepublish
flock() { :; } # Fixture-only lock transport; no host locks.
. /lib/functions/procd.sh
ubus() { printf '%s\n' "$4" > /tmp/registration.json; }
setuci() { uci set "homepublish.main.$1=$2"; uci commit homepublish; }
register() {
 rm -f /tmp/registration.json
 procd_open_service homepublish-uci-fixture
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
setuci router_token_file /etc/homepublish/router.token
# Already set fixed reference in UCI fixture, but no credential yet.
reject missing-token
printf '%s' AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > /etc/homepublish/router.token
chmod 600 /etc/homepublish/router.token
/usr/libexec/homepublish-lease --check-publication /etc/homepublish/router.token
register
command=$(jsonfilter -i /tmp/registration.json -e '@.instances.lease.command[*]')
[ "$command" = "$(printf '%s\n' /usr/libexec/homepublish-lease --provision 60 18444 18443 turn.cloudflare.com example.com publish)" ]
[ -z "$(jsonfilter -i /tmp/registration.json -e '@.instances.lease.respawn')" ]
[ -z "$(jsonfilter -i /tmp/registration.json -e '@.triggers[*]')" ]
[ "$(lua /usr/share/homepublish/config-cli.lua status)" = '{"state":"configured","publication":"configured","mapped":"unknown","reachable":"unverified"}' ]
echo 'PASS opt-in exact native command; bounded TTL; no respawn/triggers; honest status'
mv /usr/bin/curl /usr/bin/curl.save;reject missing-curl;mv /usr/bin/curl.save /usr/bin/curl
mv /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca.save;reject missing-ca;mv /etc/ssl/certs/ca.save /etc/ssl/certs/ca-certificates.crt
mv /usr/libexec/homepublish-publish /usr/libexec/publish.save;reject missing-publisher;mv /usr/libexec/publish.save /usr/libexec/homepublish-publish
chmod 644 /etc/homepublish/router.token;reject public-token;chmod 600 /etc/homepublish/router.token
chown 1000 /etc/homepublish/router.token;reject owner;chown 0 /etc/homepublish/router.token
ln /etc/homepublish/router.token /etc/homepublish/hardlink;reject hardlink;rm /etc/homepublish/hardlink
mv /etc/homepublish/router.token /etc/homepublish/original;ln -s original /etc/homepublish/router.token;reject symlink;rm /etc/homepublish/router.token;mv /etc/homepublish/original /etc/homepublish/router.token
printf '%s' short > /etc/homepublish/router.token;reject short-token
printf '%s\n' AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > /etc/homepublish/router.token;reject newline-token
printf '%0130d' 0 > /etc/homepublish/router.token;reject oversized-token
printf '%s' AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > /etc/homepublish/router.token
chmod 755 /etc/homepublish;reject public-parent;chmod 700 /etc/homepublish
chmod 644 /etc/homepublish/key.pem;reject public-key;chmod 600 /etc/homepublish/key.pem
mv /etc/homepublish/cert.pem /etc/homepublish/cert.save;reject missing-cert;mv /etc/homepublish/cert.save /etc/homepublish/cert.pem
setuci router_token_file /tmp/token;reject wrong-path
setuci router_token_file /etc/homepublish/router.token
setuci ttl 121;reject ttl-overflow;setuci ttl 60
setuci router_token plaintext;reject plaintext;uci delete homepublish.main.router_token;uci commit homepublish
setuci publication_enabled 0
rm /etc/homepublish/router.token
register
[ "$(jsonfilter -i /tmp/registration.json -e '@.instances.lease.command[*]')" = "$(printf '%s\n' /usr/libexec/homepublish-lease --provision 60 18444 18443 turn.cloudflare.com example.com)" ]
echo 'PASS publication disabled legacy command; no secret needed'
uci delete homepublish.main.publication_enabled;uci delete homepublish.main.router_token_file;uci commit homepublish
register
echo 'PASS absent new options legacy registration'
[ ! -e /tmp/engine-ran ]
for d in /tmp/homepublish-service-*; do [ ! -e "$d" ]; done
echo 'PASS registration read-only: no engine/runtime/snapshot/network'
