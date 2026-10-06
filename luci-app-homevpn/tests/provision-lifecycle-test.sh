#!/bin/sh
set -e
T=$(mktemp -d /tmp/hv-provision-test.XXXXXX)
trap 'rm -rf "$T"' EXIT
sed -n '/^hv_provision_saved() {/,/^}/p' "$1/etc/init.d/homevpn" > "$T/function"
. "$T/function"
hv_get() { echo "$ENABLED"; }
hv_exclusive() { echo ownership; [ "$CONFLICT" != 1 ]; }
hv_pki_recover() { return 0; }
provision_certs() { echo certificates; }
load_env() { LAN_ADDR=192.0.2.1; }
ensure_firewall() { echo firewall; }
hv_install_guard() { echo guard; }
pidof() { [ "$RUNNING" = 1 ]; }
apply_config() { echo "apply=$1"; }
ENABLED=1 RUNNING=0 CONFLICT=0
out=$(hv_provision_saved)
[ "$out" = "$(printf 'ownership\ncertificates\nguard\nfirewall\napply=start')" ]
RUNNING=1
out=$(hv_provision_saved)
[ "$out" = "$(printf 'ownership\ncertificates\nguard\nfirewall\napply=regen')" ]
ENABLED=0
out=$(hv_provision_saved)
[ "$out" = "$(printf 'ownership\ncertificates')" ]
CONFLICT=1
if out=$(hv_provision_saved); then exit 1; fi
[ "$out" = ownership ]
echo 'PASS enabled cold/live provisioning, disabled certificate-only maintenance and ownership refusal before publication'
