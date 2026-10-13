#!/bin/sh
set -eu
R=/tmp/homedirect-test
"$R/lease-supervisor" "$R" 8 >"$R/term.log" 2>&1 &
p=$!
sleep 1
kill -TERM "$p"
sleep 1
if netstat -lnt | awk '$4 ~ /:18443$/ {found=1} END {exit !found}'; then
 kill -KILL "$p" 2>/dev/null || true
 sleep 1
 echo 'FAIL SEC003: TERM did not promptly close listener'; exit 1
fi
wait "$p" || true
[ ! -d "$R/runner.lock" ]
echo 'PASS SEC003: TERM promptly closes listener and removes lock'
