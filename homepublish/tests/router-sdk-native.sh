#!/bin/sh
set -eu
b=/tmp/homepublish-test/sdk-native
r=$b/root
cd /
mkdir -p "$r/bin" "$r/lib" "$r/usr/bin" "$r/usr/sbin" "$r/usr/lib/lua" "$r/etc/config" "$r/etc/homepublish" "$r/tmp" "$r/dev" "$r/var/run" "$r/var/lib/nginx/fastcgi" "$r/var/lib/nginx/uwsgi" "$r/var/lib/nginx/scgi"
chmod 700 "$b" "$r/etc/homepublish"; chmod 1777 "$r/tmp"
cp /bin/busybox "$r/bin/busybox"; ln -s busybox "$r/bin/sh"
cp /usr/bin/lua "$r/usr/bin/lua"; cp /usr/sbin/nginx "$r/usr/sbin/nginx"
cp /etc/passwd /etc/group "$r/etc/"
for p in /lib/*.so* /usr/lib/liblua.so* /usr/lib/libjson-c.so* /usr/lib/libpcre.so* /usr/lib/libssl.so* /usr/lib/libcrypto.so* /usr/lib/libz.so* /usr/lib/libuci.so* /usr/lib/lua/uci.so; do
 [ ! -e "$p" ] || cp -L "$p" "$r$p"
done
# /tmp is nodev; regular sink, no mount changes.
: > "$r/dev/null"
cp "$b/probe" "$r/usr/bin/natmap"
chmod 755 "$r/usr/bin/natmap" "$r/usr/libexec/homepublish-lease"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$r/etc/homepublish/key.pem" -out "$r/etc/homepublish/cert.pem" -subj /CN=fixture.example -days 1 >/dev/null 2>&1
chmod 600 "$r/etc/homepublish/"*.pem
sha256sum "$r/usr/libexec/homepublish-lease" "$r/usr/share/homepublish/"*.lua "$r/usr/sbin/nginx" "$r/usr/bin/lua" "$r/usr/bin/natmap"
sha256sum "$r/etc/homepublish/"*.pem > "$b/original-hashes"
mkdir -p "$r/tmp/homepublish-service-Foreign"; echo foreign > "$r/tmp/homepublish-service-Foreign/key.pem"
sha256sum "$r/tmp/homepublish-service-Foreign/key.pem" >> "$b/original-hashes"
cat > "$r/etc/config/homepublish" <<'CFG'
config service 'main'
 option enabled '1'
 option exposure_approved '1'
 option publication_enabled '0'
 option listen '127.0.0.1'
 option port '18443'
 option bind_port '18444'
 option ttl '5'
 option stun_server 'example.com'
 option http_server 'example.com'
 option cert '/etc/homepublish/cert.pem'
 option key '/etc/homepublish/key.pem'
config host
 option name 'fixture.example'
 option upstream 'http://127.0.0.1:18081'
CFG
chmod 600 "$r/etc/config/homepublish"
cat > "$b/backend.conf" <<CFG
worker_processes 1;
pid $b/backend.pid;
error_log $b/backend-error.log;
events { worker_connections 32; }
http { access_log off; server { listen 127.0.0.1:18081; location / { return 200 'synthetic-backend'; } location /hold { limit_rate 1; return 200 'synthetic-stream-keeps-connection-open'; } } }
CFG
/usr/sbin/nginx -p "$b/" -c "$b/backend.conf" -g 'daemon off;' > "$b/backend.out" 2>&1 &
backend=$!
"$b/probe" occupant > "$b/occupant.out" 2>&1 &
occupant=$!
cleanup() { kill "$backend" "$occupant" 2>/dev/null || :; wait "$backend" || :; wait "$occupant" || :; }
trap cleanup EXIT
sleep 1
printf '%s 3\n' "$occupant" > "$r/tmp/occupant"
"$b/probe" baseline
"$b/probe" echo
child_of() {
 for s in /proc/[0-9]*/status; do
  while read -r field value rest; do
   if [ "$field" = PPid: ] && [ "$value" = "$1" ]; then p=${s#/proc/}; echo "${p%/status}"; return; fi
  done < "$s" 2>/dev/null || :
 done
 return 1
}
verify() {
 sleep 1
 for d in "$r"/tmp/homepublish-service-*; do [ "$d" = "$r/tmp/homepublish-service-Foreign" ] || [ ! -e "$d" ] || { echo "FAIL retained $d"; exit 1; }; done
 if netstat -lnt | grep -q '127.0.0.1:18443 '; then echo 'FAIL retained TLS listener'; exit 1; fi
 sha256sum -c "$b/original-hashes"
 "$b/probe" echo
}
wait_ready() {
 deadline=$(($(date +%s)+4))
 while [ "$(date +%s)" -le "$deadline" ]; do
  if [ -f "$r/tmp/probe-ready" ] && curl --noproxy '*' -ksS --max-time 1 -H 'Host: fixture.example' https://127.0.0.1:18443/ > "$b/reply" 2>/dev/null && [ "$(cat "$b/reply")" = synthetic-backend ]; then return; fi
 done
 echo FAIL-not-ready; exit 1
}
for mode in expiry TERM controller-KILL controller-STOP guardian-KILL guardian-STOP engine-KILL nginx-KILL; do
 rm -f "$r/tmp/probe-ready"
 chroot "$r" /usr/libexec/homepublish-lease --provision 5 18444 18443 example.com example.com > "$b/$mode.out" 2>&1 &
 controller=$!
 started=$(date +%s)
 wait_ready
 if [ "$mode" = expiry ]; then
  curl --noproxy '*' -kNsS --max-time 15 -H 'Host: fixture.example' https://127.0.0.1:18443/hold > "$b/hold-body" 2> "$b/hold-error" &
  connection=$!
  sleep 1
  kill -0 "$connection"
  netstat -nt | grep '127.0.0.1:18443' | grep ESTABLISHED
 fi
 guardian=$(child_of "$controller")
 probe=$(cat "$r/tmp/probe-ready")
 case "$mode" in
 TERM) kill -TERM "$controller";;
 controller-KILL) kill -KILL "$controller";;
 controller-STOP) kill -STOP "$controller";;
 guardian-KILL) kill -KILL "$guardian";;
 guardian-STOP) kill -STOP "$guardian";;
 engine-KILL) kill -KILL "$probe";;
 nginx-KILL) phase=$(child_of "$guardian"); victim=; for s in /proc/[0-9]*/status; do p=${s#/proc/}; p=${p%/status}; [ "$p" = "$probe" ] && continue; if grep -q '^Name:[[:space:]]*nginx' "$s" 2>/dev/null && grep -q "^PPid:[[:space:]]*$phase$" "$s" 2>/dev/null; then victim=$p; kill -KILL "$p"; break; fi; done; [ -n "$victim" ]; echo "INJECT nginx KILL pid=$victim";;
 esac
 sleep 6
 verify
 echo "PASS cleanup observed before resuming any stopped supervisor mode=$mode"
 [ "$mode" != controller-STOP ] || kill -CONT "$controller" 2>/dev/null || :
 [ "$mode" != guardian-STOP ] || kill -CONT "$guardian" 2>/dev/null || :
 wait "$controller" || :
 elapsed=$(($(date +%s)-started)); [ "$elapsed" -le 12 ]; echo "BOUND mode=$mode ttl=5 observed_cleanup_seconds=$elapsed"
 if [ "$mode" = expiry ]; then
  if kill -0 "$connection" 2>/dev/null; then echo 'FAIL held TLS connection remains'; exit 1; fi
  set +e; wait "$connection"; rc=$?; set -e
  case "$rc" in 18|56) :;; *) echo "FAIL unexpected held-TLS curl exit=$rc"; exit 1;; esac; cat "$b/hold-error"
  echo 'PASS expiry established TLS stream closed before client timeout'
 fi
 if kill -0 "$probe" 2>/dev/null; then echo "FAIL mock engine remains pid=$probe"; exit 1; fi
 cat "$b/$mode.out"
 echo "PASS SDK real-nginx $mode bounded cleanup; NATMap syscall-only fixture"
done
# Preparation fault injection uses a fixture-only exec wrapper; normal runs exec genuine target Lua.
mv "$r/usr/bin/lua" "$r/usr/bin/lua-real"
cat > "$r/usr/bin/lua" <<'LUA'
#!/bin/sh
if [ -f /tmp/stall-render ]; then
 echo rendering > /tmp/rendering
 while :; do /bin/busybox sleep 1; done
fi
exec /usr/bin/lua-real "$@"
LUA
chmod 755 "$r/usr/bin/lua"
for mode in KILL STOP; do
 touch "$r/tmp/stall-render"; rm -f "$r/tmp/rendering"
 chroot "$r" /usr/libexec/homepublish-lease --provision 5 18444 18443 example.com example.com > "$b/preparation-$mode.out" 2>&1 &
 controller=$!
 deadline=$(($(date +%s)+4))
 while [ ! -f "$r/tmp/rendering" ] && [ "$(date +%s)" -le "$deadline" ]; do :; done
 [ -f "$r/tmp/rendering" ]
 guardian=$(child_of "$controller"); preparation=$(child_of "$guardian")
 kill -"$mode" "$preparation"
 sleep 6; wait "$controller" || :
 rm -f "$r/tmp/stall-render"
 verify
 echo "PASS SDK preparation $mode cleanup before real Lua render"
done
mv "$r/usr/bin/lua-real" "$r/usr/bin/lua"
# Real procd isolated namespace, no respawn; no init/UCI production changes.
service=homepublish-sdk-native-fixture-20261012
rm -f "$r/tmp/probe-ready"
ubus call service add "{\"name\":\"$service\",\"instances\":{\"lease\":{\"command\":[\"/usr/sbin/chroot\",\"$r\",\"/usr/libexec/homepublish-lease\",\"--provision\",\"5\",\"18444\",\"18443\",\"example.com\",\"example.com\"],\"term_timeout\":1,\"stdout\":false,\"stderr\":false}}}"
wait_ready
state=$(ubus call service list "{\"name\":\"$service\"}"); echo "$state"
pid=$(echo "$state" | jsonfilter -e "@[\"$service\"].instances.lease.pid")
[ -n "$pid" ]; kill -STOP "$pid"
ubus call service delete "{\"name\":\"$service\"}"
sleep 6; verify
state=$(ubus call service list "{\"name\":\"$service\"}")
[ "$(echo "$state" | tr -d ' \t\r\n')" = '{}' ]
echo 'PASS SDK genuine procd STOP TERM KILL cleanup and service absence'
# Reject unavailable boundary installation before NATMap exec and nginx exposure.
rm -f "$r/tmp/probe-ready"
"$b/probe" deny-install /usr/sbin/chroot "$r" /usr/libexec/homepublish-lease --provision 5 18444 18443 example.com example.com > "$b/denied.out" 2>&1 && exit 1
[ ! -e "$r/tmp/probe-ready" ]
verify
cat "$b/denied.out"
echo 'PASS unavailable seccomp installation fail-closed'
cleanup
trap - EXIT
cat "$b/occupant.out"
netstat -lnt
