#!/bin/sh
set -e
ROOT="$1"
. "$ROOT/usr/share/homevpn/selfsigned-pki.sh"
T="$(mktemp -d /tmp/homevpn-source-test.XXXXXX)"; trap 'rm -rf "$T"' EXIT
CA_DIR="$T/live/x509ca"; X509_DIR="$T/live/x509"; KEY_DIR="$T/live/private"
mkdir -p "$CA_DIR" "$X509_DIR" "$KEY_DIR" "$T/stage"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/stage/homevpn-server.key" -out "$T/stage/homevpn-server.crt" -days 2 -subj /CN=fixture >/dev/null 2>&1
cp "$T/stage/homevpn-server.crt" "$X509_DIR/homevpn-server.crt"
[ "$(hv_pki_cert_source)" = unknown ]
for source in selfsigned import acme; do
 hv_pki_publish_cert "$T/stage" "$source" "$X509_DIR/homevpn-server.crt" "$KEY_DIR/homevpn-server.key"
 [ "$(hv_pki_cert_source)" = "$source" ]
 cert_mode=import; [ "$(hv_pki_cert_source)" = "$source" ]
done
printf 'import WRONG\n' > "$T/live/.homevpn-cert-source"
[ "$(hv_pki_cert_source)" = unknown ]
printf 'PASS: missing/mismatching provenance is unknown; explicit publication records all sources independently of mode\n'
# Fail publication AND immediate recovery after the first rename. The receipt
# must not be replaced, and backups must survive until storage works again.
hv_pki_publish_cert "$T/stage" selfsigned "$X509_DIR/homevpn-server.crt" "$KEY_DIR/homevpn-server.key"
old="$(sha256sum "$X509_DIR/homevpn-server.crt" "$KEY_DIR/homevpn-server.key" "$T/live/.homevpn-cert-source")"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/stage/homevpn-server.key" -out "$T/stage/homevpn-server.crt" -days 2 -subj /CN=new >/dev/null 2>&1
count=0
mv() { count=$((count+1)); [ "$count" = 1 ] && command mv "$@"; }
if hv_pki_publish_cert "$T/stage" import "$X509_DIR/homevpn-server.crt" "$KEY_DIR/homevpn-server.key"; then echo 'FAIL fault accepted'; exit 1; fi
[ -f "$T/live/.homevpn-pki-journal/ready" ]
[ "$(hv_pki_cert_source)" = unknown ]
unset -f mv
hv_pki_recover
[ "$old" = "$(sha256sum "$X509_DIR/homevpn-server.crt" "$KEY_DIR/homevpn-server.key" "$T/live/.homevpn-cert-source")" ]
[ "$(hv_pki_cert_source)" = selfsigned ]
echo 'PASS: interrupted leaf publication fails closed; durable recovery restores exact leaf/key/source receipt'
# Exercise the actual upload and status dispatcher using isolated UCI/assets.
mkdir -p "$T/config" "$T/save" "$T/bin"
printf 'config homevpn config\n option remote vpn.example.com\n option cert_mode selfsigned\n option enabled 0\n' > "$T/config/homevpn"
printf '#!/bin/sh\nexec /sbin/uci -c "%s/config" -P "%s/save" "$@"\n' "$T" "$T" > "$T/bin/uci"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/pidof"
printf '#!/bin/sh\nexit 0\n' > "$T/init"
chmod +x "$T/bin/uci" "$T/bin/pidof" "$T/init"; export PATH="$T/bin:$PATH"
sed "s@SWANCTL=\"/etc/swanctl\"@SWANCTL=\"$T/live\"@; s@/usr/share/homevpn/@$ROOT/usr/share/homevpn/@g; s@/etc/init.d/homevpn@$T/init@g" "$ROOT/usr/libexec/rpcd/homevpn" > "$T/plugin"
. /usr/share/libubox/jshn.sh
invoke() { printf '%s\n' "$2" | sh "$T/plugin" call "$1"; }
assert_source() { out="$(invoke status '{}')"; json_load "$out"; json_select cert; json_get_var actual source; [ "$actual" = "$1" ] || { echo "FAIL status expected $1: $out"; exit 1; }; }
# Real signing records selfsigned, not just matching a CA or the chosen mode.
rm -f "$X509_DIR/homevpn-server.crt" "$KEY_DIR/homevpn-server.key" "$T/live/.homevpn-cert-source"
hv_pki_sync_leaf vpn.example.com
assert_source selfsigned
invoke set_settings '{"cert_mode":"import","remote":"vpn.example.com"}' >/dev/null
[ "$(uci -q get homevpn.config.cert_mode)" = import ]
assert_source selfsigned
# Upload even the same locally signed leaf is user import, not inferred selfsigned.
json_init; json_add_string server "$(cat "$X509_DIR/homevpn-server.crt")"; json_add_string key "$(cat "$KEY_DIR/homevpn-server.key")"
payload="$(json_dump)"; out="$(invoke upload_certs "$payload")"
json_load "$out"; json_get_var result ok; [ "$result" = 1 ] || { echo "$out"; exit 1; }
assert_source import
json_init; json_add_string ca "$(cat "$CA_DIR/homevpn-ca.crt")"; payload="$(json_dump)"
invoke upload_certs "$payload" >/dev/null; assert_source import
receipt="$(sha256sum "$T/live/.homevpn-cert-source")"
invoke upload_certs '{"server":"invalid","key":"invalid"}' >/dev/null
[ "$receipt" = "$(sha256sum "$T/live/.homevpn-cert-source")" ]; assert_source import
rm "$T/live/.homevpn-cert-source"; assert_source unknown
# A reusable legacy selfsigned leaf must not retroactively claim provenance.
hv_pki_sync_leaf vpn.example.com; assert_source unknown
invoke upload_certs "$payload" >/dev/null; assert_source unknown
echo 'PASS: real signing/status/upload, mode-only save, same-CA import, invalid upload, CA-only preservation and legacy unknown'
