#!/usr/bin/env python
"""Verify HomeVPN advertises the live LAN address as DNS in address pools."""
import pathlib, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parents[1]
source = (root / 'root/etc/init.d/homevpn').read_text()
render = source.split('render_conf() {', 1)[1].split('\nregen_secrets() {', 1)[0]
for mode in ('lansubnet', 'subnet'):
    with tempfile.TemporaryDirectory(prefix='homevpn-dns-') as d:
        script = '''render_conf() {''' + render + '''
effective_remote() { echo vpn.example.com; }
hv_get() { :; }
MODE="$1"; LAN_NET=192.168.1.0/24; LAN_ADDR="$2"; POOL_SUBNET=10.100.1.0/24
POOL_SPEC=192.168.1.50-192.168.1.99; PROPOSALS=default; ESP_PROPOSALS=default
SWANCTL_DIR="$3"; CONN_FILE="$3/conf.d/connection.conf"
render_conf
'''
        for address in ('192.168.1.2', '192.168.1.247'):
            result = subprocess.run(['sh', '-c', script, 'sh', mode, address, d], capture_output=True, text=True)
            assert result.returncode == 0, result.stderr
            config = (pathlib.Path(d) / 'conf.d/connection.conf').read_text()
            pool = config.split('pools {', 1)[1]
            assert f'        dns = {address}\n' in pool, (mode, address, pool)
            other = '192.168.1.247' if address == '192.168.1.2' else '192.168.1.2'
            assert f'        dns = {other}\n' not in pool, (mode, address, pool)
print('PASS DNS follows current LAN address in both static address pool modes')
