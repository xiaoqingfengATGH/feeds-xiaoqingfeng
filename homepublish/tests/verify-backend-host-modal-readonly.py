"""Read-only actual installed modal -> page validation payload diagnosis."""
import hashlib,json,os,shlex,subprocess
from pathlib import Path
R=Path('D:/DevPortal/Openwrt/feeds-xiaoqingfeng')
E=R/'docs/evidence/lua-store/backend-host-header-modal';E.mkdir(parents=True,exist_ok=True)
SSH=['ssh','-i','D:/DevPortal/CloudHosts/HomePri.key','-o','BatchMode=yes','root@192.168.1.2']
def remote(cmd):return subprocess.check_output(SSH+[cmd],text=True)
def rpc(method,payload=None):return json.loads(remote('ubus call homepublish '+method+' '+shlex.quote(json.dumps(payload or {}))))
before=rpc('status');ddns=rpc('ddns_profiles');certs=rpc('certificates')
for name,obj in [('status',before),('ddns',ddns),('certs',certs)]: (E/(name+'.json')).write_text(json.dumps(obj,indent=2))
protected=remote('sha256sum /etc/homepublish/product/state /etc/config/firewall /etc/ddns-go/config.yaml /etc/config/ddns-go')
assets={}
for name in ['product.js','services.js']:
    data=subprocess.check_output(SSH+['cat /www/luci-static/resources/view/homepublish/'+name])
    source=(R/'luci-app-homepublish/htdocs/luci-static/resources/view/homepublish'/name).read_bytes()
    assets[name]={'installed_sha256':hashlib.sha256(data).hexdigest(),'source_sha256':hashlib.sha256(source).hexdigest(),'equal':data==source}
env=os.environ.copy();env.update(HP_MODAL_INSTALLED='1',HP_MODAL_STATUS=str(E/'status.json'),HP_MODAL_DDNS=str(E/'ddns.json'),HP_MODAL_CERTS=str(E/'certs.json'),HP_MODAL_PAYLOAD=str(E/'payload.json'))
p=subprocess.run(['node','luci-app-homepublish/tests/backend-host-header-page-save-native.test.cjs'],cwd=R,env=env,capture_output=True,text=True,timeout=90)
(E/'native-output.txt').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stdout+p.stderr
payload=json.loads((E/'payload.json').read_text());validation=rpc('validate',{'config':payload});(E/'validation.json').write_text(json.dumps(validation,indent=2))
assert validation['valid'] and validation['config']['services'][0]['backend']['host_header']=='ai.iwonderful.top'
after=rpc('status');(E/'after.json').write_text(json.dumps(after,indent=2))
keys=['saved_revision','active_revision','saved_config','active_config','desired_state'];assert all(before[k]==after[k] for k in keys)
assert protected==remote('sha256sum /etc/homepublish/product/state /etc/config/firewall /etc/ddns-go/config.yaml /etc/config/ddns-go')
report={'reproduced':False,'installed_assets':assets,'native_result':json.loads(p.stdout.strip().splitlines()[-1]),'actual_ubus_validation_retains_host':True,'saved_revision_before':before['saved_revision'],'saved_revision_after':after['saved_revision'],'production_unchanged':True,'production_writes':False,'deployment':False,'next_evidence_required':'Failing existing browser draft submitted payload and loaded product/services module contents; do not refresh or discard user drafts.'}
(E/'result.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
