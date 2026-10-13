#!/bin/sh
set -eu
R=/tmp/homestun-test
HOMESTUN_DELAY=1 "$R/preparation-fault" "$R" 3 >"$R/preparation-crash.log" 2>&1 & p=$!
sleep 1
kill -KILL "$p"
wait "$p" || true
sleep 2
if [ -d "$R/runner.lock" ]; then
 # Current bounded injection eventually errors; wait before fixture cleanup.
 sleep 3
 rm -rf "$R/runner.lock"
 echo 'FAIL SEC003: controller death during preparation strands lock beyond TTL'; exit 1
fi
echo 'PASS SEC003: controller death during preparation promptly removes lock'
