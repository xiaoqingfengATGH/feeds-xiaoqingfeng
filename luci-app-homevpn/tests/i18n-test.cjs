/* No RPC calls: test presentation-only localization. */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const src = fs.readFileSync(path.join(root, 'htdocs/luci-static/resources/view/homevpn/overview.js'), 'utf8');
const poPath = path.join(root, 'po/zh_Hans/homevpn.po');
assert.ok(fs.existsSync(poPath), 'Chinese catalog must ship');
const parse = p => Object.fromEntries([...fs.readFileSync(p, 'utf8').matchAll(/^msgid (".*")\r?\nmsgstr (".*")/gm)].map(m => [JSON.parse(m[1]), JSON.parse(m[2])]));
const po = parse(poPath), pot = parse(path.join(root, 'po/templates/homevpn.pot'));
const ids = [...new Set([...src.matchAll(/_\('((?:\\.|[^'\\])*)'\)/g)].map(m => vm.runInNewContext("'"+m[1]+"'")))].sort();
assert.deepEqual(Object.keys(po).filter(Boolean).sort(), ids);
assert.deepEqual(Object.keys(pot).filter(Boolean).sort(), ids);
for (const id of ids) {
 assert.equal(id.trim(), id, 'No edge whitespace: '+id);
 assert.ok(po[id], 'Untranslated: '+id);
 assert.equal((id.match(/%s/g)||[]).length, (po[id].match(/%s/g)||[]).length, 'Format: '+id);
}
assert.match(src, /E\('h2', \{\}, _\('HomeVPN'\)\),\s*E\('div', \{ 'class': 'cbi-map-descr' \},/,
 'Page description must use the theme div.cbi-map-descr contract, not a section description');
assert.equal((src.match(/class': 'cbi-map-descr'/g)||[]).length, 1, 'Exactly one page description');
assert.equal(po['HomeVPN'], 'HomeVPN');
const dirtyMessage = 'Settings have unsaved changes. Save and apply first; deployed certificate details remain unchanged.';
const exactDirtyChinese = '设置已修改，点击"保存并应用"保存，证书操作耗时较长（大概10秒），点击后请稍等页面刷新；已部署证书信息保持不变。';
assert.equal(po[dirtyMessage], exactDirtyChinese);
const dirtyUpdater = src.match(/pkiDraft\.textContent = pkiDirty\(\) \? _\('((?:\\.|[^'\\])*)'\) : '';/);
assert.ok(dirtyUpdater, 'Actual draft updater must use the localized dirty message');
assert.equal(vm.runInNewContext("'" + dirtyUpdater[1] + "'"), dirtyMessage);
const dirtyContext = { pkiDraft: {}, pkiDirty: () => true, _: s => po[s] || s };
vm.runInNewContext(dirtyUpdater[0], dirtyContext);
assert.equal(dirtyContext.pkiDraft.textContent, exactDirtyChinese);
dirtyContext.pkiDirty = () => false;
vm.runInNewContext(dirtyUpdater[0], dirtyContext);
assert.equal(dirtyContext.pkiDraft.textContent, '');
console.log('PASS: exact Chinese dirty warning, ASCII double quotes, localized actual updater and clean-state clearing');
const serverDescription = "The server address must exactly match a certificate SAN; wildcard certificates are not supported. Self-signed mode prepares a local root CA and issues the server certificate only after an address is saved. Import uses your uploaded files. ACME uses a locally issued certificate (RSA is recommended for iOS).";
assert.equal(po[serverDescription], "服务器地址是客户端连接的域名或公网 IP，必须与证书中的某个 SAN 完全一致。家庭宽带IP会变，所以必须使用域名，结合本固件的DDNS实现动态更新域名地址。现代设备要求连接的VPN服务器必须有证书，本服务仅支持单一域名证书，不要使用通配符证书( 例如证书的 SAN 为 *.example.com）。证书模式支持三种：自签名证书，HomeVPN生成 CA 和服务器证书；导入，使用您上传的证书文件；ACME ，使用ACME申请的证书（推荐，兼容iOS设备要求使用RSA格式证书，申请时请注意）。");
const serverSection = src.slice(src.indexOf("_('Server settings')"));
const serverLiteral = serverSection.match(/E\('p', \{ 'class': 'cbi-section-descr' \},\s*_\('((?:\\.|[^'\\])*)'\)/)[1];
assert.equal(vm.runInNewContext("'" + serverLiteral + "'"), serverDescription);
assert.ok(!Object.hasOwn(po, "Server address is what clients dial (DDNS name or public IP) — it must EXACTLY equal one SAN of the certificate: strongSwan never matches wildcard SANs (*.example.com), so an address only wildcard-covered fails every connection. Self-signed mode generates a CA + server certificate on first boot; import mode uploads your own certificate files; ACME mode syncs a certificate issued by the Let's Encrypt app (on sync failure the previously deployed certificate keeps serving — it never silently switches to self-signed)."), "Obsolete server description removed");
assert.equal(po['Homelede customized IKEv2 + EAP-MSCHAPv2 VPN server, supporting the default clients on iOS, Android, Windows and MacOS for convenient device access to your home network.'], 'Homelede 定制的 IKEv2＋EAP-MSCHAPv2 VPN服务器，支持iOS、Android、Windows、MacOS默认客户端接入，实现设备便捷接入家庭网络。');
assert.equal(po['strongSwan (charon)'], 'VPN Server 服务进程(charon)');
assert.equal(po["ACME (Let's Encrypt)"], '使用ACME管理的证书');
assert.equal(po['IP allocation mode (applied)'], 'VPN客户端IP分配模式');
assert.equal(po['Client IP allocation'], 'VPN客户端IP分配模式');
assert.ok(src.includes("E('div', { 'class': 'cbi-value-field' }, [ sIpMode, modeHint ])"), 'Mode explanation follows its select inside the same field');
assert.ok(!src.includes('\n\t\t\tmodeHint,'), 'Mode explanation is not above its control');
const context = vm.createContext({rpc:{declare:()=>()=>{}}, view:{extend:x=>x}, _:s=>po[s]||s});
vm.runInContext('String.prototype.format = function(...args) { let i=0; return this.replace(/%s/g,()=>String(args[i++])); };', context);
vm.runInContext('(function(){'+src+';})()', context);
// Obtain helper without executing render or any RPC.
vm.runInContext(src.slice(0,src.indexOf('return view.extend')), context);
assert.equal(vm.runInContext('backendMessage("user \'alice\' not found")',context), '未找到用户“alice”');
assert.equal(vm.runInContext('backendMessage("pool_start \'bad\' is not a valid IPv4 address")',context), '地址池起始地址“bad”不是有效的 IPv4 地址');
assert.equal(vm.runInContext('backendMessage("invalid domain; keeping previous settings")',context), '域名无效；保留之前的设置');
assert.equal(vm.runInContext('backendMessage("unknown external diagnostic")',context), 'unknown external diagnostic');
assert.equal(JSON.parse(fs.readFileSync(path.join(root,'root/usr/share/luci/menu.d/luci-app-homevpn.json')) )['admin/vpn/homevpn'].title,'HomeVPN');
// Execute the actual status-row construction without RPC or rendering settings.
const statusCode = src.slice(src.indexOf('\t\tvar modeLabel ='), src.indexOf('\t\tvar sBox ='));
const modeLabelsCode = src.match(/\t\tvar modeLabels = .*;/)[0];
const exactDhcp = '通过本机DHCP获取地址';
context.E = (tag, attrs, children) => ({tag, attrs, children});
function statusRow(applied, selected, pool) {
 context.st = {applied_mode:applied, ip_mode:selected, applied_pool:pool};
 vm.runInContext(modeLabelsCode + statusCode, context);
 return context.appliedModeRow;
}
const text = node => node == null ? '' : typeof node === 'string' ? node : Array.isArray(node) ? node.map(text).join('') : text(node.children);
for (const pool of ['dhcp (real LAN leases via local dnsmasq)', '', 'unexpected detail']) {
 const row = statusRow('dhcp', 'dhcp', pool);
 assert.equal(text(row.children[1]), exactDhcp);
 assert.ok(!text(row.children[1]).includes('DHCP（本机 dnsmasq）'));
}
for (const mode of ['lansubnet', 'subnet', 'unknown', '']) {
 const row = statusRow(mode, mode, '192.168.224.50-192.168.224.99');
 assert.equal(text(row.children[1]), (context.modeLabels[mode] || mode || '—') + ' — 192.168.224.50-192.168.224.99');
 const empty = statusRow(mode, mode, '');
 assert.equal(text(empty.children[1]), context.modeLabels[mode] || mode || '—');
}
for (const [applied, selected] of [['dhcp','subnet'], ['subnet','dhcp']]) {
 const row = statusRow(applied, selected, 'pool');
 assert.equal(row.attrs.style, vm.runInContext("hintColors('error')", context));
 assert.equal(row.children[1].children[0].tag, 'strong');
 if (applied === 'dhcp') assert.equal(text(row.children[1].children[0]), exactDhcp);
 assert.equal(text(row.children[1].children[2]), po['Selected %s is NOT applied — the precheck refused it (reason below). The highlighted mode is what clients get right now.'].replace('%s',context.modeLabels[selected]));
}
console.log(`PASS: ${ids.length} synchronized translated messages, placeholders, title, exact description, backend presentation and fallback; exact DHCP status, other modes and divergence warning`);

// Exercise the real dynamic hint updater with lightweight DOM stubs.
context.sIpMode = {value:'dhcp'}; context.modeHint = {};
for (const key of ['sPs','sPe','sPc','sMasq']) context[key] = {};
const hintCode = src.slice(src.indexOf('\t\tfunction updModeHint()'), src.indexOf('\t\tsIpMode.addEventListener'));
vm.runInContext(hintCode + '\nupdModeHint();', context);
assert.equal(context.modeHint.textContent, "通过本机DHCP获取地址，VPN客户端获得与本地设备相同网段的IP，此模式依赖本机dnsmasq，本机负责局域网DHCP服务时才可以使用。支持 mDNS/AirPlay。此模式支持为VPN用户分配固定 IP，在\"EAP 账户\"区域\"固定 IP（DHCP 模式）\"列设置。当防火墙开启流量卸载时此模式不可用。");
for (const mode of ['lansubnet','subnet']) {
 context.sIpMode.value = mode; vm.runInContext('updModeHint()',context);
 assert.ok(context.modeHint.textContent.length > 20);
}
console.log('PASS: exact DHCP dynamic hint including ASCII double quotes');

context.sIpMode.value = 'lansubnet'; vm.runInContext('updModeHint()', context);
assert.equal(context.modeHint.textContent, '从局域网子网划出地址池（默认 .50-.99）—— 适合旁路由使用，此时DHCP是主路由负责，注意让主路由DHCP分配IP范围避开本机为VPN客户端预留的范围');
const poolCode = src.slice(src.indexOf('\t\tvar poolLan ='), src.indexOf('\t\tvar sPc ='));
const remoteCode = src.match(/\t\tvar sRemote = .*;/)[0];
for (const [net, prefix] of [
 ['192.168.224.0/24', '192.168.224'], ['10.20.30.0/24', '10.20.30'],
 ['', '192.168.1'], [undefined, '192.168.1'], ['garbage', '192.168.1'],
 ['999.168.1.0/24', '192.168.1'], ['192.168.224.999/24', '192.168.1'],
 ['10.20.0.0/16', '192.168.1'], ['192.168.224.0/25', '192.168.1']
]) {
 for (const saved of [{}, {pool_start:'192.168.224.60',pool_end:'192.168.224.80'}]) {
  context.st = {lan_net:net}; context.set = {...saved};
  vm.runInContext(poolCode + remoteCode, context);
  for (const [key, option, suffix] of [['sPs','pool_start','.50'], ['sPe','pool_end','.99']]) {
   assert.equal(context[key].attrs.style, context.sRemote.attrs.style);
   assert.equal(context[key].attrs.style, 'width:16em');
   assert.equal(context[key].attrs.placeholder, '示例：' + prefix + suffix);
   assert.equal(context[key].attrs.value, saved[option] || '');
  }
  assert.deepEqual(context.set, saved, 'Placeholder generation must not mutate settings');
 }
}
console.log('PASS: exact lansubnet hint; pool widths match sRemote; full IPv4 .50/.99 examples, CIDR validation/fallback, saved and empty values preserved');
