#!/bin/sh
set -e
ROOT="$1"; RPC="$ROOT/usr/libexec/rpcd/homevpn"
T="$(mktemp -d /tmp/homevpn-selfsigned-rpc.XXXXXX)"; trap 'rm -rf "$T"' EXIT
mkdir "$T/config" "$T/save" "$T/bin"
printf 'config homevpn config\n option remote vpn.example.com\n option cert_mode selfsigned\n option enabled 0\n' > "$T/config/homevpn"
printf '#!/bin/sh\nexec /sbin/uci -c "%s/config" -P "%s/save" "$@"\n' "$T" "$T" > "$T/bin/uci"
chmod +x "$T/bin/uci"; export PATH="$T/bin:$PATH"
# Source-execute the actual dispatcher branch; isolate lifecycle boundaries.
{
 printf '. /usr/share/libubox/jshn.sh\nCFG=homevpn\ncfg() { uci -q get "homevpn.config.$1"; }\nerr() { json_init; json_add_boolean ok 0; json_add_string error "$1"; json_dump; exit 0; }\nok() { json_add_boolean ok 1; }\n'
 printf '. "%s/usr/share/homevpn/selfsigned-pki.sh"\n' "$ROOT"
 printf 'json_load "$1"\ncase set_settings in\n'
 sed -n '/^[[:space:]]*set_settings)/,/^[[:space:]]*provision)/p' "$RPC" | sed '$d' | sed "s@/etc/init.d/homevpn@$T/init@g"
 printf 'esac\n'
} > "$T/branch"
printf '#!/bin/sh\necho "$*" >> "%s/calls"\n[ "$1" != check-ownership ] || [ "${BLOCK_OWNERSHIP:-0}" = 0 ] || exit 1\n[ "$1" != unconfigure ] || [ "${BLOCK_CLEAR:-0}" = 0 ]\n' "$T" > "$T/init"; chmod +x "$T/init"
. /usr/share/libubox/jshn.sh
out=$(sh "$T/branch" '{"remote":"","cert_mode":"selfsigned","vpn_name":"empty"}')
json_load "$out"; json_get_var saved saved || :; json_get_var reason reason || :; json_get_var applied applied || :
[ "$saved" = 1 ] && [ "$reason" = remote_required ] && [ "$applied" = 0 ] || { echo "FAIL blank-save contract: $out"; exit 1; }
[ -z "$(uci -q get homevpn.config.remote)" ]
# An unload refusal cannot mutate even unrelated settings.
uci set homevpn.config.remote=vpn.example.com; uci commit homevpn
before="$(sha256sum "$T/config/homevpn")"
export BLOCK_CLEAR=1
out=$(sh "$T/branch" '{"remote":"","cert_mode":"selfsigned","vpn_name":"must-not-save"}')
[ "$before" = "$(sha256sum "$T/config/homevpn")" ] || { echo 'FAIL: unsafe clear mutated settings'; exit 1; }
json_load "$out"; json_get_var result ok; [ "$result" = 0 ]
unset BLOCK_CLEAR
for remote in 'https://vpn.example.com' 'vpn.example.com:500' '*.example.com' '999.1.1.1'; do
 out=$(sh "$T/branch" "{\"remote\":\"$remote\",\"vpn_name\":\"must-not-save\"}")
 [ "$before" = "$(sha256sum "$T/config/homevpn")" ]
 json_load "$out"; json_get_var result ok; [ "$result" = 0 ]
done
echo 'PASS: explicit empty save, unsafe unload refusal and invalid address leave unrelated UCI untouched'
# Execute full plugin against relocated fixtures, no real daemon/service calls.
mkdir -p "$T/swanctl/x509ca" "$T/swanctl/x509" "$T/swanctl/private"
sed "s@SWANCTL=\"/etc/swanctl\"@SWANCTL=\"$T/swanctl\"@; s@/usr/share/homevpn/@$ROOT/usr/share/homevpn/@g; s@/etc/init.d/homevpn@$T/init@g" "$RPC" > "$T/plugin"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/pidof"; chmod +x "$T/bin/pidof"
invoke() { printf '%s\n' "$2" | sh "$T/plugin" call "$1"; }
export BLOCK_OWNERSHIP=1
out="$(invoke ensure_selfsigned_ca '{"replace":false}')"
json_load "$out"; json_get_var result ok
[ "$result" = 0 ] && [ ! -e "$T/swanctl/x509ca/homevpn-ca.crt" ] || { echo 'FAIL ownership refusal must precede CA publication'; exit 1; }
unset BLOCK_OWNERSHIP
out="$(invoke ensure_selfsigned_ca '{"replace":false}')"
json_load "$out"; json_get_var result ok; [ "$result" = 1 ]
[ ! -e "$T/swanctl/x509/homevpn-server.crt" ]
asset="$(sha256sum "$T/swanctl/x509ca/homevpn-ca.crt" "$T/swanctl/private/homevpn-ca.key")"
out="$(invoke ensure_selfsigned_ca '{"replace":false}')"
[ "$asset" = "$(sha256sum "$T/swanctl/x509ca/homevpn-ca.crt" "$T/swanctl/private/homevpn-ca.key")" ]
# stale confirmation cannot replace trust.
out="$(invoke ensure_selfsigned_ca '{"replace":true,"fingerprint":"stale"}')"
json_load "$out"; json_get_var result ok; [ "$result" = 0 ]
[ "$asset" = "$(sha256sum "$T/swanctl/x509ca/homevpn-ca.crt" "$T/swanctl/private/homevpn-ca.key")" ]
uci set homevpn.config.remote=; uci commit homevpn
out="$(invoke download '{"what":"mobileconfig","name":"fixture"}')"
json_load "$out"; json_get_var error error; [ "$error" = remote_required ]
out="$(invoke download '{"what":"ca"}')"
json_load "$out"; json_get_var result ok; [ "$result" = 1 ]
# Valid disabled profiles export from saved SAN and current trust, without daemon.
CA_DIR="$T/swanctl/x509ca"; X509_DIR="$T/swanctl/x509"; KEY_DIR="$T/swanctl/private"
. "$ROOT/usr/share/homevpn/selfsigned-pki.sh"
hv_pki_sync_leaf vpn.example.com
uci set homevpn.config.remote=vpn.example.com
uci set homevpn.config.enabled=0
uci add homevpn user >/dev/null
uci set 'homevpn.@user[-1].name=fixture'
uci set 'homevpn.@user[-1].password=FixtureOnly123'
uci commit homevpn
for profile in mobileconfig sswan; do
 out="$(invoke download "{\"what\":\"$profile\",\"name\":\"fixture\"}")"
 json_load "$out"; json_get_var result ok; [ "$result" = 1 ]
 echo "PASS: valid disabled $profile export"
done
# Read-only status must not rotate or create any PKI asset.
assets="$(sha256sum "$CA_DIR/homevpn-ca.crt" "$KEY_DIR/homevpn-ca.key" "$X509_DIR/homevpn-server.crt" "$KEY_DIR/homevpn-server.key")"
invoke status '{}' >/dev/null
[ "$assets" = "$(sha256sum "$CA_DIR/homevpn-ca.crt" "$KEY_DIR/homevpn-ca.key" "$X509_DIR/homevpn-server.crt" "$KEY_DIR/homevpn-server.key")" ]
# Actual unconfigure function: live daemon refusal retains generated file.
extra_command() { :; }
# Isolate sourced libraries without changing production files.
sed "s@/usr/share/homevpn/@$ROOT/usr/share/homevpn/@g; s@/etc/config/@$T/config/@g" "$ROOT/etc/init.d/homevpn" > "$T/init-source"
. "$T/init-source"
CONN_FILE="$T/owned.conf"; STATE_FILE="$T/state"; printf owned > "$CONN_FILE"
pidof() { return 0; }
if hv_unconfigure; then echo 'FAIL: live unconfigure accepted'; exit 1; fi
[ -s "$CONN_FILE" ]
pidof() { return 1; }
hv_unconfigure
[ ! -e "$CONN_FILE" ]
# Execute maintenance while disabled and prove it never reaches service apply.
CA_DIR="$T/swanctl/x509ca"; X509_DIR="$T/swanctl/x509"; KEY_DIR="$T/swanctl/private"
hv_get() { uci -q get "homevpn.config.$1"; }
hv_regen() { echo 'FAIL: disabled maintenance reached service apply' >&2; return 1; }
hv_provision_saved
[ "$(uci -q get homevpn.config.enabled)" = 0 ]
# Blank start fails before firewall or daemon work, even when enabled.
uci set homevpn.config.enabled=1; uci set homevpn.config.remote=; uci commit homevpn
hv_exclusive() { return 0; }; load_env() { LAN_ADDR=192.0.2.1; }
TRACE="$T/start-trace"
ensure_firewall() { echo firewall >> "$TRACE"; }
if hv_start; then echo 'FAIL: blank address started service'; exit 1; fi
[ ! -e "$TRACE" ]
echo 'PASS: actual disabled certificate maintenance and blank-address start refusal before firewall'
echo 'PASS: real RPC CA idempotency, stale rotation refusal, blank profile gate, CA-only download and actual safe unconfigure'
