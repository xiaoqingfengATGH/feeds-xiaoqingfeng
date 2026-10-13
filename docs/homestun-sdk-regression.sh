#!/bin/bash
set -euo pipefail
cd /mnt/d/DevPortal/homelede/feeds-xiaoqingfeng-homestun
ip link set lo up
hosts=$(mktemp -d /tmp/homestun-sdk-hosts-XXXXXX)
cleanup() { umount /etc/hosts; rm -rf "$hosts"; }
trap cleanup EXIT
printf '127.0.0.1 localhost stun-test.innonext.win\n' > "$hosts/hosts"
mount --bind "$hosts/hosts" /etc/hosts
run_tests() {
 for test in token-validation publication-security publication socket-boundary lifecycle recipe package source-cleanup; do
  echo "=== $test ==="
  python3 -B "homestun/tests/test-$test.py" -v || return $?
 done
 for test in core config publication-config; do
  echo "=== Lua $test ==="
  /home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1 "homestun/tests/test-$test.lua" homestun/files/usr/share/homestun || return $?
 done
 echo 'SDK_FINAL_LOCAL_SUITE_PASS'
}
run_tests 2>&1 | tee docs/homestun-sdk-final-regression.txt
