import importlib.util,json,hashlib,subprocess
from pathlib import Path
R=Path('D:/DevPortal/Openwrt/feeds-xiaoqingfeng');spec=importlib.util.spec_from_file_location('deploy',R/'homepublish/tests/deploy-backend-host-header.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
d=json.loads((m.E/'deployment.json').read_text());m.report=d
assert d['after']['runtime']['active_verified'] and d['after']['runtime']['phase']=='running'
d['diagnostic_issue_resolved']=d.pop('error')
d['firewall']=m.run('nft list chain inet fw4 input_lan')
d['installed_readback_hashes']=m.run('sha256sum '+' '.join(d['sha256']))
assets=m.E/'installed-assets';assets.mkdir(exist_ok=True)
for p,want in d['sha256'].items():
 data=subprocess.check_output(m.SSH+['cat '+p]);assert hashlib.sha256(data).hexdigest()==want;(assets/p.rsplit('/',1)[1]).write_bytes(data)
s=m.status()
for k in ['saved_config','active_config','saved_revision','active_revision','desired_state']:assert s[k]==d['before'][k],k
assert s['runtime']['active_verified'] and s['runtime']['phase']=='running';assert m.protect()==d['protected_before']
d['final_status']=s;d['deployed']=True
(m.E/'deployment.json').write_text(json.dumps(d,indent=2)+'\n')
print(json.dumps({'deployed':True,'revision':s['saved_revision'],'phase':s['runtime']['phase'],'generation':s['runtime']['generation'],'protectedSettingsUnchanged':True,'backup':d['backup'],'diagnosticIssueResolved':True}))
