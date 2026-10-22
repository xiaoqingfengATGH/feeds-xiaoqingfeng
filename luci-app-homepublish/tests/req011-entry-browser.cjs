/* REQ-011 实机验收: entry 页 boot_restore Flag 控件渲染 + 保存回读。
 * 复用 p4-overview-browser.cjs 模式: 设备 ubus 会话 cookie → 1081 LuCI。
 * 只读验证为主; 保存操作前后断言 revision 不回退、boot_restore 值保留。 */
const {execSync}=require('node:child_process'),assert=require('node:assert/strict');
const SSH_PREFIX='ssh -o ProxyCommand=none -o ProxyJump=none -o IdentitiesOnly=yes -o BatchMode=yes -i D:/DevPortal/CloudHosts/HomePri.key -p 222 root@127.0.0.1';
function ssh(cmd){return execSync(SSH_PREFIX+' '+cmd,{shell:'bash',encoding:'utf8',stdio:['ignore','pipe','pipe']});}
function deviceStatus(){
 const out=execSync(SSH_PREFIX+' /usr/bin/lua /usr/share/homepublish/product-device-cli.lua',{shell:'bash',encoding:'utf8',stdio:['pipe','pipe','pipe'],input:'{"action":"status"}'+'\n'});
 return JSON.parse(out);
}
const {chromium}=require(process.env.HP_PLAYWRIGHT || 'D:/DevPortal/homelede/artifacts/palette-switch-cache/test-deps/node_modules/playwright');
(async()=>{
 const before=deviceStatus();
 console.log('BEFORE revision',before.saved_revision,'boot_restore',before.saved_config.publication_policy.boot_restore,'phase',before.runtime.phase);
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try{
  const sid=[...ssh('"ubus call session list"').matchAll(/"ubus_rpc_session":\s*"([a-f0-9]{32})"/g)].map(x=>x[1]).find(x=>!/^0+$/.test(x));
  assert.ok(sid,'session');
  const context=await browser.newContext();
  await context.addCookies([{name:'sysauth_http',value:sid,url:'http://127.0.0.1:1081',httpOnly:true,sameSite:'Lax'}]);
  const page=await context.newPage(),errors=[];
  page.on('pageerror',e=>errors.push(String(e)));
  await page.goto('http://127.0.0.1:1081/cgi-bin/luci/admin/services/homepublish/entry');
  await page.waitForSelector('#hp-save',{timeout:15000});
  // 1. Flag 控件存在且文案正确
  const flag=page.locator('.cbi-value:has(.cbi-value-title:text-is("重启后恢复发布"))');
  await flag.waitFor({timeout:10000});
  const checkbox=flag.locator('input[type=checkbox]');
  assert.ok(await checkbox.count()===1,'one checkbox');
  const desc=await flag.innerText();
  assert.ok(/重启后自动恢复/.test(desc.replace(/\s+/g,'')),'description mentions reboot recovery: '+desc);
  console.log('FLAG_DESC',desc.replace(/\n/g,' '));
  // 2. 勾选状态与 saved 一致 (当前 false → 未勾选)
  const initial=before.saved_config.publication_policy.boot_restore===true;
  assert.equal(await checkbox.isChecked(),initial,'checkbox matches saved boot_restore');
  // 3. 运行方式=持续运行 时 Flag 可见; 切到 限定时长 时隐藏 (depends)
  const modeSel=page.locator('select[id$=".mode"], .cbi-value:has(.cbi-value-title:text-is("运行方式")) select').first();
  await modeSel.selectOption('temporary');
  await page.waitForTimeout(300);
  assert.equal(await checkbox.isVisible(),false,'hidden in temporary mode');
  await modeSel.selectOption('continuous');
  await page.waitForTimeout(300);
  assert.equal(await checkbox.isVisible(),true,'visible in continuous mode');
  // 4. 勾选并保存 → 回读 saved boot_restore=true; 再关掉保存 → false (验证保存链路, 终态还原)
  await checkbox.check();
  await page.locator('#hp-save').click();
  await page.waitForTimeout(1500);
  let s=deviceStatus();
  assert.equal(s.saved_config.publication_policy.boot_restore,true,'saved boot_restore=true after save');
  assert.equal(s.saved_revision,before.saved_revision+1,'revision increments');
  assert.equal(s.runtime.phase,'running','publication still running (save never stops)');
  console.log('SAVED_ON revision',s.saved_revision,'boot_restore=true phase',s.runtime.phase);
  await page.reload();await page.waitForSelector('#hp-save',{timeout:15000});
  const flag2=page.locator('.cbi-value:has(.cbi-value-title:text-is("重启后恢复发布")) input[type=checkbox]');
  await flag2.waitFor({timeout:10000});
  assert.equal(await flag2.isChecked(),true,'reloaded checkbox=true');
  // 还原: 取消勾选保存
  await flag2.uncheck();
  await page.locator('#hp-save').click();
  await page.waitForTimeout(1500);
  s=deviceStatus();
  assert.equal(s.saved_config.publication_policy.boot_restore,false,'restored boot_restore=false');
  assert.equal(s.runtime.phase,'running','publication still running');
  console.log('RESTORED revision',s.saved_revision,'boot_restore=false phase',s.runtime.phase);
  assert.equal(errors.length,0,'no page errors: '+errors.join(';'));
  console.log('REQ011_ENTRY_BROWSER_PASS');
 }finally{await browser.close();}
})().catch(e=>{console.error('FAIL',e.message);process.exit(1)});
