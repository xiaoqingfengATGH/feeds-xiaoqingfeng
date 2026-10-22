/* New-service fallback through the installed loader. */

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
const scenario=process.env.HP_DNS_CASE || 'unavailable';
if(scenario==='empty')code=code.replace('available:false,profiles:[]','available:true,profiles:[]');
if(scenario==='failure')code=code.replace("else if(m==='ddns_profiles')data={available:false,profiles:[]};","else if(m==='ddns_profiles')throw Error('discovery fixture failure');");
code=code.replace("await page.getByRole('button',{name:'Edit',exact:true}).click()","await page.getByRole('button',{name:'Add',exact:true}).click()");
const start=code.indexOf(" await tab('access');"),end=code.indexOf(' }finally{',start);
code=code.slice(0,start)+`
 await tab('access');assert.equal(await field('dns_mode').inputValue(),'manual');
 await field('hostname').fill('manual.example.test');
 await tab('general');await field('name').fill('Manual service');await field('type').selectOption('http_proxy');
 await tab('backend');await field('backend_host').fill('192.0.2.2');await field('backend_port').fill('8080');
 await modal.getByRole('button',{name:'Save',exact:true}).click();await modal.waitFor({state:'hidden'});
 const svc=await page.evaluate(async()=>{const dom=await L.require('dom'),api=await L.require('view.homepublish.product');return api.collectConfig(dom.findClassInstance(document.querySelector('.cbi-map'))).services[1];});
 assert.equal(svc.hostname,'manual.example.test');assert.deepEqual(svc.dns,{mode:'manual'});
 assert.deepEqual(errors,[]);console.log(JSON.stringify({scenario:${JSON.stringify(scenario)},newManualFallback:true,productionWrites:false}));
`+code.slice(end);
const Module=require('node:module'),m=new Module(__filename,module);m.filename=__filename;m.paths=module.paths;m._compile(code,__filename);
