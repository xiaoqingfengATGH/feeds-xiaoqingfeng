"""Scoped DDNS source deployment with private rollback; no DNS mutation."""
import hashlib,json,shlex,subprocess,time,uuid
from pathlib import Path
R=Path('D:/DevPortal/Openwrt/feeds-xiaoqingfeng'); E=R/'docs/evidence/lua-store/ddns-phase2-deploy'; E.mkdir(parents=True,exist_ok=True)
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
B='/root/homepublish-lua-store/ddns-phase2-deploy-'+uuid.uuid4().hex[:12]
report={'backup':B,'success':False}
def run(s,data=None):
 p=subprocess.run(SSH+[s],input=data,capture_output=True,timeout=100)
 if p.returncode: raise RuntimeError((s,p.returncode,p.stderr.decode()))
 return p.stdout.decode()
def ub(method,p={}):return json.loads(run('ubus call homepublish '+method+' '+shlex.quote(json.dumps(p))))
def svc(n):return json.loads(run('ubus call service list '+shlex.quote(json.dumps({'name':n}))))
def protected():return run('sha256sum /etc/config/firewall /etc/config/homepublish /etc/ddns-go/config.yaml /etc/config/ddns-go')
def snap():
 s=ub('status');return {'status':s,'controller':svc('homepublish'),'runtime':svc('homepublish-runtime'),'protected':protected(),'journal':run('sha256sum /etc/homepublish/product/state'),'listeners':run('cat /proc/net/tcp /proc/net/tcp6')}
def normalized(c):
 c=json.loads(json.dumps(c))
 if isinstance(c,dict) and 'services' in c:
  for service in c['services']:service.setdefault('dns',{'mode':'manual'})
 return c
def save(): (E/'deployment.json').write_text(json.dumps(report,indent=2)+'\n')
def main():
 files={}
 for n in ['canonical-v2.lua','product-ddns.lua','product-controller.lua','product-provider.lua','product-rpc.lua','product-json.lua']: files['/usr/share/homepublish/'+n]=(R/'homepublish/files/usr/share/homepublish'/n).read_bytes()
 for n in ['services.js','product.js']:files['/www/luci-static/resources/view/homepublish/'+n]=(R/'luci-app-homepublish/htdocs/luci-static/resources/view/homepublish'/n).read_bytes()
 for n in ['usr/libexec/rpcd/homepublish','usr/share/rpcd/acl.d/luci-app-homepublish.json']:files['/'+n]=(R/'luci-app-homepublish/root'/n).read_bytes()
 before=snap();report['before']=before;save();s=before['status'];assert s['runtime']['phase']=='running' and s['desired_state']['state']=='enabled'
 assert all(x.get('dns',{'mode':'manual'}).get('mode')=='manual' for x in s['saved_config']['services'])
 existing=run('for p in '+ ' '.join(shlex.quote(x) for x in files)+'; do test ! -e "$p" || printf "%s\\n" "$p"; done').splitlines()
 report['previously_absent']=sorted(set(files)-set(existing))
 run('umask 077; mkdir -p '+B+'/stage; chmod 700 '+B+'; tar -C / -czf '+B+'/rollback.tar.gz '+' '.join(shlex.quote(x.lstrip('/')) for x in existing)+' etc/homepublish/product/state etc/config/homepublish etc/config/firewall etc/ddns-go/config.yaml etc/config/ddns-go')
 report['hashes']={}
 for i,(target,data) in enumerate(files.items()):
  stage=B+'/stage/'+str(i); run('umask 077; cat > '+stage,data);expected=hashlib.sha256(data).hexdigest();assert run('sha256sum '+stage).split()[0]==expected
  if target.endswith('.lua'):run('lua -e '+shlex.quote('assert(loadfile('+json.dumps(stage)+'))'))
  report['hashes'][target]={'sha256':expected,'stage':stage}
 save()
 old=before['controller']['homepublish']['instances']['controller']['pid'];run("ubus call service delete '{\"name\":\"homepublish\"}'")
 for _ in range(60):
  if run('test ! -d /proc/'+str(old)+'; printf "%s" "$?"')=='0':break
  time.sleep(.25)
 else:raise RuntimeError('old controller alive')
 for target,m in report['hashes'].items():
  mode='755' if target=='/usr/libexec/rpcd/homepublish' else '644';run('cp '+m['stage']+' '+shlex.quote(target+'.ddns-new')+' && chmod '+mode+' '+shlex.quote(target+'.ddns-new')+' && mv '+shlex.quote(target+'.ddns-new')+' '+shlex.quote(target))
  assert run('sha256sum '+shlex.quote(target)).split()[0]==m['sha256']
 run('/etc/init.d/rpcd reload; /etc/init.d/homepublish start')
 for _ in range(60):
  try:
   st=ub('status')
   if st['runtime']['phase']=='stopped':break
  except Exception:pass
  time.sleep(.25)
 assert normalized(st['saved_config'])==normalized(s['saved_config']) and st['desired_state']==s['desired_state']
 report['start_result']=json.loads(run('printf "%s\\n" '+shlex.quote(json.dumps({'action':'start','revision':s['saved_revision'],'approved':True}))+' | lua /usr/share/homepublish/product-device-cli.lua'))
 after=snap();report['after']=after
 for k in ['saved_config','saved_revision','active_config','active_revision','desired_state']:assert normalized(after['status'][k])==normalized(s[k]),k
 assert after['protected']==before['protected'];assert after['status']['runtime']['phase']=='running' and after['status']['runtime']['active_verified']
 assert all(v['ready'] for v in after['status']['runtime']['services'].values())
 assert after['controller']['homepublish']['instances']['controller']['pid']!=old
 report['profiles']=ub('ddns_profiles');report['ubus_methods']=run('ubus -v list homepublish');report['rpcd_list']=json.loads(run('/usr/libexec/rpcd/homepublish list'))
 report['acl_readback']=json.loads(run('cat /usr/share/rpcd/acl.d/luci-app-homepublish.json'))
 for target,m in report['hashes'].items():assert run('sha256sum '+shlex.quote(target)).split()[0]==m['sha256']
 report['success']=True;save();print(json.dumps({'success':True,'backup':B,'file_count':len(files),'profiles_count':len(report['profiles'].get('profiles',[]))}))
try:main()
except Exception as e:report['error']=repr(e);save();raise
