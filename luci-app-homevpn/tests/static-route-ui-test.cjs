'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const root=path.resolve(__dirname,'..'),src=fs.readFileSync(path.join(root,'htdocs/luci-static/resources/view/homevpn/overview.js'),'utf8');
const code="var routeCard = E('div');\n"+src.slice(src.indexOf('/* The route guidance'),src.indexOf('\n\t\t\trouteCard.appendChild(routeContent);'))+"\nrouteCard.appendChild(routeContent);\n";
const hint=src.slice(src.indexOf('\t\tfunction updModeHint()'),src.indexOf('\t\tsIpMode.addEventListener'));
assert.ok(!/call\w+\(|saveSettings|regen|innerHTML/.test(code));
assert.ok(src.indexOf('\n\t\t\trouteCard,')>src.indexOf("_('NAT masquerade (side-router compatibility)')), E("));
function E(tag,attrs={},children=[]){if(typeof attrs==='string'){children=attrs;attrs={};}return {tag,attrs,children:Array.isArray(children)?children:[children],style:{display:attrs.style?.includes('display:none')?'none':''},appendChild(c){this.children.push(c)},focus(){this.focused=true},select(){this.selected=true}};}
const text=n=>typeof n==='string'?n:(n.children||[]).map(text).join('');
async function main(){
for(const masq of ['0','1'])for(const precheck of ['ok','refused'])for(const selected of ['subnet','dhcp']){
 const st={applied_mode:'subnet',ip_mode:selected,applied_pool:'10.100.1.0/24',applied_masq:masq,precheck,suggest:'main router: destination 10.100.1.0/24 / gateway 192.168.224.247 (ip route add 10.100.1.0/24 via 192.168.224.247)'};
 const c=vm.createContext({E,_:s=>s,document:{createTextNode:s=>s},st,navigator:{},ui:{addNotification(){}},set:{pool_subnet:'10.222.0.0/16'},sIpMode:{value:selected},modeHint:{},sPs:{},sPe:{},sPc:{value:'10.222.0.0/16'},sMasq:{}});
 vm.runInContext(code+hint,c);
 assert.equal(c.commandText,'ip route add 10.100.1.0/24 via 192.168.224.247');
 assert.equal(c.routeTarget[1],'10.100.1.0/24');assert.equal(c.routeGateway[1],'192.168.224.247');
 assert.ok(text(c.routeCard).includes('Get main-router static route command (side-router mode only)'));
 assert.ok(!text(c.routeCard).includes('currently applied subnet, not the draft'));
 assert.ok(!text(c.routeCard).includes('Main-router static route (side-router scenario)'));
 for(let i=0;i<20;i++){c.routeToggle.attrs.click();assert.equal(c.routeBody.style.display,i%2===0?'':'none');}
 c.copyButton.attrs.click();assert.ok(c.commandInput.selected&&c.commandInput.focused);
 c.commandInput.selected=false;c.navigator.clipboard={writeText:()=>Promise.reject(new Error('denied'))};c.copyButton.attrs.click();await new Promise(r=>setImmediate(r));assert.ok(c.commandInput.selected);
 let copied;c.navigator.clipboard={writeText:s=>{copied=s;return Promise.resolve()}};c.copyButton.attrs.click();await new Promise(r=>setImmediate(r));assert.equal(copied,c.commandText);
 c.updModeHint();assert.equal(c.routeCard.style.display,'');assert.equal(c.sPc.value,'10.222.0.0/16');
}
for(const selected of ['subnet','dhcp']){
 const notifications=[];
 const c=vm.createContext({E,_:s=>s,st:{applied_mode:'dhcp'},sIpMode:{value:selected},modeHint:{},sPs:{},sPe:{},sPc:{},sMasq:{},ui:{addNotification:(a,node)=>notifications.push(text(node))}});vm.runInContext(code+hint,c);c.updModeHint();assert.equal(c.routeCard.style.display,selected==='subnet'?'':'none');assert.ok(text(c.routeCard).includes('Get main-router static route command (side-router mode only)'));assert.equal(c.routeBody,undefined);c.routeToggle.attrs.click();assert.deepEqual(notifications,['Apply the IP allocation settings first.']);
}
console.log('PASS route guidance: applied/failed/draft, both masq states, 20 reopens each, safe text, clipboard success/rejection/absent fallback, read-only, placement and un-applied gating');
}
main().catch(e=>{console.error(e);process.exitCode=1});
