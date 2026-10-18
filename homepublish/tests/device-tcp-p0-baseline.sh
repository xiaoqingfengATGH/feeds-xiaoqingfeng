#!/bin/sh
# P0 read-only final baseline. No service/config mutations.
set -eu
free
df -h / /tmp
ip -4 route show
ip -6 route show
ip rule show
ubus call service list '{"name":"homepublish"}'
sha256sum /etc/config/firewall /etc/config/network /etc/config/homepublish
test ! -e /tmp/homepublish-tcp-p0
printf '%s\n' P0_BASELINE_READBACK_OK
