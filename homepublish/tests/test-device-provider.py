#!/usr/bin/env python3
"""Fixed target adapter contract: no ambient root exec or public listener."""
from pathlib import Path
import subprocess
r=Path(__file__).resolve().parents[1]
def text(p): return (r/p).read_text()
assert 'procd_open_instance controller' in text('files/etc/init.d/homepublish'), 'controller is not registered with procd'
assert 'product-daemon.lua' in text('files/etc/init.d/homepublish')
assert 'procd_set_param respawn' not in text('files/etc/init.d/homepublish')
assert 'setuid(65534)' in text('src/device-provider.c'), 'fixed provider must run nonroot'
assert 'hp_guard_start_device' in text('src/device-provider.c')
assert '127.0.0.1' in text('files/usr/share/homepublish/product-device-provider.lua')
assert '49284' in text('files/usr/share/homepublish/product-device-provider.lua')
print('PASS fixed target controller and nonroot provider contract')
