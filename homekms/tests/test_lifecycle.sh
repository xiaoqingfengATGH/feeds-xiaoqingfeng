#!/bin/sh
# Run with ash or bash; replaces OpenWrt boundaries, not the service logic.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
[ -f "$ROOT/files/etc/init.d/homekms" ] || { echo 'FAIL: init missing'; exit 1; }
. "$ROOT/files/etc/init.d/homekms"
EVENTS=$(mktemp); trap 'rm -f "$EVENTS"' EXIT
config_load() { :; }
config_get_bool() { eval "$1=\${TEST_$3:-$4}"; }
config_get() { eval "$1=\${TEST_$3:-$4}"; }
logger() { :; }
# DNS is exercised independently with an isolated UCI boundary.
homekms_sync_discovery() { :; }
procd_open_instance() { echo open >> "$EVENTS"; }
procd_close_instance() { :; }
procd_set_param() { echo "$*" >> "$EVENTS"; }
procd_open_data() { :; }
procd_close_data() { :; }
json_add_array() { echo "array $*" >> "$EVENTS"; }
json_add_object() { :; }
json_close_array() { :; }
json_close_object() { :; }
json_add_string() { echo "$*" >> "$EVENTS"; }
procd_add_reload_trigger() { echo "trigger $*" >> "$EVENTS"; }
start() { echo start >> "$EVENTS"; start_service; }
HOMEKMS_DATA="$EVENTS"
TEST_enabled=0
start_service
! grep -q '^open' "$EVENTS"
service_triggers
grep -q 'trigger homekms' "$EVENTS"
TEST_enabled=1
start_service
grep -q 'command /usr/bin/python3 -B -u .*pykms_Server.py 0.0.0.0 1688 -F STDOUT' "$EVENTS"
grep -q 'user homekms' "$EVENTS"
! grep -q '^src wan' "$EVENTS"
: > "$EVENTS"
TEST_wan_access=1; TEST_port=21688
start_service
grep -q '^src wan' "$EVENTS"
grep -q '^dest_port 21688' "$EVENTS"
! grep -q '^dest ' "$EVENTS"
for TEST_port in 0 1023 65536 abc '1688;exit'; do
 : > "$EVENTS"; start_service || :; ! grep -q '^open' "$EVENTS"
done
TEST_port=1688
: > "$EVENTS"; TEST_enabled=0; reload_service
grep -q '^start' "$EVENTS"; ! grep -q '^open' "$EVENTS"
HOMEKMS_DATA=/nonexistent
: > "$EVENTS"; TEST_enabled=1; start_service || :; ! grep -q '^open' "$EVENTS"
# Model the exact rc.common stop order read on OpenWrt 24.10:
# stop_service -> procd_kill (deletes service/triggers) -> service_stopped.
procd_lock() { :; }
stop_service() { :; }
procd_kill() { SERVICE_PRESENT=0; INSTANCE_PRESENT=0; }
rc_procd() { SERVICE_PRESENT=1; INSTANCE_PRESENT=0; "$@"; service_triggers; }
stop() {
 procd_lock
 stop_service
 procd_kill homekms
 if type service_stopped >/dev/null 2>&1; then service_stopped; fi
}
SERVICE_PRESENT=1; INSTANCE_PRESENT=1
stop
[ "$INSTANCE_PRESENT" = 0 ] || { echo 'FAIL: stop left an instance'; exit 1; }
[ "$SERVICE_PRESENT" = 1 ] || { echo 'FAIL: temporary stop lost config reload triggers'; exit 1; }
TEST_enabled=1; HOMEKMS_DATA="$EVENTS"
: > "$EVENTS"; reload_service
grep -q '^open' "$EVENTS"
# Real service integration must enable discovery and clean it on stop/off.
homekms_sync_discovery() { echo "dns $*" >> "$EVENTS"; }
TEST_enabled=1; TEST_auto_discovery=1
: > "$EVENTS"; start_service
grep -q '^dns 1 1688$' "$EVENTS" || { echo 'FAIL: start did not publish DNS'; exit 1; }
: > "$EVENTS"; TEST_enabled=0; start_service
grep -q '^dns 0 1688$' "$EVENTS" || { echo 'FAIL: disabled service left DNS'; exit 1; }
: > "$EVENTS"; service_stopped
grep -q '^dns 0 1688$' "$EVENTS" || { echo 'FAIL: stop left DNS'; exit 1; }
echo 'PASS: lifecycle including stop -> retained triggers -> apply resumes instance, DNS integration'
