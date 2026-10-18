"""Deploy ONLY overview.js, backup/readback, protect production; no lifecycle/config APIs."""
import hashlib,json,subprocess,shlex
from pathlib import Path
R=Path('D:/DevPortal/Openwrt/feeds-xiaoqingfeng')
E=R/'docs/evidence/lua-store/overview-public-entry';E.mkdir(parents=True,exist_ok=True)
S=R/'luci-app-homepublish/htdocs/luci-static/resources/view/homepublish/overview.js'
base=['-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key']
def remote(c):return subprocess.check_output(['ssh',*base,'root@192.168.1.2',c]).decode()
protected='sha256sum /etc/homepublish/product/state /etc/config/firewall /etc/config/homepublish /etc/ddns-go/config.yaml /www/luci-static/resources/view/homepublish/product.js /www/luci-static/resources/view/homepublish/services.js'
before=remote(protected);status=json.loads(remote("ubus call homepublish status '{}'"));pid=remote("ubus call service list '{\"name\":\"homepublish\"}'")
(E/'before-status.json').write_text(json.dumps(status,indent=2));(E/'before-protected.txt').write_text(before)
backup=remote('mkdir -p /root/homepublish-lua-store; mktemp -d /root/homepublish-lua-store/overview-public-entry.XXXXXX').strip()
target='/www/luci-static/resources/view/homepublish/overview.js'
old=remote('sha256sum '+target)
remote('cp -p '+target+' '+backup+'/overview.js; sha256sum '+backup+'/overview.js')
subprocess.run(['scp','-O',*base,str(S),'root@192.168.1.2:'+backup+'/overview.new.js'],check=True,capture_output=True)
sha=hashlib.sha256(S.read_bytes()).hexdigest();assert remote('sha256sum '+backup+'/overview.new.js').split()[0]==sha
remote('cp -p '+backup+'/overview.js '+backup+'/overview.stage.js; cat '+backup+'/overview.new.js > '+backup+'/overview.stage.js; mv '+backup+'/overview.stage.js '+target+'; rm -f /tmp/luci-indexcache; rm -rf /tmp/luci-modulecache')
installed=remote('sha256sum '+target);assert installed.split()[0]==sha
assert remote('sha256sum '+backup+'/overview.js').split()[0]==old.split()[0]
after=remote(protected);assert before==after,'Protected production bytes changed'
after_status=json.loads(remote("ubus call homepublish status '{}'"));after_pid=remote("ubus call service list '{\"name\":\"homepublish\"}'");assert pid==after_pid
for key in ['saved_config','active_config','saved_revision','active_revision','intent_revision','desired_state']:assert status[key]==after_status[key],key
assert after_status['runtime']['phase']=='running' and after_status['runtime']['generation']==status['runtime']['generation']
report={'backup':backup,'before_sha256':old.split()[0],'installed_sha256':sha,'protected_before':before,'protected_after':after,'controller':json.loads(after_pid),'saved_revision':after_status['saved_revision'],'active_revision':after_status['active_revision'],'generation':after_status['runtime']['generation'],'production_preserved':True,'only_deployed':['overview.js']}
(E/'deployment.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
