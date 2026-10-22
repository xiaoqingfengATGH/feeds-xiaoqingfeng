/* Real installed LuCI loader + native modal; local RPC fixtures only. */

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
code=code.replace("else if(m==='ddns_profiles')data={available:false,profiles:[]};else if(m==='certificates')", "else if(m==='ddns_profiles')data={available:true,profiles:[{profile_id:'opaque-one',name:'家庭域名',provider:'DNSPod',a:{enabled:true,domains:[]},aaaa:{enabled:false,domains:[]}}]};else if(m==='certificates')");
const start=code.indexOf(" await tab('access');"),end=code.indexOf(' }finally{',start);
code=code.slice(0,start)+`
 await tab('access');
 await field('dns_mode').waitFor({state:'visible',timeout:3000});
 assert.equal(await field('dns_mode').inputValue(),'manual');
 await field('dns_mode').selectOption('ddns_go');
 assert.ok((await modal.textContent()).includes('家庭域名 · DNSPod'));
 assert.equal(await field('dns_a').isChecked(),true);
 assert.equal(await field('dns_aaaa').isChecked(),false);
 assert.equal(await field('dns_aaaa').isDisabled(),true);
 await field('hostname').fill('brand-new.example.test');
 await tab('general');await field('type').selectOption('tls_passthrough');await tab('access');
 assert.equal(await field('dns_mode').inputValue(),'ddns_go');
 await modal.getByRole('button',{name:'Save',exact:true}).click();await modal.waitFor({state:'hidden'});
 const payload=await page.evaluate(async()=>{const dom=await L.require('dom'),api=await L.require('view.homepublish.product');return api.collectConfig(dom.findClassInstance(document.querySelector('.cbi-map')));});
 assert.deepEqual(payload.services[0].dns,{mode:'ddns_go',profile_id:'opaque-one',record_types:['A']});
 assert.equal(payload.services[0].hostname,'brand-new.example.test');
 assert.equal((await page.locator('.cbi-section-table').textContent()).includes('opaque-one'),false);
 assert.deepEqual(errors,[]);
 console.log(JSON.stringify({nativeLoader:true,singleProfile:true,defaultManual:true,freeHostname:true,typeSwitchRetains:true,ipv6NeverEnabled:true,productionWrites:false}));
`+code.slice(end);
const Module=require('node:module'),m=new Module(__filename,module);m.filename=__filename;m.paths=module.paths;m._compile(code,__filename);
