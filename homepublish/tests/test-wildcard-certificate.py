"""Read-only production validate and private target-Lua wildcard regression."""
import json,subprocess,shlex,uuid,io,tarfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
E=ROOT/'docs/evidence/input-firewall'
def run(cmd,data=None):
 p=subprocess.run(SSH+[cmd],input=data,capture_output=True,timeout=90)
 if p.returncode:raise RuntimeError(p.stdout.decode()+p.stderr.decode())
 return p.stdout.decode()
def main():
 payload=json.loads((E/'wildcard-native-payload.json').read_text())['payload']
 result=json.loads(run('ubus call homepublish validate '+shlex.quote(json.dumps({'config':payload}))))
 print('ACTUAL_UBUS',json.dumps(result))
 tag='green' if not result.get('error') else 'red'
 (E/('wildcard-validate-'+tag+'.json')).write_text(json.dumps(result,indent=2)+'\n')
 private='/root/homepublish-lua-store/wildcard-test-'+uuid.uuid4().hex[:10]
 test="""local J=dofile('/usr/share/homepublish/product-json.lua')
local C=dofile(ROOT..'/canonical-v2.lua')
local f=assert(io.open(ROOT..'/payload.json'));local base=J.decode(f:read('*a'));f:close()
local function clone() return J.decode(J.encode(base)) end
local c,e,d=C.validate(base);assert(c,'literal inventory wildcard reference rejected: '..tostring(e))
local override=clone();override.services[1].certificate_ref=base.default_certificate_ref;assert(C.validate(override),'service wildcard override')
local optional=clone();optional.default_certificate_ref=nil;assert(C.validate(optional),'optional default with explicit override')
local count=1
for _,ref in ipairs({'acme:*.example.test_ecc','acme:*.example.test_rsa','acme:legacy_name','import:legacy_name'}) do local x=clone();x.default_certificate_ref=ref;assert(C.validate(x),ref);count=count+1 end
for _,ref in ipairs({'acme:../evil','acme:*.example.test/evil','acme:*foo.example','acme:foo.*.test','acme:*.foo..test','import:*.example.test','acme:*.foo;id','acme:*.foo\\\\evil','acme:*.foo\"evil','acme:..','acme:*.foo%2fevil'}) do local x=clone();x.default_certificate_ref=ref;assert(not C.validate(x),'unsafe ref accepted: '..ref);count=count+1 end
local M=dofile('/usr/share/homepublish/certificate-metadata.lua')
assert(M.match({'*.innonext.win'},'vm.innonext.win')=='wildcard')
assert(not M.match({'*.innonext.win'},'innonext.win'))
assert(not M.match({'*.innonext.win'},'a.b.innonext.win'))
assert(not M.match({'*.innonext.win'},'other.win'))
package.path='/usr/share/homepublish/?.lua;'..package.path
local I=require('device-integrations')
assert(I.certificate_source(base.default_certificate_ref,'vm.innonext.win'),'real wildcard source must resolve')
assert(not I.certificate_source(base.default_certificate_ref,'innonext.win'))
assert(not I.certificate_source(base.default_certificate_ref,'a.b.innonext.win'))
local R=dofile(ROOT..'/direct-renderer.lua')
local plan={services={{hostname='vm.innonext.win',certificate_ref=base.default_certificate_ref,backend={addressFamily='ipv4',host='127.0.0.1',port=8080,allowed_ranges={'127.0.0.0/8'}}}},access_profile={listeners={{family='ipv4',address='192.168.1.2',interface='br-lan',zone='lan',protocol='tcp',internal_port=49443}}}}
local providers={authorize_listener=function()return true end,authorize_backend=function()return true end,healthy=function()return true end,certificate_snapshot=function(ref,host)assert(I.certificate_source(ref,host));return {certificate='/tmp/homepublish-test/cert.pem',key='/tmp/homepublish-test/key.pem'} end}
local rendered,why=R.render(plan,providers);assert(rendered,'wildcard renderer rejected: '..tostring(why))
print(J.encode({passed=true,reference_cases=count,san_cases=4,real_source_cases=3,renderer=true}))
"""
 files={n:(ROOT/'homepublish/files/usr/share/homepublish'/n).read_bytes() for n in ['canonical-v2.lua','direct-address.lua','direct-renderer.lua','certificate-reference.lua'] if (ROOT/'homepublish/files/usr/share/homepublish'/n).exists()}
 files['payload.json']=json.dumps(payload).encode();files['test.lua']=('local ROOT='+json.dumps(private)+'\n'+test).encode()
 b=io.BytesIO()
 with tarfile.open(fileobj=b,mode='w:gz') as tar:
  for name,data in files.items():
   i=tarfile.TarInfo(name);i.size=len(data);i.mode=0o600;tar.addfile(i,io.BytesIO(data))
 run('umask 077; mkdir '+private+'; tar xzf - -C '+private,b.getvalue())
 regression=json.loads(run('cd /; lua '+private+'/test.lua'))
 (E/'wildcard-regression-green.json').write_text(json.dumps({'private_root':private,'result':regression},indent=2)+'\n')
 print(json.dumps(regression))
 assert result.get('valid') is True,'actual production validate must be green'
if __name__=='__main__':main()
