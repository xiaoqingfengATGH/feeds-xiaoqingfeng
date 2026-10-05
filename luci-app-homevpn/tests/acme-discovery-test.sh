#!/bin/sh
# Read-only RPC tests; fixtures live ONLY in a private /tmp directory.
set -eu
ROOT="${1:-/}"
RPC="$ROOT/usr/libexec/rpcd/homevpn"
T=$(mktemp -d /tmp/homevpn-discovery.XXXXXX)
trap 'rm -rf "$T"' EXIT
export HV_ACME_STATE_DIR="$T/acme" HV_ACME_LINK_DIR="$T/links"
mkdir -p "$HV_ACME_STATE_DIR/test.example" "$HV_ACME_STATE_DIR/test.example_ecc" "$HV_ACME_LINK_DIR"
probe() { printf '%s\n' '{"domain":"test.example"}' | sh "$RPC" call discover_acme; }
check() {
 result=$(probe)
 [ "$(printf '%s' "$result" | jsonfilter -e '@.ok')" = true ] || { echo "FAIL: discovery RPC: $result"; exit 1; }
 types=$(printf '%s' "$result" | jsonfilter -e '@.types[*]' | tr '\n' ' ')
 [ "$types" = "$1" ] || { echo "FAIL: expected [$1] got [$types]"; exit 1; }
 echo "PASS: read-only discovery [$types]"
}
check ''
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$HV_ACME_STATE_DIR/test.example/test.example.key" -out "$HV_ACME_STATE_DIR/test.example/fullchain.cer" -days 1 -subj /CN=test.example >/dev/null 2>&1
check 'rsa '
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$HV_ACME_STATE_DIR/test.example_ecc/test.example.key" -out "$HV_ACME_STATE_DIR/test.example_ecc/fullchain.cer" -days 1 -subj /CN=test.example >/dev/null 2>&1
check 'rsa ecc '
rm -rf "$HV_ACME_STATE_DIR/test.example"
check 'ecc '
cp "$HV_ACME_STATE_DIR/test.example_ecc/fullchain.cer" "$HV_ACME_LINK_DIR/test.example.fullchain.crt"
cp "$HV_ACME_STATE_DIR/test.example_ecc/test.example.key" "$HV_ACME_LINK_DIR/test.example.key"
rm -rf "$HV_ACME_STATE_DIR/test.example_ecc"
check 'ecc '
printf '%s\n' '{"domain":"../../etc"}' | sh "$RPC" call discover_acme | jsonfilter -e '@.ok' | grep -qx false
printf '%s\n' '{"domain":""}' | sh "$RPC" call discover_acme | jsonfilter -e '@.ok' | grep -qx false
echo 'PASS: empty and invalid domains are errors, not missing certificates'
sh "$RPC" list | jsonfilter -e '@.discover_acme.domain' | grep -qx ''
echo 'PASS: discovery method advertises domain parameter'
