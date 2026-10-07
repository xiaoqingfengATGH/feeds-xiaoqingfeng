#!/bin/sh
# Shared, side-effect-free validators and explicit self-signed PKI mutations.
# Callers hold service-lock.sh. Never infer identity from network interfaces.
hv_pki_fail() { HV_PKI_ERROR="$1"; return 1; }
hv_pki_valid_remote() {
 [ -n "$1" ] && [ "${#1}" -le 253 ] || return 1
 case "$1" in *[!A-Za-z0-9.-]*|.*|*.|*..*) return 1;; esac
 case "$1" in *[!0-9.]* )
  printf '%s\n' "$1" | awk -F. '{for(i=1;i<=NF;i++)if(length($i)>63 || $i !~ /^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/)exit 1}' ;;
 *) printf '%s\n' "$1" | awk -F. 'NF!=4 {exit 1} {for(i=1;i<=4;i++)if($i !~ /^[0-9]+$/ || length($i)>3 || $i>255 || (length($i)>1 && substr($i,1,1)=="0"))exit 1}' ;;
 esac
}
hv_pki_pair() {
 local cp kp
 openssl pkey -in "$2" -passin pass: -noout >/dev/null 2>&1 || return 1
 cp="$(openssl x509 -in "$1" -pubkey -noout 2>/dev/null)" || return 1
 kp="$(openssl pkey -in "$2" -passin pass: -pubout 2>/dev/null)" || return 1
 [ -n "$cp" ] && [ "$cp" = "$kp" ]
}
hv_pki_ca_valid() {
 HV_PKI_ERROR=
 local cert="$CA_DIR/homevpn-ca.crt" key="$KEY_DIR/homevpn-ca.key" text
 hv_pki_pair "$cert" "$key" || { hv_pki_fail ca_key_invalid; return 1; }
 text="$(openssl x509 -in "$cert" -noout -text 2>/dev/null)" || return 1
 printf '%s' "$text" | grep -q 'CA:TRUE' || { hv_pki_fail ca_constraints_invalid; return 1; }
 printf '%s' "$text" | grep -q 'Certificate Sign' || { hv_pki_fail ca_usage_invalid; return 1; }
 [ "$(openssl x509 -in "$cert" -noout -subject | sed 's/^subject=//')" = "$(openssl x509 -in "$cert" -noout -issuer | sed 's/^issuer=//')" ] || { hv_pki_fail ca_not_selfsigned; return 1; }
 openssl verify -check_ss_sig -CAfile "$cert" "$cert" >/dev/null 2>&1 || { hv_pki_fail ca_signature_or_validity_invalid; return 1; }
}
hv_pki_san() {
 local want s
 [ -n "$1" ] || return 1
 want="$(printf '%s' "$1" | tr 'a-z' 'A-Z')"
 for s in $(openssl x509 -in "$2" -noout -ext subjectAltName 2>/dev/null | tail -n +2 | tr -d ' \n' | tr 'a-z' 'A-Z' | sed 's/IPADDRESS:/IP:/g' | tr ',' ' '); do
  [ "DNS:$want" = "$s" ] || [ "IP:$want" = "$s" ] && return 0
 done
 return 1
}
hv_pki_leaf_valid() {
 local cert="$X509_DIR/homevpn-server.crt" key="$KEY_DIR/homevpn-server.key" text
 hv_pki_valid_remote "$1" || { hv_pki_fail remote_required; return 1; }
 hv_pki_ca_valid || return 1
 hv_pki_pair "$cert" "$key" || { hv_pki_fail leaf_key_invalid; return 1; }
 hv_pki_san "$1" "$cert" || { hv_pki_fail leaf_san_mismatch; return 1; }
 openssl x509 -in "$cert" -checkend "${2:-2592000}" -noout >/dev/null 2>&1 || { hv_pki_fail leaf_renewal_required; return 1; }
 text="$(openssl x509 -in "$cert" -noout -text 2>/dev/null)" || return 1
 printf '%s' "$text" | grep -q 'CA:FALSE' || { hv_pki_fail leaf_constraints_invalid; return 1; }
 printf '%s' "$text" | grep -q 'TLS Web Server Authentication' || { hv_pki_fail leaf_usage_invalid; return 1; }
 printf '%s' "$text" | grep -q 'Digital Signature' || { hv_pki_fail leaf_usage_invalid; return 1; }
 openssl verify -purpose sslserver -CAfile "$CA_DIR/homevpn-ca.crt" "$cert" >/dev/null 2>&1 || { hv_pki_fail leaf_chain_invalid; return 1; }
}
# Provenance is an explicit publication receipt bound to the leaf DER SHA-256.
# Never infer origin from selected mode, issuer names or local CA verification.
hv_pki_cert_fingerprint() {
 local fp
 fp="$(openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null)" || return 1
 fp="${fp#*=}"
 [ "${#fp}" = 95 ] || return 1
 printf '%s\n' "$fp"
}
hv_pki_source_file() {
 # CA replacement builds a complete flat candidate set in a private directory.
 if [ "$CA_DIR" = "$X509_DIR" ]; then printf '%s/.homevpn-cert-source\n' "$X509_DIR"; else printf '%s/.homevpn-cert-source\n' "$(dirname "$CA_DIR")"; fi
}
hv_pki_cert_source() {
 local source recorded extra actual
 actual="$(hv_pki_cert_fingerprint "$X509_DIR/homevpn-server.crt")" || { echo unknown; return; }
 if [ -f "$(hv_pki_source_file)" ] && read -r source recorded extra < "$(hv_pki_source_file)"; then
  case "$source" in selfsigned|import|acme)
   [ -z "$extra" ] && [ "$actual" = "$recorded" ] && { echo "$source"; return; };;
  esac
 fi
 echo unknown
}
hv_pki_publish_cert() {
 local stage="$1" source="$2" fp
 shift 2
 case "$source" in selfsigned|import|acme) ;; *) return 1;; esac
 fp="$(hv_pki_cert_fingerprint "$stage/homevpn-server.crt")" || return 1
 (umask 077; printf '%s %s\n' "$source" "$fp" > "$stage/.homevpn-cert-source") || return 1
 hv_pki_publish "$stage" "$@" "$(hv_pki_source_file)"
}
# Durable undo journal. Callers hold the transaction lock, including readers.
# A crash or persistent I/O failure keeps backups on the destination filesystem;
# subsequent consumers must recover successfully before reading/loading assets.
hv_pki_recover() {
 local j="$(dirname "$CA_DIR")/.homevpn-pki-journal" f n=0 failed=0
 [ -d "$j" ] || return 0
 [ -f "$j/ready" ] || { rm -rf "$j"; return $?; }
 while IFS= read -r f; do
  n=$((n+1))
  if [ -f "$j/old-$n" ]; then
   cp -p "$j/old-$n" "$f.recover" && mv "$f.recover" "$f" || failed=1
  else
   rm -f "$f" || failed=1
  fi
  rm -f "$f.new"
 done < "$j/manifest"
 [ "$failed" = 0 ] || { hv_pki_fail pki_recovery_required; return 1; }
 sync
 rm -f "$j/ready" || { hv_pki_fail pki_recovery_required; return 1; }
 sync
 rm -rf "$j" || { hv_pki_fail pki_recovery_required; return 1; }
 sync
}
hv_pki_publish() {
 local stage="$1" j="$(dirname "$CA_DIR")/.homevpn-pki-journal" f n=0
 shift
 hv_pki_recover || return 1
 (umask 077; mkdir -p "$j") || return 1
 for f in "$@"; do
  n=$((n+1))
  mkdir -p "$(dirname "$f")" || return 1
  if [ -e "$f" ]; then cp -p "$f" "$j/old-$n" || return 1; fi
  cp -p "$stage/$(basename "$f")" "$j/new-$n" || return 1
  printf '%s\n' "$f" >> "$j/manifest" || return 1
 done
 # ready is created only after a complete durable backup/manifest exists.
 sync
 : > "$j/ready" || return 1
 sync
 n=0
 for f in "$@"; do
  n=$((n+1))
  if ! { cp -p "$j/new-$n" "$f.new" && mv "$f.new" "$f"; }; then
   hv_pki_recover || return 1
   hv_pki_fail pki_publish_failed; return 1
  fi
 done
 sync
 # Removing ready commits; a crash before this rolls the whole set back.
 rm -f "$j/ready" || return 1
 sync
 rm -rf "$j" || return 1
}
hv_pki_ensure_ca() {
 HV_PKI_ERROR=; HV_PKI_CHANGED=0
 hv_pki_recover || return 1
 [ "${1:-0}" = 1 ] || { hv_pki_ca_valid && return 0; }
 if [ "${1:-0}" != 1 ] && { [ -e "$CA_DIR/homevpn-ca.crt" ] || [ -e "$KEY_DIR/homevpn-ca.key" ] || [ -e "$X509_DIR/homevpn-server.crt" ] || [ -e "$KEY_DIR/homevpn-server.key" ]; }; then
  hv_pki_fail ca_replace_confirmation_required; return 1
 fi
 local T rc oldca="$CA_DIR" oldkey="$KEY_DIR" oldcert="$X509_DIR"
 T="$(mktemp -d /tmp/homevpn-ca.XXXXXX)" || return 1
 chmod 700 "$T"
 (
  umask 077
  openssl genrsa -out "$T/homevpn-ca.key" 3072 2>/dev/null &&
  openssl req -x509 -new -sha256 -days 3650 -key "$T/homevpn-ca.key" -out "$T/homevpn-ca.crt" -subj '/CN=HomeVPN Root CA' -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign' 2>/dev/null || exit 1
  CA_DIR="$T"; KEY_DIR="$T"; X509_DIR="$T"
  hv_pki_ca_valid || exit 1
  [ -z "${2:-}" ] || hv_pki_sync_leaf "$2"
 )
 rc=$?
 if [ "$rc" = 0 ]; then
  if [ -n "${2:-}" ]; then hv_pki_publish_cert "$T" selfsigned "$oldca/homevpn-ca.crt" "$oldkey/homevpn-ca.key" "$oldcert/homevpn-server.crt" "$oldkey/homevpn-server.key"; else hv_pki_publish "$T" "$oldca/homevpn-ca.crt" "$oldkey/homevpn-ca.key"; fi
  rc=$?
 fi
 rm -rf "$T"
 [ "$rc" = 0 ] || { hv_pki_fail ca_creation_failed; return 1; }
 HV_PKI_CHANGED=1; HV_PKI_ERROR=
}
hv_pki_sync_leaf() {
 HV_PKI_ERROR=; HV_PKI_LEAF_CHANGED=0
 hv_pki_valid_remote "$1" || { hv_pki_fail remote_required; return 1; }
 hv_pki_ensure_ca 0 || return 1
 hv_pki_leaf_valid "$1" 2592000 && return 0
 openssl x509 -in "$CA_DIR/homevpn-ca.crt" -checkend 2678400 -noout >/dev/null 2>&1 || { hv_pki_fail ca_lifetime_insufficient; return 1; }
 local T low=1 high=825 mid days san="DNS:$1" rc
 # Bound leaf lifetime by CA remaining lifetime, with one-day safety margin.
 while [ "$low" -le "$high" ]; do
  mid=$(((low + high) / 2))
  if openssl x509 -in "$CA_DIR/homevpn-ca.crt" -checkend "$(((mid + 1) * 86400))" -noout >/dev/null 2>&1; then days="$mid"; low=$((mid+1)); else high=$((mid-1)); fi
 done
 T="$(mktemp -d /tmp/homevpn-leaf.XXXXXX)" || return 1
 chmod 700 "$T"
 case "$1" in *[!0-9.]* ) ;; *) san="IP:$1";; esac
 (
  umask 077
  if openssl pkey -in "$KEY_DIR/homevpn-server.key" -passin pass: -noout >/dev/null 2>&1; then cp "$KEY_DIR/homevpn-server.key" "$T/homevpn-server.key"; else openssl genrsa -out "$T/homevpn-server.key" 2048 2>/dev/null; fi || exit 1
  printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=%s\n' "$san" > "$T/ext"
  openssl req -new -sha256 -key "$T/homevpn-server.key" -out "$T/req" -subj "/CN=$1" 2>/dev/null &&
  openssl x509 -req -sha256 -days "$days" -in "$T/req" -CA "$CA_DIR/homevpn-ca.crt" -CAkey "$KEY_DIR/homevpn-ca.key" -set_serial "0x$(openssl rand -hex 16)" -out "$T/homevpn-server.crt" -extfile "$T/ext" 2>/dev/null || exit 1
  KEY_DIR="$T"; X509_DIR="$T"
  # Validate against the live CA without requiring its key in staging.
  hv_pki_pair "$T/homevpn-server.crt" "$T/homevpn-server.key" && hv_pki_san "$1" "$T/homevpn-server.crt" && openssl verify -purpose sslserver -CAfile "$CA_DIR/homevpn-ca.crt" "$T/homevpn-server.crt" >/dev/null 2>&1
 )
 rc=$?
 [ "$rc" != 0 ] || { hv_pki_publish_cert "$T" selfsigned "$X509_DIR/homevpn-server.crt" "$KEY_DIR/homevpn-server.key"; rc=$?; }
 rm -rf "$T"
 [ "$rc" = 0 ] || { hv_pki_fail leaf_signing_failed; return 1; }
 HV_PKI_LEAF_CHANGED=1; HV_PKI_ERROR=
}
