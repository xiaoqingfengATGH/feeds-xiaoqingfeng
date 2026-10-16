#!/bin/sh
# Isolated UCI boundary: real init functions, no router writes.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT/files/etc/init.d/homekms"
EVENTS=$(mktemp); trap 'rm -f "$EVENTS"' EXIT
TYPE=''; SRV=''; TARGET=''; PORT=''
uci() {
 [ "${1:-}" != -q ] || shift
 case "$1:$2" in
 get:dhcp.homekms) [ -n "$TYPE" ] && echo "$TYPE";;
 get:dhcp.homekms.srv) echo "$SRV";;
 get:dhcp.homekms.target) echo "$TARGET";;
 get:dhcp.homekms.port) echo "$PORT";;
 get:dhcp.@dnsmasq\[0\].domain) echo lan;;
 get:system.@system\[0\].hostname) echo router;;
 set:dhcp.homekms=*) TYPE=${2#*=}; echo "$*" >> "$EVENTS";;
 set:dhcp.homekms.srv=*) SRV=${2#*=}; echo "$*" >> "$EVENTS";;
 set:dhcp.homekms.target=*) TARGET=${2#*=}; echo "$*" >> "$EVENTS";;
 set:dhcp.homekms.port=*) PORT=${2#*=}; echo "$*" >> "$EVENTS";;
 delete:dhcp.homekms) TYPE=''; SRV=''; TARGET=''; PORT=''; echo "$*" >> "$EVENTS";;
 commit:dhcp) echo commit >> "$EVENTS";;
 *) echo "FAIL: unexpected UCI mutation $*" >&2; return 1;;
 esac
}
homekms_reload_dns() { echo reload >> "$EVENTS"; }
logger() { :; }
# Default off must not touch dhcp.
homekms_sync_discovery 0 1688
[ ! -s "$EVENTS" ]
homekms_sync_discovery 1 1688
[ "$TYPE:$SRV:$TARGET:$PORT" = 'srvhost:_vlmcs._tcp.lan:router.lan:1688' ]
grep -q '^reload$' "$EVENTS"
: > "$EVENTS"; homekms_sync_discovery 1 1688; [ ! -s "$EVENTS" ]
homekms_sync_discovery 1 21688; [ "$PORT" = 21688 ]
: > "$EVENTS"; homekms_sync_discovery 0 21688; [ -z "$TYPE" ]; grep -q '^reload$' "$EVENTS"
: > "$EVENTS"; homekms_sync_discovery 0 21688; [ ! -s "$EVENTS" ]
echo 'PASS: DNS default off, SRV creation, idempotency, port update, cleanup'
