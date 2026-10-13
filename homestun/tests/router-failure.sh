#!/bin/sh
set -eu
R=/tmp/homestun-test
"$R/lease-supervisor" "$R" 3 >"$R/failure.log" 2>&1 &
p=$!
sleep 1
kill -KILL "$p"
sleep 3
if netstat -lnt | awk '$4 ~ /:18443$/ {found=1} END {exit !found}'; then
 if [ -f "$R/runner.lock/nginx.pid" ]; then kill -TERM "$(cat "$R/runner.lock/nginx.pid")"; fi
 sleep 1
 rm -rf "$R/runner.lock"
 echo 'FAIL SEC003: SIGKILL left TLS listener'; exit 1
fi
wait "$p" || true
[ ! -d "$R/runner.lock" ]
echo 'PASS SEC003: SIGKILL closes TLS listener and removes lock'
