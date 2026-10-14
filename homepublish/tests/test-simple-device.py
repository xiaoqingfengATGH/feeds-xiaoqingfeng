#!/usr/bin/env python3
"""Packaging/lifecycle contract for the conventional device slice."""
from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Makefile').read_text()
assert 'homepublish_device.so' not in m, 'complex C adapter remains packaged'
assert '+luci-lib-nixio' in m
init=(r/'files/etc/init.d/homepublish-nginx').read_text()
assert 'procd_set_param command /usr/sbin/nginx' in init
assert 'respawn' not in init
provider=(r/'files/usr/share/homepublish/product-device-provider.lua').read_text()
assert 'homepublish_device' not in provider
assert 'user nobody' in provider
assert 'nginx -t' in provider
print('PASS conventional package/procd provider contract')
