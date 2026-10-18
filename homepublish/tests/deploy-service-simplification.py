"""Direct source/UI deployment; preserve saved config, intent and UCI; no package/firewall reload."""
import hashlib, io, json, os, shlex, subprocess, tarfile, time, uuid
from pathlib import Path
REPO=Path(__file__).resolve().parents[2]
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
BACKUP='/root/homepublish-lua-store/service-simplification-deploy-'+uuid.uuid4().hex[:12]
EVIDENCE=REPO/'docs/evidence/input-firewall/service-simplification-deploy.json'
report={'backup':BACKUP,'commands':[],'deployed':False}
def run(cmd,data=None):
 p=subprocess.run(SSH+[cmd],input=data,capture_output=True,timeout=90)
 report['commands'].append({'command':cmd,'code':p.returncode,'stdout':p.stdout.decode(errors='replace'),'stderr':p.stderr.decode(errors='replace')})
 if p.returncode:raise RuntimeError(report['commands'][-1])
 return p.stdout.decode()
def status():return json.loads(run("printf '%s\\n' '{\"action\":\"status\"}' | lua /usr/share/homepublish/product-device-cli.lua"))
def service():return json.loads(run("ubus call service list '{\"name\":\"homepublish\"}'"))
def protect():return run('sha256sum /etc/config/firewall /etc/config/homepublish')
def main():
 try:
  files={}
  for name in ['canonical-v2.lua','direct-address.lua','direct-backend.lua','product-probe.lua','product-v2-runtime.lua']:
   files['/usr/share/homepublish/'+name]=(REPO/'homepublish/files/usr/share/homepublish'/name).read_bytes()
  for name in ['product.js','services.js']:
   files['/www/luci-static/resources/view/homepublish/'+name]=(REPO/'luci-app-homepublish/htdocs/luci-static/resources/view/homepublish'/name).read_bytes()
  before=status();report['before']=before;report['uci_before']=protect();report['controller_before']=service()
  assert before['runtime']['phase']=='running' and before['desired_state']['state']=='enabled',before
  run('umask 077; mkdir '+BACKUP+'; tar -C / -czf '+BACKUP+'/rollback.tar.gz '+ ' '.join(shlex.quote(x.lstrip('/')) for x in files)+' etc/homepublish/product/state etc/config/firewall etc/config/homepublish')
  # Byte-exact upload with temporary sibling + rename; no arbitrary production files.
  report['sha256']={}
  for target,data in files.items():
   run('cat > '+shlex.quote(target+'.service-simplification-new')+' && chmod 644 '+shlex.quote(target+'.service-simplification-new')+' && mv '+shlex.quote(target+'.service-simplification-new')+' '+shlex.quote(target),data)
   expected=hashlib.sha256(data).hexdigest();actual=run('sha256sum '+target).split()[0];assert actual==expected
   report['sha256'][target]=actual
  # Delete only controller instance: init stop_service would disable user intent.
  oldpid=report['controller_before']['homepublish']['instances']['controller']['pid']
  run("ubus call service delete '{\"name\":\"homepublish\"}'")
  for _ in range(60):
   if run('test ! -d /proc/'+str(oldpid)+'; printf "%s" "$?"').strip()=='0':break
   time.sleep(.2)
  else:raise RuntimeError('controller did not exit')
  report['controller_deleted']=service();assert not report['controller_deleted']
  run('/etc/init.d/homepublish start')
  restored=None
  for _ in range(60):
   try:
    restored=status()
    if restored['runtime']['phase']=='stopped':break
   except Exception:pass
   time.sleep(.25)
  assert restored and restored['runtime']['phase']=='stopped',restored
  for key in ['saved_config','saved_revision','desired_state','active_config','active_revision']:
   assert restored[key]==before[key],key
  payload=json.dumps({'action':'start','revision':before['saved_revision'],'approved':True})
  report['started']=json.loads(run('printf "%s\\n" '+shlex.quote(payload)+' | lua /usr/share/homepublish/product-device-cli.lua'))
  for _ in range(60):
   after=status()
   if after['runtime']['phase']=='running' and after['runtime'].get('active_verified'):break
   time.sleep(.25)
  report['after']=after;report['controller_after']=service();report['uci_after']=protect()
  for key in ['saved_config','saved_revision','desired_state','active_config','active_revision']:
   assert after[key]==before[key],key
  assert report['uci_before']==report['uci_after']
  assert after['runtime']['phase']=='running' and after['runtime']['active_verified']
  assert all(s['ready'] for s in after['runtime']['services'].values())
  new=report['controller_after']['homepublish']['instances']['controller'];assert new['running'] and new['pid']!=oldpid
  report['runtime_readback']=json.loads(run("ubus call service list '{\"name\":\"homepublish-runtime\"}'"))
  report['production_https_response']=run("env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR curl -q --noproxy '*' --silent --show-error --max-time 8 -w '|%{http_code}' --resolve home.iwonderful.top:8443:192.168.1.2 https://home.iwonderful.top:8443/")
  report['deployed']=True
 except Exception as e:
  report['error']=repr(e)
 finally:
  EVIDENCE.parent.mkdir(parents=True,exist_ok=True);EVIDENCE.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({k:report.get(k) for k in ['deployed','backup','sha256','error','production_https_response']},indent=2))
 return 0 if report['deployed'] else 1
if __name__=='__main__':raise SystemExit(main())
