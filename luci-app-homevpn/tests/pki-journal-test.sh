#!/bin/sh
set -e
. "$1/usr/share/homevpn/selfsigned-pki.sh"
T=$(mktemp -d /tmp/hv-journal-test.XXXXXX)
trap 'rm -rf "$T"' EXIT
CA_DIR="$T/live/ca"; KEY_DIR="$T/live/key"; X509_DIR="$T/live/cert"
mkdir -p "$CA_DIR" "$KEY_DIR" "$X509_DIR" "$T/stage"
a="$X509_DIR/homevpn-server.crt"; b="$KEY_DIR/homevpn-server.key"
printf old-cert > "$a"; printf old-key > "$b"
printf new-cert > "$T/stage/homevpn-server.crt"; printf new-key > "$T/stage/homevpn-server.key"
set +e
(
 mv() { command mv "$@" || return; case "$2" in "$a") exit 99;; esac; }
 hv_pki_publish "$T/stage" "$a" "$b"
)
rc=$?
set -e
[ "$rc" = 99 ]
hv_pki_recover
[ "$(cat "$a")" = old-cert ] && [ "$(cat "$b")" = old-key ]
echo 'PASS interruption after first rename restores whole set'
cp() { case "$*" in *homevpn-server.key.new*|*.recover*) return 1;; esac; command cp "$@"; }
if hv_pki_publish "$T/stage" "$a" "$b"; then exit 23; fi
[ -d "$(dirname "$CA_DIR")/.homevpn-pki-journal" ]
if hv_pki_recover; then exit 25; fi
unset -f cp
hv_pki_recover
[ "$(cat "$a")" = old-cert ] && [ "$(cat "$b")" = old-key ]
echo 'PASS persistent I/O failure retains backup until recovery succeeds'
