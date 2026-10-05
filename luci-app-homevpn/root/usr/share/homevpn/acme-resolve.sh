#!/bin/sh
# Shared resolver: explicit type, never mtime or cross-type fallback.
# Directory overrides are for isolated shell regression tests.
homevpn_acme_valid_domain() {
 case "$1" in ''|*[!A-Za-z0-9.*_-]*|*..*|.*) return 1;; esac
 return 0
}
homevpn_acme_resolve() {
 HV_ACME_CRT=""; HV_ACME_KEY=""; HV_ACME_ERROR=""
 local d="$1" kind="${2:-rsa}" dirs base f key cert_pub key_pub
 homevpn_acme_valid_domain "$d" || { HV_ACME_ERROR="invalid domain"; return 1; }
 base="${HV_ACME_STATE_DIR:-/etc/acme}"
 case "$kind" in
 rsa) dirs="$base/$d $base/${d}_rsa";;
 ecc) dirs="$base/${d}_ecc";;
 *) HV_ACME_ERROR="invalid key type (use rsa or ecc)"; return 1;;
 esac
 for f in $dirs "${HV_ACME_LINK_DIR:-/etc/ssl/acme}"; do
  if [ "$f" = "${HV_ACME_LINK_DIR:-/etc/ssl/acme}" ]; then
   key="$f/$d.key"; f="$f/$d.fullchain.crt"
  else
   key="$f/$d.key"; f="$f/fullchain.cer"
  fi
  [ -s "$f" ] && [ -s "$key" ] || continue
  cert_pub="$(openssl x509 -in "$f" -pubkey -noout 2>/dev/null)" || continue
  key_pub="$(openssl pkey -in "$key" -passin pass: -pubout 2>/dev/null)" || continue
  [ -n "$cert_pub" ] && [ "$cert_pub" = "$key_pub" ] || continue
  case "$kind" in
   rsa) printf '%s\n' "$cert_pub" | openssl rsa -pubin -noout >/dev/null 2>&1 || continue;;
   ecc) printf '%s\n' "$cert_pub" | openssl ec -pubin -noout >/dev/null 2>&1 || continue;;
  esac
  HV_ACME_CRT="$f"; HV_ACME_KEY="$key"
  return 0
 done
 HV_ACME_ERROR="no valid matching $kind certificate/key for $d in $base or ${HV_ACME_LINK_DIR:-/etc/ssl/acme}"
 return 1
}
