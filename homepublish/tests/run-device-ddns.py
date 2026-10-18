"""Run staged backend on real target in a private root; never production DNS POST."""
import io, json, subprocess, tarfile, uuid, sys, hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
private='/root/homepublish-lua-store/ddns-test-'+uuid.uuid4().hex[:10]
case=sys.argv[1]; label=sys.argv[2]
files={p.name:p.read_bytes() for p in (ROOT/'homepublish/files/usr/share/homepublish').glob('*.lua')}
files['test.lua']=(('local ROOT='+json.dumps(private)+'\npackage.path=ROOT..\'/?.lua;\'..package.path\n').encode()+(ROOT/'homepublish/tests'/('device-ddns-'+case+'.lua')).read_bytes())
files['rpcd-homepublish']=(ROOT/'luci-app-homepublish/root/usr/libexec/rpcd/homepublish').read_bytes().replace(b'/usr/share/homepublish',private.encode())
files['acl.json']=(ROOT/'luci-app-homepublish/root/usr/share/rpcd/acl.d/luci-app-homepublish.json').read_bytes()
# Socket injection exists only in copied fixture bytes, never in RPC/config.
if 'product-ddns.lua' in files:
 files['product-ddns.lua']=files['product-ddns.lua'].replace(b"/var/run/ddns-go/local-api.sock",(private+'/api.sock').encode())
b=io.BytesIO()
with tarfile.open(fileobj=b,mode='w:gz') as t:
 for name,data in files.items():
  i=tarfile.TarInfo(name);i.size=len(data);i.mode=0o600;t.addfile(i,io.BytesIO(data))
def baseline():
 p=subprocess.run(SSH+['sha256sum /etc/homepublish/product/state /etc/ddns-go/config.yaml /etc/config/ddns-go /etc/config/firewall'],capture_output=True,timeout=30)
 if p.returncode: raise RuntimeError(p.stderr.decode())
 return p.stdout.decode()
before=baseline()
p=subprocess.run(SSH+['umask 077; mkdir '+private+'; tar xzf - -C '+private+'; lua '+private+'/test.lua'],input=b.getvalue(),capture_output=True,timeout=90)
after=baseline()
result={'source_sha256':{name:hashlib.sha256(data).hexdigest() for name,data in files.items()},'private_root':private,'production_hashes_before':before,'production_hashes_after':after,'production_unchanged':before==after,'case':case,'returncode':p.returncode,'stdout':p.stdout.decode(),'stderr':p.stderr.decode()}
assert before==after,'production configuration changed during private tests'
e=ROOT/'docs/evidence/lua-store'/('ddns-'+label+'.json');e.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ('source_sha256','production_hashes_before','production_hashes_after')}));sys.exit(p.returncode)
