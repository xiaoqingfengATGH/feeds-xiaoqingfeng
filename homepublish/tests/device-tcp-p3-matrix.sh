#!/bin/sh
# Private real-device task20 matrix; no installed provider or global mutation.
set -eu
ROOT=/tmp/homepublish-tcp-p3
R=$ROOT/matrix-runtime
E=$ROOT/matrix-evidence
AUTH=/root/homepublish-p3-matrix-auth
NG=$ROOT/nginx-private
PIDS=''
test ! -e "$R"; test ! -e "$AUTH"
mkdir -p "$E"; chmod 700 "$E"
immutable() { sha256sum /etc/homepublish/product/state /etc/config/firewall /etc/config/dropbear /etc/config/uhttpd /etc/config/passwall2 /etc/resolv.conf /etc/hosts /usr/sbin/nginx; }
management() { netstat -lntp | grep -E '(/dropbear|/uhttpd|/xray)' | grep -v ':49547 '; }
stopall() {
 for p in $PIDS; do kill "$p" 2>/dev/null || true; done
 sleep 1
 for p in $PIDS; do kill -KILL "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done
 for p in $PIDS; do ! kill -0 "$p" 2>/dev/null || return 1; done
 PIDS=''
}
cleanup() {
 rc=$?; trap - EXIT INT TERM
 if stopall; then rm -rf "$R" "$AUTH"; else rc=1; fi
 immutable >"$E/immutable-after.txt"; cmp -s "$E/immutable-before.txt" "$E/immutable-after.txt" || rc=1
 management >"$E/management-after.txt"; cmp -s "$E/management-before.txt" "$E/management-after.txt" || rc=1
 netstat -lntp >"$E/listeners-after.txt"
 if grep -E ':(49543|49546|49547|49549|49550|49556|49557)[[:space:]]' "$E/listeners-after.txt"; then rc=1; fi
 test ! -e "$R" && test ! -e "$AUTH" || rc=1
 echo "PASS cleanup readback rc=$rc; management/global DNS/journal/config baselines compared"
 exit "$rc"
}
immutable >"$E/immutable-before.txt"; management >"$E/management-before.txt"
netstat -lntp >"$E/listeners-before.txt"
! grep -E ':(49543|49546|49547|49549|49550|49556|49557)[[:space:]]' "$E/listeners-before.txt"
trap cleanup EXIT INT TERM
umask 077; mkdir "$R" "$AUTH"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=tls.fixture.home -addext subjectAltName=DNS:tls.fixture.home -keyout "$R/tls.key" -out "$R/tls.pem" >"$E/keygen.log" 2>&1
dropbearkey -t ed25519 -f "$R/ssh-host.key" >"$E/ssh-host-public.txt" 2>&1
dropbearkey -t ed25519 -f "$R/ssh-client.key" >"$E/ssh-client-public.txt" 2>&1
grep '^ssh-ed25519 ' "$E/ssh-client-public.txt" >"$AUTH/authorized_keys"
fetch() { env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --connect-timeout 2 --max-time 5 --silent --show-error "$@"; }
for family in ipv4 ipv6; do
 if [ "$family" = ipv4 ]; then backend=127.0.0.1; else backend='[::1]'; fi
 lua "$ROOT/device-tcp-p3-matrix-render.lua" "$ROOT" "$family" >"$E/$family-render.txt"
 cat >"$R/backend.conf" <<EOF
worker_processes 1; daemon off; pid backend.pid; error_log stderr error;
events { worker_connections 32; }
http { access_log off; client_body_temp_path body; proxy_temp_path proxy; fastcgi_temp_path fastcgi; uwsgi_temp_path uwsgi; scgi_temp_path scgi;
server { listen $backend:49546 ssl; server_name tls.fixture.home; ssl_certificate $R/tls.pem; ssl_certificate_key $R/tls.key; return 200 'HP_TASK20_$family'; } }
EOF
 dropbear -F -E -s -j -k -r "$R/ssh-host.key" -D "$AUTH" -P "$R/ssh.pid" -p "$backend:49547" -c 'echo HP_TASK20_SSH' >"$E/$family-ssh.log" 2>&1 & PIDS="$PIDS $!"
 for conf in backend front; do
  OPENSSL_CONF=/dev/null "$NG" -t -p "$R/" -c "$conf.conf" >"$E/$family-$conf-config.txt" 2>&1
  OPENSSL_CONF=/dev/null "$NG" -p "$R/" -c "$conf.conf" >"$E/$family-$conf-process.txt" 2>&1 & PIDS="$PIDS $!"
 done
 "$ROOT/sslh-select.private" -F "$R/sslh.cfg" >"$E/$family-sslh.txt" 2>&1 & PIDS="$PIDS $!"
 sleep 1
 # Dual-stack shared and independent sockets coexist in one running graph.
 for ingress in 127.0.0.1 '[::1]'; do
  if [ "$ingress" = 127.0.0.1 ]; then label=v4; sshhost=127.0.0.1; else label=v6; sshhost=::1; fi
  fetch --fail --cacert "$R/tls.pem" --resolve "tls.fixture.home:49543:$ingress" https://tls.fixture.home:49543/ >"$E/$family-$label-shared.txt" & a=$!
  fetch --fail --cacert "$R/tls.pem" --resolve "tls.fixture.home:49550:$ingress" https://tls.fixture.home:49550/ >"$E/$family-$label-independent.txt" & b=$!
  timeout 8 dbclient -y -y -i "$R/ssh-client.key" -p 49543 "root@$sshhost" fixture >"$E/$family-$label-ssh.txt" 2>"$E/$family-$label-ssh-client.txt" & d=$!
  wait "$a"; wait "$b"; wait "$d"
  grep -qx "HP_TASK20_$family" "$E/$family-$label-shared.txt"
  grep -qx "HP_TASK20_$family" "$E/$family-$label-independent.txt"
  grep -qx HP_TASK20_SSH "$E/$family-$label-ssh.txt"
  echo "PASS ingress=$label backend=$family shared TLS + native SSH + independent TCP simultaneous graph; no ingress certificate snapshot"
 done
 for host in unknown.fixture.home tls.fixture.home.evil; do
  if fetch -k --resolve "$host:49543:[::1]" "https://$host:49543/" >"$E/$family-$host.txt" 2>&1; then exit 1; fi
 done
 timeout 5 openssl s_client -connect '[::1]:49543' -noservername </dev/null >"$E/$family-no-sni.txt" 2>&1 || true
 grep -q 'no peer certificate available' "$E/$family-no-sni.txt"
 lua "$ROOT/device-tcp-p3-reject.lua"
 echo "PASS nonHTTPS $family unknown/suffix/noSNI/garbage/PROXY/idle rejection"
 netstat -lntp >"$E/$family-listeners.txt"
 stopall
 done
sha256sum "$ROOT/device-tcp-p3-matrix-render.lua" "$ROOT/device-tcp-p3-matrix.sh" "$ROOT/sslh-renderer.lua" "$ROOT/tcp-route-plan.lua" >"$E/source-sha256.txt"
lua "$ROOT/device-tcp-p3-post-render.lua" "$ROOT" >"$E/post-render.txt"
: >"$E/post-primary.txt"; : >"$E/post-alternate.txt"
cat >"$R/post-backend.conf" <<EOF
worker_processes 1; daemon off; pid post-backend.pid; error_log stderr error;
events { worker_connections 32; }
http { log_format counts '\$request_method \$uri'; client_body_temp_path body; proxy_temp_path proxy; fastcgi_temp_path fastcgi; uwsgi_temp_path uwsgi; scgi_temp_path scgi;
server { listen 127.0.0.1:49557; access_log $E/post-primary.txt counts; location /ok { return 200 HP_POST_OK; } location /drop { return 444; } }
server { listen 127.0.0.2:49557; access_log $E/post-alternate.txt counts; return 200 HP_REPLAY_FORBIDDEN; } }
EOF
for conf in post-backend post; do
 OPENSSL_CONF=/dev/null "$NG" -t -p "$R/" -c "$conf.conf" >"$E/$conf-config.txt" 2>&1
 OPENSSL_CONF=/dev/null "$NG" -p "$R/" -c "$conf.conf" >"$E/$conf-process.txt" 2>&1 & PIDS="$PIDS $!"
done
sleep 1
fetch --fail --cacert "$R/tls.pem" --resolve 'tls.fixture.home:49556:[::1]' -X POST --data-binary 'nonidempotent=one' https://tls.fixture.home:49556/ok >"$E/post-ok.txt"
grep -qx HP_POST_OK "$E/post-ok.txt"
code=$(fetch --cacert "$R/tls.pem" --resolve 'tls.fixture.home:49556:[::1]' -X POST --data-binary 'nonidempotent=two' -o "$E/post-drop.txt" -w '%{http_code}' https://tls.fixture.home:49556/drop)
test "$code" = 502
sleep 1
test "$(wc -l <"$E/post-primary.txt")" = 2
test "$(grep -c '^POST /ok$' "$E/post-primary.txt")" = 1
test "$(grep -c '^POST /drop$' "$E/post-primary.txt")" = 1
test ! -s "$E/post-alternate.txt"
echo 'PASS non-idempotent POST counts: primary /ok=1 /drop=1; upstream close gives502; alternate=0; no replay'
echo P3_TASK20_MATRIX_ISOLATED_GREEN
