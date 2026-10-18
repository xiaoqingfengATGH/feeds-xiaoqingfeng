import json,subprocess,os,shlex,hashlib
from pathlib import Path
R=Path('D:/DevPortal/Openwrt/feeds-xiaoqingfeng');T=R/'luci-app-homepublish/tests';E=R/'docs/evidence/lua-store/ddns-phase2-deploy';d=json.loads((E/'deployment.json').read_text());SSH=['ssh','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2']
def remote(c):return subprocess.check_output(SSH+[c]).decode()
status=json.loads(remote("ubus call homepublish status '{}'"));profiles=json.loads(remote("ubus call homepublish ddns_profiles '{}'"));before=remote('sha256sum /etc/homepublish/product/state /etc/ddns-go/config.yaml /etc/config/ddns-go /etc/config/firewall /etc/config/homepublish');
source=(T/'upstream-tls-form-probe.cjs').read_text();lines=source.splitlines();lines[4]='const config='+json.dumps(status['saved_config'])+';';source='\n'.join(lines)
source=source.replace("data={saved_config:config,saved_revision:1,desired_state:{state:'disabled'},runtime:{phase:'stopped',cleanup:'confirmed'}}",'data='+json.dumps(status))
source=source.replace("data={available:false,profiles:[]}",'data='+json.dumps(profiles))
source=source.replace("page.getByRole('button',{name:'Edit',exact:true}).click()","page.getByRole('button',{name:'Edit',exact:true}).first().click()")
source=source.replace("path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish')",json.dumps(str(E/'installed-assets')))
start=source.index(" await tab('access');");end=source.index(' }finally{',start)
body="""
 await tab('access');await field('dns_mode').waitFor({state:'visible'});assert.equal(await field('dns_mode').inputValue(),'manual');
 const collect=()=>page.evaluate(async()=>{const dom=await L.require('dom'),api=await L.require('view.homepublish.product');return api.collectConfig(dom.findClassInstance(document.querySelector('.cbi-map')));});
 const manual=await collect();await field('dns_mode').selectOption('ddns_go');
 const profile=PROFILES.profiles[0];assert.equal(PROFILES.profiles.length,1);
 const selected=modal.locator('.cbi-value').filter({has:field('dns_profile')});
 assert.ok((await modal.textContent()).includes(profile.provider));assert.equal(await field('dns_profile').isVisible(),false);
 assert.equal(await field('dns_a').isChecked(),profile.a.enabled);assert.equal(await field('dns_aaaa').isChecked(),!profile.a.enabled && profile.aaaa.enabled);
 assert.equal(await field('dns_a').isDisabled(),!profile.a.enabled);assert.equal(await field('dns_aaaa').isDisabled(),!profile.aaaa.enabled);
 await modal.getByRole('button',{name:'Save',exact:true}).click();await modal.waitFor({state:'hidden'});
 const auto=await collect();assert.equal(auto.services[0].dns.mode,'ddns_go');assert.equal(auto.services[0].dns.profile_id,profile.profile_id);
 fs.writeFileSync(PAYLOAD,JSON.stringify({manual,auto}));assert.deepEqual(errors,[]);console.log(JSON.stringify({installedLoader:true,installedAssets:true,actualReadOnlyUbusStatus:true,actualReadOnlyUbusProfiles:true,profileCount:1,defaultManual:true,profileSummaryPresent:true,ipv4Enabled:profile.a.enabled,ipv6Enabled:profile.aaaa.enabled,productionWrites:false}));
""".replace('PROFILES',json.dumps(profiles)).replace('PAYLOAD',json.dumps(str(E/'native-payloads.json')))
source=source[:start]+body+source[end:]
launcher="const Module=require('node:module');const m=new Module("+json.dumps(str(T/'live-installed-ddns-probe.cjs'))+",module);m.filename="+json.dumps(str(T/'live-installed-ddns-probe.cjs'))+";m.paths=module.paths;m._compile("+json.dumps(source)+",m.filename);"
(E/'live-installed-probe.cjs').write_text(launcher)
# Resolve Playwright from its absolute dependency path, not the evidence directory.
env=os.environ.copy();q=subprocess.run(['node','-r',str(E/'installed-preload.cjs'),str(E/'live-installed-probe.cjs')],capture_output=True,text=True,timeout=120,env=env)
report={'native':{'code':q.returncode,'stdout':q.stdout,'stderr':q.stderr},'ordinary_browser_blocker':'Browser profile locked; not closed to preserve user tabs. Native installed LuCI loader fallback uses actual read-only ubus discovery/status through isolated RPC transport, not an authenticated ordinary LuCI page.'}
if q.returncode==0:
 payloads=json.loads((E/'native-payloads.json').read_text());report['validation']={}
 for kind,cfg in payloads.items():
  value=json.loads(remote('ubus call homepublish validate '+shlex.quote(json.dumps({'config':cfg}))))
  report['validation'][kind]=value
 report['protected_before']=before;report['protected_after']=remote('sha256sum /etc/homepublish/product/state /etc/ddns-go/config.yaml /etc/config/ddns-go /etc/config/firewall /etc/config/homepublish');assert before==report['protected_after']
(E/'live-readonly-ui.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2));assert q.returncode==0
