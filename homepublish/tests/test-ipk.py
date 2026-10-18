#!/usr/bin/env python3
"""Unpack real SDK IPKs and verify installed contract, not recipe text."""
import hashlib, io, json, pathlib, sys, tarfile
sdk=pathlib.Path(sys.argv[1]); source=pathlib.Path(sys.argv[2]); result=[]
def unpack(p):
 with tarfile.open(p) as outer:
  def inner(name):
   m=next(x for x in outer.getmembers() if x.name.lstrip('./')==name)
   return tarfile.open(fileobj=io.BytesIO(outer.extractfile(m).read()))
  with inner('data.tar.gz') as d,inner('control.tar.gz') as c:
   files={m.name.lstrip('./'):(m.mode,d.extractfile(m).read()) for m in d.getmembers() if m.isfile()}
   control=next(c.extractfile(m).read().decode() for m in c.getmembers() if m.name.lstrip('./')=='control')
 return files,control
for name in ['homepublish','luci-app-homepublish']:
 p=next((sdk/'bin/packages/x86_64/homestunlocal').glob(name+'_*.ipk'))
 files,control=unpack(p)
 assert not any('test' in x or '__pycache__' in x or 'adapter' in x for x in files)
 if name=='homepublish':
  for f in (source/name/'files/usr/share/homepublish').glob('*.lua'):
   assert files['usr/share/homepublish/'+f.name]==(0o644,f.read_bytes()),f
  for f in ['homepublish-guard','homepublish-lease','homepublish-publish']:
   mode,b=files['usr/libexec/'+f];assert mode==0o755 and b[:4]==b'\x7fELF'
  assert files['usr/lib/lua/homepublish_store.so'][1][:4]==b'\x7fELF'
  assert files['etc/init.d/homepublish'][0]==0o755
  assert b'product-lifecycle.lua' in files['etc/init.d/homepublish'][1]
  assert b"option enabled '0'" in files['etc/config/homepublish'][1]
  for dep in ['liblua','lua','libuci-lua','nginx-ssl','natmap','curl','ca-bundle']:assert dep in control
 else:
  assert files['usr/libexec/rpcd/homepublish'][0]==0o755
  for f in ['usr/share/luci/menu.d/luci-app-homepublish.json','usr/share/rpcd/acl.d/luci-app-homepublish.json']:
   json.loads(files[f][1])
  assert 'homepublish' in control and 'luci-base' in control
 result.append({'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'control':control,'installed_files':len(files)})
print(json.dumps(result,indent=2));print('PASS actual IPK installed modules, ELF, permissions, disabled defaults, menu/ACL, dependencies, no test adapter')
