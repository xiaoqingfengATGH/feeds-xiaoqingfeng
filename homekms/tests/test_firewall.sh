#!/bin/sh
# Regression model: procd data publication does NOT imply nft reconciliation.
# Run with ash/bash. Model rc.common post-commit hooks, not a Python daemon.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT/files/etc/init.d/homekms"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
HOMEKMS_DATA="$TMP/database"; : > "$HOMEKMS_DATA"
config_load() { :; }
config_get_bool() { eval "$1=\${TEST_$3:-$4}"; }
config_get() { eval "$1=\${TEST_$3:-$4}"; }
logger() { :; }
homekms_sync_discovery() { :; }
procd_open_instance() { :; }
procd_close_instance() { :; }
procd_set_param() { :; }
procd_open_data() { :; }
procd_close_data() { :; }
json_add_array() { :; }
json_add_object() { :; }
json_close_array() { :; }
json_close_object() { :; }
json_add_string() { [ "$1" != dest_port ] || PENDING="$2"; }
# A real rc.common start sends service.set BEFORE service_started.
start() {
 PENDING=''
 IN_TRANSACTION=1
 start_service
 DATA="$PENDING"
 IN_TRANSACTION=0
 if type service_started >/dev/null 2>&1; then service_started; fi
}
rc_procd() { DATA=''; "$@"; }
stop() {
 DATA=''
 service_stopped
}
# Only a firewall refresh reads current ubus data into the installed ruleset.
homekms_reload_firewall() {
 [ "$IN_TRANSACTION" = 0 ] || { echo 'FAIL: firewall queried uncommitted service data'; exit 1; }
 NFT="$DATA"
 [ "${FAIL_RELOAD:-0}" = 0 ]
}
check() {
 [ "$NFT" = "$1" ] || { echo "FAIL: $2: nft port '$NFT', expected '$1' (ubus '$DATA')"; exit 1; }
}
DATA=''; NFT=''; IN_TRANSACTION=0
TEST_enabled=1; TEST_wan_access=1; TEST_port=1688
start
# Establish the actual bug baseline even with the unfixed init: opening's
# automatic data event has already caused fw4 to install the initial rule.
NFT="$DATA"
TEST_wan_access=0
reload_service
check '' 'WAN off left the previous ACCEPT rule'
TEST_wan_access=1
reload_service
check 1688 'WAN on did not reconcile'
TEST_port=21688
reload_service
check 21688 'port change retained the old ACCEPT port'
stop
check '' 'stop retained the ACCEPT rule'
start
check 21688 'start after stop did not restore rule'
TEST_enabled=0
reload_service
check '' 'master disable retained the ACCEPT rule'
# Errors must reach callers instead of reporting a completed security change.
FAIL_RELOAD=1
if reload_service; then echo 'FAIL: swallowed firewall reload failure'; exit 1; fi
if service_stopped; then echo 'FAIL: stop swallowed firewall reload failure'; exit 1; fi
echo 'PASS: firewall WAN off/on, port change, stop/start, disable, post-commit ordering and failure propagation'
