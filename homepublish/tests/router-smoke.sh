#!/bin/sh
# Isolated router test: no UCI, firewall, NAS or management configuration changes.
set -eu
R=/tmp/homepublish-test
cleanup() {
 [ ! -f "$R/backend.pid" ] || nginx -s stop -p "$R/" -c "$R/backend.conf" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=homepublish-test -keyout "$R/key.pem" -out "$R/cert.pem" >/dev/null 2>&1
chmod 600 "$R/key.pem" "$R/cert.pem" "$R/nginx.conf"
# Non-sensitive backend fixture in its own nginx instance.
printf '%s\n' "pid $R/backend.pid; error_log $R/backend-error.log; events {} http { access_log off; client_body_temp_path $R/backend-body; server { listen 127.0.0.1:18081; return 200 'homepublish-nas-fixture'; } server { listen 127.0.0.1:18082; return 200 'homepublish-files-fixture'; } }" > "$R/backend.conf"
nginx -t -p "$R/" -c "$R/backend.conf"
nginx -p "$R/" -c "$R/backend.conf"
nginx -t -p "$R/" -c "$R/nginx.conf"
# Runner must own foreground nginx, stop it on lease expiry and not touch management.
"$R/lease-supervisor" "$R" 4 > "$R/runner.log" 2>&1 &
runner=$!
ready=0
for i in 1 2 3; do
 if curl --noproxy '*' -skf --resolve nas-stun-test.innonext.win:18443:127.0.0.1 https://nas-stun-test.innonext.win:18443/ > "$R/nas.out"; then ready=1; break; fi
 sleep 1
done
[ "$ready" = 1 ]
[ "$(cat "$R/nas.out")" = homepublish-nas-fixture ]
[ "$(curl --noproxy '*' -skf --resolve files-stun-test.innonext.win:18443:127.0.0.1 https://files-stun-test.innonext.win:18443/)" = homepublish-files-fixture ]
if curl --noproxy '*' -skf -H 'Host: invalid.example' https://127.0.0.1:18443/ >/dev/null; then exit 1; fi
for host in unknown.innonext.win child.nas-stun-test.innonext.win; do
 if curl --noproxy '*' -skf --resolve "$host:18443:127.0.0.1" "https://$host:18443/" >/dev/null; then exit 1; fi
 if curl --noproxy '*' -skf --resolve nas-stun-test.innonext.win:18443:127.0.0.1 -H "Host: $host" https://nas-stun-test.innonext.win:18443/ >/dev/null; then exit 1; fi
done
wait "$runner"
if curl --noproxy '*' -sk --connect-timeout 1 https://127.0.0.1:18443/ >/dev/null; then exit 1; fi
printf '%s\n' 'PASS multi-host proxy, unknown-host denial, lease expiry closes real TLS listener'
# management must remain present
netstat -lnt | awk '$4 ~ /:80$|:443$|:22$/ {print}'
