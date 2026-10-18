"""Read-only production verification after native overview tests."""
import hashlib,json,subprocess
from pathlib import Path
R=Path('D:/DevPortal/Openwrt/feeds-xiaoqingfeng');E=R/'docs/evidence/lua-store/overview-public-entry'
d=json.loads((E/'deployment.json').read_text())
ssh=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
def remote(c):return subprocess.check_output(ssh+[c]).decode()
p=remote('sha256sum /etc/homepublish/product/state /etc/config/firewall /etc/config/homepublish /etc/ddns-go/config.yaml /www/luci-static/resources/view/homepublish/product.js /www/luci-static/resources/view/homepublish/services.js');assert p==d['protected_before']
s=json.loads(remote("ubus call homepublish status '{}'"));controller=json.loads(remote("ubus call service list '{\"name\":\"homepublish\"}'"));assert controller==d['controller']
assert (s['saved_revision'],s['active_revision'],s['runtime']['generation'])==(d['saved_revision'],d['active_revision'],d['generation'])
assert s['runtime']['phase']=='running' and s['runtime']['active_verified'] and s['desired_state']['state']=='enabled'
sha=remote('sha256sum /www/luci-static/resources/view/homepublish/overview.js').split()[0];assert sha==d['installed_sha256']==hashlib.sha256((R/'luci-app-homepublish/htdocs/luci-static/resources/view/homepublish/overview.js').read_bytes()).hexdigest()
config=remote('cat /tmp/homepublish-runtime/sslh.cfg');listeners=remote('netstat -lntp 2>/dev/null');assert 'port: "8443"' in config and '{ name: "ssh"; host: "192.168.1.2"; port: "22"; }' in config
owned=[line for line in listeners.splitlines() if 'sslh-select' in line];assert any('0.0.0.0:8443' in line for line in owned) and any(':::8443' in line for line in owned)
report={'production_preserved':True,'protected_sha256':p,'installed_sha256':sha,'controller_pid':controller['homepublish']['instances']['controller']['pid'],'saved_revision':s['saved_revision'],'active_revision':s['active_revision'],'generation':s['runtime']['generation'],'phase':s['runtime']['phase'],'sslh_configuration':config,'actual_owned_listeners':owned,'ssh_port_explanation':'HomePublish SSH shares public listener 8443; 192.168.1.2:22 is its backend. No dedicated public SSH 22 forwarding is configured.'}
(E/'final-production.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
