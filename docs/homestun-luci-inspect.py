#!/usr/bin/env python3
"""Read-only real IPK inspection; never installs/executes payload."""
import pathlib,tarfile,io,json,hashlib,fcntl,subprocess,re
repo=pathlib.Path('/mnt/d/DevPortal/homelede/feeds-xiaoqingfeng-homestun'); root=pathlib.Path('/home/eric/homestun-sdk-check'); sdk=root/'openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def unpack(p):
 with tarfile.open(p,'r:gz') as outer:
  archives={x:outer.extractfile('./'+x+'.tar.gz').read() for x in ['control','data']}
 result={};entries=[]
 for kind,blob in archives.items():
  with tarfile.open(fileobj=io.BytesIO(blob),mode='r:gz') as t:
   result[kind]={m.name.removeprefix('./'):t.extractfile(m).read() for m in t if m.isfile()}
   if kind=='data':entries=[{'name':m.name,'mode':oct(m.mode),'uid':m.uid,'gid':m.gid,'bytes':m.size} for m in t.getmembers()]
 return result,entries
with (root/'build.lock').open('a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 ipk=repo/'docs/artifacts/luci-app-homestun_0.1.0-r1_all.ipk';parts,entries=unpack(ipk);control=parts['control']['control'].decode();data=parts['data']
 assert 'Architecture: all\n' in control
 deps={s.strip().split()[0] for s in next(x for x in control.splitlines() if x.startswith('Depends:')).split(':',1)[1].split(',')}
 assert {'homestun','luci-base'}<=deps
 expected={str(p.relative_to(repo/'luci-app-homestun/root')):p for p in (repo/'luci-app-homestun/root').rglob('*') if p.is_file()}
 for name,p in expected.items():assert data[name]==p.read_bytes(),name
 for name in ['schema.js','settings.js']:
  path='www/luci-static/resources/view/homestun/'+name
  assert path in data and len(data[path])>0
 acl=json.loads(data['usr/share/rpcd/acl.d/luci-app-homestun.json'])['luci-app-homestun']
 assert acl['read']=={'uci':['homestun'],'ubus':{'homestun':['status']}} and acl['write']=={'uci':['homestun'],'ubus':{'uci':['commit']}}
 # SDK minifies JS: bind each packaged byte to the real minifier output.
 for name in ['schema.js','settings.js']:
  source=repo/'luci-app-homestun/htdocs/luci-static/resources/view/homestun'/name
  packed=data['www/luci-static/resources/view/homestun/'+name]
  minimized=subprocess.run([str(sdk/'staging_dir/hostpkg/bin/jsmin')],input=source.read_bytes(),stdout=subprocess.PIPE,check=True).stdout
  assert packed==minimized,name
 settings=data['www/luci-static/resources/view/homestun/settings.js'].decode()
 assert 'return view.extend({' in settings and 'handleSave:function()' in settings
 assert "method:'commit',params:['config'],reject:true" in settings and "commit('homestun')" in settings
 assert 'handleSaveApply:null' in settings and 'silent===true' in settings
 assert not re.search(r"method:['\"](?:apply|reload|start|restart)['\"]",settings)
 allowed=set(expected)|{'www/luci-static/resources/view/homestun/'+x for x in ['schema.js','settings.js']}
 assert set(data)==allowed,sorted(set(data)^allowed)
 # Stock LuCI cache/rpcd refresh is present; no HomeSTUN activation hook.
 stock_hooks={'postinst','postinst-pkg','prerm'}
 assert set(parts['control'])==stock_hooks|{'control'}
 hooks={k:parts['control'][k].decode() for k in sorted(stock_hooks)}
 assert hooks['postinst-pkg']=='[ -n "${IPKG_INSTROOT}" ] || { rm -f /tmp/luci-indexcache.*\n\trm -rf /tmp/luci-modulecache/\n\tkillall -HUP rpcd 2>/dev/null\n\texit 0\n}\n'
 assert not any(re.search(r'homestun|/etc/init.d/|enable|restart|firewall|nft',v) for v in hooks.values())
 browser=json.loads((repo/'docs/artifacts/luci-browser-acceptance.json').read_text())
 assert browser['result']=='PASS' and browser['errors']==[]
 browser_binding={k:v for k,v in browser['sources'].items() if k.startswith('luci-app-homestun/')}
 for name,h in browser_binding.items():assert sha(repo/name)==h,name
 sdk_binding=json.loads((repo/'docs/homestun-luci-sdk.json').read_text())
 assert sdk_binding['sha256']==sha(ipk)
 for item in sdk_binding['source_binding']:
  rel=item['file'];h=item['sha256']
  assert sha(repo/'luci-app-homestun'/rel)==h and sha(root/'source-feed/luci-app-homestun'/rel)==h,rel
 menu=json.loads(data['usr/share/luci/menu.d/luci-app-homestun.json']);assert menu['admin/services/homestun']['action']['path']=='homestun/settings'
 assert next(x for x in entries if x['name'].endswith('/rpcd/homestun'))['mode']=='0o755'
 assert all(x['uid']==0 and x['gid']==0 for x in entries)
 assert all(x['mode'] in ('0o644','0o755') for x in entries),entries
 assert not any(x.startswith('etc/init.d/') or x.startswith('etc/uci-defaults/') or x.startswith('etc/config/') for x in data)
 core=repo/'docs/artifacts/homestun_0.1.0-r1_x86_64.ipk';corehash=sha(core);assert corehash=='84087e052d2cefacc7ac943ef9bc74000206379d80ca31b4de5f9c58d0ca4c22',corehash
 cp,_=unpack(core);config=cp['data']['etc/config/homestun'].decode();assert "option enabled '0'" in config
 binding=json.loads((repo/'docs/homestun-sdk-dependency-source-binding.json').read_text()); immutable={k:v for k,v in binding.items() if k=='Makefile' or k.startswith('files/') or k.startswith('src/')}
 for name,h in immutable.items():assert sha(repo/'homestun'/name)==h,name
 index=(sdk/'feeds/homestunlocal.index').read_text();assert 'Package: luci-app-homestun\n' in index
 link=sdk/'package/feeds/homestunlocal/luci-app-homestun';assert link.is_symlink()
 active=[]
 for p in pathlib.Path('/proc').iterdir():
  if not p.name.isdigit():continue
  try:
   cwd=(p/'cwd').resolve();comm=(p/'comm').read_text().strip()
   if comm in ['make','gmake'] and (cwd==sdk or sdk in cwd.parents):active.append(p.name)
  except (OSError,RuntimeError):pass
 assert not active,active
 report={'artifact':str(ipk),'sha256':sha(ipk),'bytes':ipk.stat().st_size,'control':control,'payload':entries,'acl':acl,'menu':menu,'core_sha256':corehash,'core_production_files_unchanged':list(immutable),'core_config':config,'sdk_discovery':'standard feeds index and package symlink verified','active_sdk_make':active,'installed':False,'activated':False,'package_checks':{'minified_js_source_match':True,'class_export':True,'scoped_save_commit':True,'silent_row_lifecycle':True,'payload_allowlist':sorted(allowed),'homestun_activation_hooks':False},'standard_luci_control_hooks':hooks,'browser_evidence':{'result':browser['result'],'errors':browser['errors'],'source_binding':browser_binding},'source_binding_manifest':'docs/homestun-luci-sdk.json','limitations':['corrected IPK not installed on router; browser PASS exercised matching source with genuine target assets in isolated fixture','final independent review pending','real enabled engines/procd, target HTTPS, STUN/public TCP and Cloudflare deployment remain separate gates']}
 (repo/'docs/homestun-luci-inspection.json').write_text(json.dumps(report,indent=2)+'\n');(repo/'docs/homestun-luci-discovery-index.txt').write_text(index)
 print(json.dumps(report,indent=2))
