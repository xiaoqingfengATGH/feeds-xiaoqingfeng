"""Deploy product UI recovery only; never refresh browser or mutate runtime/config."""
import hashlib,json,subprocess,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
def run(command,data=None):
 p=subprocess.run(SSH+[command],input=data,capture_output=True,timeout=40)
 if p.returncode:raise RuntimeError(p.stderr.decode(errors='replace'))
 return p.stdout.decode()
def baseline():
 s=json.loads(run("ubus call homepublish status '{}'"))
 return {'state':{k:s.get(k) for k in ['saved_config','saved_revision','active_config','active_revision','intent_revision','desired_state']},'uci':run('sha256sum /etc/config/homepublish /etc/config/firewall'),'controller':json.loads(run("ubus call service list '{\"name\":\"homepublish\"}'"))}
report={'frontend_only':True,'production_writes':False,'deployed':False}
try:
 report['before']=baseline()
 backup='/root/homepublish-lua-store/save-recovery-'+uuid.uuid4().hex[:12]
 target='/www/luci-static/resources/view/homepublish/product.js'
 run('umask 077; mkdir '+backup+' && cp '+target+' '+backup+'/product.js')
 data=(ROOT/'luci-app-homepublish/htdocs/luci-static/resources/view/homepublish/product.js').read_bytes()
 run('cat > '+target+'.recovery-new && chmod 644 '+target+'.recovery-new && mv '+target+'.recovery-new '+target,data)
 report['backup']=backup;report['sha256']=hashlib.sha256(data).hexdigest()
 assert run('sha256sum '+target).split()[0]==report['sha256']
 report['after']=baseline();assert report['before']==report['after']
 report['deployed']=True
except Exception as e:report['error']=repr(e)
finally:
 out=ROOT/'docs/evidence/input-firewall/save-recovery-deploy.json';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({k:report.get(k) for k in ['deployed','backup','sha256','error']},indent=2))
raise SystemExit(0 if report['deployed'] else 1)
