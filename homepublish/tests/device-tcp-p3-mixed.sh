#!/bin/sh
# Device-only isolated P3 task16. No journal mutation, init restart or firewall.
set -eu
ROOT=/tmp/homepublish-tcp-p3
R="$ROOT/mixed-runtime"
E="$ROOT/mixed-evidence"
NG="$ROOT/nginx-private"
mkdir -p "$E"; chmod 700 "$ROOT" "$E"
test ! -e "$R"
PIDS=''; FRONT=''; SOURCE_BEFORE=''; CERT=''; KEY=''
read_source() { sha256sum "$CERT" "$KEY"; ls -lnL "$CERT" "$KEY"; }
stop_owned() {
 p="$1"; kill "$p" 2>/dev/null || true
 for n in 1 2 3 4 5; do
  if ! kill -0 "$p" 2>/dev/null; then wait "$p" 2>/dev/null || true; return 0; fi
  sleep 1
 done
 kill -KILL "$p" 2>/dev/null || true
 sleep 1
 if kill -0 "$p" 2>/dev/null; then return 1; fi
 wait "$p" 2>/dev/null || true
}
stop_front() {
 if [ -n "$FRONT" ]; then stop_owned "$FRONT" || return 1; FRONT=''; fi
}
cleanup() {
 rc=$?; trap - EXIT INT TERM
 residual=0
 stop_front || residual=1
 for p in $PIDS; do stop_owned "$p" || residual=1; done
 for p in /proc/[0-9]*/exe; do
  [ "$(readlink "$p" 2>/dev/null || true)" != "$NG" ] || residual=1
 done
 for p in $PIDS; do ! kill -0 "$p" 2>/dev/null || residual=1; done
 if [ -n "$SOURCE_BEFORE" ]; then
  if [ "$SOURCE_BEFORE" = "$(read_source)" ]; then echo 'PASS business source certificate/key SHA256 + uid/gid/mode preserved (server-only comparison)'; else echo 'FAIL business source preservation'; rc=1; fi
 fi
 if [ "$residual" = 0 ]; then
  rm -rf "$R"; test ! -e "$R"; echo 'PASS private processes exited; all snapshots + fixture keys removed'
 else echo 'FAIL owned process residual; retaining runtime for owner cleanup'; rc=1; fi
 sha256sum /etc/homepublish/product/state /etc/config/firewall /etc/config/dropbear /etc/config/uhttpd /etc/config/passwall2 /usr/sbin/nginx >"$E/immutable-after.txt"
 if cmp -s "$E/immutable-before.txt" "$E/immutable-after.txt"; then echo 'PASS live journal + firewall/management/proxy configs + system nginx unchanged'; else echo 'FAIL immutable baseline mismatch'; rc=1; fi
 netstat -lntp >"$E/listeners-after.txt"
 if grep -E ':(49543|49544|49545|49546|49549)[[:space:]]' "$E/listeners-after.txt"; then echo 'FAIL test listener residual'; rc=1; fi
 exit "$rc"
}
sha256sum /etc/homepublish/product/state /etc/config/firewall /etc/config/dropbear /etc/config/uhttpd /etc/config/passwall2 /usr/sbin/nginx >"$E/immutable-before.txt"
netstat -lntp >"$E/listeners-before.txt"
! grep -E ':(49543|49544|49545|49546|49549)[[:space:]]' "$E/listeners-before.txt"
trap cleanup EXIT INT TERM
umask 077; mkdir "$R" "$R/www"
# Read-only, self-contained HomePublish ACME resolver. Paths only, never key bytes.
set -- $(lua -e "package.path='$ROOT/?.lua;/usr/share/homepublish/?.lua;'..package.path; local s=assert(require('device-integrations').certificate_source('acme:home_rsa','home.iwonderful.top')); print(s.certificate,s.key)")
CERT="$1"; KEY="$2"; SOURCE_BEFORE=$(read_source)
cp "$CERT" "$R/cert.pem"; cp "$KEY" "$R/key.pem"; chmod 600 "$R/cert.pem" "$R/key.pem"
lua -e "local fs=require('nixio').fs;for _,p in ipairs({'$R/cert.pem','$R/key.pem'}) do local s=assert(fs.stat(p));assert(s.uid==0 and s.modestr=='rw-------',s.modestr) end;local s=assert(fs.stat('$R'));assert(s.uid==0 and s.modestr=='rwx------',s.modestr);print('PASS private snapshot uid0 mode0600 / runtime0700')"
lua "$ROOT/device-tcp-p3-mixed-render.lua" "$ROOT"
# All following certificates are labelled fixtures; no trust store mutation.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=P3_FIXTURE_CA -keyout "$R/ca.key" -out "$R/ca.pem" >"$E/fixture-generation.log" 2>&1
openssl req -newkey rsa:2048 -nodes -subj /CN=tls.fixture.home -keyout "$R/tls.key" -out "$R/tls.csr" >>"$E/fixture-generation.log" 2>&1
printf 'subjectAltName=DNS:tls.fixture.home\nextendedKeyUsage=serverAuth\n' >"$R/ext"
openssl x509 -req -in "$R/tls.csr" -CA "$R/ca.pem" -CAkey "$R/ca.key" -CAcreateserial -days 1 -extfile "$R/ext" -out "$R/tls.pem" >>"$E/fixture-generation.log" 2>&1
openssl req -newkey rsa:2048 -nodes -subj /CN=P3_FIXTURE_CLIENT -keyout "$R/client.key" -out "$R/client.csr" >>"$E/fixture-generation.log" 2>&1
openssl x509 -req -in "$R/client.csr" -CA "$R/ca.pem" -CAkey "$R/ca.key" -CAcreateserial -days 1 -out "$R/client.pem" >>"$E/fixture-generation.log" 2>&1
cat >"$R/backend.conf" <<EOF
worker_processes 1; daemon off; pid backend.pid; error_log $E/backend-error.log error;
events { worker_connections 32; }
http {
access_log off; client_body_temp_path body; proxy_temp_path proxy; fastcgi_temp_path fastcgi; uwsgi_temp_path uwsgi; scgi_temp_path scgi;
server { listen 127.0.0.1:49545; return 200 'HP_P3_MIXED_WEB|\$http_x_real_ip|\$http_x_forwarded_for'; }
server { listen 127.0.0.1:49546 ssl; server_name tls.fixture.home; ssl_certificate $R/tls.pem; ssl_certificate_key $R/tls.key; ssl_client_certificate $R/ca.pem; ssl_verify_client on;
location / { return 200 'HP_P3_END_TO_END_MTLS|\$ssl_client_s_dn|\$ssl_client_verify'; } }
}
EOF
chmod 700 "$ROOT/sslh-select.private"
for config in backend front; do
 OPENSSL_CONF=/dev/null "$NG" -e stderr -t -p "$R/" -c "$config.conf" >"$E/$config-config.log" 2>&1
 OPENSSL_CONF=/dev/null "$NG" -e stderr -p "$R/" -c "$config.conf" >"$E/$config-process.log" 2>&1 & PIDS="$PIDS $!"
done
"$ROOT/sslh-select.private" -F "$R/sslh.cfg" >"$E/sslh-process.log" 2>&1 & FRONT=$!
sleep 1; kill -0 "$FRONT"
fetch() { env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --connect-timeout 2 --max-time 5 --silent --show-error "$@"; }
fetch --fail --resolve 'home.iwonderful.top:49543:[::1]' -H 'X-Real-IP: 203.0.113.9' -H 'X-Forwarded-For: 203.0.113.9' https://home.iwonderful.top:49543/ >"$E/web-response.txt"
grep -qx 'HP_P3_MIXED_WEB|::1|::1' "$E/web-response.txt"
echo 'PASS mixed HTTPS business systemCA/hostname + exact PROXY identity; forged headers replaced'
fetch --fail --cacert "$R/ca.pem" --cert "$R/client.pem" --key "$R/client.key" --resolve 'tls.fixture.home:49543:[::1]' https://tls.fixture.home:49543/ >"$E/mtls-response.txt"
grep -qx 'HP_P3_END_TO_END_MTLS|CN=P3_FIXTURE_CLIENT|SUCCESS' "$E/mtls-response.txt"
echo 'PASS end-to-end backend TLS hostname/fixtureCA + original client mTLS identity (no PROXY to backend)'
# Backend certificate is identical direct versus passthrough, public cert only.
: >"$E/backend-cert-fingerprints.txt"
for endpoint in '[::1]:49543' '127.0.0.1:49546'; do
 timeout 5 openssl s_client -connect "$endpoint" -servername tls.fixture.home -showcerts </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256 >>"$E/backend-cert-fingerprints.txt"
done
test "$(wc -l <"$E/backend-cert-fingerprints.txt")" = 2
test "$(sort -u "$E/backend-cert-fingerprints.txt" | wc -l)" = 1
echo 'PASS backend certificate fingerprint unchanged through passthrough'
code=$(fetch --cacert "$R/ca.pem" --resolve 'tls.fixture.home:49543:[::1]' -o "$E/no-client-response.txt" -w '%{http_code}' https://tls.fixture.home:49543/)
test "$code" = 400; ! grep -q HP_P3_END_TO_END_MTLS "$E/no-client-response.txt"
echo 'PASS backend mTLS denies missing client certificate, no business marker'
for host in unknown.fixture.home tls.fixture.home.evil; do
 if fetch -k --resolve "$host:49543:[::1]" "https://$host:49543/" >"$E/$host-response.txt" 2>"$E/$host-error.txt"; then exit 1; fi
 test ! -s "$E/$host-response.txt"
done
timeout 5 openssl s_client -connect '[::1]:49543' -noservername </dev/null >"$E/no-sni.txt" 2>&1 || true
grep -q 'no peer certificate available' "$E/no-sni.txt"
lua "$ROOT/device-tcp-p3-reject.lua"
echo 'PASS unknown/suffix SNI + no SNI + unrecognized + idle timeout rejected without business fallback'
netstat -lntp >"$E/listeners-running.txt"
sha256sum "$ROOT/direct-renderer.lua" "$ROOT/tcp-route-plan.lua" "$ROOT/sslh-renderer.lua" "$ROOT/device-tcp-p3-mixed-render.lua" "$ROOT/device-tcp-p3-mixed.sh" "$ROOT/device-tcp-p3-reject.lua" "$ROOT/sslh-select.private" >"$E/source-sha256.txt"
echo P3_TASK17_ISOLATED_GREEN
