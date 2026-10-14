#!/bin/sh
set -eu
e=/tmp/homepublish-r7-evidence
for p in /etc/homepublish/device-test '/etc/acme/*.fixture.home' '/etc/acme/*.fixture.home_ecc'; do test ! -e "$p"; done
uci -q get acme.fixture_rsa && exit 1 || true
uci -q get acme.fixture_ecc && exit 1 || true
cp /etc/config/acme "$e/acme.before"
mkdir -p /etc/homepublish/device-test "$e/www" "$e/www2" '/etc/acme/*.fixture.home' '/etc/acme/*.fixture.home_ecc'
chmod 700 /etc/homepublish/device-test '/etc/acme/*.fixture.home' '/etc/acme/*.fixture.home_ecc'
touch /etc/homepublish/device-test/enabled
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=wrong.invalid -addext 'subjectAltName=DNS:*.fixture.home,DNS:fixture.home' -keyout '/etc/acme/*.fixture.home/*.fixture.home.key' -out '/etc/acme/*.fixture.home/fullchain.cer' >"$e/rsa.log" 2>&1
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj /CN=wrong.invalid -addext 'subjectAltName=DNS:*.fixture.home,DNS:fixture.home' -keyout '/etc/acme/*.fixture.home_ecc/*.fixture.home.key' -out '/etc/acme/*.fixture.home_ecc/fullchain.cer' >"$e/ecc.log" 2>&1
chmod 600 /etc/acme/\*.fixture.home*/*
uci set acme.fixture_rsa=cert
uci set 'acme.fixture_rsa.domains=*.fixture.home'
uci set acme.fixture_rsa.key_type=rsa2048
uci set acme.fixture_ecc=cert
uci set 'acme.fixture_ecc.domains=*.fixture.home'
uci set acme.fixture_ecc.key_type=ec256
uci commit acme
printf 'HP_R7_A\n' >"$e/www/index.html"
printf 'HP_R7_B\n' >"$e/www2/index.html"
uhttpd -f -p 127.0.0.1:49285 -h "$e/www" >"$e/backend.log" 2>&1 & echo $! >"$e/backend.pid"
uhttpd -f -p 127.0.0.1:49286 -h "$e/www2" >"$e/backend2.log" 2>&1 & echo $! >"$e/backend2.pid"
/etc/init.d/homepublish start
sleep 2
ubus call homepublish status
