/* Native installed LuCI loader/form/UI; fixture RPC rejects all writes. */

/* Explicit device/tooling configuration is mandatory; unavailable dependencies fail. */
require.resolve(require('./env.cjs').playwright);
const fs=require('node:fs'),Module=require('node:module');
let code=fs.readFileSync(require('node:path').join(__dirname,'upstream-tls-form-probe.cjs'),'utf8');
const start=code.indexOf(" await tab('access');"),end=code.indexOf(' }finally{',start);
code=code.slice(0,start)+`
 const negativeMode=process.env.HP_HOST_NEGATIVE_MODE||'click';assert(['click','caught-parse'].includes(negativeMode));
 await page.evaluate(async()=>{window.hpTrace={parse:[],saves:[],unhandled:[]};window.addEventListener('unhandledrejection',e=>hpTrace.unhandled.push({message:e.reason.message,stack:e.reason.stack}));const form=await L.require('form');for(const key of ['parse','save']){const original=form.Map.prototype[key];form.Map.prototype[key]=function(){const events=key==='parse'?hpTrace.parse:hpTrace.saves;events.push({called:true});return Promise.resolve(original.apply(this,arguments)).then(v=>{events.push({resolved:true});return v;},e=>{events.push({rejected:e.message,stack:e.stack});throw e;});}}});
 const payload=()=>page.evaluate(async()=>{const dom=await L.require('dom'),api=await L.require('view.homepublish.product');return api.collectConfig(dom.findClassInstance(document.querySelector('.cbi-map')));});
 const save=async()=>{await modal.getByRole('button',{name:'填写完毕',exact:true}).click();await modal.waitFor({state:'hidden'});};
 const open=async()=>{await page.getByRole('button',{name:'Edit',exact:true}).click();await modal.waitFor();};
 await tab('backend');assert.equal(await field('backend_host_header').isVisible(),true,'origin Host must be visible in native backend tab');
 assert.equal(await field('backend_host_header').inputValue(),'');await save();assert.equal(Object.hasOwn((await payload()).services[0].backend,'host_header'),false);await open();
 for(const type of ['http_proxy','https_proxy'])for(const scheme of ['http','https']){
  await tab('general');await field('type').selectOption(type);await tab('backend');await field('upstream_scheme').selectOption(scheme);
  assert.equal(await field('backend_host_header').isVisible(),true);
  const labels=await field('backend_host_header').evaluate(e=>e.closest('.cbi-value').textContent);assert.match(labels,/回源 Host/);assert.match(labels,/指定后端网站使用的域名，留空使用外网访问域名。后端按域名区分网站时填写。/);
  await field('backend_host_header').fill('origin.example.test:8080');
  if(scheme==='https')await field('tls_server_name').fill('certificate.example.test');
  await save();const svc=(await payload()).services[0];assert.equal(svc.backend.host_header,'origin.example.test:8080');if(process.env.HP_HOST_HEADER_PAYLOAD)fs.writeFileSync(process.env.HP_HOST_HEADER_PAYLOAD,JSON.stringify(await payload(),null,2));assert.deepEqual(svc.dns,{mode:'manual'});if(scheme==='https')assert.equal(svc.upstream_tls.server_name,'certificate.example.test');
  await open();await tab('backend');assert.equal(await field('backend_host_header').inputValue(),'origin.example.test:8080');
 }
 for(const type of ['tls_passthrough','ssh','tcp_forward']){
  await tab('general');await field('type').selectOption(type);await tab('backend');assert.equal(await field('backend_host_header').isVisible(),false);
  await tab('general');await field('type').selectOption('http_proxy');await tab('backend');assert.equal(await field('backend_host_header').inputValue(),'origin.example.test:8080');
 }
 await field('upstream_scheme').selectOption('http');
 for(const value of ['http://bad.test','site.test/path','bad.test\\r\\nX: y','site.test:0','site.test:65536','bad..test','-bad.test','[not-ipv6]']){
  const unchanged=await payload();await field('backend_host_header').fill(value);await field('backend_host_header').blur();
  if(negativeMode==='caught-parse'){
   const rejection=await page.evaluate(async()=>{const dom=await L.require('dom'),m=dom.findClassInstance(document.querySelector('.modal .cbi-map'));try{await m.parse();return null;}catch(e){return {message:e.message,stack:e.stack};}});
   assert.match(rejection.message,/Option.*回源 Host.*invalid input value/);
  }else{
   const n=errors.length;await modal.getByRole('button',{name:'填写完毕',exact:true}).click();await page.waitForFunction(()=>!document.querySelector('.modal .cbi-button-positive').disabled);
   await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
   if(errors.length>n)assert.equal(errors.length,n+1,'at most one uncaught rejection per native click');
   assert.match(await modal.locator('.hp-modal-validation-alert').innerText(),/有效的域名或 IP 地址/);
  }
  assert.equal(await modal.isVisible(),true,'invalid Host rejected: '+value);assert.equal(await field('backend_host_header').evaluate(e=>e.classList.contains('cbi-input-invalid')),true);
  assert.equal((await payload()).services[0].backend.host_header,unchanged.services[0].backend.host_header,'rejected Host must not enter the page draft');
 }
 for(const value of ['site.test','192.168.1.8:80','[2001:db8::1]:443','']){
  await field('backend_host_header').fill(value);await save();const svc=(await payload()).services[0];assert.equal(svc.backend.host_header,value||undefined);await open();await tab('backend');
 }
 await field('backend_host_header').fill('origin.example.test');await tab('general');await field('type').selectOption('tls_passthrough');await save();assert.equal((await payload()).services[0].backend.host_header,undefined);
 if(negativeMode==='click'){
  await open();await tab('backend');
  await page.evaluate(async()=>{const dom=await L.require('dom'),map=dom.findClassInstance(document.querySelector('.modal .cbi-map'));window.hpOriginalSave=map.save;map.save=function(){return Promise.reject(new Error('HomePublish unexpected save test'));};});
  await modal.getByRole('button',{name:'填写完毕',exact:true}).click();await page.waitForFunction(()=>!document.querySelector('.modal .cbi-button-positive').disabled);
  assert.equal(await modal.isVisible(),true,'unexpected error keeps modal/draft');assert.match(await page.locator('body').innerText(),/无法完成服务填写.*HomePublish unexpected save test/);
  await page.evaluate(async()=>{const dom=await L.require('dom');dom.findClassInstance(document.querySelector('.modal .cbi-map')).save=window.hpOriginalSave;});
 }
 const trace=await page.evaluate(()=>hpTrace);const diagnosis={negativeMode,pageErrors:errors,trace,productionWrites:false,classification:negativeMode==='click'?(errors.length?'PRODUCT_DEFECT_NATIVE_HANDLER_REJECTION':'NATIVE_CLICK_PASS'):'CAUGHT_PARSE_CONTRACT_ONLY',ordinaryProductionLifecycle:'NOT_RUN'};fs.writeFileSync(require('node:path').join(require('./env.cjs').evidence,'host-'+negativeMode+'-diagnosis.json'),JSON.stringify(diagnosis,null,2));console.log('HOST_DIAGNOSIS',JSON.stringify(diagnosis));
 assert.deepEqual(errors,[],'native click rejection remains a product acceptance failure; caught parse is only a separate API contract');console.log(JSON.stringify({nativeLoader:true,visibilityMatrix:4,legacyEmpty:true,roundtrip:true,sniIndependent:true,noDnsChanges:true,hiddenTypes:3,retainSwitchback:true,invalidHosts:8,validHosts:4,typeChangeExcludes:true,deviceWrites:false}));
`+code.slice(end);
const m=new Module(__filename,module);m.filename=__filename;m.paths=module.paths;m._compile(code,__filename);