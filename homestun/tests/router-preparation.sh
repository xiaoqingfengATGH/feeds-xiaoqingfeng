#!/bin/sh
set -eu
R=/tmp/homestun-test
if "$R/preparation-fault" "$R" 3 >"$R/preparation.log" 2>&1; then exit 1; fi
if [ -d "$R/runner.lock" ]; then
 rm -rf "$R/runner.lock"
 echo 'FAIL SEC003: snapshot fsync failure strands runner.lock'; exit 1
fi
echo 'PASS SEC003: snapshot fsync failure removes lock'
HOMESTUN_DELAY=1 "$R/preparation-fault" "$R" 3 >"$R/preparation-delay.log" 2>&1 & p=$!
sleep 3
if kill -0 "$p" 2>/dev/null; then
 kill -KILL "$p"; wait "$p" || true; rm -rf "$R/runner.lock"
 echo 'FAIL SEC003: delayed preparation exceeds startup deadline'; exit 1
fi
wait "$p" || true
[ ! -d "$R/runner.lock" ]
echo 'PASS SEC003: delayed preparation bounded by startup deadline'
