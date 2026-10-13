#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Native helper enforces the hard deadline. A detached waiter owns sources:
# killing/stopping the procd-facing adapter cannot suppress source cleanup.
set -u
if [ "${1-}" != --owned-watch ]; then
 [ "$#" = 6 ] || exit 2
 child=
 cancel() { [ -z "$child" ] || kill -TERM "$child" 2>/dev/null || :; }
 trap cancel TERM INT
 setsid /bin/sh "$0" --owned-watch "$@" &
 child=$!
 while :; do
  wait "$child"; result=$?
  kill -0 "$child" 2>/dev/null || break
 done
 exit "$result"
fi
shift
[ "$#" = 6 ] || exit 2
runtime=$1
case "$2" in ''|0*|*[!0-9]*) exit 2 ;; esac
[ "${#2}" -le 3 ] && [ "$2" -le 120 ] || exit 2
case "$runtime" in /tmp/homestun-service-*) suffix=${runtime#/tmp/homestun-service-} ;; *) exit 2 ;; esac
case "$suffix" in ''|*[!a-zA-Z0-9]*) exit 2 ;; esac
[ ! -L "$runtime" ] && [ -d "$runtime" ] || exit 2
metadata=$(/usr/libexec/homestun-lease --metadata "$runtime") || exit 2
[ "${metadata%:*}" = '0:700' ] || exit 2
[ ! -e "$runtime/runner.lock" ] && [ ! -L "$runtime/runner.lock" ] || exit 2
umask 077
# A competing adapter never acquires cleanup ownership.
mkdir "$runtime/source.owner" || exit 2
directory=$(/usr/libexec/homestun-lease --identity "$runtime")
owner=$(/usr/libexec/homestun-lease --identity "$runtime/source.owner")
cert=$(/usr/libexec/homestun-lease --identity "$runtime/cert.pem")
key=$(/usr/libexec/homestun-lease --identity "$runtime/key.pem")
config=$(/usr/libexec/homestun-lease --identity "$runtime/nginx.conf")
cleanup() {
 [ ! -L "$runtime" ] && [ "$(/usr/libexec/homestun-lease --identity "$runtime" 2>/dev/null)" = "$directory" ] || return
 [ ! -L "$runtime/source.owner" ] && [ "$(/usr/libexec/homestun-lease --identity "$runtime/source.owner" 2>/dev/null)" = "$owner" ] || return
 [ ! -e "$runtime/runner.lock" ] && [ ! -L "$runtime/runner.lock" ] || return
 for file in cert.pem key.pem nginx.conf; do
  case "$file" in cert.pem) expected=$cert ;; key.pem) expected=$key ;; nginx.conf) expected=$config ;; esac
  [ ! -L "$runtime/$file" ] && [ "$(/usr/libexec/homestun-lease --identity "$runtime/$file" 2>/dev/null)" = "$expected" ] && rm -f "$runtime/$file"
 done
 rmdir "$runtime/source.owner"
 # Never recursively delete unknown/replaced files.
 rmdir "$runtime" 2>/dev/null || :
}
child=
cancel() { [ -z "$child" ] || kill -TERM "$child" 2>/dev/null || :; }
trap cancel TERM INT
/usr/libexec/homestun-lease "$@" &
child=$!
# Signals interrupt wait: reap the helper before deleting sources.
while :; do
 wait "$child"; result=$?
 kill -0 "$child" 2>/dev/null || break
done
trap '' TERM INT
# Controller SIGKILL can be reaped before its surviving guardian has removed
# runner.lock. Never delete an active/foreign snapshot; give the independent
# native guardian its bounded lease plus two polling intervals to finish.
case "$2" in ''|*[!0-9]*) budget=0 ;; *) budget=$(( $2 + 2 )) ;; esac
[ "$budget" -le 122 ] || budget=122
while [ -e "$runtime/runner.lock" ] && [ "$budget" -gt 0 ]; do
 sleep 1
 budget=$((budget - 1))
done
cleanup
exit "$result"

