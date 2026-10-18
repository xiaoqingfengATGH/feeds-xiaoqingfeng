/* Real device resources and official LuCI view lifecycle; no local source execution. */
const {chromium}=require(process.env.HP_PLAYWRIGHT || 'D:/DevPortal/homelede/artifacts/palette-switch-cache/test-deps/node_modules/playwright');
const http=require('node:http'),assert=require('node:assert/strict'),{execFileSync}=require('node:child_process');
const ssh=(cmd,input)=>execFileSync('ssh',['-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','-o','StrictHostKeyChecking=yes','root@192.168.1.2',cmd],{encoding:'utf8',timeout:45000,input});
const privateCall=(m,a={})=>{assert(['status','certificates','network_inventory','migration_preview','validate','save'].includes(m));return JSON.parse(ssh(`lua /tmp/homepublish-p2-ui/device-tcp-p2-ui.lua ${m}`,JSON.stringify(a)));};
const call=(o,m,a={})=>{const out=ssh(`ubus call ${o} ${m} '${JSON.stringify(a)}'`);return out.trim()?JSON.parse(out):null;};
const fs=require('node:fs'),path=require('node:path');
const staticRoot=path.resolve(__dirname,'../htdocs/luci-static/resources/view/homepublish');
const installedBaseline=new Map();
const restore=()=>{for(const [f,bytes] of installedBaseline)assert.equal(ssh(`cat /www/luci-static/resources/view/homepublish/${f}.js`),bytes,`installed ${f} changed during probe; no restore attempted`);return 'INSTALLED_FOUR_UNCHANGED_NO_WRITES';};
(async()=>{let server,browser,sid,viewSequence=0;try{
 require('./p2-lua-support.cjs').prepare(ssh);
 for(const f of ['product','services','entry','certificates']){const installed=ssh(`cat /www/luci-static/resources/view/homepublish/${f}.js`);installedBaseline.set(f,installed);assert.equal(installed,fs.readFileSync(path.join(staticRoot,f+'.js'),'utf8'),`installed ${f} differs from worktree; deploy via owner before acceptance`);}
 sid=call('session','create',{timeout:300}).ubus_rpc_session;
 call('session','grant',{ubus_rpc_session:sid,scope:'ubus',objects:['status','certificates','validate','save','network_inventory'].map(m=>['homepublish',m]).concat([['uci','get'],['uci','changes']])});
 call('session','grant',{ubus_rpc_session:sid,scope:'uci',objects:[['luci','read'],['network','read'],['firewall','read']]});
 assert.equal(call('session','access',{ubus_rpc_session:sid,scope:'ubus',object:'uci',function:'commit'}).access,false);
 server=http.createServer(async(req,res)=>{try{
 if(/^\/(entry|services|certificates)$/.test(req.url)){res.setHeader('Content-Type','text/html');res.end(`<!doctype html><html><head><link rel="stylesheet" href="/luci-static/bootstrap/cascade.css"></head><body><div id="maincontent"><div id="view"></div></div><script>window._=s=>s;window.cbi_init=()=>{};</script><script src="/luci-static/resources/cbi.js"></script><script src="/luci-static/resources/luci.js"></script><script>window.L=Object.create(LuCI.prototype);Object.assign(L.env,{base_url:'/luci-static/resources',resource:'/luci-static/resources',scriptname:'/cgi-bin/luci',cgi_base:'/cgi-bin',requestpath:[],documentroot:'/www',ubuspath:'/ubus',sessionid:'${sid}',apply_display:0});L.loaded=true;window.result={viewId:${++viewSequence},route:'${req.url.slice(1)}'};L.probeRPCBaseURL().then(()=>L.require('ui')).then(()=>L.require('view')).then(view=>{const init=view.prototype.__init__;view.prototype.__init__=function(){const ready=init.apply(this,arguments);window.hpViewReady=ready;return ready;};return L.require('view.homepublish.${req.url.slice(1)}');}).then(()=>window.hpViewReady).then(()=>{result.loader='PASS';}).catch(e=>{result.loader='FAIL';result.error=e.message;});</script></body></html>`);return;}
 let chunks=[];for await(const c of req)chunks.push(c);const body=Buffer.concat(chunks);
 if(req.method==='POST' && req.url.startsWith('/ubus')){const raw=JSON.parse(body),items=Array.isArray(raw)?raw:[raw];if(items.some(q=>q.params && q.params[1]==='homepublish')){const replies=[];for(const q of items){if(q.params[1]==='homepublish')replies.push({jsonrpc:'2.0',id:q.id,result:[0,privateCall(q.params[2],q.params[3])]});else{const upstream=await fetch('http://192.168.1.2'+req.url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(q)});replies.push(await upstream.json());}}res.setHeader('Content-Type','application/json');res.end(JSON.stringify(Array.isArray(raw)?replies:replies[0]));return;}}
 const r=await fetch('http://192.168.1.2'+req.url,{method:req.method,headers:{'Content-Type':'application/json'},...(req.method==='POST'?{body}:{})});res.statusCode=r.status;res.setHeader('Content-Type',r.headers.get('content-type')||'text/javascript');res.end(Buffer.from(await r.arrayBuffer()));
 }catch(e){res.statusCode=500;console.error('PROXY',req.url,e.message);res.end(e.message);}});await new Promise(r=>server.listen(18997,'127.0.0.1',r));
 browser=await chromium.launch({channel:'chrome',headless:true});const pageErrors=[];const page=await browser.newPage();const rpcTrace=[];page.on('request',r=>{if(r.method()==='POST')rpcTrace.push({url:r.url(),methods:JSON.parse(r.postData()||'null')});});page.rpcTrace=rpcTrace;page.on('pageerror',e=>{pageErrors.push(e.message);console.error('PAGEERROR',e.stack);});page.on('console',m=>{if(m.type()==='error')console.error('CONSOLE',m.text());});
 const load=async(route)=>{const before=await page.evaluate(()=>window.result&&result.viewId);await page.goto('http://127.0.0.1:18997/'+route);await page.waitForFunction(old=>window.result&&result.viewId!==old&&result.loader,before);const ready=await page.evaluate(()=>result);assert.equal(ready.loader,'PASS',ready.error);assert.equal(ready.route,route);assert.notEqual(ready.viewId,before,'load must await a new document, not an old attached editor');assert.equal(await page.locator('#view > div .cbi-map, #view > .cbi-map').count(),1,'official lifecycle renders exactly one map');console.log('VIEW_READY',JSON.stringify(ready));return ready;};
 await load('entry');
 await page.waitForTimeout(2000);console.log('LOADED',await page.locator('body').innerText());if(privateCall('status').saved_config.schema_version===1){
 const rev=privateCall('status').saved_revision;
 await page.locator('#hp-migration-preview').click();await page.waitForFunction(()=>!document.querySelector('#hp-migration-confirm').disabled);
 assert.equal(privateCall('status').saved_revision,rev);
 await page.locator('#hp-migration-confirm').click();await page.getByRole('button',{name:'取消',exact:true}).click();assert.equal(privateCall('status').saved_revision,rev);
 await page.locator('#hp-migration-confirm').click();await page.getByRole('button',{name:'确认保存',exact:true}).click();await page.waitForTimeout(2500);console.log('MIGRATION RESULT',await page.locator('body').innerText());await page.locator('#hp-save').waitFor();assert.equal(privateCall('status').saved_config.schema_version,2);console.log('PASS explicit migration preview/cancel/confirm/readback');
 }
 await page.locator('#hp-save').waitFor();assert.equal(await page.locator('[data-field$=".external_port"]').count(),0);
 console.log('ENTRY DOM',await page.locator('input,select,button').evaluateAll(ns=>ns.map(n=>({id:n.id,text:n.textContent,value:n.value}))).then(JSON.stringify));
 const before=privateCall('status'),port=before.saved_config.access_profile.listeners[0].port===25443?25444:25443;await page.locator('input[id$=".port"]').fill(String(port));await Promise.all([page.waitForEvent('load'),page.locator('#hp-save').click()]);await page.locator('#hp-save').waitFor();
 const after=privateCall('status');assert.equal(after.saved_revision,before.saved_revision+1,await page.locator('body').innerText());assert.equal(after.saved_config.access_profile.listeners[0].port,port);assert.equal(after.desired_state.state,'disabled');assert.equal(after.active_revision,undefined);assert.equal(await page.locator('input[id$=".port"]').inputValue(),String(port));console.log('PASS entry native form/save/private Lua journal/readback/reload, no activation');
 const dirty=()=>page.evaluate(()=>{const e=new Event('beforeunload',{cancelable:true});window.dispatchEvent(e);return e.defaultPrevented;});
 const add=async(type,name,port,hostname)=>{
  await page.getByRole('button',{name:'Add',exact:true}).click();const modal=page.locator('.modal');await modal.waitFor();
  const field=k=>modal.locator('input[id$=".'+k+'"],select[id$=".'+k+'"]');
  await modal.locator('li[data-tab="general"] a').click();await field('type').selectOption(type);await field('name').fill(name);
  if(type==='tcp_forward'||hostname){await modal.locator('li[data-tab="access"] a').click();if(type==='tcp_forward')await field('listen_port').fill(String(port));else await field('hostname').fill(hostname);}
  if(type==='https_proxy') {await field('certificate_mode').selectOption('override');const ref=await field('certificate_ref').locator('option').evaluateAll(ns=>ns.map(n=>n.value).find(Boolean));assert(ref,'device certificate inventory required');await field('certificate_ref').selectOption(ref);}
  await modal.locator('li[data-tab="backend"] a').click();await field('backend_host').fill('192.168.1.10');await field('backend_port').fill('8080');
  await modal.locator('li[data-tab="advanced"] a').click();await modal.locator('.cbi-dynlist input').fill('192.168.1.0/24');await modal.locator('.cbi-dynlist input').press('Enter');
  await modal.getByRole('button',{name:'Save',exact:true}).click();await modal.waitFor({state:'hidden',timeout:3000});
 };
 const persist=async()=>{const rev=privateCall('status').saved_revision;await Promise.all([page.waitForEvent('load',{timeout:8000}),page.locator('#hp-save').click()]);await page.locator('#hp-save').waitFor();const s=privateCall('status');assert.equal(s.saved_revision,rev+1);assert.equal(s.desired_state.state,'disabled');assert.equal(s.active_revision,undefined);return s;};
 await load('services');await page.locator('#hp-save').waitFor();
 await add('tcp_forward','P2 TCP 中文',26443);if(['dirty','extended'].includes(process.env.HP_CASE))assert.equal(await dirty(),true,'global modal Save must protect unsaved draft');
 const first=await persist();assert.equal(first.saved_config.services[0].type,'tcp_forward');assert.equal(first.saved_config.services[0].hostname,undefined);console.log('PASS native TCP popup Save + private journal reload');
 await add('tcp_forward','second',26444);const two=await persist();const retained=two.saved_config.services[1].service_id;
 await page.locator('.cbi-section-table-row').filter({hasText:'P2 TCP 中文'}).getByRole('button',{name:'Delete',exact:true}).click();await persist();
 await add('tcp_forward','third',26445);
 const ids=await page.evaluate(async()=>{const dom=await L.require('dom'),api=await L.require('view.homepublish.product');return api.collectConfig(dom.findClassInstance(document.querySelector('.cbi-map'))).services.map(s=>s.service_id);});
 assert.equal(new Set(ids).size,2,'IDs must not collide after two/add/delete-first/save/reload/add');const three=await persist();assert.equal(three.saved_config.services[0].service_id,retained);console.log('PASS stable IDs add-two/delete-first/save/reload/add');
 if(['dirty','extended'].includes(process.env.HP_CASE)){
  assert.equal(await dirty(),false,'fresh reload clean');
  await page.getByRole('button',{name:'Add',exact:true}).click();await page.locator('.modal').waitFor();await page.locator('.modal input[id$=".name"]').fill('cancelled');await page.locator('.modal').getByRole('button',{name:'Dismiss',exact:true}).click();assert.equal(await dirty(),false,'cancelled modal must remain clean');
  await page.locator('.cbi-section-table-row').filter({hasText:'third'}).getByRole('button',{name:'Delete',exact:true}).click();assert.equal(await dirty(),true,'delete must protect draft');await persist();console.log('PASS dirty modal Save/delete and clean cancellation');
 }
 for(const [type,hostname] of [['ssh',null],['tls_passthrough','p2-tls.example.test'],['https_proxy','p2-https.example.test']]){
  await add(type,'P2 '+type,null,hostname);const saved=await persist(),svc=saved.saved_config.services.at(-1);assert.equal(svc.type,type);assert.equal(svc.hostname,hostname || undefined);assert.equal(svc.listen_port,undefined);if(type!=='https_proxy'){assert.equal(svc.certificate_ref,undefined);assert.equal(svc.upstream_scheme,undefined);}else{assert.equal(svc.certificate_mode,'override');assert(svc.certificate_ref);}console.log('PASS native '+type+' popup/private Save/reload/type-specific serialization');
 }
 if(process.env.HP_CASE==='extended')await require('./tcp-ingress-device-extended.cjs')({page,load,persist,dirty,privateCall,ssh,browser});
 assert.deepEqual(pageErrors,[],'real browser has no uncaught widget errors');console.log('PASS no uncaught real-browser widget errors');
 console.log(JSON.stringify({deviceLoader:'PASS',entryPersistence:'PASS',externalPortRemoved:'PASS',fourTypes:'PASS',extended:process.env.HP_CASE==='extended'?'PASS':'NOT_RUN'}));
 }finally{try{if(browser)await browser.close();if(server)await new Promise(r=>server.close(r));if(sid)call('session','destroy',{ubus_rpc_session:sid});}finally{console.log(restore());require('./p2-lua-support.cjs').verify(ssh);}}})().catch(e=>{console.error(e);process.exitCode=1;});
