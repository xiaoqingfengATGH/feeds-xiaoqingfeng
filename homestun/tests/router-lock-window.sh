#!/bin/sh
set -eu
R=/tmp/homestun-test
HOMESTUN_LOCK_DELAY=1 "$R/preparation-fault" "$R" 3 >"$R/lock-window.log" 2>&1 & p=$!
sleep 1
[ -d "$R/runner.lock" ]
guardian=$(awk -v parent="$p" '$4==parent {print $1}' /proc/[0-9]*/stat 2>/dev/null || true)
[ -n "$guardian" ]
kill -KILL $guardian
sleep 2
wait "$p" || true
if [ -d "$R/runner.lock" ]; then
 sleep 3
 rm -rf "$R/runner.lock"
 echo 'FAIL SEC003: guardian death in lock creation window strands lock'; exit 1
fi
echo 'PASS SEC003: guardian death in lock creation window removes lock'
HOMESTUN_PREFORK_DELAY=1 "$R/preparation-fault" "$R" 3 >"$R/prefork.log" 2>&1 & p=$!
sleep 1
[ ! -d "$R/runner.lock" ]
kill -KILL "$p"
wait "$p" || true
[ ! -d "$R/runner.lock" ]
echo 'PASS SEC003: controller prefork death creates no lock'
# Exclusion must preserve both stale and live snapshots, not "clean" a rival.
mkdir "$R/runner.lock"
printf '%s\n' keep >"$R/runner.lock/sentinel"
if "$R/lease-supervisor" "$R" 3 >"$R/exclusion.log" 2>&1; then exit 1; fi
[ "$(cat "$R/runner.lock/sentinel")" = keep ]
rm "$R/runner.lock/sentinel"; rmdir "$R/runner.lock"
echo 'PASS SEC003: pre-existing lock preserved on rejection'
"$R/lease-supervisor" "$R" 3 >"$R/exclusion.log" 2>&1 & p=$!
sleep 1
[ -f "$R/runner.lock/nginx.pid" ]
master=$(cat "$R/runner.lock/nginx.pid")
if "$R/lease-supervisor" "$R" 3 >"$R/exclusion-rival.log" 2>&1; then exit 1; fi
[ "$(cat "$R/runner.lock/nginx.pid")" = "$master" ]
kill -0 "$master"
wait "$p"
[ ! -d "$R/runner.lock" ]
echo 'PASS SEC003: concurrent helper rejected without removing live snapshot'
for signal in TERM INT; do
 HOMESTUN_DELAY=1 "$R/preparation-fault" "$R" 3 >"$R/preparation-signal.log" 2>&1 & p=$!
 sleep 1
 kill -"$signal" "$p"
 sleep 1
 if kill -0 "$p" 2>/dev/null; then kill -KILL "$p"; wait "$p" || true; echo "FAIL SEC003: preparation $signal shutdown not prompt"; exit 1; fi
 wait "$p" || true
 [ ! -d "$R/runner.lock" ]
 echo "PASS SEC003: preparation $signal promptly removes lock"
done
