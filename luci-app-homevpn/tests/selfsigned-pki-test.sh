#!/bin/sh
# Run on OpenWrt ash against isolated filesystem fixtures only.
set -eu
ROOT="$1"
T="$(mktemp -d /tmp/homevpn-pki-test.XXXXXX)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ca" "$T/cert" "$T/key"
CA_DIR="$T/ca"; X509_DIR="$T/cert"; KEY_DIR="$T/key"
# Expected new library contract; first red fails here, not in a mock.
[ -f "$ROOT/usr/share/homevpn/selfsigned-pki.sh" ] || { echo 'FAIL: independent CA lifecycle missing'; exit 1; }
. "$ROOT/usr/share/homevpn/selfsigned-pki.sh"
hv_pki_ensure_ca 0
[ -s "$CA_DIR/homevpn-ca.crt" ]
[ ! -e "$X509_DIR/homevpn-server.crt" ]
a="$(sha256sum "$CA_DIR/homevpn-ca.crt" "$KEY_DIR/homevpn-ca.key")"
hv_pki_ensure_ca 0
[ "$a" = "$(sha256sum "$CA_DIR/homevpn-ca.crt" "$KEY_DIR/homevpn-ca.key")" ]
if hv_pki_sync_leaf ''; then echo 'FAIL: blank address accepted'; exit 1; fi
[ ! -e "$X509_DIR/homevpn-server.crt" ]
hv_pki_sync_leaf vpn.example.com
hv_pki_leaf_valid vpn.example.com 2592000
b="$(sha256sum "$X509_DIR/homevpn-server.crt" "$KEY_DIR/homevpn-server.key")"
hv_pki_sync_leaf vpn.example.com
[ "$b" = "$(sha256sum "$X509_DIR/homevpn-server.crt" "$KEY_DIR/homevpn-server.key")" ]
hv_pki_sync_leaf 192.0.2.15
hv_pki_leaf_valid 192.0.2.15 2592000
[ "$a" = "$(sha256sum "$CA_DIR/homevpn-ca.crt" "$KEY_DIR/homevpn-ca.key")" ]
openssl x509 -in "$X509_DIR/homevpn-server.crt" -noout -ext subjectAltName | grep -q 'IP Address:192.0.2.15'
# Force rotation of a valid CA is explicit and creates a matching staged leaf.
old_fp="$(sha256sum "$CA_DIR/homevpn-ca.crt")"
hv_pki_ensure_ca 1 vpn.example.com
[ "$old_fp" != "$(sha256sum "$CA_DIR/homevpn-ca.crt")" ]
hv_pki_leaf_valid vpn.example.com 2592000
# Issue deliberately near-expiry and wrong-purpose leaves with real OpenSSL.
key_before="$(sha256sum "$KEY_DIR/homevpn-server.key")"
openssl req -new -key "$KEY_DIR/homevpn-server.key" -out "$T/req" -subj '/CN=vpn.example.com' 2>/dev/null
printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:vpn.example.com\n' > "$T/ext"
openssl x509 -req -in "$T/req" -CA "$CA_DIR/homevpn-ca.crt" -CAkey "$KEY_DIR/homevpn-ca.key" -set_serial 42 -days 29 -extfile "$T/ext" -out "$X509_DIR/homevpn-server.crt" 2>/dev/null
if hv_pki_leaf_valid vpn.example.com 2592000; then echo 'FAIL: renewal window not enforced'; exit 1; fi
hv_pki_sync_leaf vpn.example.com
[ "$key_before" = "$(sha256sum "$KEY_DIR/homevpn-server.key")" ]
mkdir -p "$T/ca-db"; : > "$T/index"; printf '10\n' > "$T/serial"
cat > "$T/ca.conf" <<EOF
[ca]
default_ca=test
[test]
database=$T/index
new_certs_dir=$T/ca-db
serial=$T/serial
certificate=$CA_DIR/homevpn-ca.crt
private_key=$KEY_DIR/homevpn-ca.key
default_md=sha256
policy=subject
[subject]
commonName=supplied
EOF
openssl ca -batch -config "$T/ca.conf" -startdate 20000101000000Z -enddate 20010101000000Z -in "$T/req" -out "$X509_DIR/homevpn-server.crt" -extfile "$T/ext" >/dev/null 2>&1
if hv_pki_leaf_valid vpn.example.com 0; then echo 'FAIL: expired leaf accepted'; exit 1; fi
hv_pki_sync_leaf vpn.example.com
sed -i 's/serverAuth/clientAuth/' "$T/ext"
openssl x509 -req -in "$T/req" -CA "$CA_DIR/homevpn-ca.crt" -CAkey "$KEY_DIR/homevpn-ca.key" -set_serial 43 -days 365 -extfile "$T/ext" -out "$X509_DIR/homevpn-server.crt" 2>/dev/null
if hv_pki_leaf_valid vpn.example.com 0; then echo 'FAIL: clientAuth accepted'; exit 1; fi
hv_pki_sync_leaf vpn.example.com
hv_pki_leaf_valid vpn.example.com 2592000
# Short-lived valid CA bounds new leaf validity and fails closed under 31 days.
cp "$CA_DIR/homevpn-ca.crt" "$T/original-ca.crt"
openssl req -x509 -new -sha256 -days 45 -key "$KEY_DIR/homevpn-ca.key" -out "$CA_DIR/homevpn-ca.crt" -subj '/CN=HomeVPN Root CA' -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign' 2>/dev/null
hv_pki_sync_leaf short.example.com
hv_pki_leaf_valid short.example.com 2592000
if openssl x509 -in "$X509_DIR/homevpn-server.crt" -checkend 3888000 -noout >/dev/null; then echo 'FAIL: leaf outlives CA'; exit 1; fi
openssl req -x509 -new -sha256 -days 1 -key "$KEY_DIR/homevpn-ca.key" -out "$CA_DIR/homevpn-ca.crt" -subj '/CN=HomeVPN Root CA' -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign' 2>/dev/null
leaf_before="$(sha256sum "$X509_DIR/homevpn-server.crt" "$KEY_DIR/homevpn-server.key")"
if hv_pki_sync_leaf new.example.com; then echo 'FAIL: nearly expired CA signed leaf'; exit 1; fi
[ "$leaf_before" = "$(sha256sum "$X509_DIR/homevpn-server.crt" "$KEY_DIR/homevpn-server.key")" ]
# A structurally valid self-signed certificate is not necessarily a signing CA.
openssl req -x509 -new -sha256 -days 365 -key "$KEY_DIR/homevpn-ca.key" -out "$CA_DIR/homevpn-ca.crt" -subj '/CN=HomeVPN Root CA' -addext 'basicConstraints=critical,CA:FALSE' -addext 'keyUsage=digitalSignature' 2>/dev/null
if hv_pki_ca_valid; then echo 'FAIL: non-CA root accepted'; exit 1; fi
cp "$T/original-ca.crt" "$CA_DIR/homevpn-ca.crt"
# Corrupt the signature only: PEM still parses and public key still matches.
openssl x509 -in "$CA_DIR/homevpn-ca.crt" -outform DER -out "$T/root.der"
openssl base64 -A -in "$T/root.der" | sed 's/A\([A-Za-z0-9+/=]\{3\}\)$/B\1/; t; s/.\([A-Za-z0-9+/=]\{3\}\)$/A\1/' | openssl base64 -d -A -out "$T/bad.der"
openssl x509 -inform DER -in "$T/bad.der" -out "$CA_DIR/homevpn-ca.crt"
hv_pki_pair "$CA_DIR/homevpn-ca.crt" "$KEY_DIR/homevpn-ca.key"
if hv_pki_ca_valid; then echo 'FAIL: corrupt self-signature accepted'; exit 1; fi
cp "$T/original-ca.crt" "$CA_DIR/homevpn-ca.crt"
hv_pki_sync_leaf vpn.example.com
# Existing broken trust is never silently overwritten.
printf broken > "$KEY_DIR/homevpn-ca.key"
a="$(sha256sum "$CA_DIR/homevpn-ca.crt" "$KEY_DIR/homevpn-ca.key" "$X509_DIR/homevpn-server.crt")"
if hv_pki_ensure_ca 0; then echo 'FAIL: damaged CA silently replaced'; exit 1; fi
[ "$a" = "$(sha256sum "$CA_DIR/homevpn-ca.crt" "$KEY_DIR/homevpn-ca.key" "$X509_DIR/homevpn-server.crt")" ]
hv_pki_ensure_ca 1
hv_pki_ca_valid
if hv_pki_leaf_valid vpn.example.com 0; then echo 'FAIL: old leaf trusted after rotation'; exit 1; fi
for address in 'https://vpn.example.com' 'a/b' 'vpn.example.com:500' '*.example.com' '999.1.1.1' '::1'; do
 if hv_pki_valid_remote "$address"; then echo "FAIL: accepted $address"; exit 1; fi
done
echo 'PASS: CA-only initialization, idempotency, leaf reuse/re-sign, IP SAN, trust replacement and address rejection'
