#!/usr/bin/env python
"""A VIP's IPsec policy route must not invalidate a LAN address-pool precheck."""
import pathlib, subprocess
root = pathlib.Path(__file__).resolve().parents[1]
source = (root/'root/etc/init.d/homevpn').read_text()
route_get = source.split('route_get() {', 1)[1].split('\n}\n', 1)[0]
script = '''route_get() {''' + route_get + '''
}
ip() {
  case "$*" in
    "route show table local match 192.168.1.6") :;;
    "route show table local match 192.168.1.2") echo 'local 192.168.1.2 dev br-lan src 192.168.1.2';;
    "route show table main match 192.168.1.6") printf '%s\n' 'default via 192.168.1.1 dev br-lan' '192.168.1.0/24 dev br-lan src 192.168.1.2';;
    *) echo "unexpected ip invocation: $*" >&2; return 1;;
  esac
}
route_get 192.168.1.6
route_get 192.168.1.2
'''
r = subprocess.run(['sh','-c',script], text=True, capture_output=True)
assert r.returncode == 0, r.stderr
lines = r.stdout.splitlines()
assert len(lines) == 2 and 'dev br-lan' in lines[0] and ' via ' not in lines[0], lines
assert lines[1].startswith('local 192.168.1.2 '), lines
print('PASS pool precheck consults LAN main table, not XFRM policy route')
