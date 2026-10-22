/* Native modal edge cases, safe metadata fixtures only. */

/* REQ-012 prerequisite guard: this file is a real-device/browser acceptance
 * script, not a self-contained unit test. When the device LuCI (HP_DEVICE_URL,
 * default http://192.168.1.2) or the local playwright install is unreachable,
 * skip gracefully so `node --test` stays green offline. */
{
 const device=(process.env.HP_DEVICE_URL||'http://192.168.1.2').replace(/\/$/,'');
 const pw=process.env.HP_PLAYWRIGHT||process.env.LOCALAPPDATA+'/hermes/cache/scratch/hp-p2-browser-deps/node_modules/playwright';
 let ok=true;
 try{require.resolve(pw);}catch(e){ok=false;}
 if(ok){try{require('node:child_process').execSync('curl -s -m 2 -o /dev/null '+device,{stdio:'ignore'});}catch(e){ok=false;}}
 if(!ok){console.log('SKIP: device LuCI ('+device+') or playwright ('+pw+') unavailable; this is a real-device acceptance script.');process.exit(0);}
}
const fs=require('node:fs'),path=require('node:path');
let code=fs.readFileSync(path.join(__dirname,'upstream-tls-form-probe.cjs'),'utf8');
const scenario=process.env.HP_DNS_CASE||'multiple';
const profiles=[{profile_id:'opaque-one',name:'家庭域名',provider:'DNSPod',a:{enabled:true},aaaa:{enabled:true}},{profile_id:'opaque-two',name:'备用域名',provider:'Cloudflare',a:{enabled:false},aaaa:{enabled:true}}];
code=code.replace("else if(m==='ddns_profiles')data={available:false,profiles:[]};else if(m==='certificates')", "else if(m==='ddns_profiles')"+(scenario==='failure'?"throw Error('fixture unavailable');":"data="+JSON.stringify({available:scenario!=='empty'&&scenario!=='retained',profiles:scenario==='multiple'?profiles:[]})+';')+"else if(m==='certificates')");
if(scenario==='retained')code=code.replace("hostname:'same.example.test'","dns:{mode:'ddns_go',profile_id:'old-opaque',record_types:['AAAA']},hostname:'same.example.test'");
const start=code.indexOf(" await tab('access');"),end=code.indexOf(' }finally{',start);
code=code.slice(0,start)+`
 await tab('access');
 const scenario=${JSON.stringify(scenario)};
 const collect=()=>page.evaluate(async()=>{const dom=await L.require('dom'),api=await L.require('view.homepublish.product');return api.collectConfig(dom.findClassInstance(document.querySelector('.cbi-map'))).services[0];});
 if(scenario==='multiple'){
  await field('dns_mode').selectOption('ddns_go');
  assert.equal(await field('dns_profile').inputValue(),'');
  await modal.getByRole('button',{name:'Save',exact:true}).click();assert.equal(await modal.isVisible(),true);
  await field('dns_profile').selectOption('opaque-two');
  assert.equal(await field('dns_a').isDisabled(),true);assert.equal(await field('dns_aaaa').isChecked(),true);
  await field('dns_profile').selectOption('opaque-one');
  assert.equal(await field('dns_a').isDisabled(),false);assert.equal(await field('dns_a').isChecked(),true);assert.equal(await field('dns_aaaa').isChecked(),false);
  await field('dns_aaaa').check();
  await modal.getByRole('button',{name:'Save',exact:true}).click();await modal.waitFor({state:'hidden'});
  assert.deepEqual((await collect()).dns,{mode:'ddns_go',profile_id:'opaque-one',record_types:['A','AAAA']});
  await page.getByRole('button',{name:'Edit',exact:true}).click();await modal.waitFor();await tab('general');await field('type').selectOption('ssh');
  assert.equal(await field('dns_mode').isVisible(),false);
  await modal.getByRole('button',{name:'Save',exact:true}).click();await modal.waitFor({state:'hidden'});assert.deepEqual((await collect()).dns,{mode:'manual'});
 }else if(scenario==='retained'){
  assert.equal(await field('dns_mode').inputValue(),'ddns_go');
  assert.ok((await modal.textContent()).includes('请先在 ddns-go 中配置域名服务商并启用服务。'));
  await modal.getByRole('button',{name:'Save',exact:true}).click();await modal.waitFor({state:'hidden'});
  assert.deepEqual((await collect()).dns,{mode:'ddns_go',profile_id:'old-opaque',record_types:['AAAA']});
 }else{
  assert.equal(await field('dns_mode').inputValue(),'manual');
  await field('dns_mode').selectOption('ddns_go');await modal.getByRole('button',{name:'Save',exact:true}).click();assert.equal(await modal.isVisible(),true);
  assert.ok((await modal.textContent()).includes('请先在 ddns-go 中配置域名服务商并启用服务。'));
  await field('dns_mode').selectOption('manual');
  await modal.getByRole('button',{name:'Save',exact:true}).click();await modal.waitFor({state:'hidden'});assert.deepEqual((await collect()).dns,{mode:'manual'});
 }
 assert.deepEqual(errors,[]);console.log(JSON.stringify({scenario,nativeModal:true,productionWrites:false}));
`+code.slice(end);
const Module=require('node:module'),m=new Module(__filename,module);m.filename=__filename;m.paths=module.paths;m._compile(code,__filename);
