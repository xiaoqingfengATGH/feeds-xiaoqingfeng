#!/bin/sh
# Exercise the real HomeVPN DHCP readiness guard with isolated runtime fixtures.
set -eu
SOURCE="${1:?homevpn init path}"
T=$(cygpath -m "$(mktemp -d)")
trap 'rm -rf "$T"' EXIT
python - "$SOURCE" "$T/check.sh" "$T" <<'PY'
import pathlib,sys
src=pathlib.Path(sys.argv[1]).read_text()
start=src.index('dhcp_lan_ready() {') if 'dhcp_lan_ready() {' in src else -1
body=src[start:src.index('\n}\n',start)+3] if start>=0 else 'dhcp_lan_ready() { :; }\n'
body=body.replace('/var/run/dnsmasq/',sys.argv[3]+'/run/').replace('/proc/',sys.argv[3]+'/proc/').replace('/var/etc/dnsmasq.conf.',sys.argv[3]+'/conf.')
pathlib.Path(sys.argv[2]).write_text(body)
PY
mkdir -p "$T/run" "$T/proc/987"; printf '987\n' > "$T/run/dnsmasq.cfg.pid"
printf '/usr/sbin/dnsmasq\000-C\000%s/conf.cfg\000-k\000' "$T" > "$T/proc/987/cmdline"
printf 'dhcp-range=192.168.1.100,192.168.1.249,255.255.255.0,12h\n' > "$T/conf.cfg"
. "$T/check.sh"
LAN_IF=br-lan
LAN_ADDR=192.168.1.2
uci() {
 case "$*" in
 '-q get dhcp.lan.interface') echo lan;;
 '-q get dhcp.lan.ignore') echo "${IGNORE:-0}";;
 '-q get dhcp.lan.dhcpv4') echo "${DHCPV4:-server}";;
 '-q get dhcp.lan.dynamicdhcp') echo "${DYNAMIC:-1}";;
 '-q get network.lan.device') echo br-lan;;
 *) return 1;;
 esac
}
kill() { [ "$*" = '-0 987' ] && [ "${ALIVE:-1}" = 1 ]; }
valid_ip() { echo "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; }
route_get() { case "$1" in 192.168.1.*) echo "192.168.1.0/24 dev br-lan src 192.168.1.2";; *) echo 'default via 192.168.1.1 dev br-lan';; esac; }
pass() { dhcp_lan_ready || { echo "FAIL: $1 should pass"; exit 1; }; }
fail() { if dhcp_lan_ready; then echo "FAIL: $1 should refuse"; exit 1; fi; }
pass 'running LAN DHCP'
IGNORE=1; fail 'disabled LAN DHCP'; IGNORE=0
DHCPV4=disabled; fail 'IPv4 disabled'; DHCPV4=server
DYNAMIC=0; fail 'no dynamic leases'; DYNAMIC=1
ALIVE=0; fail 'stopped instance'; ALIVE=1
printf 'dhcp-range=192.168.224.100,192.168.224.249,255.255.255.0,12h\n' > "$T/conf.cfg"
fail 'range on another subnet'
printf 'dhcp-range=192.168.1.100,192.168.1.249,255.255.255.0,12h\n' > "$T/conf.cfg"
printf '/usr/sbin/dnsmasq\000-C\000/other/instance.conf\000' > "$T/proc/987/cmdline"
fail 'stale config from a different running instance'
printf '/usr/sbin/dnsmasq\000-C\000%s/conf.cfg\000-k\000' "$T" > "$T/proc/987/cmdline"
printf 'dhcp-range=192.168.1.100,192.168.224.249,255.255.255.0,12h\n' > "$T/conf.cfg"
fail 'range end outside LAN'
printf 'dhcp-range=192.168.1.100,192.168.1.249,255.255.255.0,12h\n' > "$T/conf.cfg"
rm "$T/run/dnsmasq.cfg.pid"; fail 'no live pid file'
echo 'PASS: live local dnsmasq instance with dynamic br-lan DHCP required; invalid cases refused'
