#!/bin/sh
# Isolated router fixture only; no install, sockets, firewall or management edits.
set -eu
base=/tmp/homedirect-test/source-cleanup-fixture
root=$base/root
runtime=$root/tmp/homedirect-service-Test123
service=homedirect-source-cleanup-fixture
[ -d "$root/seed" ] || exit 2
# Gate actual target prerequisites: injecting a host stat masks activation bugs.
chroot "$root" /bin/sh -c '! command -v stat >/dev/null 2>&1' || exit 2
[ "$(chroot "$root" /usr/libexec/homedirect-lease --metadata /etc/homedirect/key.pem)" = '0:600:1' ]
echo 'PASS target-native metadata; stat absent'
reset_runtime() {
 [ ! -d "$runtime" ] || { echo "FAIL stale runtime"; exit 1; }
 mkdir -m 700 "$runtime"
 cp "$root/seed/"* "$runtime/"
 rm -f "$root/tmp/ready"
}
start_adapter() {
 chroot "$root" /bin/sh /usr/share/homedirect/lease-run.sh /tmp/homedirect-service-Test123 2 18444 18443 example.com example.com &
 adapter=$!
 for i in 1 2 3 4 5 6 7 8 9 10; do
  [ ! -f "$root/tmp/ready" ] || return 0
  sleep 1
 done
 echo 'FAIL not ready'; exit 1
}
verify() {
 for i in 1 2 3 4 5 6; do
  [ -d "$runtime" ] || break
  sleep 1
 done
 [ ! -e "$runtime" ] || { echo 'FAIL runtime retained'; exit 1; }
 [ "$(cat "$root/etc/homedirect/cert.pem")" = original-cert.pem ]
 [ "$(cat "$root/etc/homedirect/key.pem")" = original-key.pem ]
 [ "$(cat "$root/tmp/homedirect-service-Foreign/key.pem")" = foreign ]
}
for mode in expiry TERM KILL STOP; do
 reset_runtime
 start_adapter
 case "$mode" in expiry) : ;; *) kill -"$mode" "$adapter" ;; esac
 verify
 [ "$mode" != STOP ] || kill -CONT "$adapter"
 wait "$adapter" || :
 echo "PASS BusyBox $mode owned cleanup + foreign/original preservation"
done
# Real procd registration in a unique service namespace; stopped adapter forces
# procd's one-second TERM->KILL path. This is not the installed HomeDirect service.
reset_runtime
ubus call service add '{"name":"homedirect-source-cleanup-fixture","instances":{"lease":{"command":["/usr/sbin/chroot","/tmp/homedirect-test/source-cleanup-fixture/root","/bin/sh","/usr/share/homedirect/lease-run.sh","/tmp/homedirect-service-Test123","2","18444","18443","example.com","example.com"],"term_timeout":1,"stdout":false,"stderr":false}}}'
trap 'ubus call service delete "{\"name\":\"$service\"}" >/dev/null 2>&1 || :' EXIT
sleep 1
state=$(ubus call service list "{\"name\":\"$service\"}")
printf '%s\n' "$state"
pid=$(printf '%s' "$state" | jsonfilter -e '@["homedirect-source-cleanup-fixture"].instances.lease.pid')
[ -n "$pid" ]
kill -STOP "$pid"
ubus call service delete "{\"name\":\"$service\"}"
verify
state=$(ubus call service list "{\"name\":\"$service\"}")
[ "$(printf '%s' "$state" | tr -d ' \t\r\n')" = '{}' ] || { printf '%s\n' "$state"; exit 1; }
echo 'PASS isolated real procd STOP->TERM->KILL cleanup; service readback absent'
