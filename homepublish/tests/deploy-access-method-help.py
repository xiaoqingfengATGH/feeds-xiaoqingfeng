"""Deploy only three LuCI JS files; no configuration/lifecycle/firewall writes."""
import hashlib,json,subprocess,uuid
from pathlib import Path
REPO=Path(__file__).resolve().parents[2]
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
backup='/root/homepublish-lua-store/access-method-help-'+uuid.uuid4().hex[:12]
evidence=REPO/'docs/evidence/ui-simplification/access-method-help-deploy.json'
report={'backup':backup,'deployed':False}
def run(cmd,data=None):
 p=subprocess.run(SSH+[cmd],input=data,capture_output=True,timeout=60)
 if p.returncode:raise RuntimeError(p.stderr.decode(errors='replace'))
 return p.stdout.decode()
def status():return json.loads(run("printf '%s\\n' '{\"action\":\"status\"}' | lua /usr/share/homepublish/product-device-cli.lua"))
def protected():return run('sha256sum /etc/config/firewall /etc/config/homepublish /etc/homepublish/product/state')
def processes():return {n:json.loads(run("ubus call service list '{\"name\":\""+n+"\"}'")) for n in ['homepublish','homepublish-runtime']}
try:
 files={('/www/luci-static/resources/view/homepublish/'+n):(REPO/'luci-app-homepublish/htdocs/luci-static/resources/view/homepublish'/n).read_bytes() for n in ['services.js','overview.js','product.js']}
 report['before']=status();report['protected_before']=protected();report['processes_before']=processes()
 run('umask 077; mkdir '+backup+'; tar -C / -czf '+backup+'/rollback.tar.gz '+' '.join(x.lstrip('/') for x in files))
 report['sha256']={}
 for target,data in files.items():
  run('cat > '+target+'.access-method-new && chmod 644 '+target+'.access-method-new && mv '+target+'.access-method-new '+target,data)
  actual=run('sha256sum '+target).split()[0];assert actual==hashlib.sha256(data).hexdigest();report['sha256'][target]=actual
 report['after']=status();report['protected_after']=protected();report['processes_after']=processes()
 assert report['protected_before']==report['protected_after'],'state/config changed'
 assert report['processes_before']==report['processes_after'],'process state changed'
 for k in ['saved_config','saved_revision','desired_state','active_config','active_revision','runtime']:assert report['before'].get(k)==report['after'].get(k),k
 report['deployed']=True
finally:
 evidence.parent.mkdir(parents=True,exist_ok=True);evidence.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print(json.dumps({'deployed':report['deployed'],'backup':backup,'sha256':report.get('sha256'),'evidence':str(evidence)},indent=2))
