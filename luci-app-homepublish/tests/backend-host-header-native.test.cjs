/* Native installed LuCI loader/form with worktree UI; fixture RPC rejects all writes. */
const fs=require('node:fs'),Module=require('node:module');
let code=fs.readFileSync(require('node:path').join(__dirname,'upstream-tls-form-probe.cjs'),'utf8');
const start=code.indexOf(" await tab('access');"),end=code.indexOf(' }finally{',start);
code=code.slice(0,start)+`
 const payload=()=>page.evaluate(async()=>{const dom=await L.require('dom'),api=await L.require('view.homepublish.product');return api.collectConfig(dom.findClassInstance(document.querySelector('.cbi-map')));});
 const save=async()=>{await modal.getByRole('button',{name:'Save',exact:true}).click();await modal.waitFor({state:'hidden'});};
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
  await field('backend_host_header').fill(value);await modal.getByRole('button',{name:'Save',exact:true}).click();assert.equal(await modal.isVisible(),true,'invalid Host rejected: '+value);
 }
 for(const value of ['site.test','192.168.1.8:80','[2001:db8::1]:443','']){
  await field('backend_host_header').fill(value);await save();const svc=(await payload()).services[0];assert.equal(svc.backend.host_header,value||undefined);await open();await tab('backend');
 }
 await field('backend_host_header').fill('origin.example.test');await tab('general');await field('type').selectOption('tls_passthrough');await save();assert.equal((await payload()).services[0].backend.host_header,undefined);
 assert.deepEqual(errors,[]);console.log(JSON.stringify({nativeLoader:true,visibilityMatrix:4,legacyEmpty:true,roundtrip:true,sniIndependent:true,noDnsChanges:true,hiddenTypes:3,retainSwitchback:true,invalidHosts:8,validHosts:4,typeChangeExcludes:true,deviceWrites:false}));
`+code.slice(end);
const m=new Module(__filename,module);m.filename=__filename;m.paths=module.paths;m._compile(code,__filename);
