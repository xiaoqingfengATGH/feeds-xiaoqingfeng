/* Browser acceptance only: installed device modules + fixed private native journal. */
const assert=require('node:assert/strict');
module.exports=async({page,load,persist,dirty,privateCall,ssh,browser})=>{
 const config=()=>privateCall('status').saved_config;
 const field=k=>page.locator('input[id$=".'+k+'"],select[id$=".'+k+'"]');
 const edit=async(name)=>{await page.locator('.cbi-section-table-row').filter({hasText:name}).getByRole('button',{name:'Edit',exact:true}).click();await page.locator('.modal').waitFor();};
 const tab=async(name)=>page.locator('.modal li[data-tab="'+name+'"] a').click();
 const modalSave=async()=>{await page.locator('.modal').getByRole('button',{name:'Save',exact:true}).click();await page.locator('.modal').waitFor({state:'hidden'});};
 const reset=async(cancel=false)=>{await page.locator('#hp-reset').click();if(cancel)await page.locator('.modal').getByRole('button',{name:'取消',exact:true}).click();else{await Promise.all([page.waitForEvent('load'),page.locator('.modal').getByRole('button',{name:'重新载入',exact:true}).click()]);await page.locator('#hp-save').waitFor();}};
 const inv=privateCall('network_inventory');console.log('ACTUAL_NETWORK_INVENTORY',JSON.stringify(inv));
 const lan=inv.networks.find(n=>n.up && ['ipv4','ipv6'].every(f=>n.addresses.some(a=>a.family===f)));assert(lan,'real dualstack network required');
 const v4=lan.addresses.find(a=>a.family==='ipv4').address,v6=lan.addresses.find(a=>a.family==='ipv6').address;
 const oldServices=config().services;
 await load('entry');await field('family').selectOption('dual');
 for(const [f,a] of [['ipv4',v4],['ipv6',v6]]){await field(f+'_network').selectOption(lan.network);const options=await field(f+'_address').locator('option').evaluateAll(ns=>ns.map(n=>n.value));assert(options.includes(a));await field(f+'_address').selectOption(a);}
 const cert=privateCall('certificates').certificates[0].certificate_ref;await field('default_certificate_ref').selectOption(cert);
 await field('mode').selectOption('temporary');await field('temporary_minutes').fill('45');
 const dual=await persist();assert.deepEqual(dual.saved_config.services,oldServices,'entry Save preserves every service field');assert.equal(dual.saved_config.access_profile.listeners.length,2);
 for(const [f,a] of [['ipv4',v4],['ipv6',v6]])assert(dual.saved_config.access_profile.listeners.some(l=>l.family===f&&l.network===lan.network&&(f==='ipv6'?new URL('http://['+l.address+']/').hostname===new URL('http://['+a+']/').hostname:l.address===a)),'canonical listener preserves semantic address identity for '+f);
 assert.equal(dual.saved_config.publication_policy.temporary_duration,2700);console.log('PASS actual LAN dualstack select/save/reload and entry-to-service preservation');
 const entrySnapshot=structuredClone(dual.saved_config);await load('services');await edit('P2 https_proxy');await tab('general');await field('name').fill('P2 https edited');await modalSave();await persist();
 const changed=config();for(const k of ['access_profile','publication_policy','default_certificate_ref'])assert.deepEqual(changed[k],entrySnapshot[k],k+' preserved by services');
 await load('entry');assert.equal(await field('family').inputValue(),'dual');assert.equal(await field('temporary_minutes').inputValue(),'45');console.log('PASS services-to-entry default certificate/policy/both listeners preserved across page refresh');
 // A deliberate network change clears the old bind; disappeared saved binds are a separate case.
 const unavailable=inv.networks.find(n=>!n.up&&!n.addresses.length);assert(unavailable,'real unavailable network required');
 for(const f of ['ipv4','ipv6']){const expected=inv.networks.filter(n=>n.up===true&&n.addresses.some(a=>a.family===f&&a.address!=='0.0.0.0'&&a.address!=='::')).map(n=>n.network);assert.deepEqual(await field(f+'_network').locator('option').evaluateAll(ns=>ns.filter(n=>!n.disabled).map(n=>n.value)),expected,'candidate set follows capability not interface names');}
 console.log('PASS only family-capable ready networks are selectable; empty docker/loopback excluded');
 // Deliberate stale value injection tests validation; it is not a user-selectable candidate.
 const unavailableBefore=privateCall('status');await field('ipv4_network').evaluate((e,value)=>{e.add(new Option('injected stale binding',value));e.value=value;e.dispatchEvent(new Event('change',{bubbles:true}));},unavailable.network);
 assert.equal(await field('ipv4_address').inputValue(),'');assert.deepEqual(await field('ipv4_address').locator('option').evaluateAll(ns=>ns.map(n=>({value:n.value,disabled:n.disabled}))),[{value:'',disabled:true}]);assert((await field('ipv4_address').locator('option:checked').innerText()).includes('无可用地址'));
 await page.locator('#hp-save').click();await page.waitForFunction(()=>!document.querySelector('#hp-save').disabled&&document.querySelector('#hp-message').textContent!=='保存只更新本应用配置，不启动发布');
 assert.equal(privateCall('status').saved_revision,unavailableBefore.saved_revision);assert.deepEqual(config(),unavailableBefore.saved_config);assert.equal(await dirty(),true);
 const validationModal=page.locator('.modal');console.log('EMPTY_NETWORK_VALIDATION',await validationModal.innerText());assert.match(await validationModal.innerText(),/IPv4 (网络|地址)/);await validationModal.getByRole('button',{name:'Dismiss',exact:true}).click();
 await reset();assert.equal(await field('ipv4_network').inputValue(),lan.network);console.log('PASS unavailable network retains explicit address, rejects Save without revision/write/wildcard, reset restores');
 // Real second page commits while first page retains an older revision.
 const beforeConflict=privateCall('status');await field('port').fill('25446');
 const second=await browser.newPage();try{await second.goto('http://127.0.0.1:18997/entry');await second.waitForFunction(()=>result.loader==='PASS');await second.locator('input[id$=".port"]').fill('25447');await Promise.all([second.waitForEvent('load'),second.locator('#hp-save').click()]);await second.locator('#hp-save').waitFor();}finally{await second.close();}
 const concurrent=privateCall('status');assert.equal(concurrent.saved_revision,beforeConflict.saved_revision+1);
 await page.locator('#hp-save').click();await page.waitForFunction(()=>document.querySelector('#hp-save').disabled && document.querySelector('#hp-message').textContent.includes('其他页面'));
 assert.equal(privateCall('status').saved_revision,concurrent.saved_revision);assert.equal(await field('port').inputValue(),'25446');assert.equal(await dirty(),true);
 await reset(true);assert.equal(await field('port').inputValue(),'25446');await reset();assert.equal(await field('port').inputValue(),'25447');assert.equal(await dirty(),false);assert.equal(await page.locator('#hp-save').isEnabled(),true);console.log('PASS real two-page stale revision refusal; draft retained; reset cancel and confirm recover latest revision');
 // Cancel an existing typed row, then commit type changes with stale hidden controls retained.
 await load('services');const beforeCancel=config();await edit('P2 https edited');await tab('general');await field('type').selectOption('tcp_forward');await tab('access');await field('listen_port').fill('27443');await page.locator('.modal').getByRole('button',{name:'Dismiss',exact:true}).click();assert.equal(await dirty(),false);assert.deepEqual(config(),beforeCancel);
 await edit('P2 https edited');await tab('general');assert.equal(await field('type').inputValue(),'https_proxy');await field('type').selectOption('tcp_forward');await tab('access');await field('listen_port').fill('27443');await modalSave();let typed=(await persist()).saved_config.services.find(s=>s.name==='P2 https edited');assert.equal(typed.type,'tcp_forward');assert.equal(typed.listen_port,27443);for(const k of ['hostname','certificate_mode','certificate_ref','upstream_scheme','upstream_tls'])assert.equal(typed[k],undefined,k+' must not serialize on TCP');
 await edit('P2 https edited');await tab('general');await field('type').selectOption('https_proxy');await tab('access');await field('hostname').fill('p2-https.example.test');await field('certificate_mode').selectOption('inherit');await tab('backend');await field('upstream_scheme').selectOption('http');await modalSave();typed=(await persist()).saved_config.services.find(s=>s.name==='P2 https edited');assert.equal(typed.type,'https_proxy');assert.equal(typed.certificate_mode,'inherit');for(const k of ['listen_port','certificate_ref','upstream_tls'])assert.equal(typed[k],undefined);console.log('PASS existing HTTPS-to-TCP cancel clean; Save strips hidden HTTPS fields; reverse switch strips port/override and preserves inherit');
 await load('certificates');await page.locator('.cbi-section-table-row').first().waitFor();
 const table=await page.locator('.cbi-section-table').evaluate(el=>({headers:[...el.querySelectorAll('.tr.cbi-section-table-titles > .th')].map(n=>n.textContent.trim()),rows:[...el.querySelectorAll('.cbi-section-table-row')].map(r=>({cells:[...r.children].map(c=>c.textContent.trim()),bounds:[...r.children].map(c=>({left:c.getBoundingClientRect().left,right:c.getBoundingClientRect().right}))})),actions:el.querySelectorAll('.cbi-section-actions').length,controls:el.querySelectorAll('input,select,button').length}));
 console.log('CERTIFICATE_TABLE',JSON.stringify(table));assert.equal(table.headers.length,6);assert(table.headers.every(Boolean));assert.equal(table.actions,0);assert.equal(table.controls,0);assert.equal(table.rows.length,privateCall('certificates').certificates.length);for(const r of table.rows)assert.equal(r.cells.length,6);
 const used=table.rows.find(r=>r.cells.join(' ').includes('入口默认'));assert(used);assert(used.cells[5].includes('p2-https.example.test'));assert(!used.cells[5].includes('p2-tls.example.test'));console.log('PASS readonly certificate actual inventory count/six headers/six cells/no action column/default+inherit usage excludes passthrough');
 for(const route of ['entry','services','certificates']){await page.setViewportSize({width:375,height:812});await load(route);await page.waitForTimeout(300);const size=await page.evaluate(()=>({viewport:innerWidth,body:document.body.scrollWidth,html:document.documentElement.scrollWidth,overflow:[...document.querySelectorAll('*')].filter(n=>n.getBoundingClientRect().right>innerWidth+1).slice(0,12).map(n=>({tag:n.tagName,cls:n.className,right:n.getBoundingClientRect().right}))}));console.log('NARROW',route,JSON.stringify(size));assert(size.html<=size.viewport+1,route+' horizontal page overflow');}
 // Keep one interception registered across fixture transitions. Repeated unrouteAll/route
 // can leave a new document's RPC un-intercepted; lifecycle-only waits reproduced it.
 let fixture=null;
 const rpcPattern=url=>new URL(url).pathname==='/ubus';
 await page.route(rpcPattern,async route=>{
  const active=fixture;if(!active)return route.continue();
  const request=route.request().postDataJSON(),queries=Array.isArray(request)?request:[request];
  const response=await route.fetch(),raw=await response.json();
  for(const item of (Array.isArray(raw)?raw:[raw])){
   const q=queries.find(q=>q.id===item.id);if(!q||!q.params||q.params[1]!=='homepublish')continue;
   const method=q.params[2],body=item.result&&item.result[1];assert(body,'fixture requires successful '+method+' response');
   if(method==='network_inventory'){
    assert(Array.isArray(body.networks));
    if(active.kind==='second')body.networks.push({network:'fixture_second',device:'fixture0',up:true,zones:['fixture_zone'],addresses:[{family:'ipv4',address:'192.0.2.9',prefix:24}]});
    else for(const n of body.networks)n.addresses=[];
   }
   if(method==='status'&&active.kind==='empty')delete body.saved_config;
   active.methods.push(method);
   if(method==='status')active.savedConfigPresent=Object.hasOwn(body,'saved_config');
   if(method==='network_inventory')active.addressCount=body.networks.reduce((n,x)=>n+x.addresses.length,0);
  }
  await route.fulfill({response,json:raw});active.completed++;
 });
 const fixtureLoad=async kind=>{
  fixture={kind,methods:[],completed:0};const active=fixture;
  const ready=await load('entry');
  assert.deepEqual(active.methods.slice().sort(),['certificates','network_inventory','status'],'every new-view editor RPC must traverse the current fixture');
  assert(active.completed>0,'fixture response must complete before view readiness');
  assert.equal(active.savedConfigPresent,kind!=='empty');if(kind!=='second')assert.equal(active.addressCount,0);
  console.log('FIXTURE_READY',JSON.stringify({...active,viewId:ready.viewId}));return ready;
 };
 // A second network is a process-local inventory fixture, not another actual device interface.
 await fixtureLoad('second');await field('ipv4_network').locator('option[value="fixture_second"]').waitFor({state:'attached'});assert.equal(await field('ipv6_network').locator('option[value="fixture_second"]').count(),0);await field('ipv4_network').selectOption('fixture_second');assert.equal(await field('ipv4_address').inputValue(),'192.0.2.9');assert.deepEqual(await field('ipv4_address').locator('option').evaluateAll(ns=>ns.map(n=>n.value)),['192.0.2.9']);assert.match(await page.locator('[id="cbid.json.cfg_listener.ipv4_zone"]').evaluate(n=>n.parentElement.textContent),/fixture_zone/);await field('ipv4_network').selectOption(lan.network);assert.equal(await field('ipv4_address').inputValue(),v4);fixture=null;console.log('PASS process-local second network: family-filtered options, native network change replaces address and zone, return LAN restores address; not actual second interface');
 // Inventory loss of a saved original binding is diagnostic, never a normal selectable candidate.
 await fixtureLoad('saved-loss');await field('ipv4_address').waitFor({state:'attached'});for(const f of ['ipv4','ipv6']){const options=await field(f+'_address').locator('option').evaluateAll(ns=>ns.map(n=>({value:n.value,text:n.text,disabled:n.disabled})));assert.equal(options.length,1);assert(options[0].value&&options[0].disabled&&options[0].text.includes('已不可用'));const nets=await field(f+'_network').locator('option').evaluateAll(ns=>ns.map(n=>({value:n.value,text:n.text,disabled:n.disabled})));assert.equal(nets.length,1);assert(nets[0].disabled&&nets[0].text.includes('已不可用'));}console.log('PASS disappeared saved original network/address bindings visibly retained disabled, no wildcard or normal candidate');fixture=null;
 // Process-local RPC response fixture only: all candidates disappear on an untouched editor.
 await fixtureLoad('empty');await field('ipv4_network').waitFor({state:'attached'});for(const f of ['ipv4','ipv6']){for(const suffix of ['network','address']){const opts=await field(f+'_'+suffix).locator('option').evaluateAll(ns=>ns.map(n=>({value:n.value,text:n.text,disabled:n.disabled})));assert.equal(opts.length,1);assert.equal(opts[0].value,'');assert(opts[0].disabled&&opts[0].text.includes('无可用'));}}
 const emptyBefore=privateCall('status');await page.locator('#hp-save').click();await page.locator('.modal').waitFor();assert.match(await page.locator('.modal').innerText(),/IPv4 网络/);assert.equal(privateCall('status').saved_revision,emptyBefore.saved_revision);assert.deepEqual(config(),emptyBefore.saved_config);await page.locator('.modal').getByRole('button',{name:'Dismiss',exact:true}).click();fixture=null;console.log('PASS process-local empty inventory/no saved config: disabled network/address placeholders and Save blocked without journal write');
 await page.setViewportSize({width:1280,height:900});console.log('PASS 375px entry/services/certificates page has no horizontal overflow');
};
