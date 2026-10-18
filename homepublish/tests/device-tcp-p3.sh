#!/bin/sh
# Device-only isolated P3 task16. No journal mutation, init restart or firewall.
set -eu
ROOT=/tmp/homepublish-tcp-p3
R="$ROOT/runtime"
E="$ROOT/evidence"
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
 if grep -E ':(49443|49445|49446|49447)[[:space:]]' "$E/listeners-after.txt"; then echo 'FAIL test listener residual'; rc=1; fi
 exit "$rc"
}
sha256sum /etc/homepublish/product/state /etc/config/firewall /etc/config/dropbear /etc/config/uhttpd /etc/config/passwall2 /usr/sbin/nginx >"$E/immutable-before.txt"
netstat -lntp >"$E/listeners-before.txt"
! grep -E ':(49443|49445|49446|49447)[[:space:]]' "$E/listeners-before.txt"
trap cleanup EXIT INT TERM
umask 077; mkdir "$R" "$R/www"
# Read-only, self-contained HomePublish ACME resolver. Paths only, never key bytes.
set -- $(lua -e "package.path='$ROOT/?.lua;/usr/share/homepublish/?.lua;'..package.path; local s=assert(require('device-integrations').certificate_source('acme:home_rsa','home.iwonderful.top')); print(s.certificate,s.key)")
CERT="$1"; KEY="$2"; SOURCE_BEFORE=$(read_source)
cp "$CERT" "$R/cert.pem"; cp "$KEY" "$R/key.pem"; chmod 600 "$R/cert.pem" "$R/key.pem"
lua -e "local fs=require('nixio').fs;for _,p in ipairs({'$R/cert.pem','$R/key.pem'}) do local s=assert(fs.stat(p));assert(s.uid==0 and s.modestr=='rw-------',s.modestr) end;local s=assert(fs.stat('$R'));assert(s.uid==0 and s.modestr=='rwx------',s.modestr);print('PASS private snapshot uid0 mode0600 / runtime0700')"
lua "$ROOT/device-tcp-p3-render.lua" "$ROOT"
lua "$ROOT/device-tcp-p3-https-matrix-render.lua" "$ROOT"
# All backend sockets are owned by the private Nginx fixture (no installed uhttpd changes).
# Untrusted server certificate remains a fixture: never copied into system trust.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=home.iwonderful.top -addext subjectAltName=DNS:home.iwonderful.top -keyout "$R/untrusted.key" -out "$R/untrusted.pem" >"$E/fixture-generation.log" 2>&1
cat >"$R/backend.conf" <<EOF
worker_processes 1;
daemon off;
pid backend.pid;
error_log $E/backend-error.log error;
events { worker_connections 32; }
http {
 access_log off;
 client_body_temp_path body; proxy_temp_path proxy; fastcgi_temp_path fastcgi; uwsgi_temp_path uwsgi; scgi_temp_path scgi;
 server { listen 127.0.0.1:49445; server_name home.iwonderful.top; return 200 'HP_P3_IPV6_TO_IPV4_HTTP_MARKER'; }
 server { listen 127.0.0.1:49446 ssl; server_name home.iwonderful.top; ssl_certificate $R/cert.pem; ssl_certificate_key $R/key.pem; return 200 'HP_P3_VERIFIED_HTTPS_UPSTREAM'; }
 server { listen [::1]:49445 ipv6only=on; server_name home.iwonderful.top; return 200 'HP_P3_IPV6_BACKEND_HTTP'; }
 server { listen [::1]:49446 ssl ipv6only=on; server_name home.iwonderful.top; ssl_certificate $R/cert.pem; ssl_certificate_key $R/key.pem; return 200 'HP_P3_IPV6_BACKEND_HTTPS'; }
 server { listen 127.0.0.1:49447 ssl; server_name home.iwonderful.top; ssl_certificate $R/untrusted.pem; ssl_certificate_key $R/untrusted.key; return 200 'MUST_NOT_REACH_UNTRUSTED_MARKER'; }
}
EOF
OPENSSL_CONF=/dev/null "$NG" -e stderr -t -p "$R/" -c backend.conf >"$E/backend-config.log" 2>&1
OPENSSL_CONF=/dev/null "$NG" -e stderr -p "$R/" -c backend.conf >"$E/backend-process.log" 2>&1 & PIDS="$PIDS $!"
fetch() {
 env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --connect-timeout 2 --max-time 5 --resolve 'home.iwonderful.top:49443:[::1]' --silent --show-error "$@" https://home.iwonderful.top:49443/
}
start_front() {
 OPENSSL_CONF=/dev/null "$NG" -e stderr -t -p "$R/" -c "$1.conf" >"$E/$1-config.log" 2>&1
 OPENSSL_CONF=/dev/null "$NG" -e stderr -p "$R/" -c "$1.conf" >"$E/$1-process.log" 2>&1 & FRONT=$!
 sleep 1; kill -0 "$FRONT"
}
start_front http
fetch --fail >"$E/http-response.txt"
grep -qx HP_P3_IPV6_TO_IPV4_HTTP_MARKER "$E/http-response.txt"
echo 'PASS actual [::1]:49443 HTTPS system-CA + hostname -> 127.0.0.1:49445 HTTP exact marker'
netstat -lntp >"$E/listeners-running.txt"
stop_front
start_front https
fetch --fail >"$E/https-response.txt"
grep -qx HP_P3_VERIFIED_HTTPS_UPSTREAM "$E/https-response.txt"
echo 'PASS HTTPS upstream system-CA + explicit hostname/SNI verified marker'
stop_front
start_front wrong-name
code=$(fetch --output "$E/wrong-name-response.txt" --write-out '%{http_code}')
test "$code" = 502
grep -q 'does not match' "$E/wrong-name-process.log"
echo 'PASS HTTPS upstream wrong verify-name rejected (502 + name mismatch TLS error)'
stop_front
start_front untrusted
code=$(fetch --output "$E/untrusted-response.txt" --write-out '%{http_code}')
test "$code" = 502
grep -q 'certificate verify error' "$E/untrusted-process.log"
! grep -q MUST_NOT_REACH_UNTRUSTED_MARKER "$E/untrusted-response.txt"
echo 'PASS HTTPS upstream untrusted chain rejected (502 + certificate verify error, no backend marker)'
stop_front
for backend in ipv4 ipv6; do
 for scheme in http https; do
  start_front "matrix-$backend-$scheme"
  if [ "$backend" = ipv4 ]; then
   if [ "$scheme" = http ]; then marker=HP_P3_IPV6_TO_IPV4_HTTP_MARKER; else marker=HP_P3_VERIFIED_HTTPS_UPSTREAM; fi
  else
   if [ "$scheme" = http ]; then marker=HP_P3_IPV6_BACKEND_HTTP; else marker=HP_P3_IPV6_BACKEND_HTTPS; fi
  fi
  for ingress in ipv4 ipv6; do
   if [ "$ingress" = ipv4 ]; then endpoint=127.0.0.1; else endpoint='[::1]'; fi
   env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --connect-timeout 2 --max-time 5 --resolve "home.iwonderful.top:49443:$endpoint" --silent --show-error --fail https://home.iwonderful.top:49443/ >"$E/matrix-$ingress-$backend-$scheme.txt"
   grep -qx "$marker" "$E/matrix-$ingress-$backend-$scheme.txt"
   echo "PASS HTTPS_MATRIX ingress=$ingress backend=$backend upstream=$scheme systemCA+hostname exact-marker=$marker"
  done
  stop_front
 done
done
echo P3_TASK20_HTTPS_ALL4_HTTP_AND_HTTPS_UPSTREAM_GREEN
OPENSSL_CONF=/dev/null "$NG" -e stderr -V >"$E/nginx-version.txt" 2>&1
sha256sum "$ROOT/"*.lua "$NG" "$ROOT/device-tcp-p3.sh" >"$E/source-sha256.txt"
echo P3_TASK16_ISOLATED_GREEN
