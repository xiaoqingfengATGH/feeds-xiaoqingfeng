const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {JSDOM}=require('jsdom');
const code=fs.readFileSync(path.resolve(__dirname,'../htdocs/luci-static/resources/view/homestatus/overview.js'),'utf8');
async function mountDashboard(extra={}){
 const dom=new JSDOM('<html><head><link href="/luci-static/resources/view/homestatus/overview.css?v=1" rel="stylesheet"></head><body><main><div id="view"><h2>Overview</h2><div class="col-12"><div class="card"><section class="cbi-section"><h3>System</h3><table id="classic"><tr><td>native status</td></tr></table></section></div></div></div></main></body></html>',{url:'http://localhost/cgi-bin/luci/admin/status/overview',runScripts:'outside-only',pretendToBeVisual:true});
 const w=dom.window, intervals=[];w.innerWidth=900;w.setInterval=(fn,ms)=>{intervals.push({fn,ms});return intervals.length;};
 w.E=function(tag,attrs,kids){const n=w.document.createElement(tag);for(const [k,v] of Object.entries(attrs||{})){if(typeof v==='function')n.addEventListener(k,v);else if(v!=null)n.setAttribute(k,String(v));}function add(k){if(Array.isArray(k))k.forEach(add);else if(k!=null)n.appendChild(k.nodeType?k:w.document.createTextNode(String(k)));}add(kids);return n;};
 const replies={board:{hostname:'fixture',model:'fixture x86'},info:{uptime:60,memory:{total:1024,available:900}},dump:{interface:[{interface:'lan',up:true,device:'br-lan','ipv4-address':[{address:'192.168.1.1',mask:24}]},{interface:'wan',up:true,device:'eth1','ipv4-address':[{address:'10.0.0.2',mask:24}]}]},status:{config:{},apps:[{id:'test',label:'test disabled',state:'disabled',restartable:false}],disks:[]},netprobe:{ok:true,result:{cn:{ok:true},intl:{ok:true}}},wol_targets:{ok:true,etherwake:true,targets:[]}};
 Object.assign(replies,extra);
 const rpc={declare:({object,method})=>()=>Promise.resolve(object==='network.device'?(extra.deviceStatus||{'br-lan':{type:'bridge',present:true,'bridge-members':['eth0']},eth0:{present:true,carrier:true}}):(replies[method]||{}))};
 w.L={loaded:true,env:{scriptname:'/cgi-bin/luci'},resource:p=>'/luci-static/resources/'+p,require:n=>Promise.resolve(n==='rpc'?rpc:{trimmed:p=>Promise.resolve(p.endsWith('_max')?'65536':'42')}),resolveDefault:(p,d)=>Promise.resolve(p).catch(()=>d)};
 w.eval(code);await new Promise(r=>setTimeout(r,100));return {dom,w,intervals,replies};
}
module.exports={mountDashboard};
test('LAN preserves conntrack capacity, conditional WiFi and DHCP link',async()=>{
 const {dom,w}=await mountDashboard({devices:{devices:['wlan0']},assoclist:{results:[{},{}]}});try{
 const preview=w.document.querySelector('.ngov-device-preview');
 assert.match(preview.textContent,/42 \/ 65536/);assert.match(preview.textContent,/WiFi/);assert.match(preview.textContent,/2 个客户端/);
 assert.ok(w.document.querySelector('a[href$="/admin/network/dhcp"]'));
 }finally{dom.window.close();}
});
test('body panel copies palette variables and retains ngov component scope',async()=>{
 const {dom,w}=await mountDashboard();try{
 w.document.querySelector('.ngov').style.setProperty('--ngov-card','rgb(1, 2, 3)');
 w.document.querySelector('.ngov-devices-open').click();const shade=w.document.querySelector('.ngov-device-shade');
 assert.ok(shade.classList.contains('ngov'));assert.equal(shade.style.getPropertyValue('--ngov-card'),'rgb(1, 2, 3)');
 }finally{dom.window.close();}
});
test('LAN preview explains upstream-inclusive counts without changing the client headline',async()=>{
 for(const includeUpstream of [true,false]){
 const fixture={getDHCPLeases:{dhcp_leases:[{macaddr:'02:00:00:00:00:01',hostname:'client',ipaddr:'192.168.1.10'}]}};
 if(includeUpstream){
 fixture.dump={interface:[{interface:'lan',up:true,device:'br-lan','ipv4-address':[{address:'192.168.1.1',mask:24}],route:[{target:'0.0.0.0',mask:0,nexthop:'192.168.1.254'}]}]};
 fixture.getHostHints={'02:00:00:00:02:01':{ipaddrs:['192.168.1.254']}};
 }
 const {dom,w}=await mountDashboard(fixture);try{
 const preview=w.document.querySelector('.ngov-device-preview'),card=preview.closest('.ngov-card');
 assert.equal(card.querySelector('.cnt').textContent,'1 台');
 assert.equal(preview.querySelector('.ngov-dfoot').textContent,includeUpstream?'概览显示 2 / 2 台（含上游）':'概览显示 1 / 1 台');
 assert.equal(preview.querySelectorAll('.ngov-device-row').length,includeUpstream?2:1);
 }finally{dom.window.close();}
 }
});
test('LAN summary uses three single-line columns and compact statistics, not detail density',async()=>{
 const {dom,w}=await mountDashboard(devices());try{
 const d=w.document,preview=d.querySelector('.ngov-device-preview');
 assert.deepEqual([...preview.querySelectorAll('th')].map(n=>n.textContent),['设备','IP 地址','状态']);
 assert.equal(preview.querySelectorAll('.ngov-device-row').length,4);
 assert.equal(preview.querySelector('.ngov-mini'),null);
 assert.ok(preview.querySelector('.ngov-device-stats'));
 for(const row of preview.querySelectorAll('.ngov-device-row'))assert.equal(row.children.length,3);
 d.querySelector('.ngov-devices-open').click();
 assert.deepEqual([...d.querySelectorAll('.ngov-device-list th')].map(n=>n.textContent),['设备','IP 地址','接入方式','状态']);
 assert.equal(d.querySelectorAll('.ngov-device-list .ngov-device-row').length,9);
 }finally{dom.window.close();}
});
const devices=()=>({getDHCPLeases:{dhcp_leases:Array.from({length:9},(_,i)=>({macaddr:`02:00:00:00:00:0${i}`,hostname:`client-${i}`,ipaddr:`192.168.1.${i+10}`}))}});
test('LAN preview limits devices to four and opens complete independent panel',async()=>{
 const {dom,w}=await mountDashboard(devices());try{
 const d=w.document;
 assert.equal(d.querySelectorAll('.ngov-device-preview tbody tr[data-device]').length,4);
 assert.equal(d.querySelector('.ngov-devscroll'),null);
 const open=d.querySelector('.ngov-devices-open');assert.ok(open);open.click();
 assert.equal(d.querySelectorAll('[role="dialog"] .ngov-device-row').length,9);
 assert.equal(d.querySelectorAll('[role="dialog"]').length,1);
 }finally{dom.window.close();}
});
test('device list is Tab reachable in the focus trap and retains focus and scroll on refresh',async()=>{
 const {dom,w,intervals}=await mountDashboard(devices());try{
 const d=w.document;d.querySelector('.ngov-devices-open').click();
 const panel=d.querySelector('[role="dialog"]'),search=panel.querySelector('input'),list=panel.querySelector('.ngov-device-list'),close=panel.querySelector('.ngov-device-close');
 const tab=(node,shiftKey=false)=>node.dispatchEvent(new w.KeyboardEvent('keydown',{key:'Tab',shiftKey,bubbles:true,cancelable:true}));
 tab(search);assert.equal(d.activeElement,list);
 assert.equal(list.tabIndex,0);assert.equal(list.getAttribute('aria-label'),'全部接入设备列表');
 tab(list);assert.equal(d.activeElement,close);
 tab(close,true);assert.equal(d.activeElement,list);
 tab(list,true);assert.equal(d.activeElement,search);
 tab(search);list.scrollTop=137;list.scrollLeft=41;
 intervals[0].fn();await new Promise(r=>setTimeout(r,30));
 assert.equal(panel.querySelector('.ngov-device-list'),list);assert.equal(d.activeElement,list);
 assert.equal(list.scrollTop,137);assert.equal(list.scrollLeft,41);
 }finally{dom.window.close();}
});
test('device search survives polling without replacing controls or list scroller',async()=>{
 const {dom,w,intervals}=await mountDashboard(devices());try{
 const d=w.document;d.querySelector('.ngov-devices-open').click();
 const panel=d.querySelector('[role="dialog"]'),search=panel.querySelector('input[type="search"]');assert.ok(search);
 search.value='CLIENT-7';search.dispatchEvent(new w.Event('input'));search.focus();
 assert.equal(panel.querySelectorAll('.ngov-device-row').length,1);
 const list=panel.querySelector('.ngov-device-list');list.scrollTop=137;
 intervals[0].fn();await new Promise(r=>setTimeout(r,30));
 assert.equal(d.querySelector('[role="dialog"]'),panel);assert.equal(panel.querySelector('input'),search);
 assert.equal(search.value,'CLIENT-7');assert.equal(d.activeElement,search);assert.equal(list.scrollTop,137);
 search.value='02:00:00:00:00:03';search.dispatchEvent(new w.Event('input'));assert.equal(panel.querySelectorAll('.ngov-device-row').length,1);
 search.value='192.168.1.18';search.dispatchEvent(new w.Event('input'));assert.equal(panel.querySelectorAll('.ngov-device-row').length,1);
 search.value='not found';search.dispatchEvent(new w.Event('input'));assert.equal(panel.querySelectorAll('.ngov-device-row').length,0);assert.match(panel.textContent,/没有匹配/);
 }finally{dom.window.close();}
});
test('device panel traps focus and restores background, page position and refreshed opener',async()=>{
 const {dom,w,intervals}=await mountDashboard(devices());try{
 const d=w.document,body=d.body;body.style.overflow='scroll';
 let restored;Object.defineProperty(w,'scrollY',{value:246,configurable:true});w.scrollTo=(x,y)=>{restored=[x,y];};
 const opener=d.querySelector('.ngov-devices-open');opener.focus();opener.click();
 const panel=d.querySelector('[role="dialog"]'),search=panel.querySelector('input'),close=panel.querySelector('.ngov-device-close');assert.ok(close);
 assert.equal(body.style.overflow,'hidden');assert.ok(d.querySelector('main').hasAttribute('inert'));assert.equal(d.activeElement,search);
 search.dispatchEvent(new w.KeyboardEvent('keydown',{key:'Tab',shiftKey:true,bubbles:true,cancelable:true}));assert.equal(d.activeElement,close);
 close.dispatchEvent(new w.KeyboardEvent('keydown',{key:'Tab',bubbles:true,cancelable:true}));assert.equal(d.activeElement,search);
 d.querySelector('.ngov-sysbtn').focus();assert.equal(d.activeElement,search);
 intervals[0].fn();await new Promise(r=>setTimeout(r,30));
 d.dispatchEvent(new w.KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}));
 assert.equal(d.querySelector('[role="dialog"]'),null);assert.equal(body.style.overflow,'scroll');assert.equal(d.querySelector('main').hasAttribute('inert'),false);assert.deepEqual(restored,[0,246]);
 assert.equal(d.activeElement,d.querySelector('.ngov-devices-open'));
 for(let i=0;i<3;i++){d.querySelector('.ngov-devices-open').click();assert.equal(d.querySelectorAll('[role="dialog"]').length,1);d.querySelector('.ngov-device-shade').click();assert.equal(d.querySelector('[role="dialog"]'),null);}
 d.querySelector('.ngov-devices-open').click();d.querySelector('.ngov-device-close').click();assert.equal(d.querySelector('[role="dialog"]'),null);
 }finally{dom.window.close();}
});
test('network grouping filter persists on refresh and keeps empty and unclassified facts',async()=>{
 const fixture=devices();fixture.dump={interface:[
 {interface:'lan',up:true,device:'br-lan','ipv4-address':[{address:'192.168.1.1',mask:24}],route:[{target:'0.0.0.0',mask:0,nexthop:'192.168.1.254'}]},
 {interface:'guest',up:true,device:'eth2','ipv4-address':[{address:'192.168.2.1',mask:24}]},
 {interface:'iot',up:false,device:'eth3','ipv4-address':[{address:'192.168.3.1',mask:24}]}]};
 fixture.deviceStatus={'br-lan':{type:'bridge',present:true,'bridge-members':['eth0']},eth0:{present:true,carrier:true},eth2:{present:true,carrier:true},eth3:{present:true,carrier:false}};
 fixture.getDHCPLeases.dhcp_leases.push({macaddr:'02:00:00:00:01:01',hostname:'guest-printer',ipaddr:'192.168.2.10'});
 fixture.getHostHints={'02:00:00:00:02:01':{ipaddrs:['192.168.1.254']},'02:00:00:00:02:02':{ipaddrs:[],ip6addrs:['fe80::beef']}};
 const {dom,w,intervals,replies}=await mountDashboard(fixture);try{
 const d=w.document;d.querySelector('.ngov-devices-open').click();const panel=d.querySelector('[role="dialog"]'),filter=panel.querySelector('select');assert.ok(filter);
 assert.match(panel.textContent,/GUEST/);assert.match(panel.textContent,/IOT/);assert.match(panel.textContent,/0\/1 口在线/);assert.match(panel.textContent,/其他 \/ 未分类/);
 filter.value='guest';filter.dispatchEvent(new w.Event('change'));assert.equal(panel.querySelectorAll('.ngov-device-row').length,1);assert.match(panel.textContent,/guest-printer/);
 replies.getDHCPLeases.dhcp_leases.push({macaddr:'02:00:00:00:01:02',hostname:'guest-new',ipaddr:'192.168.2.11'});
 const list=panel.querySelector('.ngov-device-list');list.scrollTop=77;intervals[0].fn();await new Promise(r=>setTimeout(r,30));
 assert.equal(filter.value,'guest');assert.equal(list.scrollTop,77);assert.equal(panel.querySelectorAll('.ngov-device-row').length,2);
 filter.value='iot';filter.dispatchEvent(new w.Event('change'));assert.equal(panel.querySelectorAll('.ngov-device-row').length,0);assert.match(panel.textContent,/IOT/);
 filter.value='__other';filter.dispatchEvent(new w.Event('change'));assert.equal(panel.querySelectorAll('.ngov-device-row').length,2);assert.match(panel.textContent,/WAN 上游/);assert.match(panel.textContent,/IPv6 邻居/);
 }finally{dom.window.close();}
});
test('IPv6 details use actual host hints without changing online or lease classification',async()=>{
 const hints={'02:00:00:00:AA:01':{ipaddrs:[],ip6addrs:['fe80::abcd','fd00::1234']}};
 const {dom,w}=await mountDashboard({getHostHints:hints,deviceStatus:{'br-lan':{type:'bridge',present:true,'bridge-members':['eth0']},eth0:{present:true,carrier:true},eth9:{present:true,carrier:true}}});try{
 const d=w.document;assert.match(d.querySelector('.ngov-device-preview').textContent,/暂无 DHCP 租约/);
 assert.doesNotMatch(d.querySelector('.ngov-device-preview').textContent,/fd00::1234|02:00:00:00:AA:01/);
 d.querySelector('.ngov-devices-open').click();const panel=d.querySelector('[role="dialog"]');
 assert.match(panel.textContent,/fd00::1234/);assert.match(panel.textContent,/IPv6 邻居/);assert.match(panel.textContent,/在线/);assert.match(panel.textContent,/暂无 DHCP 租约/);assert.match(panel.textContent,/未划入网络/);assert.match(panel.textContent,/eth9（已插线）/);
 const search=panel.querySelector('input');search.value='fd00::1234';search.dispatchEvent(new w.Event('input'));assert.equal(panel.querySelectorAll('.ngov-device-row').length,1);
 }finally{dom.window.close();}
});
test('empty devices and a disappearing selected group recover without losing filter or focus',async()=>{
 const {dom,w,intervals,replies}=await mountDashboard();try{
 const d=w.document;d.querySelector('.ngov-devices-open').click();const panel=d.querySelector('[role="dialog"]'),filter=panel.querySelector('select');
 assert.match(panel.textContent,/未发现接入设备/);assert.equal(filter.hidden,true);
 filter.value='lan';filter.dispatchEvent(new w.Event('change'));filter.focus();
 const original=replies.dump;replies.dump={interface:[]};intervals[0].fn();await new Promise(r=>setTimeout(r,30));
 assert.equal(filter.value,'lan');assert.equal(filter.hidden,false);assert.match(filter.textContent,/当前数据中不存在/);assert.equal(d.activeElement,filter);
 replies.dump=original;replies.getDHCPLeases={dhcp_leases:[{macaddr:'02:00:00:00:00:01',hostname:'returned',ipaddr:'192.168.1.10'}]};
 intervals[0].fn();await new Promise(r=>setTimeout(r,30));
 assert.equal(filter.value,'lan');assert.doesNotMatch(filter.textContent,/当前数据中不存在/);assert.equal(panel.querySelectorAll('.ngov-device-row').length,1);assert.match(panel.textContent,/returned/);
 }finally{dom.window.close();}
});
test('closing repeatedly removes exact document listeners and restores preexisting background attributes',async()=>{
 const {dom,w}=await mountDashboard();try{
 const d=w.document,main=d.querySelector('main');main.setAttribute('inert','prior');main.setAttribute('aria-hidden','false');w.scrollTo=()=>{};
 const active=new Map(),add=d.addEventListener.bind(d),remove=d.removeEventListener.bind(d);
 d.addEventListener=(type,fn,options)=>{if(type==='keydown'||type==='focusin')active.set(fn,type);add(type,fn,options);};
 d.removeEventListener=(type,fn,options)=>{if(type==='keydown'||type==='focusin'){assert.equal(active.get(fn),type);active.delete(fn);}remove(type,fn,options);};
 for(let i=0;i<4;i++){
 d.querySelector('.ngov-devices-open').click();assert.equal(active.size,2);
 d.querySelector('.ngov-device-close').click();assert.equal(active.size,0);
 assert.equal(main.getAttribute('inert'),'prior');assert.equal(main.getAttribute('aria-hidden'),'false');
 }
 }finally{dom.window.close();}
});
test('compact summary CSS wraps statistics but not device rows without a height cap',()=>{
 const css=fs.readFileSync(path.resolve(__dirname,'../htdocs/luci-static/resources/view/homestatus/overview.css'),'utf8');
 assert.match(css,/\.ngov-device-stats\s*\{[^}]*display:\s*flex[^}]*flex-wrap:\s*wrap/);
 assert.match(css,/\.ngov-device-preview td\s*\{[^}]*white-space:\s*nowrap/);
 assert.doesNotMatch(css,/\.ngov-device-preview[^{}]*\{[^}]*(?:max-height|overflow-y):/);
});
test('wide panel CSS owns its scroll area, sticky header and mobile full screen',()=>{
 const css=fs.readFileSync(path.resolve(__dirname,'../htdocs/luci-static/resources/view/homestatus/overview.css'),'utf8');
 assert.match(css,/\.ngov-device-panel\s*\{[^}]*width:\s*min\(1120px,\s*100%\)/);
 assert.match(css,/\.ngov-device-list\s*\{[^}]*min-height:\s*0[^}]*overflow:\s*auto/);
 assert.match(css,/\.ngov-device-list th\s*\{[^}]*position:\s*sticky/);
 assert.match(css,/@media\s*\(max-width:\s*700px\)[\s\S]*\.ngov-device-panel\s*\{[^}]*height:\s*100dvh/);
 assert.match(css,/\.ngov\.ngov-device-shade\s*\{[^}]*position:\s*fixed[^}]*flex-direction:\s*row[^}]*gap:\s*0[^}]*margin:\s*0/);
 assert.match(css,/\.ngov-device-tools\s*\{[^}]*flex:\s*0 0 auto/);
 assert.match(css,/\.ngov-device-panel\s*\{[^}]*background:\s*var\(--ngov-card\)/);
 assert.match(css,/\.ngov-device-preview table\s*\{[^}]*table-layout:\s*fixed/);
});
test('real DOM mount renders cards and moves native includes without losing identity',async()=>{
 const {dom,w,intervals}=await mountDashboard();try{
 const d=w.document;assert.equal(d.querySelectorAll('.ngov').length,1);assert.equal(d.querySelectorAll('.ngov-kpi').length,5);assert.ok(d.querySelector('.ngov-rest #classic'));assert.ok(d.querySelector('.ngov-app.dis'));assert.deepEqual(intervals.map(x=>x.ms),[5000,30000]);assert.equal(d.querySelectorAll('link').length,1);
 d.dispatchEvent(new w.Event('ng-page-rendered'));assert.equal(d.querySelectorAll('.ngov').length,1);
 const classic=d.querySelector('#classic');intervals[0].fn();await new Promise(r=>setTimeout(r,30));assert.equal(d.querySelector('#classic'),classic);
 d.querySelector('.ngov-sysbtn').click();assert.ok(d.querySelector('#ngov-syspop'));d.querySelector('.ngov-syspop-x').click();assert.equal(d.querySelector('#ngov-syspop'),null);
 }finally{dom.window.close();}
});
