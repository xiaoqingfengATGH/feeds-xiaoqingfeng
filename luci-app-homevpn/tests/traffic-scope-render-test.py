#!/usr/bin/env python
"""Exercise the actual render_conf function in a local sandbox, never a router."""
import pathlib, re, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parents[1]
src = (root/'root/etc/init.d/homevpn').read_text()
render = src.split('render_conf() {',1)[1].split('\nregen_secrets() {',1)[0]
with tempfile.TemporaryDirectory(prefix='homevpn-scope-') as d:
 for mode, scope, expected in [('lansubnet','', '192.168.1.0/24'),('lansubnet','lan','192.168.1.0/24'),('subnet','lan','192.168.1.0/24, 10.100.1.0/24'),('dhcp','lan','192.168.1.0/24'),('lansubnet','full','0.0.0.0/0'),('subnet','full','0.0.0.0/0'),('dhcp','full','0.0.0.0/0')]:
  script = '''render_conf() {'''+render+'''\neffective_remote() { echo vpn.example.com; }
hv_get() { [ "$1" = traffic_scope ] && printf '%s' "$SCOPE"; }
MODE="$1"; SCOPE="$2"; LAN_NET=192.168.1.0/24; POOL_SUBNET=10.100.1.0/24
POOL_SPEC=192.168.1.50-192.168.1.99; PROPOSALS=default; ESP_PROPOSALS=default
SWANCTL_DIR="$3"; CONN_FILE="$3/conf.d/connection.conf"
render_conf
'''
  result = subprocess.run(['sh','-c',script,'sh',mode,scope,d],capture_output=True,text=True)
  assert result.returncode==0,(mode,scope,result.stderr)
  conf = (pathlib.Path(d)/'conf.d/connection.conf').read_text()
  match = re.search(r'^\s+local_ts = (.*)$',conf,re.M)
  assert match and match.group(1)==expected,(mode,scope,match.group(1) if match else conf)
 print('PASS actual render_conf: legacy/default LAN, subnet selector, all three IPv4 full modes')
