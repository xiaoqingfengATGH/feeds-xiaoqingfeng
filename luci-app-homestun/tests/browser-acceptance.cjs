const {chromium}=require('C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch/homestun-browser/node_modules/playwright');
const fs=require('node:fs'),assert=require('node:assert/strict'),{execFileSync}=require('node:child_process');
const root='/tmp/homestun-luci-isolated', artifact='docs/artifacts/';
function ssh(cmd){return execFileSync('ssh',['-F','/dev/null','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','-o','BatchMode=yes','root@127.0.0.1',cmd],{encoding:'utf8'});}
(async()=>{const b=await chromium.launch({channel:'chrome',headless:true});const evidence={requests:[],errors:[],sources:{}};for(const name of ['luci-app-homestun/htdocs/luci-static/resources/view/homestun/settings.js','luci-app-homestun/htdocs/luci-static/resources/view/homestun/schema.js','luci-app-homestun/root/usr/share/rpcd/acl.d/luci-app-homestun.json','docs/artifacts/luci-target-assets/www/luci-static/resources/luci.js','docs/artifacts/luci-target-assets/www/luci-static/resources/form.js'])evidence.sources[name]=require('node:crypto').createHash('sha256').update(fs.readFileSync(name)).digest('hex');try{
 const p=await b.newPage();p.on('pageerror',e=>evidence.errors.push(e.message));p.on('request',r=>{if(r.method()==='POST'){try{const data=r.postDataJSON();for(const q of Array.isArray(data)?data:[data])if(q.method==='call')evidence.requests.push({object:q.params[1],method:q.params[2],args:q.params[3]});}catch{}}});
 async function load(){await p.goto('http://127.0.0.1:18991/');await p.waitForFunction(()=>window.result?.loader);assert.equal(await p.evaluate(()=>result.loader),'PASS');await p.evaluate(async()=>{window.v=await L.require('view.homestun.settings');});await p.locator('.cbi-button-save').waitFor();}
 const field=(id,key)=>['enabled','exposure_approved','publication'].includes(key)?p.locator(`[id="cbid.homestun.${id}.${key}"] input[type="checkbox"]`):p.locator(`[id="widget.cbid.homestun.${id}.${key}"]`);
 await load();evidence.inputs=await p.locator('input').evaluateAll(es=>es.map(e=>({id:e.id,type:e.type,value:e.value})));
 await field('main','enabled').check();await field('main','exposure_approved').check();
 await field('main','ttl').fill('75');await field('fixture','name').fill('browser.example');await field('fixture','upstream').fill('http://192.168.1.8:18082');
 await p.locator('.cbi-button-save').click();await p.waitForFunction(()=>v.statusNode.textContent.includes('configured'));await p.waitForTimeout(500);
 const committed=ssh(`chroot ${root} /sbin/uci export homestun`);assert.match(committed,/option ttl '75'/);assert.match(committed,/browser.example/);assert.match(committed,/option enabled '1'/);
 evidence.save={committed,status:await p.evaluate(()=>v.statusNode.textContent),session:await p.evaluate(async()=>{const r=await L.require('rpc');return r.declare({object:'uci',method:'get',params:['config'],expect:{values:{}}})('homestun');})};
 evidence.save.otherCommitted=ssh(`chroot ${root} /sbin/uci get other.main.value`).trim();assert.equal(evidence.save.otherCommitted,'before');
 evidence.save.changes=await p.evaluate(async()=>{const r=await L.require('rpc');return r.declare({object:'uci',method:'changes',expect:{changes:{}}})();});assert.match(JSON.stringify(evidence.save.changes),/staged-other/);assert.equal(evidence.save.session.main.ttl,'75');assert.equal(evidence.save.session.fixture.name,'browser.example');
 evidence.save.plan=ssh(`chroot ${root} /usr/bin/lua /usr/share/homestun/config-cli.lua plan`);assert.match(evidence.save.plan,/75/);
 evidence.save.dom=await p.locator('#view').innerText();
 await p.screenshot({path:artifact+'luci-browser-save.png',fullPage:true});
 ssh(`chroot ${root} /sbin/uci set homestun.main.ttl=broken; chroot ${root} /sbin/uci set homestun.fixture.name=INVALID; chroot ${root} /sbin/uci commit homestun`);
 await load();await field('main','enabled').uncheck();await p.locator('.cbi-button-save').click();await p.waitForFunction(()=>v.statusNode.textContent.startsWith('Configuration: disabled'));await p.waitForTimeout(500);
 evidence.disabled={committed:ssh(`chroot ${root} /sbin/uci export homestun`),status:await p.evaluate(()=>v.statusNode.textContent)};assert.match(evidence.disabled.committed,/option enabled '0'/);assert.match(evidence.disabled.committed,/option ttl 'broken'/);assert.match(evidence.disabled.committed,/option name 'INVALID'/);
 evidence.disabled.session=await p.evaluate(async()=>{const r=await L.require('rpc');return r.declare({object:'uci',method:'get',params:['config'],expect:{values:{}}})('homestun');});assert.equal(evidence.disabled.session.main.enabled,'0');assert.equal(evidence.disabled.session.main.ttl,'broken');
 evidence.disabled.plan=ssh(`chroot ${root} /usr/bin/lua /usr/share/homestun/config-cli.lua plan`);
 evidence.disabled.dom=await p.locator('#view').innerText();evidence.disabled.inputs=await p.locator('input').evaluateAll(es=>es.map(e=>({id:e.id,value:e.value,checked:e.checked})));
 await p.screenshot({path:artifact+'luci-browser-disabled.png',fullPage:true});
 assert(!evidence.requests.some(q=>['apply','reload','start','restart'].includes(q.method)));assert(evidence.requests.filter(q=>q.method==='commit').every(q=>q.args.config==='homestun'));
 evidence.runtime=ssh(`test ! -e ${root}/var/run/homestun; test ! -e ${root}/tmp/homestun; printf 'No lease runtime created\n'; for p in /proc/[0-9]*; do if [ "$(readlink "$p/root")" = '${root}' ]; then tr '\\0' ' ' < "$p/cmdline"; printf '\\n'; fi; done`);
 assert(!/natmap|homestun-supervisor/.test(evidence.runtime));assert.deepEqual(evidence.errors,[]);evidence.result='PASS';console.log('PASS actual Chrome DOM Save and damaged-disable; scoped commit; other pending preserved; no activation');
 }catch(e){evidence.result='FAIL';evidence.failure=e.stack;throw e;}finally{fs.writeFileSync(artifact+'luci-browser-acceptance.json',JSON.stringify(evidence,null,2));await b.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
