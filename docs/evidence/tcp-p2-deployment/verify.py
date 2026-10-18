import json,pathlib,subprocess,hashlib,urllib.request
S=pathlib.Path('C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch/homepublish-deploy');m=json.loads((S/'deployment-manifest.json').read_text())
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','root@127.0.0.1']
def remote(s):return subprocess.check_output(SSH+[s],text=True)
results={}
for meth,args in [('status',{}),('network_inventory',{}),('migration_preview',{'expected_revision':99}),('migration_preview',{'expected_revision':0}),('preflight',{'revision':99}),('preflight',{'revision':0})]:
 key=meth+str(args);results[key]=json.loads(remote("ubus call homepublish "+meth+" '"+json.dumps(args)+"'"))
assert results["status{}"]['saved_revision']==0
assert results["status{}"]['intent_revision']==7
assert results["migration_preview{'expected_revision': 99}"]['error_code']=='REVISION_CONFLICT'
assert results["preflight{'revision': 99}"]['error_code']=='REVISION_CONFLICT'
results['native']=remote("lua -e 'local s=require(\"homepublish_store\"); print(\"migration_backup=\"..tostring(s.migration_backup))'")
assert 'migration_backup=true' in results['native']
results['http_static']=[]
for x in m['files']:
 if x['target'].startswith('/www/'):
  url='http://127.0.0.1:1081/'+x['target'][5:]
  with urllib.request.urlopen(url,timeout=15) as f:b=f.read();status=f.status
  h=hashlib.sha256(b).hexdigest();assert h==x['sha256'],url
  results['http_static'].append({'url':url,'status':status,'sha256':h})
results['final_invariants']=remote("sha256sum -c '"+m['backup']+"/private.sha256'; sha256sum -c '"+m['backup']+"/config.sha256'; test ! -e /etc/homepublish/device-test/enabled; test ! -S /var/run/homepublish/control.sock; netstat -lntp 2>/dev/null | grep -E ':80 |:443 |:22 '; ps w | grep -E '[h]omepublish|[n]ginx.*homepublish' || true")
results['backup_manifest_readback']=remote("sha256sum '"+m['backup']+"/deployment-manifest.json'").split()[0]
assert results['backup_manifest_readback']==hashlib.sha256((S/'deployment-manifest.json').read_bytes()).hexdigest()
(S/'verification.json').write_text(json.dumps(results,indent=2,ensure_ascii=False))
print(json.dumps(results,indent=2,ensure_ascii=False))
