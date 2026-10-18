"""Target Lua clean-loader regression: exact native payload and safety boundaries."""
import hashlib,json,subprocess,tarfile,io,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SSH=['ssh','-o','ProxyCommand=none','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
PRIVATE='/root/homepublish-lua-store/save-validation-'+uuid.uuid4().hex[:10]
E=ROOT/'docs/evidence/input-firewall'
def run(cmd,data=None):
 p=subprocess.run(SSH+[cmd],input=data,capture_output=True,timeout=60)
 if p.returncode:raise RuntimeError(p.stderr.decode()+p.stdout.decode())
 return p.stdout.decode()
def main():
 payload=json.loads((E/'services-save-native-payload.json').read_text())
 files={n:(ROOT/'homepublish/files/usr/share/homepublish'/n).read_bytes() for n in ['canonical-v2.lua','direct-address.lua','certificate-reference.lua']}
 # Encode via target's fixed JSON module; do not import the product directory.
 test="""local J=dofile('/usr/share/homepublish/product-json.lua')
local C=dofile(ROOT..'/canonical-v2.lua')
local f=assert(io.open(ROOT..'/payload.json'));local c=J.decode(f:read('*a'));f:close()
assert(not package.path:find('/usr/share/homepublish',1,true))
local out,e,d=C.validate(c);assert(out,e)
local count=0
for _,s in ipairs(c.services) do assert(s.backend.allowed_ranges==nil);count=count+1 end
for _,kind in ipairs({'http_proxy','https_proxy','tls_passthrough','ssh','tcp_forward'}) do
 local x=J.decode(J.encode(c));local s=x.services[1];x.services={s};s.type=kind
 s.hostname=nil;s.upstream_scheme=nil;s.certificate_mode=nil;s.certificate_ref=nil;s.listen_port=nil
 if kind=='http_proxy' or kind=='https_proxy' or kind=='tls_passthrough' then s.hostname='save.test' end
 if kind=='http_proxy' or kind=='https_proxy' then s.upstream_scheme='http' end
 if kind=='https_proxy' then s.certificate_mode='inherit' end
 if kind=='tcp_forward' then s.listen_port=29001 end
 assert(C.validate(x),kind)
end
local bad=J.decode(J.encode(c));bad.services[1].backend.host='8.8.8.8'
assert(not C.validate(bad),'public backend rejected')
bad=J.decode(J.encode(c));bad.services[1].unexpected_help='not schema'
assert(not C.validate(bad),'unknown fields rejected')
print(J.encode({valid=true,native_services=count,protocols=5,public_backend_rejected=true,unknown_field_rejected=true,clean_package_path=true}))
"""
 files['regression.lua']=("local ROOT="+json.dumps(PRIVATE)+'\n'+test).encode()
 files['payload.json']=json.dumps(payload).encode()
 b=io.BytesIO()
 with tarfile.open(fileobj=b,mode='w:gz') as t:
  for name,data in files.items():
   i=tarfile.TarInfo(name);i.size=len(data);i.mode=0o600;t.addfile(i,io.BytesIO(data))
 run('umask 077; mkdir '+PRIVATE+'; tar xzf - -C '+PRIVATE,b.getvalue())
 result=json.loads(run('cd /; lua '+PRIVATE+'/regression.lua'))
 (E/'services-save-isolated-validation.json').write_text(json.dumps({'private_root':PRIVATE,'result':result},indent=2)+'\n')
 print(json.dumps(result))
if __name__=='__main__':main()
