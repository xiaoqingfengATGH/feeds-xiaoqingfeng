const {chromium}=require(process.env.HP_PLAYWRIGHT || 'D:/DevPortal/homelede/artifacts/palette-switch-cache/test-deps/node_modules/playwright');
const assert=require('node:assert/strict');
(async()=>{const browser=await chromium.launch({channel:'chrome',headless:true});try{
const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));

/* r9 form.Map 语义：真实浏览器 + 真实 rpcd/ubus fixture，验证 GridSection 服务表单全生命周期 */
await page.goto('http://127.0.0.1:18993/');
await page.waitForFunction(()=>window.result.loader);
assert.equal((await page.evaluate(()=>window.result)).loader,'PASS',JSON.stringify(await page.evaluate(()=>window.result)));

/* 1. form.Map 渲染：cbi-map 存在、表格有默认 nas 行、无旧 r7 自绘 dialog 残留 */
await page.waitForSelector('.cbi-map');
assert.equal(await page.locator('.cbi-map').count(),1);
await page.waitForSelector('.cbi-tblsection table tr.cbi-section-table-row');
let rows=await page.locator('.cbi-tblsection table tr.cbi-section-table-row').count();
assert.ok(rows>=1,'expected default nas row, got '+rows);
/* GridSection 表格列：启用/域名/后端/证书（textvalue 呈现） */
const bodyText=await page.locator('.cbi-map').innerText();
assert.ok(bodyText.includes('nas.example.test'),'grid row hostname missing: '+bodyText);
assert.ok(bodyText.includes('nas.example.test · RSA'),'grid row certificate textvalue missing: '+bodyText);

/* 2. modal 新增服务：Add → .cbi-modal 表单 → 保存走后端 canonical 校验 */
await page.locator('.cbi-tblsection-create .cbi-button-add').click();
await page.waitForSelector('#modal_overlay .cbi-modal');
const modal=page.locator('#modal_overlay .cbi-modal');
assert.ok((await modal.innerText()).includes('新服务'),'modal title should use modaltitle 新服务');
await modal.locator('[data-field$=".name"] input, [data-field$=".name"] select, [data-field$=".name"] textarea').fill('未覆盖服务');
await modal.locator('[data-field$=".hostname"] input, [data-field$=".hostname"] select, [data-field$=".hostname"] textarea').fill('uncovered.example.test');
await modal.locator('[data-field$=".backend_url"] input, [data-field$=".backend_url"] select, [data-field$=".backend_url"] textarea').fill('http://192.168.1.20:8080');
/* allowed_ranges 必填（rmempty=false）：新行空会被 form.parse 拒，modal 无法关闭 */
await modal.locator('[data-field$=".allowed_ranges"] input, [data-field$=".allowed_ranges"] textarea, [data-field$=".allowed_ranges"] select').fill('192.168.1.0/24');
await modal.locator('.cbi-button-positive').click();
/* modal 内 Save 只是写回行数据；真正 canonical 校验在 #hp-save */
await page.waitForFunction(()=>!document.body.classList.contains('modal-overlay-active'));
await page.locator('#hp-save').click();
await page.waitForFunction(()=>{const t=document.querySelector('#hp-message').textContent;return t.includes('保存失败')||t.includes('已保存 revision')});
assert.ok((await page.locator('#hp-message').innerText()).includes('保存失败'),'expected save failure for uncovered hostname');

/* 3. 修成 SAN 覆盖域名 → modal 编辑 → Save 成功（revision+1，绝不启动） */
const photoRow=page.locator('.cbi-tblsection table tr.cbi-section-table-row').filter({hasText:'uncovered.example.test'});
await photoRow.locator('.cbi-button-edit').first().click();
await page.waitForSelector('#modal_overlay .cbi-modal');
const modal2=page.locator('#modal_overlay .cbi-modal');
await modal2.locator('[data-field$=".hostname"] input, [data-field$=".hostname"] select, [data-field$=".hostname"] textarea').fill('photos.example.test');
await modal2.locator('[data-field$=".name"] input, [data-field$=".name"] select, [data-field$=".name"] textarea').fill('相册');
await modal2.locator('.cbi-button-positive').click();
await page.waitForFunction(()=>!document.body.classList.contains('modal-overlay-active'));
await page.waitForFunction(()=>document.querySelectorAll('.cbi-tblsection table tr.cbi-section-table-row').length>=2);
await page.locator('#hp-save').click();
await page.waitForFunction(()=>document.querySelector('#hp-message').textContent.includes('已保存 revision'));
let state=await page.evaluate(()=>L.require('view.homepublish.product').then(a=>a.status()));
assert.ok(state.saved_revision>=1,'saved_revision should advance');
assert.equal(state.active_revision,undefined,'save must never start');
assert.equal(await page.locator('#hp-start').isDisabled(),false,'start enabled after save (real capabilities)');

/* 4. 行删除（GridSection addremove）+ Save */
await page.locator('.cbi-tblsection table tr.cbi-section-table-row').filter({hasText:'photos.example.test'}).locator('.cbi-button-remove').first().click();
await page.locator('#hp-save').click();
await page.waitForFunction(()=>document.querySelector('#hp-message').textContent.includes('已保存 revision'));
state=await page.evaluate(()=>L.require('view.homepublish.product').then(a=>a.status()));
assert.equal(state.saved_config.services.filter(s=>s.hostname==='photos.example.test').length,0,'removed service should not persist');

/* 5. 重新载入（snapshot 语义）+ 按钮使能由真实状态驱动 */
await page.reload();await page.waitForFunction(()=>window.result.loader==='PASS');
await page.waitForSelector('.cbi-map');
assert.equal(await page.locator('#hp-start').isDisabled(),false,'saved_revision>0 & not running → start enabled');
assert.equal(await page.locator('#hp-apply').isDisabled(),true,'not running → apply disabled');
assert.equal(await page.locator('#hp-stop').isDisabled(),true,'not running → stop disabled');

/* 6. overview 页（?overview 加载 view.homepublish.overview，真实状态驱动按钮，假门控文案已除） */
await page.goto('http://127.0.0.1:18993/?overview');
await page.waitForFunction(()=>window.result.loader==='PASS');
await page.waitForSelector('#hp-start');
const ovText=await page.locator('#view').innerText();
assert.ok(!ovText.includes('不支持公网开启'),'fake-gating copy must be gone from overview');
assert.equal(await page.locator('#hp-start').isDisabled(),false);

console.log(JSON.stringify({r9FormMapBrowser:'PASS',gridRows:rows,revision:state.saved_revision,errors}));
assert.deepEqual(errors,[]);
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
