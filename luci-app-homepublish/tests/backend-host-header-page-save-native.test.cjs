/* Native modal Save then actual page Save/Apply; all write RPCs are local fixtures. */

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
const fs=require('node:fs'),path=require('node:path'),Module=require('node:module');
let code=fs.readFileSync(path.join(__dirname,'upstream-tls-form-probe.cjs'),'utf8');
code=code.replace('if(local){','if(local && !process.env.HP_MODAL_INSTALLED){');
code=code.replace("(async()=>{let browser,server;try{",'let submitted;\n(async()=>{let browser,server;try{');
code=code.replace("else throw Error('unexpected mutation/RPC '+m);", "else if(m==='validate'){submitted=p[3].config;data={error:'fixture captured validation; no production writes'};}else throw Error('unexpected mutation/RPC '+m);");
if(process.env.HP_MODAL_STATUS)code=code.replace(/const config=\{[^\n]+\};/,"const config=JSON.parse(fs.readFileSync(process.env.HP_MODAL_STATUS,'utf8')).saved_config;");
if(process.env.HP_MODAL_DDNS)code=code.replace("data={available:false,profiles:[]}","data=JSON.parse(fs.readFileSync(process.env.HP_MODAL_DDNS,'utf8'))");
if(process.env.HP_MODAL_CERTS)code=code.replace("data={certificates:[]}","data=JSON.parse(fs.readFileSync(process.env.HP_MODAL_CERTS,'utf8'))");
code=code.replace("page.getByRole('button',{name:'Edit',exact:true}).click()","page.getByRole('button',{name:'Edit',exact:true}).first().click()");
const start=code.indexOf(" await tab('access');"),end=code.indexOf(' }finally{',start);
code=code.slice(0,start)+`
 await tab('backend');await field('backend_host_header').fill('ai.iwonderful.top');
 await modal.getByRole('button',{name:'Save',exact:true}).click();await modal.waitFor({state:'hidden'});
 const collect=()=>page.evaluate(async()=>{const dom=await L.require('dom'),api=await L.require('view.homepublish.product');return api.collectConfig(dom.findClassInstance(document.querySelector('.cbi-map')));});
 assert.equal((await collect()).services[0].backend.host_header,'ai.iwonderful.top','modal Save retains Host');
 await page.locator('#hp-save-apply').click();await page.waitForFunction(()=>document.querySelector('#hp-message').textContent.includes('fixture captured'));
 assert.equal(submitted.services[0].backend.host_header,'ai.iwonderful.top','actual page Save/Apply must retain Host after native map.save redraw');
 if(process.env.HP_MODAL_PAYLOAD)fs.writeFileSync(process.env.HP_MODAL_PAYLOAD,JSON.stringify(submitted));
 assert.deepEqual(errors,[]);console.log(JSON.stringify({nativeModalSave:true,nativePageSaveApply:true,submittedHost:submitted.services[0].backend.host_header,productionWrites:false}));
`+code.slice(end);
const m=new Module(__filename,module);m.filename=__filename;m.paths=module.paths;m._compile(code,__filename);
