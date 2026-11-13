#!/usr/bin/env python3
"""Upload only private source; never deploy or restart production."""
import io,json,subprocess,tarfile,uuid,sys,hashlib
from pathlib import Path
repo=Path(__file__).resolve().parents[2]
root='/root/homepublish-lua-store/restart-'+uuid.uuid4().hex[:10]
runtime='/tmp/homepublish-restart-'+uuid.uuid4().hex[:10]
ssh=['ssh','-o','BatchMode=yes','-o','IdentitiesOnly=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
label=sys.argv[1] if len(sys.argv)>1 else 'restart'
case=sys.argv[2] if len(sys.argv)>2 else 'controller'
protected="sha256sum /etc/homepublish/product/state /etc/config/firewall /tmp/homepublish-runtime/nginx.conf; ubus call service list '{\"name\":\"homepublish\"}'"
def run(cmd,data=None):
 p=subprocess.run(ssh+[cmd],input=data,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);return p.returncode,p.stdout.decode(errors='replace')
buf=io.BytesIO()
with tarfile.open(fileobj=buf,mode='w') as tar:
 files=list((repo/'homepublish/files/usr/share/homepublish').glob('*.lua'))+list((repo/'homepublish/tests').glob('device-restart*.lua'))
 for f in files:
  text=f.read_text(encoding='utf-8')
  if f.name=='product-store.lua':text="return dofile('"+root+"/product-store-core.lua').new('"+root+"/store')\n"
  text=text.replace('/var/run/homepublish',runtime).replace('/usr/share/homepublish',root)
  b=text.encode();info=tarfile.TarInfo(f.name);info.size=len(b);info.mode=0o600;tar.addfile(info,io.BytesIO(b))
 init=(repo/'homepublish/files/etc/init.d/homepublish').read_text().replace('/var/run/homepublish',runtime).replace('/usr/share/homepublish',root)
 b=init.encode();info=tarfile.TarInfo('init');info.size=len(b);info.mode=0o600;tar.addfile(info,io.BytesIO(b))
rc,out=run("umask 077; mkdir -p '"+root+"'; tar -xf - -C '"+root+"'",buf.getvalue());assert rc==0,out
cmd="lua '"+root+"/device-restart"+('' if case=='controller' else '-'+case)+".lua' '"+root+"' '"+runtime+"'"
before_rc,before=run(protected);assert before_rc==0,before
rc,out=run(cmd)
cleanup_rc,cleanup=run("test ! -e '"+runtime+"' || exit 1; ubus call service list '{\"name\":\"homepublish-restart-"+root.rsplit('-',1)[1]+"\"}'")
if cleanup_rc!=0 or json.loads(cleanup or '{}'):
 out+='\nPRIVATE_CLEANUP_FAILED\n'+cleanup;rc=1
after_rc,after=run(protected)
if after_rc!=0 or before!=after:
 out+='\nPRODUCTION_BASELINE_CHANGED\n'+before+'\n'+after;rc=1
evidence=repo/'docs/evidence/lua-store';evidence.mkdir(parents=True,exist_ok=True)
(evidence/(label+'.json')).write_text(json.dumps({'root':root,'runtime':runtime,'command':cmd,'exit_code':rc,'output':out,'production_before':before,'production_after':after,'private_cleanup':cleanup,'archive_sha256':hashlib.sha256(buf.getvalue()).hexdigest()},indent=2),encoding='utf-8')
print(out);print('exit_code',rc,'root',root,'runtime',runtime)
sys.exit(rc)
