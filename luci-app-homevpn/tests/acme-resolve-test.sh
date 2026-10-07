#!/bin/sh
# Run on OpenWrt: sh acme-resolve-test.sh /path/to/package/root
set -eu
ROOT="${1:-$(pwd)/root}"
T=$(mktemp -d /tmp/homevpn-test.XXXXXX)
trap 'rm -rf "$T"' EXIT
export HV_ACME_STATE_DIR="$T/acme" HV_ACME_LINK_DIR="$T/links"
mkdir -p "$HV_ACME_STATE_DIR/test.example" "$HV_ACME_STATE_DIR/test.example_ecc" "$HV_ACME_LINK_DIR"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/rsa.key" -out "$T/rsa.crt" -days 1 -subj /CN=test.example -addext subjectAltName=DNS:test.example >/dev/null 2>&1
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$T/ecc.key" -out "$T/ecc.crt" -days 1 -subj /CN=test.example -addext subjectAltName=DNS:test.example >/dev/null 2>&1
cp "$T/rsa.key" "$HV_ACME_STATE_DIR/test.example/test.example.key"
cp "$T/rsa.crt" "$HV_ACME_STATE_DIR/test.example/fullchain.cer"
cp "$T/ecc.key" "$HV_ACME_STATE_DIR/test.example_ecc/test.example.key"
cp "$T/ecc.crt" "$HV_ACME_STATE_DIR/test.example_ecc/fullchain.cer"
. "$ROOT/usr/share/homevpn/acme-resolve.sh"
fail() { echo "FAIL: $*"; exit 1; }
homevpn_acme_resolve test.example || fail 'default RSA resolution'
[ "$HV_ACME_CRT" = "$HV_ACME_STATE_DIR/test.example/fullchain.cer" ] || fail 'default chooses RSA'
echo 'PASS: default RSA in /etc/acme layout'
for stamp in 202001010000 203001010000; do
 touch -t "$stamp" "$HV_ACME_STATE_DIR/test.example_ecc/fullchain.cer"
 homevpn_acme_resolve test.example rsa || fail rsa
 [ "$HV_ACME_CRT" = "$HV_ACME_STATE_DIR/test.example/fullchain.cer" ] || fail 'mtime RSA'
 homevpn_acme_resolve test.example ecc || fail ecc
 [ "$HV_ACME_CRT" = "$HV_ACME_STATE_DIR/test.example_ecc/fullchain.cer" ] || fail 'mtime ECC'
done
echo 'PASS: explicit RSA/ECC independent of mtime'
extra_command() { :; }
sed "s@/usr/share/homevpn/@$ROOT/usr/share/homevpn/@g" "$ROOT/etc/init.d/homevpn" > "$T/init"
. "$T/init"
ACME_RESOLVER="$ROOT/usr/share/homevpn/acme-resolve.sh"
X509_DIR="$T/swan/x509"; KEY_DIR="$T/swan/private"; CA_DIR="$T/swan/x509ca"
mkdir -p "$X509_DIR" "$KEY_DIR" "$CA_DIR"
hv_get() { [ "$1" != acme_key_type ] || echo ecc; }
effective_remote() { echo test.example; }
logger_tag() { :; }
sync_acme_certs test.example || fail 'sync ECC'
[ "$(hv_pki_cert_source)" = acme ] || fail 'ACME publication provenance'
cmp "$X509_DIR/homevpn-server.crt" "$T/ecc.crt" || fail 'init must honor selected ECC'
echo 'PASS: init honors configured key type'
# A renewed certificate may reuse its key. Compare the entire leaf, not pubkey.
openssl req -x509 -new -key "$T/ecc.key" -out "$T/renew.crt" -days 2 -subj /CN=test.example -addext subjectAltName=DNS:test.example >/dev/null 2>&1
cp "$T/renew.crt" "$HV_ACME_STATE_DIR/test.example_ecc/fullchain.cer"
sync_acme_certs test.example || fail renewal
cmp "$X509_DIR/homevpn-server.crt" "$T/renew.crt" || fail 'renewed leaf with same key'
echo 'PASS: same-key renewed certificate installed'
cp "$T/rsa.key" "$KEY_DIR/homevpn-server.key"
sync_acme_certs test.example || fail 'repair deployed key'
cmp "$KEY_DIR/homevpn-server.key" "$T/ecc.key" || fail 'stale deployed key must be repaired'
echo 'PASS: stale deployed key repaired'
effective_remote() { echo wrong.example; }
sync_acme_certs test.example && fail 'SAN mismatch accepted'
cmp "$X509_DIR/homevpn-server.crt" "$T/renew.crt" || fail 'SAN refusal changed deployed leaf'
effective_remote() { echo test.example; }
echo 'PASS: SAN mismatch preserves deployed certificate'
# Exercise the production one-PEM-per-file splitter with generated PEM fixtures.
cat "$T/renew.crt" "$T/rsa.crt" "$T/ecc.crt" > "$HV_ACME_STATE_DIR/test.example_ecc/fullchain.cer"
sync_acme_certs test.example || fail 'chain install'
for cert in "$X509_DIR/homevpn-server.crt" "$CA_DIR/homevpn-acme-01.crt" "$CA_DIR/homevpn-acme-02.crt"; do
 [ "$(grep -c 'BEGIN CERTIFICATE' "$cert")" = 1 ] || fail 'multiple PEM blocks in deployed file'
done
cat "$T/renew.crt" "$T/rsa.crt" > "$HV_ACME_STATE_DIR/test.example_ecc/fullchain.cer"
sync_acme_certs test.example || fail 'shorter chain install'
[ ! -e "$CA_DIR/homevpn-acme-02.crt" ] || fail 'stale chain file left behind'
echo 'PASS: one PEM per file and stale chain cleanup'
cp "$T/rsa.key" "$HV_ACME_STATE_DIR/test.example_ecc/test.example.key"
homevpn_acme_resolve test.example ecc && fail 'mismatched key accepted'
[ -z "$HV_ACME_CRT$HV_ACME_KEY" ] || fail 'stale resolver output'
echo 'PASS: mismatched pair rejected, output cleared'
cp "$T/ecc.key" "$HV_ACME_STATE_DIR/test.example/test.example.key"
cp "$T/ecc.crt" "$HV_ACME_STATE_DIR/test.example/fullchain.cer"
homevpn_acme_resolve test.example rsa && fail 'EC in RSA directory accepted'
echo 'PASS: actual algorithm checked, not directory name'
rm -rf "$HV_ACME_STATE_DIR/test.example" "$HV_ACME_STATE_DIR/test.example_ecc"
cp "$T/ecc.crt" "$HV_ACME_LINK_DIR/test.example.fullchain.crt"
cp "$T/ecc.key" "$HV_ACME_LINK_DIR/test.example.key"
homevpn_acme_resolve test.example rsa && fail 'cross-type stable link fallback'
homevpn_acme_resolve test.example ecc || fail 'same-type stable link fallback'
homevpn_acme_resolve missing.example rsa && fail 'missing certificate accepted'
homevpn_acme_resolve test.example invalid && fail 'invalid type accepted'
echo 'PASS: missing/invalid type rejected; fallback type-safe'
# rpcd must advertise the type argument or ubus drops it before dispatch.
sed "s@/usr/share/homevpn/@$ROOT/usr/share/homevpn/@g" "$ROOT/usr/libexec/rpcd/homevpn" > "$T/rpc"
sh "$T/rpc" list | grep -q '"acme_key_type"' || fail 'rpcd key-type contract missing'
echo 'PASS: rpcd advertises key-type setting'
sh "$T/rpc" list | grep -q '"ip_mode"' || fail 'key-type saves must preserve UI network fields through ubus'
echo 'PASS: rpcd advertises existing network settings'
