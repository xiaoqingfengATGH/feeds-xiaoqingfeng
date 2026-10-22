/* Native LuCI picker: multiple accounts/suffixes, conservative fallback. */

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
const profiles=[{profile_id:'first',name:'家庭域名',provider:'DNSPod',a:{enabled:true,domains:['home.iwonderful.top','nas.example.test','camera.iwonderful.top']},aaaa:{enabled:false,domains:[]}},{profile_id:'second',name:'备用域名',provider:'Cloudflare',a:{enabled:false,domains:[]},aaaa:{enabled:true,domains:['example.org']}}];
code=code.replace("else if(m==='ddns_profiles')data={available:false,profiles:[]}","else if(m==='ddns_profiles')data="+JSON.stringify({available:true,profiles}));
code=code.replace("await page.getByRole('button',{name:'Edit',exact:true}).click()","await page.getByRole('button',{name:'Add',exact:true}).click()");
const start=code.indexOf(" await tab('access');"),end=code.indexOf(' }finally{',start);
code=code.slice(0,start)+`
 await tab('access');
 assert.equal(await field('dns_mode').inputValue(),'ddns_go');
 assert.equal(await field('dns_profile').inputValue(),'');
 assert.equal(await field('dns_suffix').inputValue(),'');
 await field('dns_profile').selectOption('first');
 const picker=modal.locator('select[data-dns-candidates]');
 assert.equal(await picker.locator('option').count(),3,'deduplicate same suffix from configured records');
 assert.equal(await picker.inputValue(),'','multiple candidates require explicit selection');
 assert.equal(await field('dns_suffix').inputValue(),'');
 await field('dns_label').fill('nas');await field('dns_label').blur();
 assert.equal(await field('hostname').inputValue(),'');
 await picker.selectOption('iwonderful.top');
 assert.equal(await field('hostname').inputValue(),'nas.iwonderful.top');
 await field('dns_profile').selectOption('second');
 assert.equal(await picker.locator('option').count(),2);
 assert.equal(await field('dns_suffix').inputValue(),'example.org','two-label source is retained whole, not a guessed zone');
 assert.ok((await modal.textContent()).includes('来源：example.org'));
 assert.equal(await field('hostname').inputValue(),'nas.example.org');
 assert.equal(await field('dns_a').isDisabled(),true);
 assert.equal(await field('dns_aaaa').isChecked(),true);
 await field('dns_suffix').fill('chosen.example.net');await field('dns_suffix').blur();
 await tab('general');await field('type').selectOption('tls_passthrough');await tab('access');
 assert.equal(await field('dns_suffix').inputValue(),'chosen.example.net');
 await field('dns_mode').selectOption('manual');
 assert.equal(await field('hostname').inputValue(),'nas.chosen.example.net');
 assert.equal(await field('dns_suffix').isVisible(),false);
 await modal.getByRole('button',{name:'Dismiss',exact:true}).click();
 await page.getByRole('button',{name:'Edit',exact:true}).first().click();await modal.waitFor();await tab('access');
 assert.equal(await field('dns_mode').inputValue(),'manual');
 await field('dns_mode').selectOption('ddns_go');
 await field('dns_profile').selectOption('first');
 assert.equal(await field('hostname').inputValue(),'same.example.test','selecting an account must not erase an existing hostname');
 await field('dns_profile').selectOption('second');
 assert.equal(await field('hostname').inputValue(),'same.example.test','single candidate must not replace an existing hostname');
 assert.equal(await field('dns_suffix').inputValue(),'example.test');
 assert.deepEqual(errors,[]);console.log(JSON.stringify({multipleAccounts:true,multipleSuffixes:true,conservativeFallback:true,productionWrites:false}));
`+code.slice(end);
const Module=require('node:module'),m=new Module(__filename,module);m.filename=__filename;m.paths=module.paths;m._compile(code,__filename);
