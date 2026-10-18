/* Native installed LuCI serializer, live saved snapshot, zero production writes. */
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'), evidence=path.join(root,'docs/evidence/input-firewall');
const original=fs.readFileSync(path.join(__dirname,'upstream-tls-form-probe.cjs'),'utf8');
const snapshot=JSON.parse(fs.readFileSync(path.join(evidence,'services-save-before.json'))).saved_config;
let code=original.replace(/const config=.*?;\n/, 'const config='+JSON.stringify(snapshot)+';\n');
code=code.replace("await page.getByRole('button',{name:'Edit',exact:true}).click()", "await page.getByRole('button',{name:'Edit',exact:true}).first().click()");
const start=code.indexOf(" await tab('access');");
const end=code.indexOf(' }finally{',start);
code=code.slice(0,start)+`
 await modal.getByRole('button',{name:'Save',exact:true}).click();await modal.waitFor({state:'hidden'});
 const payload=await page.evaluate(async()=>{const dom=await L.require('dom'),api=await L.require('view.homepublish.product');return api.collectConfig(dom.findClassInstance(document.querySelector('.cbi-map')));});
 fs.writeFileSync(${JSON.stringify(path.join(evidence,'services-save-native-payload.json'))},JSON.stringify(payload,null,2));
 const ssh=['-o','ProxyCommand=none','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2'];
 const response=JSON.parse(require('node:child_process').execFileSync('ssh',ssh.concat("ubus call homepublish validate '"+JSON.stringify({config:payload})+"'"),{encoding:'utf8'}));
 fs.writeFileSync(${JSON.stringify(path.join(evidence,'services-save-native-validation.json'))},JSON.stringify(response,null,2));
 assert.equal(response.valid,true,JSON.stringify(response));assert.deepEqual(errors,[]);
 console.log(JSON.stringify({nativeModalSaved:true,actualRpcCanonical:true,serviceCount:payload.services.length,deviceConfigWrites:false}));
`+code.slice(end);
// Compile with this test's filename so installed probe dependencies resolve identically.
const Module=require('node:module'),m=new Module(__filename,module);m.filename=__filename;m.paths=module.paths;m._compile(code,__filename);
