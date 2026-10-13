#!/bin/sh
set -eu
cd /
b=/tmp/homestun-test/sdk-native
r=$b/root
date
sha256sum -c "$b/original-hashes"
sha256sum "$r/usr/libexec/homestun-lease" "$r/usr/share/homestun/"*.lua "$r/usr/bin/lua" "$r/usr/sbin/nginx"
for d in "$r"/tmp/homestun-service-*; do [ "$d" = "$r/tmp/homestun-service-Foreign" ] || [ ! -e "$d" ] || exit 1; done
state=$(ubus call service list '{"name":"homestun-sdk-native-fixture-20261012"}')
printf '%s\n' "$state"
[ "$(echo "$state" | tr -d ' \t\r\n')" = '{}' ]
scan() {
 for p in /proc/[0-9]*; do
  for link in root exe cwd; do
   target=$(readlink "$p/$link" 2>/dev/null || :)
   case "$target" in "$b"*) echo "FAIL fixture process $p/$link $target"; exit 1;; esac
  done
 done
}
scan
echo 'PASS pre-cleanup no fixture process (root/exe/cwd), service or owned runtime; original and foreign hashes unchanged'
rm -rf "$b"
rmdir /tmp/homestun-test
[ ! -e "$b" ]
[ ! -e /tmp/homestun-test ]
scan
listeners=$(netstat -lnt)
printf '%s\n' "$listeners"
if echo "$listeners" | grep -E ':(18443|18444|18081) '; then exit 1; fi
for port in 22 80 443; do echo "$listeners" | grep ":$port "; done
echo 'PASS exact fixture removed, no processes/services/test listeners, 22/80/443 preserved'
date
