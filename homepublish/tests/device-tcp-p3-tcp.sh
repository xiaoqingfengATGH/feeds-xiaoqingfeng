#!/bin/sh
# Device-only isolated P3 task16. No journal mutation, init restart or firewall.
set -eu
ROOT=/tmp/homepublish-tcp-p3
R="$ROOT/tcp-runtime"
E="$ROOT/tcp-evidence"
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
 if grep -E ':(49550|49551|49552|49553|49554|49555)[[:space:]]' "$E/listeners-after.txt"; then echo 'FAIL test listener residual'; rc=1; fi
 exit "$rc"
}
sha256sum /etc/homepublish/product/state /etc/config/firewall /etc/config/dropbear /etc/config/uhttpd /etc/config/passwall2 /usr/sbin/nginx >"$E/immutable-before.txt"
netstat -lntp >"$E/listeners-before.txt"
! grep -E ':(49550|49551|49552|49553|49554|49555)[[:space:]]' "$E/listeners-before.txt"
trap cleanup EXIT INT TERM
umask 077; mkdir "$R"
netstat -lntp | grep -E '(/dropbear|/uhttpd|/xray)' >"$E/management-before.txt"
lua "$ROOT/device-tcp-p3-tcp-render.lua" "$ROOT"
OPENSSL_CONF=/dev/null "$NG" -e stderr -t -p "$R/" -c front.conf >"$E/front-config.log" 2>&1
for pair in 'server-first 49551' 'client-first 49553' 'server-half 49555'; do
 set -- $pair
 lua "$ROOT/device-tcp-p3-tcp-sockets.lua" "$1" "$2" >"$E/backend-$1.log" 2>&1 & PIDS="$PIDS $!"
done
OPENSSL_CONF=/dev/null "$NG" -e stderr -p "$R/" -c front.conf >"$E/front-process.log" 2>&1 & FRONT=$!
sleep 1; kill -0 "$FRONT"
for pair in 'client-server-first 49550' 'client-client-first 49552' 'client-server-half 49554'; do
 set -- $pair
 timeout 20 lua "$ROOT/device-tcp-p3-tcp-sockets.lua" "$1" "$2" >"$E/$1.log" 2>&1
 cat "$E/$1.log"
done
for p in $PIDS; do wait "$p"; done
PIDS=''
for mode in server-first client-first server-half; do cat "$E/backend-$mode.log"; done
netstat -lntp >"$E/listeners-running.txt"
sha256sum "$ROOT/direct-renderer.lua" "$ROOT/tcp-route-plan.lua" "$ROOT/tcp-stream-renderer.lua" "$ROOT/device-tcp-p3-tcp-render.lua" "$ROOT/device-tcp-p3-tcp-sockets.lua" "$ROOT/device-tcp-p3-tcp.sh" >"$E/source-sha256.txt"
netstat -lntp | grep -E '(/dropbear|/uhttpd|/xray)' >"$E/management-after.txt"
cmp -s "$E/management-before.txt" "$E/management-after.txt"
echo 'PASS management SSH/Web/proxy PID+listeners unchanged'
echo P3_TASK19_ISOLATED_GREEN
