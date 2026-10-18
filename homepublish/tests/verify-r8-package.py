import tarfile,pathlib,hashlib,subprocess,json
base=pathlib.Path('/home/eric/homestun-sdk-check/device-r8-source')
out=pathlib.Path('/mnt/d/DevPortal/homelede/artifacts/homepublish-r8')
rows=[]
for ipk in sorted(out.glob('*.ipk')):
 with tarfile.open(ipk) as outer:
  names=outer.getnames();data=next(n for n in names if 'data.tar' in n);ctrl=next(n for n in names if 'control.tar' in n)
  with tarfile.open(fileobj=outer.extractfile(ctrl),mode='r:*') as c:
   text=c.extractfile(next(n for n in c.getnames() if n.endswith('control'))).read().decode();assert 'Version: 0.1.0-r8' in text,text
  with tarfile.open(fileobj=outer.extractfile(data),mode='r:*') as d:
   for member in d.getmembers():
    if not member.isfile():continue
    path=member.name.lstrip('./');body=d.extractfile(member).read();source=None
    if path.startswith('www/luci-static/resources/view/homepublish/'):source=base/'luci-app-homepublish/htdocs'/path[4:]
    elif path.startswith('usr/share/homepublish/') or path.startswith('etc/init.d/homepublish'):source=base/'homepublish/files'/path
    elif path.startswith('usr/libexec/rpcd/') or path.startswith('usr/share/rpcd/acl.d/') or path.startswith('usr/share/luci/menu.d/'):source=base/'luci-app-homepublish/root'/path
    if source:
     assert body==source.read_bytes(),path
     rel=source.relative_to(base).as_posix();blob=subprocess.check_output(['git.exe','-C','D:/DevPortal/homelede/homepublish-product','show','9b7b93e:'+rel]);assert body==blob,path
    rows.append({'path':'/'+path,'sha256':hashlib.sha256(body).hexdigest(),'mode':oct(member.mode),'sourceMatched':bool(source)})
(out/'installed-manifest.json').write_text(json.dumps(rows,indent=2))
(out/'installed.sha256').write_text(''.join(r['sha256']+'  '+r['path']+'\n' for r in rows))
print(json.dumps({'packageFiles':len(rows),'sourceMatched':sum(r['sourceMatched'] for r in rows),'packages':[p.name for p in out.glob('*.ipk')]}))
