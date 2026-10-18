"""Frontend-only loading feedback deployment; no config mutation, restart or refresh."""
import hashlib,json,shlex,subprocess,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
report={'backup':'/root/homepublish-lua-store/services-loading-'+uuid.uuid4().hex[:12],'deployed':False,'frontend_only':True}
def run(cmd,data=None):
 p=subprocess.run(SSH+[cmd],input=data,capture_output=True,timeout=40)
 if p.returncode:raise RuntimeError(p.stderr.decode(errors='replace'))
 return p.stdout.decode()
def state():return json.loads(run("ubus call homepublish status '{}'"))
def protect():return run('sha256sum /etc/config/firewall /etc/config/homepublish')
def controller():return json.loads(run("ubus call service list '{\"name\":\"homepublish\"}'"))
try:
 before=state();report['before']={k:before.get(k) for k in ['saved_config','saved_revision','desired_state','active_config','active_revision']};report['uci_before']=protect();report['controller_before']=controller()
 names=['product.js','services.js'];targets=['/www/luci-static/resources/view/homepublish/'+n for n in names]
 run('umask 077; mkdir '+report['backup']+'; tar -C / -czf '+report['backup']+'/frontend-before.tar.gz '+' '.join(shlex.quote(t.lstrip('/')) for t in targets))
 report['sha256']={}
 for name,target in zip(names,targets):
  data=(ROOT/'luci-app-homepublish/htdocs/luci-static/resources/view/homepublish'/name).read_bytes()
  run('cat > '+target+'.loading-new && chmod 644 '+target+'.loading-new && mv '+target+'.loading-new '+target,data)
  digest=hashlib.sha256(data).hexdigest();assert run('sha256sum '+target).split()[0]==digest
  report['sha256'][target]=digest
 after=state();report['after']={k:after.get(k) for k in report['before']};report['uci_after']=protect();report['controller_after']=controller()
 assert report['before']==report['after'];assert report['uci_before']==report['uci_after'];assert report['controller_before']==report['controller_after']
 report['deployed']=True
except Exception as e:report['error']=repr(e)
finally:
 (ROOT/'docs/evidence/input-firewall/services-loading-deploy.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({k:report.get(k) for k in ['deployed','backup','sha256','error']},indent=2))
raise SystemExit(0 if report['deployed'] else 1)
