#!/usr/bin/env python3
"""Verify a real current HomePublish IPK against this source tree."""
import argparse, hashlib, io, pathlib, tarfile
p=argparse.ArgumentParser();p.add_argument('ipk',type=pathlib.Path);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
with tarfile.open(a.ipk,'r:*') as outer:
 def nested(name):
  member=next(x for x in outer.getmembers() if x.name.removeprefix('./')==name)
  return tarfile.open(fileobj=io.BytesIO(outer.extractfile(member).read()),mode='r:*')
 with nested('data.tar.gz') as data,nested('control.tar.gz') as control:
  files={m.name.removeprefix('./'):(m.mode,data.extractfile(m).read()) for m in data if m.isfile()}
  meta=next(control.extractfile(m).read().decode() for m in control if m.name.removeprefix('./')=='control')
  for source in (root/'files/usr/share/homepublish').glob('*.lua'):
   mode,body=files['usr/share/homepublish/'+source.name]
   assert mode==0o644 and body==source.read_bytes().replace(b'\r\n',b'\n'),source.name
  assert 'usr/lib/lua/homepublish_store.so' not in files
  for name in ('product-store-core.lua','product-store.lua','product-controller.lua'):
   assert 'usr/share/homepublish/'+name in files
  assert files['etc/init.d/homepublish'][0]==0o755
  assert b'/etc/homepublish/product' in files['lib/upgrade/keep.d/homepublish'][1]
  conffiles=next(control.extractfile(m).read() for m in control.getmembers() if m.name.removeprefix('./')=='conffiles')
  assert b'/etc/config/homepublish' in conffiles
  assert files['etc/config/homepublish'][0]==0o600
  assert b"option enabled '0'" in files['etc/config/homepublish'][1]
  deps=next(line.split(': ',1)[1] for line in meta.splitlines() if line.startswith('Depends: ')).split(', ')
  assert {'lua','libuci-lua','libubus-lua','homepublish-engines','luci-lib-nixio','firewall4','nftables-json','flock'} <= set(deps)
  assert 'Package: homepublish\n' in meta
  assert not any('__pycache__' in k or k.startswith('tests/') for k in files)
print('CURRENT_IPK_PASS',hashlib.sha256(a.ipk.read_bytes()).hexdigest(),'files',len(files))
