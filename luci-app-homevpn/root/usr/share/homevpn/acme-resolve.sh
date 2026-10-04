#!/bin/sh
# =============================================================================
# homevpn — ACME certificate resolver, shared by /etc/init.d/homevpn and
# /usr/libexec/rpcd/homevpn (single source of truth — edit here only).
#
# Locates the certificate luci-app-acme / acme.sh issued for a domain:
#   homevpn_acme_resolve <domain>
# sets
#   HV_ACME_CRT — full chain, leaf FIRST (openssl x509 reads the leaf from it)
#   HV_ACME_KEY — matching private key
# and returns 0 when both exist, 1 otherwise. No side effects.
#
# Layouts handled (acme.sh 3.x / acme-common 1.5.x):
#   state dirs  /etc/acme/<dom>/ (RSA), /etc/acme/<dom>_ecc/ (EC),
#               /etc/acme/<dom>_rsa/ — the key-type suffix is on the
#               DIRECTORY only; inside, files are named after the domain:
#               <dom>.cer (LEAF ONLY — not a fullchain!), <dom>.key,
#               fullchain.cer, ca.cer. NB: <dom>.cer must never be used as
#               the server certificate (lone leaf) nor for CA extraction
#               (its only cert IS the leaf).
#   stable links /etc/ssl/acme/<dom>.fullchain.crt / .key / .chain.crt
#               (acme-common /usr/lib/acme/hook link_certs). Fallback for
#               custom state_dir setups — NOT preferred over state dirs:
#               a re-issue with a different key type re-points nothing, the
#               links keep targeting the OLD directory.
# When several state dirs exist the NEWEST fullchain.cer wins (test -nt —
# busybox on HomeLede ships no stat(1)).
# =============================================================================
homevpn_acme_resolve() {
	HV_ACME_CRT=""; HV_ACME_KEY=""
	local d="$1" best="" f
	[ -n "$d" ] || return 1
	for f in "/etc/acme/$d/fullchain.cer" "/etc/acme/${d}_ecc/fullchain.cer" "/etc/acme/${d}_rsa/fullchain.cer"; do
		[ -s "$f" ] || continue
		[ -s "${f%fullchain.cer}$d.key" ] || continue
		[ -z "$best" ] || [ "$f" -nt "$best" ] || continue
		best="$f"
	done
	if [ -n "$best" ]; then
		HV_ACME_CRT="$best"
		HV_ACME_KEY="${best%fullchain.cer}$d.key"
		return 0
	fi
	# fallback: acme-common stable symlink dir
	if [ -s "/etc/ssl/acme/$d.fullchain.crt" ] && [ -s "/etc/ssl/acme/$d.key" ]; then
		HV_ACME_CRT="/etc/ssl/acme/$d.fullchain.crt"
		HV_ACME_KEY="/etc/ssl/acme/$d.key"
		return 0
	fi
	return 1
}
