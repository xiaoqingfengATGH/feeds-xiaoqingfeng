/* Real device LuCI loader/form/DOM; stalled fixture RPC, never production writes. */
const fs=require('node:fs'),path=require('node:path');
let code=fs.readFileSync(path.join(__dirname,'upstream-tls-form-probe.cjs'),'utf8');
code=code.replace('if(local){','if(local && !process.env.HP_LOADING_INSTALLED){');
code=code.replace("(async()=>{let browser,server;try{",'let mode="enabled",phase="validate",pending=[],calls=[],payload;\n(async()=>{let browser,server;try{');
const postStart=code.indexOf(" if(req.method==='POST')");
const postEnd=code.indexOf(" const local=",postStart);
code=code.slice(0,postStart)+`
 if(req.method==='POST'){
  let b='';for await(const c of req)b+=c;const raw=JSON.parse(b);
  async function reply(q){const p=q.params||[],m=p[2];let data={};
   if(p[1]==='homepublish'){
    calls.push(m);
    if(m==='status'){data={saved_config:calls.includes('save')?payload:config,saved_revision:phase==='conflict'?3:calls.includes('save')?2:1,desired_state:{state:mode},runtime:{phase:mode==='enabled'?'running':'stopped',active_verified:true,cleanup:'confirmed'}};if(phase==='finalstatus'&&calls.includes('apply')&&calls.filter(x=>x==='status').length===3)data=await new Promise(resolve=>pending.push(resolve));}
    else if(m==='ddns_profiles')data={available:false,profiles:[]};
    else if(m==='certificates')data={certificates:[]};
    else if(m==='validate'){payload=p[3].config;data=await new Promise(resolve=>pending.push(resolve));}
    else if(m==='save')data={saved_revision:2};
    else if(m==='apply'||m==='start')data=await new Promise(resolve=>pending.push(resolve));
    else throw Error('unexpected RPC '+m);
   }else if(m==='get')data={values:{}};else if(m==='changes')data={changes:{}};
   return {jsonrpc:'2.0',id:q.id,result:[0,data]};
  }
  res.setHeader('Content-Type','application/json');return res.end(JSON.stringify(Array.isArray(raw)?await Promise.all(raw.map(reply)):await reply(raw)));
 }
`+code.slice(postEnd);
const start=code.indexOf(" await page.getByRole('button',{name:'Edit'");
const end=code.indexOf(' }finally{',start);
code=code.slice(0,start)+`
 const url=page.url();
 async function until(fn){for(let i=0;i<150;i++){if(fn())return;await new Promise(r=>setTimeout(r,20));}throw Error('fixture wait timed out: '+JSON.stringify(calls));}
 async function fresh(next){mode=next;calls=[];pending=[];await page.goto(url);await page.waitForFunction(()=>window.loaded||window.loadError);assert.equal(await page.evaluate(()=>window.loadError),undefined);}
 async function click(){await page.locator('#hp-save-apply').click();}
 async function loading(text){assert.equal(await page.locator('#hp-message').textContent(),text);assert.equal(await page.locator('#hp-save-apply').isDisabled(),true);assert.equal(await page.locator('#hp-reset').isDisabled(),true);assert.equal(await page.locator('#hp-save-apply').evaluate(n=>n.classList.contains('spinning')),true);}
 async function noDescription(stage){assert.equal(await page.locator('.cbi-map-descr').count(),0,stage+': redundant map description must be absent');assert.equal(await page.getByText('在这里配置要开放到外网的内网服务',{exact:true}).count(),0,stage+': redundant text must be absent');assert.equal(await page.locator('.cbi-map > h2').textContent(),'HomePublish — 服务');}
 await noDescription('initial native render');
 await page.evaluate(async()=>{const dom=await L.require('dom'),map=dom.findClassInstance(document.querySelector('.cbi-map')),save=map.save;window.nativeMapSaveCount=0;map.save=function(){return save.apply(this,arguments).then(result=>{window.nativeMapSaveCount++;return result;});};});
 // Synchronous feedback must precede even map.save()'s first microtask.
 await page.evaluate(()=>{const b=document.querySelector('#hp-save-apply');b.click();window.immediate={text:document.querySelector('#hp-message').textContent,spinning:b.classList.contains('spinning'),disabled:b.disabled};b.click();document.querySelector('#hp-save').click();});
 assert.deepEqual(await page.evaluate(()=>window.immediate),{text:'正在保存并应用…',spinning:true,disabled:true});
 await until(()=>pending.length===1);await loading('正在保存并应用…');
 assert.equal(await page.evaluate(()=>window.nativeMapSaveCount),1,'real native map.save must complete its redraw');await noDescription('after native map.save redraw');
 assert.equal(calls.filter(x=>x==='validate').length,1);
 console.log('spinner-style',await page.locator('#hp-save-apply').evaluate(n=>({background:getComputedStyle(n).backgroundImage,before:getComputedStyle(n,'::before').content,visible:n.getBoundingClientRect().width>0})));
 assert.equal(await page.locator('#hp-message').count(),1);
 assert.equal(payload.services[0].hostname,'same.example.test');assert.equal(payload.services[0].backend.port,8080);
 pending.shift()({valid:true,config:payload});await until(()=>pending.length===1);await loading('正在保存并应用…');
 assert.equal(calls.filter(x=>x==='apply').length,1);
 pending.shift()({error:'certificate expired or DNS SAN mismatch'});
 await page.waitForFunction(()=>document.querySelector('#hp-message').textContent.includes('不覆盖服务域名'));
 assert.equal(await page.locator('#hp-save-apply').evaluate(n=>n.classList.contains('spinning')),false);
 assert.equal(await page.locator('#hp-save-apply').isDisabled(),true); // saved-but-not-applied requires reload
 assert.equal(await page.locator('#hp-reset').isDisabled(),false);
 assert.equal(calls.at(-1),'status','failure must reread final state');
 const writes=calls.filter(x=>x==='save'||x==='apply').length;
 phase='conflict';await page.locator('#hp-recover').click();
 await page.waitForFunction(()=>document.querySelector('#hp-message').textContent.includes('其他页面修改'));
 assert.equal(await page.locator('#hp-save').isDisabled(),true);
 phase='validate';
 const draftBefore=await page.evaluate(async()=>{const dom=await L.require('dom'),api=await L.require('view.homepublish.product'),map=dom.findClassInstance(document.querySelector('.cbi-map'));map.data.data[Object.keys(map.data.data).find(k=>map.data.data[k].service_id==='web')].name='Retained edit';return api.collectConfig(map);});
 await page.locator('#hp-recover').click();
 await page.waitForFunction(()=>!document.querySelector('#hp-save').disabled);
 assert.equal(await page.locator('#hp-save-apply').isDisabled(),false);
 assert.equal(calls.filter(x=>x==='save'||x==='apply').length,writes,'recovery must not write or retry');
 assert.equal(await page.evaluate(async()=>{const dom=await L.require('dom');return dom.findClassInstance(document.querySelector('.cbi-map')).snapshotRevision;}),2);
 assert.ok((await page.locator('#hp-message').textContent()).includes('配置仍已保存'));
 assert.deepEqual(await page.evaluate(async()=>{const dom=await L.require('dom'),api=await L.require('view.homepublish.product');return api.collectConfig(dom.findClassInstance(document.querySelector('.cbi-map')));}),draftBefore);
 await fresh('enabled');phase='finalstatus';await click();await until(()=>pending.length===1);pending.shift()({valid:true,config:payload});await until(()=>pending.length===1);pending.shift()({});await until(()=>pending.length===1);await loading('正在保存并应用…');
 assert.equal(calls.at(-1),'status');pending.shift()({error:'fixture final status failed'});await page.waitForFunction(()=>document.querySelector('#hp-message').textContent.includes('配置已保存'));
 assert.equal(await page.locator('#hp-save-apply').evaluate(n=>n.classList.contains('spinning')),false);phase='validate';
 await fresh('disabled');await click();await until(()=>pending.length===1);await loading('正在保存…');
 pending.shift()({error:'fixture validation failed',error_code:'VALIDATION_ERROR'});
 await page.waitForFunction(()=>document.querySelector('#hp-message').textContent.includes('保存失败'));
 assert.equal(await page.locator('#hp-save-apply').isDisabled(),false);assert.equal(await page.locator('#hp-save-apply').textContent(),'保存并应用');
 await click();await until(()=>pending.length===1);await Promise.all([page.waitForEvent('load'),Promise.resolve().then(()=>pending.shift()({valid:true,config:payload}))]);await page.waitForFunction(()=>window.loaded&&document.querySelector('#hp-save-apply')&&!document.querySelector('#hp-save-apply').disabled);
 assert.equal(calls.includes('apply')||calls.includes('start'),false);assert.equal(calls.filter(x=>x==='save').length,1);
 await fresh('enabled');const beforeCancel=calls.length;
 await page.evaluate(async()=>{const api=await L.require('view.homepublish.product');const config=api.clone((await api.status()).saved_config),active=api.clone(config);active.services[0].name='Previous name';api.actionDialog(document.body,{saved_config:config,active_config:active,runtime:{},saved_revision:1},'apply',()=>{},()=>{});});
 await page.locator('#hp-confirm-scope').waitFor({state:'visible'});assert.ok((await page.locator('#hp-confirm-scope').textContent()).includes('HTTP fixture'));assert.ok((await page.locator('#hp-confirm-diff').textContent()).length>0);
 await page.locator('#hp-edit-cancel').click();assert.equal(await page.locator('.modal').isVisible(),false);
 assert.deepEqual(calls.slice(beforeCancel),['status']);assert.equal(await page.locator('#hp-save-apply').isDisabled(),false);
 assert.deepEqual(errors,[]);
 console.log(JSON.stringify({immediateBeforeMapSave:true,stalledNativeRpcSpinner:true,duplicateBlocked:true,fullLifecycleAwaited:true,payloadPreserved:true,validationRecovery:true,savedApplyFailureRetained:true,disabledOnlySaves:true,productionWrites:false}));
`+code.slice(end);
const Module=require('node:module'),m=new Module(__filename,module);m.filename=__filename;m.paths=module.paths;m._compile(code,__filename);
