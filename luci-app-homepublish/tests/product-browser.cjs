const {chromium}=require(process.env.HP_PLAYWRIGHT || 'playwright');
const assert=require('node:assert/strict');
(async()=>{const browser=await chromium.launch({channel:'chrome',headless:true});try{
const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
await page.goto('http://127.0.0.1:18993/');await page.waitForFunction(()=>window.result.loader);assert.equal((await page.evaluate(()=>window.result)).loader,'PASS',JSON.stringify(await page.evaluate(()=>window.result)));
await page.locator('#hp-tab-entry').click();await page.locator('[data-field="default_certificate_ref"]').selectOption('acme:rsa');await page.locator('#hp-tab-services').click();await page.locator('#hp-add-service').click();
await page.locator('[data-field="name"]').fill('家庭相册');await page.locator('[data-field="hostname"]').fill('uncovered.example.test');
await page.locator('#hp-edit-submit').click();await page.waitForFunction(()=>document.querySelector('#hp-edit-error').textContent.length>0);
await page.locator('[data-field="hostname"]').fill('photos.example.test');await page.locator('#hp-edit-submit').click();await page.waitForFunction(()=>!document.querySelector('dialog'));await page.locator('#hp-save').click();await page.waitForFunction(()=>document.querySelector('#hp-message').textContent.includes('已保存 revision 1'));
let state=await page.evaluate(()=>L.require('view.homepublish.product').then(a=>a.status()));assert.equal(state.saved_config.services[1].certificate_mode,'inherit');assert.equal(state.active_revision,undefined);
await page.locator('#hp-tab-entry').click();await page.locator('[data-field="default_certificate_ref"]').selectOption('acme:ecc');await page.locator('#hp-save').click();await page.waitForFunction(()=>document.querySelector('#hp-message').textContent.includes('已保存 revision 2'));state=await page.evaluate(()=>L.require('view.homepublish.product').then(a=>a.status()));assert.equal(state.saved_config.services[1].certificate_ref,'acme:ecc');assert.equal(state.saved_config.services[0].certificate_ref,'acme:nas');await page.reload();await page.waitForFunction(()=>window.result.loader==='PASS');assert.equal(await page.locator('#hp-start').isDisabled(),true);
await page.locator('#hp-tab-entry').click();assert.ok(await page.locator('[data-field="default_certificate_ref"] option').count()>=1);
await page.setViewportSize({width:375,height:812});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=375));
const stock=await page.evaluate(()=>L.require('view.homepublish.product').then(a=>a.certificates()));assert.ok(Array.isArray(stock.certificates));
console.log(JSON.stringify({nativeTabs:'PASS',dialogErrors:'PASS',inventoryRPC:stock,narrow375:'PASS',errors}));assert.deepEqual(errors,[]);
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
