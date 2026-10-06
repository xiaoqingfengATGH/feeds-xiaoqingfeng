#!/bin/sh
# Execute the actual init functions under target BusyBox ash, with only
# service/network side effects replaced. Disabled entry points must do no work.
set -eu
extra_command() { :; }
INIT_FIXTURE="$(mktemp)"
LIB_DIR="$(dirname "$1")/../../usr/share/homevpn"
sed "s@/usr/share/homevpn/@$LIB_DIR/@g" "$1" > "$INIT_FIXTURE"
. "$INIT_FIXTURE"
rm -f "$INIT_FIXTURE"
TRACE="$(mktemp)"; trap 'rm -f "$TRACE"' EXIT
hv_get() { [ "$1" = enabled ] && { echo 0; return; }; return 1; }
load_env() { echo load_env >> "$TRACE"; LAN_ADDR=192.0.2.1; }
precheck() { echo precheck >> "$TRACE"; return 1; }
provision_certs() { echo certs >> "$TRACE"; }
regen_secrets() { echo secrets >> "$TRACE"; }
logger_tag() { :; }
for action in regen reload_service boot sync-acme; do
 : > "$TRACE"
 "$action" >/dev/null 2>&1 || { printf 'FAIL disabled %s returned failure\n' "$action"; exit 1; }
 if [ -s "$TRACE" ]; then printf 'FAIL disabled %s has side effects: ' "$action"; tr '\n' ' ' < "$TRACE"; echo; exit 1; fi
done
printf 'PASS disabled regen/reload/boot/ACME do no provisioning or apply\n'
