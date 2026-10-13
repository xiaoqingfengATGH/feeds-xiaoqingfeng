#!/bin/sh
set -eu
R=/tmp/homedirect-test
closed() { ! netstat -lnt | awk '$4 ~ /:18443$/ {found=1} END {exit !found}'; }
start() {
 "$R/lease-supervisor" "$R" "$1" >"$R/fault.log" 2>&1 &
 p=$!
 sleep 1
 [ -f "$R/runner.lock/nginx.pid" ]
}
start 3
kill -STOP "$p"
sleep 3
closed
[ ! -d "$R/runner.lock" ]
kill -CONT "$p"
wait "$p"
echo 'PASS SEC003: stopped controller cannot extend TTL; lock removed'
start 8
master=$(cat "$R/runner.lock/nginx.pid")
kill -KILL "$master"
sleep 1
closed
wait "$p" || true
[ ! -d "$R/runner.lock" ]
echo 'PASS SEC003: nginx exit closes listener and removes lock'
# Keep the TLS client stdin open; expiry must close the established connection.
mkfifo "$R/client.fifo"
(sleep 10) >"$R/client.fifo" & writer=$!
start 3
openssl s_client -connect 127.0.0.1:18443 -quiet <"$R/client.fifo" >"$R/client.out" 2>"$R/client.err" & client=$!
sleep 3
if kill -0 "$client" 2>/dev/null; then kill "$client" "$writer" 2>/dev/null || true; rm "$R/client.fifo"; echo 'FAIL SEC003: established TLS connection survives TTL'; exit 1; fi
wait "$client" || true
kill "$writer" 2>/dev/null || true
wait "$writer" || true
rm "$R/client.fifo"
wait "$p"
closed
[ ! -d "$R/runner.lock" ]
echo 'PASS SEC003: established TLS connection forcibly closes at TTL'
# Guardian crash is a separate fault: listener must not outlive the controller.
start 3
guardian=$(awk -v parent="$p" '$4==parent {print $1}' /proc/[0-9]*/stat 2>/dev/null || true)
[ -n "$guardian" ]
master=$(cat "$R/runner.lock/nginx.pid")
kill -KILL $guardian
sleep 3
if ! closed; then
 kill -KILL -"$master" 2>/dev/null || true
 wait "$p" || true
 sleep 1
 rm -rf "$R/runner.lock"
 echo 'FAIL SEC003: guardian death leaves TLS listener beyond TTL'; exit 1
fi
wait "$p" || true
[ ! -d "$R/runner.lock" ]
echo 'PASS SEC003: guardian death closes listener and removes lock'
