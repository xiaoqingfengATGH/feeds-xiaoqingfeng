#!/bin/sh
set -eu
r=/tmp/homestun-sdk-abi
cd /
trap 'rm -rf "$r"' EXIT
chmod 0700 "$r"
chmod 0755 "$r/homestun-lease" "$r/homestun-publish"
sha256sum "$r/homestun-lease" "$r/homestun-publish"
printf fixture > "$r/metadata"
chmod 0600 "$r/metadata"
[ "$("$r/homestun-lease" --metadata "$r/metadata")" = '0:600:1' ]
echo 'PASS SDK lease helper metadata ABI'
ln -s metadata "$r/link"
set +e
"$r/homestun-lease" --metadata "$r/link" > "$r/rejected"
rc=$?
set -e
[ "$rc" = 2 ] && [ ! -s "$r/rejected" ]
echo 'PASS SDK lease helper symlink fail-closed'
now=$(date +%s)
read uptime unused < /proc/uptime
mono=${uptime%%.*}
printf '%s %s %s %s 18444 0\n' "$now" 0123456789abcdef0123456789abcdef "$(((now+60)*1000))" "$((mono+60))" > "$r/session"
printf 'invalid!' > "$r/router.token"
chmod 0600 "$r/session" "$r/router.token"
before=$(sha256sum "$r/session")
set +e
"$r/homestun-publish" --begin "$r"
rc=$?
set -e
[ "$rc" = 2 ] && [ "$(sha256sum "$r/session")" = "$before" ]
echo 'PASS SDK publisher ABI invalid-token begin rejected without session mutation'
set +e
HOMESTUN_RUNTIME="$r" "$r/homestun-publish" 192.0.2.10 18443 unused 18444 tcp 127.0.0.1
rc=$?
set -e
[ "$rc" = 2 ] && [ "$(sha256sum "$r/session")" = "$before" ]
echo 'PASS SDK publisher invalid-token callback rejected without sequence mutation'
rm -rf "$r"
trap - EXIT
[ ! -e "$r" ]
echo 'PASS fixture cleanup'
