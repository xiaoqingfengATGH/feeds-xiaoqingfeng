'use strict';
const fs=require('fs'),assert=require('assert/strict'),path=require('path');
const src=fs.readFileSync(path.join(__dirname,'../htdocs/luci-static/resources/view/homevpn/overview.js'),'utf8');
const adapter=fs.readFileSync(path.join(__dirname,'acme-discovery-ui-test.cjs'),'utf8');
const {Node,E,all}=new Function(adapter.slice(adapter.indexOf('class Node'),adapter.indexOf('const tick'))+';return {Node,E,all};')();
String.prototype.format=function(...a){let i=0;return this.replace(/%s/g,()=>a[i++]);};
for(const cert_mode of ['acme','selfsigned','import']){
 for(const applied_mode of ['dhcp','lansubnet']){
  const calls=[];
  const rpc={declare:d=>(...args)=>{calls.push([d.method,args]);return Promise.resolve({ok:true});}};
  const ui={createHandlerFn:(_,fn)=>fn,addNotification(){}};
  const view=new Function('view','rpc','ui','E','_','document','location',src)({extend:x=>x},rpc,ui,E,x=>x,{createTextNode:x=>x},{hash:''});
  const root=view.render([{applied_mode},{users:[{name:'<img src=x onerror=alert(1)>',fixed_ip:'192.168.1.60'}]},{cert_mode}]);
  const nodes=all(root), guide=nodes.find(n=>n.attrs.id==='homevpn-client-guide');
  assert(guide,'client guide exists');assert.equal(guide.tag,'details');assert(!Object.hasOwn(guide.attrs,'open'),'initially collapsed');
  assert.equal(guide.children[0].tag,'summary');
  const text=all(guide).flatMap(n=>n.children.filter(x=>typeof x==='string')).join(' ');
  const po=fs.readFileSync(path.join(__dirname,'../po/zh_Hans/homevpn.po'),'utf8');
  const translations=Object.fromEntries([...po.matchAll(/msgid ("(?:\\.|[^"\\])*")\r?\nmsgstr ("(?:\\.|[^"\\])*")/g)].map(m=>[JSON.parse(m[1]),JSON.parse(m[2])]));
  const actual=all(guide).filter(n=>n.tag==='p'||n.tag==='strong').map(n=>n.children.map(x=>translations[x]??x).join(''));
  assert.deepEqual(actual,["根据\"服务器设置\"中\"证书模式\"的不同，接入的步骤如下：", "证书模式： ACME （推荐）", "ACME申请的证书的CA是主流客户端信任CA之一，因此无需在客户端安装 CA 证书。", "接入时，使用设备自带的 IKEv2 客户端（手机或系统内置），手动填写服务器域名、远程标识（与服务器域名相同）、EAP 用户名和密码即可连接。", "也可下载配置文件导入（每个VPN用户一个配置）：苹果系列下载 .mobileconfig 安卓提供.sswan，不同 Android 设备的系统客户端支持情况可能不同，建议使用 strongSwan App。", "再次提示：为兼容 iPhone/iPad 设备，使用ACME申请证书时候，请在证书\"高级设置\"中\"密钥长度\"下拉框中选择 RSA开头的选项，即可生成RSA证书。", "证书模式：自签名（自动生成）", "此模式下，HomeVPN会为您生成证书，并使用生成的CA证书自签名。由于自签名证书不会被主流客户端信任，因此在连接前需要在客户端导入并信任 HomeVPN 的 CA 证书。", "推荐使用本页面提供的配置文件（每个VPN用户一个配置，点击用户名后面的按钮下载）", "苹果设备(以iPhone/iPad为例)：下载，用微信或者其他方式传输到设备，保存到\"文件\"中，然后在\"文件\"中点击下载的.mobileconfig文件，系统会提示到\"设置\"中开启信任。", "随后请进入“设置 → 通用 → 关于本机 → 证书信任设置”，信任自签名的CA证书。本VPN连接信息会出现在系统VPN中，在这里连接即可。", "Android：下载 .sswan 文件并使用 strongSwan App 导入，CA 将随配置导入 App，无需额外安装到系统证书存储。导入或连接时输入账户密码；若无法直接打开文件，请使用 App 内的文件选择器。", "其他客户端：先下载并安装 CA 证书，并信任证书，再手动配置 IKEv2 连接。", "推荐使用ACME申请证书，免费迅速，还可以规避额外的信任步骤。"],'Every approved paragraph, punctuation and space preserved');
  assert(!text.includes('SSL/TLS'));
  const buttons=nodes.filter(n=>n.tag==='button').map(n=>n.children.join(''));
  for(const label of ['Android .sswan','iOS/macOS profile','Download CA certificate','Delete','Add','Random'])assert(buttons.includes(label),label);
  assert.equal(buttons.includes('Set'),applied_mode==='dhcp');assert.equal(buttons.includes('Clear'),applied_mode==='dhcp');
  assert(nodes.some(n=>n.children.includes('<img src=x onerror=alert(1)>')));assert(!nodes.some(n=>n.tag==='img'));
  assert.deepEqual(calls,[],'Rendering help must not call any RPC');
 }
}
const block=src.slice(src.indexOf("E('details', { 'id': 'homevpn-client-guide'"),src.indexOf("E('div', { 'class': 'table cbi-section-table' }, rows)"));
assert(!/innerHTML|outerHTML|insertAdjacentHTML/.test(block));
console.log('PASS: guide collapsed, both certificate paths in all modes, verbatim bilingual paragraphs, text-only DOM, no render RPC, account controls preserved');
