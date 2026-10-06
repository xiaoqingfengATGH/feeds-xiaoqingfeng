#!/bin/sh
# Real RPC runner; Python only asserts, real BusyBox/jshn serialize.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$here/sswan-profile-rpc-test.py" "${1:-$here/../root/usr/libexec/rpcd/homevpn}" "${2:-/usr/share/libubox/jshn.sh}" "${3:-$(command -v jshn)}"
