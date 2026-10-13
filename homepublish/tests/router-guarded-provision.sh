#!/bin/sh
# Isolated target native provisioning regression. Engines never open sockets.
set -eu
base=${HOMEPUBLISH_TEST_BASE:-/tmp/homepublish-test/guarded}
root=$base/root
service=${HOMEPUBLISH_TEST_SERVICE:-homepublish-guarded-fixture}
publish=${HOMEPUBLISH_TEST_PUBLICATION:-}
token_hash=
[ -z "$publish" ] || token_hash=$(sha256sum "$root/etc/homepublish/router.token")
trap 'ubus call service delete "{\"name\":\"$service\"}" >/dev/null 2>&1 || :' EXIT
verify() {
 sleep 1
 for d in "$root"/tmp/homepublish-service-*; do
  [ "$d" = "$root/tmp/homepublish-service-Foreign" ] || [ ! -e "$d" ] || { echo "FAIL retained $d"; exit 1; }
 done
 [ "$(cat "$root/etc/homepublish/key.pem")" = original-key.pem ]
 [ "$(cat "$root/etc/homepublish/cert.pem")" = original-cert.pem ]
 [ "$(cat "$root/tmp/homepublish-service-Foreign/key.pem")" = foreign ]
 [ -z "$publish" ] || [ "$(sha256sum "$root/etc/homepublish/router.token")" = "$token_hash" ]
}
wait_marker() {
 deadline=$(($(date +%s) + 5))
 while [ "$(date +%s)" -le "$deadline" ]; do
  [ ! -f "$root/tmp/$1" ] || return 0
 done
 echo 'FAIL marker absent'; exit 1
}
# CONFIG_PROC_CHILDREN is absent on this target; use the standard PPid field.
child_of() {
 for status in /proc/[0-9]*/status; do
  while read -r field value rest; do
   if [ "$field" = 'PPid:' ] && [ "$value" = "$1" ]; then
    pid=${status#/proc/}; printf '%s\n' "${pid%/status}"; return 0
   fi
  done < "$status"
 done
 return 1
}
chroot "$root" /bin/sh -c '! command -v stat >/dev/null 2>&1'
echo 'PASS target stat absent'
for mode in expiry TERM KILL STOP; do
 rm -f "$root/tmp/ready"
 chroot "$root" /usr/libexec/homepublish-lease --provision 4 18444 18443 example.com example.com $publish &
 controller=$!
 wait_marker ready
 case "$mode" in expiry) : ;; *) kill -"$mode" "$controller" ;; esac
 sleep 5
 verify
 [ "$mode" != STOP ] || kill -CONT "$controller"
 wait "$controller" || :
 echo "PASS native provision $mode cleanup + originals/foreign"
done
for mode in KILL STOP; do
 rm -f "$root/tmp/rendering"
 touch "$root/tmp/stall-render"
 chroot "$root" /usr/libexec/homepublish-lease --provision 4 18444 18443 example.com example.com $publish &
 controller=$!
 wait_marker rendering
 guardian=$(child_of "$controller")
 preparation=$(child_of "$guardian")
 kill -"$mode" "$preparation"
 wait "$controller" || :
 verify
 rm "$root/tmp/stall-render"
 echo "PASS native preparation $mode during render cleanup"
done
rm -f "$root/tmp/ready"
extra=
[ -z "$publish" ] || extra=',"publish"'
ubus call service add "{\"name\":\"$service\",\"instances\":{\"lease\":{\"command\":[\"/usr/sbin/chroot\",\"$root\",\"/usr/libexec/homepublish-lease\",\"--provision\",\"4\",\"18444\",\"18443\",\"example.com\",\"example.com\"$extra],\"term_timeout\":1,\"stdout\":false,\"stderr\":false}}}"
wait_marker ready
state=$(ubus call service list "{\"name\":\"$service\"}")
printf '%s\n' "$state"
pid=$(printf '%s' "$state" | jsonfilter -e "@[\"$service\"].instances.lease.pid")
[ -n "$pid" ]
kill -STOP "$pid"
ubus call service delete "{\"name\":\"$service\"}"
sleep 5
verify
state=$(ubus call service list "{\"name\":\"$service\"}")
[ "$(printf '%s' "$state" | tr -d ' \t\r\n')" = '{}' ]
echo 'PASS native real procd STOP->TERM->KILL cleanup; readback absent'
