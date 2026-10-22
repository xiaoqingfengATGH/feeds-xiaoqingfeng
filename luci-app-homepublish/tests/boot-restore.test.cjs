const {test}=require('node:test');const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const src=fs.readFileSync(path.resolve(__dirname,'../htdocs/luci-static/resources/view/homepublish/entry.js'),'utf8');
const product=fs.readFileSync(path.resolve(__dirname,'../htdocs/luci-static/resources/view/homepublish/product.js'),'utf8');
// REQ-011: boot_restore must be a visible form control in the entry editor, not just collected data.
test('entry editor renders a boot_restore flag in the run-policy section',()=>{
 assert.ok(/form\.Flag\s*,\s*'boot_restore'/.test(src),'entry.js must define form.Flag boot_restore');
 const m=/form\.Flag\s*,\s*'boot_restore'\s*,\s*'([^']+)'/.exec(src);
 assert.equal(m && m[1],'重启后恢复发布','boot_restore flag label');
 assert.ok(src.includes("o.depends('mode','continuous');"),'boot_restore only applies to continuous mode');
 const desc=/form\.Flag\s*,\s*'boot_restore'[\s\S]{0,400}?o\.description='([^']*)'/.exec(src);
 assert.ok(desc && /重启后自动恢复/.test(desc[1]),'boot_restore description explains reboot recovery');
});
test('collectConfig keeps boot_restore semantics for continuous and temporary modes',()=>{
 assert.ok(product.includes("boot_restore:p.mode==='temporary'?false:(p.boot_restore==='1' || p.boot_restore===true)"),'collect must keep temporary=false and read form flag');
 assert.ok(/boot_restore:policy\.boot_restore\?/.test(fs.readFileSync(path.resolve(__dirname,'../htdocs/luci-static/resources/view/homepublish/entry.js'),'utf8')),'entry.js seeds draft from saved policy');
});
test('init script registers procd respawn for the idle controller',()=>{
 const init=fs.readFileSync(path.resolve(__dirname,'../../homepublish/files/etc/init.d/homepublish'),'utf8');
 assert.ok(/procd_set_param respawn/.test(init),'init must respawn the idle controller daemon');
 assert.ok(/procd_set_param command \/usr\/bin\/lua \/usr\/share\/homepublish\/product-daemon\.lua/.test(init),'daemon command unchanged');
 assert.ok(!/respawn_threshold[^=]*=\s*\"?\$\{/.test(init),'no interpolated respawn parameters');
});

test('init shutdown path does not latch manual stop (boot_restore survives reboot)',()=>{
 const init=fs.readFileSync(path.resolve(__dirname,'../../homepublish/files/etc/init.d/homepublish'),'utf8');
 assert.ok(/^shutdown\(\)\s*\{/m.test(init),'init must override shutdown()');
 const body=/^shutdown\(\)\s*\{([^}]*)\}/m.exec(init);
 assert.ok(body && /procd_kill/.test(body[1]),'shutdown kills processes via procd_kill');
 assert.ok(!/product-device-cli/.test(body[1]),'shutdown must NOT invoke the stop CLI (no manual latch)');
 assert.ok(!/action.:..stop/.test(body[1]),'shutdown must not send action stop');
});
