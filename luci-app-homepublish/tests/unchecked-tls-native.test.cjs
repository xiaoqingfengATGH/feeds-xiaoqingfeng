/* Exact screenshot through native installed LuCI modal, no production config writes. */
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),evidence=path.join(root,'docs/evidence/input-firewall');
const ssh=['-o','ProxyCommand=none','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2'];
const snapshot=JSON.parse(cp.execFileSync('ssh',ssh.concat("ubus call homepublish status '{}'"),{encoding:'utf8'}));
fs.writeFileSync(path.join(evidence,'unchecked-tls-before.json'),JSON.stringify(snapshot,null,2));
let code=fs.readFileSync(path.join(__dirname,'upstream-tls-form-probe.cjs'),'utf8').replace(/const config=.*?;\n/,'const config='+JSON.stringify(snapshot.saved_config)+';\n');
code=code.replace("if(local){", "if(local && !process.env.HP_INSTALLED_UI){");
code=code.replace("await page.getByRole('button',{name:'Edit',exact:true}).click()","await page.getByRole('button',{name:'Edit',exact:true}).first().click()");
const start=code.indexOf(" await tab('access');"),end=code.indexOf(' }finally{',start);
code=code.slice(0,start)+`
 await tab('general');await field('name').fill('VMWARE');
 await tab('backend');await field('backend_host').fill('192.168.1.245');await field('backend_port').fill('443');await field('upstream_scheme').selectOption('https');
 assert.equal(await field('tls_verify').isChecked(),true);await field('tls_verify').uncheck();await field('tls_server_name').fill('');
 await modal.getByRole('button',{name:'Save',exact:true}).click();await modal.waitFor({state:'hidden'});
 await page.evaluate(async()=>{const api=await L.require('view.homepublish.product');api.validate=async config=>{window.actualValidatePayload=config;throw new Error('READ_ONLY_CAPTURE');};});
 await page.locator('#hp-save').click();await page.waitForFunction(()=>window.actualValidatePayload);
 const captured=await page.evaluate(async()=>{const dom=await L.require('dom'),m=dom.findClassInstance(document.querySelector('.cbi-map'));return {payload:window.actualValidatePayload,data:m.data.data};});
 fs.writeFileSync(${JSON.stringify(path.join(evidence,'unchecked-tls-native-payload.json'))},JSON.stringify(captured,null,2));
 const response=JSON.parse(require('node:child_process').execFileSync('ssh',${JSON.stringify(ssh)}.concat("ubus call homepublish validate '"+JSON.stringify({config:captured.payload})+"'"),{encoding:'utf8'}));
 fs.writeFileSync(${JSON.stringify(path.join(evidence,'unchecked-tls-native-validation.json'))},JSON.stringify(response,null,2));
 assert.deepEqual(captured.payload.services[0].upstream_tls,{verify:false});assert.equal(response.valid,true,JSON.stringify(response));assert.deepEqual(errors,[]);
 await page.getByRole('button',{name:'Edit',exact:true}).first().click();await modal.waitFor();await tab('backend');assert.equal(await field('tls_verify').isChecked(),false);
 console.log(JSON.stringify({exactScreenshot:true,uncheckedFalse:true,falseRoundtrip:true,deviceValidation:response.valid,configWrites:false}));
`+code.slice(end);
const Module=require('node:module'),m=new Module(__filename,module);m.filename=__filename;m.paths=module.paths;m._compile(code,__filename);
