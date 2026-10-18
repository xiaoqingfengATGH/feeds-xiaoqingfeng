"""Deploy only services.js; read-only production snapshots, no lifecycle RPC."""
import hashlib,json,subprocess,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/evidence/lua-store/services-description-deploy.json'
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
TARGET='/www/luci-static/resources/view/homepublish/services.js'
B='/root/homepublish-lua-store/services-description-'+uuid.uuid4().hex[:12]
def run(cmd,data=None):
 p=subprocess.run(SSH+[cmd],input=data,capture_output=True,timeout=40)
 if p.returncode:raise RuntimeError(p.stderr.decode(errors='replace'))
 return p.stdout.decode()
def snapshot():
 s=json.loads(run("ubus call homepublish status '{}'"))
 tcp=run('cat /proc/net/tcp /proc/net/tcp6')
 return {'status':{k:s.get(k) for k in ['saved_config','saved_revision','active_config','active_revision','desired_state','runtime']},'protected':run('sha256sum /etc/homepublish/product/state /etc/config/homepublish /etc/config/firewall /etc/ddns-go/config.yaml /etc/config/ddns-go'),'controller':json.loads(run("ubus call service list '{\"name\":\"homepublish\"}'")),'runtime_processes':json.loads(run("ubus call service list '{\"name\":\"homepublish-runtime\"}'")),'listeners':sorted([line.split()[1:4]+[line.split()[9]] for line in tcp.splitlines() if len(line.split())>9 and line.split()[3]=='0A'])}
r={'backup_file':B+'/services.js.before','target':TARGET,'productionWrites':False,'deployed':False}
try:
 data=(ROOT/'luci-app-homepublish/htdocs/luci-static/resources/view/homepublish/services.js').read_bytes()
 old=data.replace("'HomePublish — 服务');".encode(),"'HomePublish — 服务','在这里配置要开放到外网的内网服务');".encode())
 assert hashlib.sha256(old).hexdigest()==run('sha256sum '+TARGET).split()[0],'installed preimage differs from intended one-line change'
 r['before']=snapshot()
 run('umask 077; mkdir '+B+' && chmod 700 '+B+' && cp -p '+TARGET+' '+r['backup_file']+' && chmod 600 '+r['backup_file'])
 r['backup_sha256']=run('sha256sum '+r['backup_file']).split()[0]
 assert r['backup_sha256']==hashlib.sha256(old).hexdigest()
 run('cat > '+TARGET+'.description-new && chmod 644 '+TARGET+'.description-new && mv '+TARGET+'.description-new '+TARGET,data)
 r['sha256']=hashlib.sha256(data).hexdigest()
 assert run('sha256sum '+TARGET).split()[0]==r['sha256']
 run('rm -f /tmp/luci-indexcache; rm -rf /tmp/luci-modulecache')
 r['after']=snapshot()
 for k in r['before']:
  assert r['before'][k]==r['after'][k], 'production invariant changed: '+k
 r['invariants_unchanged']=True;r['deployed']=True
except Exception as e:r['error']=repr(e)
finally:
 OUT.write_text(json.dumps(r,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
 print(json.dumps({k:v for k,v in r.items() if k not in ('before','after')},indent=2))
raise SystemExit(0 if r['deployed'] else 1)
