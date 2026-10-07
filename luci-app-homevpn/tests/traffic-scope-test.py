#!/usr/bin/env python
"""Traffic scope contract across config, renderer, RPC, and documentation."""
import pathlib, sys
root = pathlib.Path(__file__).resolve().parents[1]
config = (root/'root/etc/config/homevpn').read_text()
init = (root/'root/etc/init.d/homevpn').read_text()
rpc = (root/'root/usr/libexec/rpcd/homevpn').read_text()
readme = (root/'README.md').read_text()
assert "option traffic_scope 'lan'" in config, 'new installs default to LAN-only'
assert 'local_ts="0.0.0.0/0"' in init, 'full IPv4 selector missing'
assert '$(hv_get traffic_scope)' in init, 'renderer must read UCI scope'
assert 'local_ts="$LAN_NET, $POOL_SUBNET"' in init, 'independent subnet LAN selector must survive'
assert 'json_add_string  traffic_scope "$(scope)"' in rpc, 'status must expose normalized scope'
assert 'json_add_string traffic_scope "$(scope)"' in rpc, 'get_settings must expose normalized scope'
assert 'json_add_string traffic_scope ""' in rpc, 'RPC signature must expose scope'
assert 'json_get_var v_scope traffic_scope' in rpc, 'set_settings must parse scope'
assert 'invalid traffic scope' in rpc, 'unknown scope must be refused before writes'
assert 'config.traffic_scope=${v_scope}' in rpc, 'scope must persist'
assert 'traffic_scope' in readme and '0.0.0.0/0' in readme, 'document scope and selector'
view = (root/'htdocs/luci-static/resources/view/homevpn/overview.js').read_text()
po = (root/'po/zh_Hans/homevpn.po').read_text()
pot = (root/'po/templates/homevpn.pot').read_text()
for msgid in ('Client traffic scope', 'Home LAN only (split tunnel)', 'All IPv4 traffic (full tunnel)', 'Home LAN only keeps other traffic on the client network. All IPv4 traffic requests a default route through this VPN; internet access also requires working forwarding and NAT on the server router. Existing client profiles may need to be reconnected or updated. IPv6 is not tunneled.'):
    assert "_('"+msgid+"')" in view, msgid
    assert 'msgid "'+msgid+'"' in po and 'msgid "'+msgid+'"' in pot, msgid
print('PASS traffic scope contract')
