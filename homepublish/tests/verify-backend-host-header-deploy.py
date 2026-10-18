"""Installed-byte native LuCI harness, read-only real ubus validation."""
import importlib.util,json,os,subprocess,hashlib
from pathlib import Path
R=Path('D:/DevPortal/Openwrt/feeds-xiaoqingfeng');spec=importlib.util.spec_from_file_location('deploy',R/'homepublish/tests/deploy-backend-host-header.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
E=m.E;T=R/'luci-app-homepublish/tests';before=m.protect();state=m.run('sha256sum /etc/homepublish/product/state')
assets=E/'installed-assets'
preload=E/'installed-preload.cjs'
preload.write_text("const fs=require('node:fs');const original=fs.readFileSync;fs.readFileSync=function(p,...args){const value=original.call(this,p,...args);if(String(p).replaceAll('\\\\','/').endsWith('/upstream-tls-form-probe.cjs')){return String(value).replace(\"listeners:[{family:\",\"listeners:[{listener_id:'fixture_ipv4',network:'',family:\").replace(\"schema_version:2,publication_policy:\",\"schema_version:2,default_certificate_ref:'acme:*.innonext.win',publication_policy:\").replace(\"firewall:{ipv4_zones:['wan']}\",\"firewall:{ipv4_zones:['wan'],ipv6_zones:[]}\").replace(\"host:'192.0.2.2'\",\"host:'192.168.1.254'\").replace(\"path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish')\","+json.dumps(json.dumps(str(assets)))+");}return value;};\n")
env=os.environ.copy();env['HP_HOST_HEADER_PAYLOAD']=str(E/'native-host-header-payload.json')
p=subprocess.run(['node','-r',str(preload),str(T/'backend-host-header-native.test.cjs')],capture_output=True,text=True,env=env,timeout=160)
report={'native':{'code':p.returncode,'stdout':p.stdout,'stderr':p.stderr},'boundary':'Installed LuCI loader/form and downloaded installed product/services bytes; fixture RPC prevents all writes. Not an authenticated ordinary LuCI browser page.'}
if p.returncode==0:
 cfg=json.loads((E/'native-host-header-payload.json').read_text());report['captured_native_config']=cfg
 report['native_validation']=m.rpc('validate',{'config':cfg})
 actual=m.status()['saved_config'];actual['services'][0]['backend']['host_header']=cfg['services'][0]['backend']['host_header']
 report['actual_saved_plus_native_host_validation']=m.rpc('validate',{'config':actual})
 report['protected_unchanged']=before==m.protect();report['journal_unchanged']=state==m.run('sha256sum /etc/homepublish/product/state')
 report['installed_hashes']={x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in assets.iterdir()}
(E/'installed-native-ui.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2));assert p.returncode==0;assert report['protected_unchanged'] and report['journal_unchanged'];assert report['native_validation']['valid'] and report['actual_saved_plus_native_host_validation']['valid']
