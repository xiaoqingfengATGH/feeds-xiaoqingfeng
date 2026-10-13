#!/bin/sh
set -eu
R=/tmp/homestun-test
"$R/lease-supervisor" "$R" 3 >"$R/guardian-stop.log" 2>&1 & p=$!
sleep 1
guardian=$(awk -v parent="$p" '$4==parent {print $1}' /proc/[0-9]*/stat 2>/dev/null || true)
[ -n "$guardian" ]
master=$(cat "$R/runner.lock/nginx.pid")
kill -STOP $guardian
sleep 3
if netstat -lnt | awk '$4 ~ /:18443$/ {found=1} END {exit !found}'; then
 kill -KILL $guardian
 wait "$p" || true
 sleep 1
 echo 'FAIL SEC003: stopped guardian extends TTL'; exit 1
fi
wait "$p" || true
[ ! -d "$R/runner.lock" ]
echo 'PASS SEC003: stopped guardian cannot extend TTL'
