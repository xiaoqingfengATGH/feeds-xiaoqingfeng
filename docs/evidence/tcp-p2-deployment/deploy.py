import pathlib,subprocess,hashlib,json,datetime
R=pathlib.Path('D:/DevPortal/homelede/homepublish-product')
S=pathlib.Path('C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch/homepublish-deploy')
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','root@127.0.0.1']
SCP=['scp','-O','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','-P','222']
def remote(cmd):return subprocess.check_output(SSH+[cmd],text=True)
files=[]
for base, dest in [(R/'homepublish/files/usr/share/homepublish','/usr/share/homepublish'),(R/'homepublish/files/etc/init.d','/etc/init.d'),(R/'luci-app-homepublish/htdocs','/www'),(R/'luci-app-homepublish/root','')]:
 for p in sorted(base.rglob('*')):
  if p.is_file():files.append({'source':str(p),'target':dest+'/'+p.relative_to(base).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
p=S/'homepublish_store.so';files.append({'source':str(p),'target':'/usr/lib/lua/homepublish_store.so','sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S');backup='/root/homepublish-backups/'+stamp
manifest={'backup':backup,'files':files,'native_source_sha256':hashlib.sha256((R/'homepublish/src/product-store.c').read_bytes()).hexdigest()}
(S/'deployment-manifest.json').write_text(json.dumps(manifest,indent=2))
# Backup includes exact installed code plus entire private journal/config; never outputs contents.
paths=' '.join(x['target'].lstrip('/') for x in files)
cmd="set -eu; umask 077; mkdir -p '"+backup+"'; chmod 700 /root/homepublish-backups '"+backup+"'; cd /; for f in "+paths+"; do if [ -e \"$f\" ]; then printf '%s\\n' \"$f\"; fi; done > '"+backup+"/existing-paths'; printf '%s\\n' etc/homepublish etc/config/homepublish >> '"+backup+"/existing-paths'; tar -czf '"+backup+"/installed-and-private.tar.gz' -T '"+backup+"/existing-paths'; while read f; do if [ -f \"$f\" ]; then sha256sum \"$f\"; fi; done < '"+backup+"/existing-paths' > '"+backup+"/before.sha256'; find /etc/homepublish -type f -exec sha256sum {} \\; > '"+backup+"/private.sha256'; sha256sum /etc/config/homepublish /etc/config/network /etc/config/firewall > '"+backup+"/config.sha256'; ubus call homepublish status > '"+backup+"/status-before.json'; chmod 600 '"+backup+"/'*; tar -tzf '"+backup+"/installed-and-private.tar.gz' >/dev/null; sha256sum '"+backup+"/installed-and-private.tar.gz'"
print(remote(cmd),flush=True)
# Upload each source directly, then exact-target readback for the complete group.
for x in files:
 target=x['target'];remote("mkdir -p '"+str(pathlib.PurePosixPath(target).parent)+"'")
 subprocess.run(SCP+[x['source'],'root@127.0.0.1:'+target],check=True,capture_output=True)
 remote("chmod "+('755' if target.startswith('/etc/init.d/') or target.startswith('/usr/libexec/') else '644')+" '"+target+"'")
actual=remote('sha256sum '+' '.join(x['target'] for x in files));(S/'installed.sha256').write_text(actual)
got={line.split(None,1)[1].strip():line.split()[0] for line in actual.splitlines()}
for x in files:assert got[x['target']]==x['sha256'],x['target']
print('EXACT_READBACK_PASS',len(files),'BACKUP',backup,flush=True)
subprocess.run(SCP+[str(S/'deployment-manifest.json'),'root@127.0.0.1:'+backup+'/deployment-manifest.json'],check=True,capture_output=True)
print(remote("chmod 600 '"+backup+"/deployment-manifest.json'; sha256sum -c '"+backup+"/private.sha256'; sha256sum -c '"+backup+"/config.sha256'; /etc/init.d/rpcd restart; sleep 2; ubus -v list homepublish; ubus call homepublish status"),flush=True)
