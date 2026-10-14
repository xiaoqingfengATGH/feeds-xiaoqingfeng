const {chromium}=require(process.env.HP_PLAYWRIGHT || 'D:/DevPortal/homelede/artifacts/palette-switch-cache/test-deps/node_modules/playwright');const http=require('node:http'),assert=require('node:assert/strict'),{execFileSync,spawn}=require('node:child_process');
const ssh=cmd=>execFileSync('ssh',['-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','root@127.0.0.1',cmd],{encoding:'utf8',timeout:45000});
const call=(o,m,a={})=>{const out=ssh(`ubus call ${o} ${m} '${JSON.stringify(a).replace(/'/g,"'\\''")}'`);return out.trim()?JSON.parse(out):null;};
const VIEW='view.homepublish.services';
(async()=>{let server,browser,sid;try{
/* ubus 会话：ACL 授权 + 断言 uci.commit 被拒 */
sid=call('session','create',{timeout:300}).ubus_rpc_session;call('session','grant',{ubus_rpc_session:sid,scope:'ubus',objects:[['status','certificates','validate','save','start','apply','stop'].map(m=>['homepublish',m]),['uci','get']].flat()});assert.equal(call('session','access',{ubus_rpc_session:sid,scope:'ubus',object:'uci',function:'commit'}).access,false);
/* 本地 HTTP 代理：静态资源转发到设备 1081 LuCI，页面注入会话加载 view 模块 */
server=http.createServer(async(req,res)=>{try{const viewFor=url=>url==='/overview'?'view.homepublish.overview':url==='/entry'?'view.homepublish.entry':'view.homepublish.services';if(req.url==='/' || req.url==='/overview' || req.url==='/entry'){res.setHeader('Content-Type','text/html');res.end(`<!doctype html><html><body><div id="maincontent"><div id="view"></div></div><script>window._=s=>s;window.cbi_init=()=>{};</script><script src="/luci-static/resources/cbi.js"></script><script src="/luci-static/resources/luci.js"></script><script>window.L=Object.create(LuCI.prototype);Object.assign(L.env,{base_url:'/luci-static/resources',resource:'/luci-static/resources',scriptname:'/cgi-bin/luci',cgi_base:'/cgi-bin',requestpath:[],documentroot:'/www',ubuspath:'/ubus',sessionid:'${sid}',apply_display:0});L.loaded=true;window.result={};L.probeRPCBaseURL().then(()=>L.require('ui')).then(()=>{const u=location.pathname;return L.require(u==='/overview'?'view.homepublish.overview':u==='/entry'?'view.homepublish.entry':'view.homepublish.services');}).then(v=>{return v.load().then(d=>v.render(d));}).then(n=>{const v=document.querySelector('#view');v.replaceChildren(n);L.Poll.start();result.loader='PASS';}).catch(e=>{result.loader='FAIL';result.error=e.message;});</script></body></html>`);return;}
let chunks=[];for await(const chunk of req)chunks.push(chunk);const data=Buffer.concat(chunks);const upstream=await fetch('http://127.0.0.1:1081'+req.url,{method:req.method,headers:{'Content-Type':'application/json'},...(req.method==='POST'?{body:data}: {})});res.statusCode=upstream.status;res.setHeader('Content-Type',upstream.headers.get('content-type')||'text/javascript');res.end(Buffer.from(await upstream.arrayBuffer()));}catch(e){res.statusCode=500;res.end(e.message);}});await new Promise(r=>server.listen(18995,'127.0.0.1',r));
browser=await chromium.launch({channel:'chrome',headless:true});const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto('http://127.0.0.1:18995/');await page.waitForFunction(()=>window.result.loader,{timeout:20000});assert.equal(await page.evaluate(()=>result.loader),'PASS',await page.evaluate(()=>result.error));
/* r9 form.Map：等 GridSection 表格行出现 */
await page.waitForSelector('.cbi-tblsection table tr.cbi-section-table-row',{timeout:20000});
const state=()=>page.evaluate(()=>L.require('view.homepublish.product').then(a=>a.status()));
/* 1. entry 页配置监听端口与默认证书（NamedSection） */
await page.goto('http://127.0.0.1:18995/entry');await page.waitForSelector('[data-field$=".internal_port"] input',{timeout:20000});
await page.locator('[data-field$=".internal_port"] input').first().fill('49284');
await page.locator('[data-field$=".external_port"] input').first().fill('49284');
await page.locator('[data-field$=".default_certificate_ref"] select').first().selectOption('acme:fixture_rsa');
await page.locator('#hp-save').click();await page.waitForFunction(()=>document.querySelector('#hp-message')&&document.querySelector('#hp-message').textContent.includes('已保存 revision'),null,{timeout:15000});
let s=await state();assert.equal(s.saved_revision>=1,true);assert.equal(s.active_revision,undefined,'save must never start');
/* 2. services 页 GridSection modal 新增两服务（真 LuCI form 表单填写 → Save pending 不启动） */
await page.goto('http://127.0.0.1:18995/');await page.waitForSelector('.cbi-tblsection-create .cbi-button-add',{timeout:20000});
async function addService(name,hostname,backendPort,ranges){await page.locator('.cbi-tblsection-create .cbi-button-add').click();await page.waitForSelector('#modal_overlay .cbi-modal');const modal=page.locator('#modal_overlay .cbi-modal');await modal.locator('[data-field$=".name"] input').fill(name);await modal.locator('[data-field$=".hostname"] input').fill(hostname);await modal.locator('[data-field$=".backend_url"] input').fill('http://127.0.0.1:'+backendPort);await modal.locator('[data-field$=".allowed_ranges"] input').fill(ranges);await modal.locator('[data-field$=".certificate_ref"] select').selectOption({label:'继承入口默认'});await modal.locator('.cbi-button-positive').click();await page.waitForFunction(()=>!document.body.classList.contains('modal-overlay-active'),null,{timeout:15000});}
await addService('共享 A','a.fixture.home',49285,'127.0.0.0/8');
await addService('共享 B','b.fixture.home',49286,'127.0.0.0/8');
await page.locator('#hp-save').click();await page.waitForFunction(()=>document.querySelector('#hp-message')&&document.querySelector('#hp-message').textContent.includes('已保存 revision'),null,{timeout:15000});
s=await state();const revision=s.saved_revision;assert.equal(s.saved_config.services.length,2,'two services saved');assert.equal(s.active_revision,undefined,'save must never start');assert.equal(s.saved_config.access_profile.listeners[0].internal_port,49284,'entry listener persisted');
assert.equal(await page.locator('#hp-start').isDisabled(),false,'start enabled (real capabilities)');
/* 3. Start：确认对话框展示 diff → 真 TLS marker */
await page.locator('#hp-start').click();await page.waitForSelector('#hp-confirm-diff');assert.ok((await page.locator('#hp-confirm-diff').innerText()).length>0);await page.locator('#hp-edit-submit').click();
await page.waitForFunction(()=>document.querySelector('#hp-message')&&document.querySelector('#hp-message').textContent.includes('已开启'),null,{timeout:20000}).catch(async()=>{const msg=await page.locator('#hp-message').innerText();throw new Error('start did not reach running: '+msg)});
s=await state();assert.equal(s.runtime.active_verified,true,'running verified');
const deadline=s.runtime.expires_at,gen=s.runtime.generation;
const marker=(host,cert,expected)=>assert.ok(ssh(`curl -q --noproxy '*' --cacert '${cert}' --resolve ${host}:49284:127.0.0.1 --fail --silent https://${host}:49284/`).includes(expected),host+' marker failed');
marker('a.fixture.home','/etc/acme/*.fixture.home/fullchain.cer','HP_R7_A');marker('b.fixture.home','/etc/acme/*.fixture.home/fullchain.cer','HP_R7_B');
assert.ok(ssh('ubus call service list \'{"name":"homepublish-nginx"}\'').includes('"running": true'),'procd nginx running');
/* 4. 编辑服务 A：改独立 ECC 证书 + 换后端 → Save pending（旧 marker 不变） */
const rowA=page.locator('.cbi-tblsection table tr.cbi-section-table-row').filter({hasText:'a.fixture.home'});
await rowA.locator('.cbi-button-edit').first().click();await page.waitForSelector('#modal_overlay .cbi-modal');const modalA=page.locator('#modal_overlay .cbi-modal');
await modalA.locator('[data-field$=".name"] input').fill('独立 ECC 待应用');
await modalA.locator('[data-field$=".certificate_ref"] select').selectOption('acme:fixture_ecc');
await modalA.locator('[data-field$=".backend_url"] input').fill('http://127.0.0.1:49286');
await modalA.locator('.cbi-button-positive').click();await page.waitForFunction(()=>!document.body.classList.contains('modal-overlay-active'),null,{timeout:15000});
await page.locator('#hp-save').click();await page.waitForFunction(()=>document.querySelector('#hp-message')&&document.querySelector('#hp-message').textContent.includes('已保存 revision'),null,{timeout:15000});
s=await state();assert.equal(s.pending_config.apply_required,true,'pending after edit');assert.equal(s.runtime.generation,gen,'save must not touch runtime');marker('a.fixture.home','/etc/acme/*.fixture.home/fullchain.cer','HP_R7_A','old cert still active before apply');
/* 5. overview 页 Apply：确认对话框含具体差异与原截止 → 整组切换 */
await page.goto('http://127.0.0.1:18995/overview');await page.waitForSelector('#hp-apply',{timeout:20000});await page.locator('#hp-apply').click();
const diff=await page.locator('#hp-confirm-diff').innerText();for(const v of ['名称','后端','证书','继承','acme:fixture_ecc'])assert.ok(diff.includes(v),'diff missing '+v+': '+diff);
assert.ok((await page.locator('dialog').innerText()).includes(String(deadline)),'deadline preserved');
await page.locator('#hp-edit-submit').click();
await page.waitForFunction(()=>document.querySelector('#hp-local')&&document.querySelector('#hp-local').textContent.includes('运行已验证'),null,{timeout:30000});
s=await state();assert.equal(s.active_revision,revision+1,'active advanced');assert.equal(s.runtime.expires_at,deadline,'deadline not extended');assert.notEqual(s.runtime.generation,gen,'new generation');
marker('a.fixture.home','/etc/acme/*.fixture.home_ecc/fullchain.cer','HP_R7_B','A switched to independent ECC + backend B');
marker('b.fixture.home','/etc/acme/*.fixture.home/fullchain.cer','HP_R7_B');
/* 6. 保持连接 + Stop：已建立连接关闭、快照删除、latch */
const holds=['a.fixture.home','b.fixture.home'].map(host=>{const cert=host[0]==='a'?'/etc/acme/*.fixture.home_ecc/fullchain.cer':'/etc/acme/*.fixture.home/fullchain.cer';const p=spawn('ssh',['-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','root@127.0.0.1',`openssl s_client -quiet -verify_return_error -verify_hostname ${host} -CAfile '${cert}' -connect 127.0.0.1:49284 -servername ${host}`]);let err='';p.stderr.on('data',d=>err+=d);p.stdout.resume();const closed=new Promise(r=>p.once('close',code=>r(code)));p.stdin.write(`GET / HTTP/1.1\r\nHost: ${host}\r\n`);return {p,closed,error:()=>err};});
await page.waitForTimeout(1500);for(const h of holds){assert.equal(h.p.exitCode,null);assert.ok(h.error().includes('verify return:1'),h.error());}
await page.locator('#hp-stop').click();await page.locator('#hp-edit-submit').click();
await page.waitForFunction(()=>document.querySelector('#hp-local')&&document.querySelector('#hp-local').textContent.includes('未运行'),null,{timeout:20000});
for(const h of holds){await Promise.race([h.closed,new Promise((_,reject)=>setTimeout(()=>reject(new Error('existing TLS connection did not close')),10000))]);h.p.stdin.end();}
assert.equal(ssh("if curl -q --noproxy '*' --connect-timeout 3 -sk https://127.0.0.1:49284/ >/dev/null; then echo unexpected; else echo refused; fi").trim(),'refused');
s=await state();assert.equal(s.desired_state.state,'disabled');assert.equal(s.runtime.cleanup,'confirmed');assert.equal(ssh('test ! -e /tmp/homepublish-device/runtime && echo absent').trim(),'absent');
assert.deepEqual(errors,[]);
console.log(JSON.stringify({browser:'actual installed r9 form.Map LuCI',entry:'PASS listener+default cert saved',grid:'PASS two services via real modal',start:'PASS two shared wildcard RSA TLS',savePending:'PASS old marker + generation unchanged',apply:'PASS independent ECC + diff + original deadline',stop:'PASS disabled confirmed snapshot absent',diff,deadline,errors}));
}finally{if(browser)await browser.close();if(server)await new Promise(r=>server.close(r));if(sid)ssh(`ubus call session destroy '{"ubus_rpc_session":"${sid}"}'`);}})().catch(e=>{console.error(e);process.exitCode=1;});
