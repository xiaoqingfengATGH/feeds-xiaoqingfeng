"""Read-only final P4 evidence collector; local code is SSH transport only."""
import hashlib,json,pathlib,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[3]
E=ROOT/'docs/evidence/tcp-p4'
SSH=['ssh','-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','root@127.0.0.1']
def remote(cmd):
 r=subprocess.run(SSH+[cmd],capture_output=True,text=True,timeout=45)
 assert r.returncode==0,(cmd,r.returncode,r.stdout,r.stderr)
 return r.stdout
names=['product-device-provider.lua','product-device-v2-profile.lua','product-v2-runtime.lua','product-procd-group.lua','product-controller.lua','direct-renderer.lua','tcp-route-plan.lua','tcp-stream-renderer.lua','sslh-renderer.lua']
manifest={}
for name in names:
 p=ROOT/'homepublish/files/usr/share/homepublish'/name
 d=hashlib.sha256(p.read_bytes()).hexdigest()
 assert remote('sha256sum /usr/share/homepublish/'+name).split()[0]==d
 manifest['installed/'+name]=d
for name in ['device-tcp-p4-installed-cli.lua','device-tcp-p4-negative-cli.lua','device-tcp-p4-policy-rpc.lua']:
 p=ROOT/'homepublish/tests'/name;d=hashlib.sha256(p.read_bytes()).hexdigest()
 assert remote('sha256sum /tmp/homepublish-tcp-p3/'+name).split()[0]==d
 manifest['private/'+name]=d
for name in ['product.js','overview.js','services.js']:
 p=ROOT/'luci-app-homepublish/htdocs/luci-static/resources/view/homepublish'/name
 d=hashlib.sha256(p.read_bytes()).hexdigest()
 assert remote('sha256sum /www/luci-static/resources/view/homepublish/'+name).split()[0]==d
 manifest['installed-ui/'+name]=d
before=(E/'task24-baseline.txt').read_text();after=(E/'task24-baseline-after.txt').read_text()
assert before==after,'final fixture management baseline differs'
assert remote('sha256sum /etc/homepublish/product/state').split()[0]==before.split()[0],'current user journal differs from test baseline'
(E/'p4-stage-final-source-sha256.json').write_text(json.dumps(manifest,indent=2))
for name in ['homepublish-p3-controller','homepublish-p3-clients','homepublish-p3-backend','homepublish-p3-blocker','homepublish-p4-policy']:
 assert json.loads(remote('ubus call service list '+repr(json.dumps({'name':name}))))=={}
cmd="""set -eu
for d in runtime mixed-runtime tcp-runtime matrix-runtime controller-runtime controller-fixture; do test ! -e /tmp/homepublish-tcp-p3/$d; done
for d in /root/homepublish-p3-ssh-auth /root/homepublish-p3-controller-auth /root/homepublish-p3-matrix-auth; do test ! -e "$d"; done
netstat -lntp > /tmp/homepublish-tcp-p3/evidence/stage-final-listeners.txt
! grep -E ':(49443|49445|49446|49447|49543|49544|49545|49546|49547|49548|49549|49550|49551|49552|49553|49554|49555|49556|49557)[[:space:]]' /tmp/homepublish-tcp-p3/evidence/stage-final-listeners.txt
lua -e "package.path='/usr/share/homepublish/?.lua;'..package.path;local p=require('product-device-provider');local r,e=p.runtime_plan({});assert(not r and e=='installed v2 capability unavailable');print('PASS authorization marker absent: installed capability denied')"
lua -e "package.path='/usr/share/homepublish/?.lua;'..package.path;local s=assert(require('product-provider').handle({action='status'}));assert(s.intent_revision==7 and s.desired_state.state=='disabled' and s.desired_state.manual_stop_latch and s.runtime.phase=='stopped');print('PASS current live revision'..s.saved_revision..' intent7 disabled latch stopped (journal SHA equals current before/after baseline)')"
echo P4_STAGE_FINAL_CLEANUP_READBACK_GREEN
"""
out=remote(cmd)
(E/'p4-stage-final-readback.log').write_text(out)
print(out)
print('PASS final installed/private SHA256 readback:',len(manifest),'files')
