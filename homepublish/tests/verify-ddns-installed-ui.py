import subprocess,json,hashlib,os
from pathlib import Path
R=Path('D:/DevPortal/Openwrt/feeds-xiaoqingfeng');E=R/'docs/evidence/lua-store/ddns-phase2-deploy';A=E/'installed-assets';A.mkdir(exist_ok=True)
SSH=['ssh','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
for n in ['services.js','product.js','probes.js','entry.js','overview.js']:
 data=subprocess.check_output(SSH+['cat /www/luci-static/resources/view/homepublish/'+n]);(A/n).write_bytes(data)
pre=E/'installed-preload.cjs';pre.write_text("const fs=require('node:fs'),path=require('node:path'),orig=fs.readFileSync;const dir="+json.dumps(str(A))+";fs.readFileSync=function(p,...a){let s=String(p).replaceAll('\\\\','/');if(s.includes('/htdocs/luci-static/resources/view/homepublish/'))p=path.join(dir,path.basename(s));let v=orig.call(this,p,...a);if(s.endsWith('/upstream-tls-form-probe.cjs'))v=String(v).replace(\"path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish')\",JSON.stringify(dir));return v;};")
results=[]
for p in sorted((R/'luci-app-homepublish/tests').glob('services-dns-*.test.cjs')):
 cases=['multiple','empty','retained','failure'] if 'edge-native' in p.name else ['default']
 for case in cases:
  env=os.environ.copy();env['HP_DNS_CASE']=case
  q=subprocess.run(['node','-r',str(pre),str(p)],capture_output=True,text=True,env=env,timeout=100)
  results.append({'test':p.name,'case':case,'code':q.returncode,'stdout':q.stdout,'stderr':q.stderr})
  print(p.name,case,q.returncode,flush=True)
(E/'installed-ui-tests.json').write_text(json.dumps({'installed_asset_hashes':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in A.glob('*.js')},'results':results},indent=2))
raise SystemExit(any(r['code'] for r in results))
