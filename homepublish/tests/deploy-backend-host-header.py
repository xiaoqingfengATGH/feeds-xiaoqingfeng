"""Authorized Host override direct deployment; no saved-policy changes/new DNS names."""
import hashlib,json,shlex,subprocess,time,uuid
from pathlib import Path
R=Path('D:/DevPortal/Openwrt/feeds-xiaoqingfeng')
E=R/'docs/evidence/lua-store/backend-host-header-deploy';E.mkdir(parents=True,exist_ok=True)
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
B='/root/homepublish-lua-store/backend-host-header-deploy-'+uuid.uuid4().hex[:12]
report={'backup':B,'commands':[],'deployed':False,'ddns_policy':'Normal start may call idempotent DDNS ensure and update existing record addresses. No new configured domain is authorized.'}
def run(cmd,data=None):
 p=subprocess.run(SSH+[cmd],input=data,capture_output=True,timeout=100)
 out=p.stdout.decode(errors='replace');report['commands'].append({'command':cmd,'code':p.returncode,'stdout':out,'stderr':p.stderr.decode(errors='replace')})
 if p.returncode:raise RuntimeError('remote command failed: '+cmd+' '+p.stderr.decode(errors='replace'))
 return out

def rpc(method,payload={}):return json.loads(run('ubus call homepublish '+method+' '+shlex.quote(json.dumps(payload))))
def status():return rpc('status')
def service():return json.loads(run("ubus call service list '{\"name\":\"homepublish\"}'"))
def protect():return run('sha256sum /etc/config/firewall /etc/config/homepublish /etc/ddns-go/config.yaml /etc/config/ddns-go')
def prove(s,p):
 profiles={v['profile_id']:v for v in p['profiles']};proof=[]
 assert p['available']
 for cfgname in ['saved_config','active_config']:
  for svc in s[cfgname]['services']:
   dns=svc.get('dns',{})
   if not svc.get('enabled') or dns.get('mode')!='ddns_go':continue
   profile=profiles[dns['profile_id']]
   for family in dns['record_types']:
    state=profile[{'A':'a','AAAA':'aaaa'}[family]]
    exists=state['enabled'] and svc['hostname'] in state['domains']
    proof.append({'snapshot':cfgname,'service':svc['service_id'],'profile_id':dns['profile_id'],'hostname':svc['hostname'],'record_type':family,'already_registered':exists})
    assert exists,proof[-1]
 return proof

def main():
 try:
  before=status();profiles=rpc('ddns_profiles');report.update(before=before,profiles=profiles)
  report['existing_domain_proof']=prove(before,profiles)
  assert before['runtime']['phase']=='running' and before['runtime']['active_verified']
  assert before['desired_state']=={'state':'enabled','manual_stop_latch':False}
  assert before['saved_config']==before['active_config']
  assert before['saved_config']['publication_policy']['mode']=='continuous','Bounded deadline needs separate preservation path; refusing restart.'
  report['protected_before']=protect();report['controller_before']=service()
  files={}
  for name in ['canonical-v2.lua','direct-renderer.lua']:files['/usr/share/homepublish/'+name]=(R/'homepublish/files/usr/share/homepublish'/name).read_bytes()
  for name in ['services.js','product.js']:files['/www/luci-static/resources/view/homepublish/'+name]=(R/'luci-app-homepublish/htdocs/luci-static/resources/view/homepublish'/name).read_bytes()
  paths=' '.join(shlex.quote(p.lstrip('/')) for p in files)
  run('umask 077; mkdir '+B+'; chmod 700 '+B+'; tar -C / -czf '+B+'/rollback.tar.gz '+paths+' etc/homepublish/product/state etc/config/firewall etc/config/homepublish; chmod 600 '+B+'/rollback.tar.gz; mkdir '+B+'/stage')
  report['installed_before_hashes']=run('sha256sum '+' '.join(files))
  for target,data in files.items():
   staged=B+'/stage/'+target.rsplit('/',1)[1]
   run('cat > '+staged,data)
   assert run('sha256sum '+staged).split()[0]==hashlib.sha256(data).hexdigest()
   if target.endswith('.lua'):run('lua -e '+shlex.quote('assert(loadfile("'+staged+'"))'))
  # Recheck fresh production truth immediately before the only disruptive step.
  fresh=status();assert all(fresh[k]==before[k] for k in ['saved_config','active_config','saved_revision','active_revision','desired_state'])
  report['pre_restart_existing_domain_proof']=prove(fresh,rpc('ddns_profiles'))
  assert protect()==report['protected_before']
  oldpid=report['controller_before']['homepublish']['instances']['controller']['pid']
  run("ubus call service delete '{\"name\":\"homepublish\"}'")
  for _ in range(60):
   if run('test ! -d /proc/'+str(oldpid)+'; printf "%s" "$?"').strip()=='0':break
   time.sleep(.25)
  else:raise RuntimeError('old controller did not exit')
  report['sha256']={}
  for target,data in files.items():
   staged=B+'/stage/'+target.rsplit('/',1)[1]
   run('cp '+staged+' '+target+'.host-header-new && chmod 644 '+target+'.host-header-new && mv '+target+'.host-header-new '+target)
   actual=run('sha256sum '+target).split()[0];assert actual==hashlib.sha256(data).hexdigest();report['sha256'][target]=actual
  run('/etc/init.d/homepublish start')
  for _ in range(80):
   restored=status()
   if restored['runtime']['phase']=='stopped':break
   time.sleep(.25)
  assert restored['runtime']['phase']=='stopped',restored
  report['restored']=restored
  for k in ['saved_config','active_config','saved_revision','active_revision','desired_state']:assert restored[k]==before[k],k
  report['before_start_proof']=prove(restored,rpc('ddns_profiles'))
  payload={'action':'start','revision':before['saved_revision'],'approved':True}
  report['normal_start_payload']=payload
  report['normal_start_result']=json.loads(run('printf "%s\\n" '+shlex.quote(json.dumps(payload))+' | lua /usr/share/homepublish/product-device-cli.lua'))
  for _ in range(80):
   after=status()
   if after['runtime']['phase']=='running' and after['runtime'].get('active_verified'):break
   time.sleep(.25)
  report['after']=after;report['controller_after']=service();report['protected_after']=protect()
  for k in ['saved_config','active_config','saved_revision','active_revision','desired_state']:assert after[k]==before[k],k
  assert report['protected_after']==report['protected_before'],'protected settings changed'
  assert after['runtime']['phase']=='running' and after['runtime']['active_verified']
  assert all(v['ready'] for v in after['runtime']['services'].values())
  controller=report['controller_after']['homepublish']['instances']['controller'];assert controller['running'] and controller['pid']!=oldpid
  report['profiles_after']=rpc('ddns_profiles');assert report['profiles_after']==profiles
  report['runtime_service']=json.loads(run("ubus call service list '{\"name\":\"homepublish-runtime\"}'"))
  report['listeners']=run('cat /proc/net/tcp /proc/net/tcp6')
  report['firewall']=run('nft list chain inet fw4 input_lan')
  report['installed_readback_hashes']=run('sha256sum '+' '.join(files))
  installed=E/'installed-assets';installed.mkdir(exist_ok=True)
  for target in files:
   (installed/target.rsplit('/',1)[1]).write_bytes(subprocess.check_output(SSH+['cat '+target]))
  report['deployed']=True
 except Exception as exc:report['error']=repr(exc)
 finally:(E/'deployment.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({k:report.get(k) for k in ['deployed','backup','sha256','existing_domain_proof','error']},indent=2))
 return 0 if report['deployed'] else 1
if __name__=='__main__':raise SystemExit(main())
