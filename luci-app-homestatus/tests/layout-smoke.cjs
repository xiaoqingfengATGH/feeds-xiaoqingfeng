/* Optional real-layout smoke. jsdom renders the actual view; isolated Edge measures it.
 * Set HOMESTATUS_PLAYWRIGHT to an installed Playwright module path; no user profile.
 * Not a live-router/theme/RPC or mobile-keyboard acceptance test. */
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require(process.env.HOMESTATUS_PLAYWRIGHT||'playwright');
const app=path.resolve(__dirname,'..');
const source=fs.readFileSync(path.join(__dirname,'dom.test.cjs'),'utf8');
const mount=new Function('require','__dirname',source.slice(0,source.indexOf('module.exports='))+';return mountDashboard;')(require,__dirname);
(async()=>{
 const browser=await chromium.launch({channel:'msedge',headless:true});
 try{
 const page=await browser.newPage({viewport:{width:1600,height:1000}}),results=[];
 for(const mode of ['upstream','wan','multi-wan']){
 const lan={interface:'lan',up:true,device:'br-lan','ipv4-address':[{address:'192.168.1.1',mask:24}]};
 const wan=i=>({interface:'wan'+(i||''),up:true,device:'eth'+(i+1),proto:'dhcp','ipv4-address':[{address:`10.0.${i}.2`,mask:24}]});
 if(mode==='upstream')lan.route=[{target:'0.0.0.0',mask:0,nexthop:'192.168.1.254'}];
 const fixture={dump:{interface:mode==='upstream'?[lan]:[lan,wan(0),...(mode==='multi-wan'?[wan(1),wan(2)]:[])]},getHostHints:{'02:00:00:00:02:01':{ipaddrs:['192.168.1.254']}},getDHCPLeases:{dhcp_leases:Array.from({length:9},(_,i)=>({macaddr:`02:00:00:00:00:0${i}`,hostname:'long-workstation-name-'+i,ipaddr:`192.168.1.${i+10}`}))},devices:{devices:['wlan0']},assoclist:{results:[{},{}]}};
 const {dom,w,intervals}=await mount(fixture);
 try{
 // Exercise the actual polling renderer before measuring the refreshed snapshot.
 intervals[0].fn();await new Promise(r=>setTimeout(r,30));
 const css=fs.readFileSync(path.join(app,'htdocs/luci-static/resources/view/homestatus/overview.css'),'utf8');
 const prefix='<style>body{margin:0;font-family:Arial;line-height:1.5}html{font-size:16px}</style><style>'+css+'</style>';
 await page.setContent(prefix+w.document.querySelector('.ngov').outerHTML);
 for(const width of [1600,1200,390])for(const scale of [16,20,24]){
 await page.setViewportSize({width,height:1000});await page.evaluate(s=>document.documentElement.style.fontSize=s+'px',scale);
 const item=await page.evaluate(({mode,width,scale})=>{const cards=[...document.querySelector('.ngov-cols').children],p=document.querySelector('.ngov-device-preview'),button=document.querySelector('.ngov-devices-open');return {mode,width,scale,heights:cards.map(c=>c.getBoundingClientRect().height),previewScroll:p.scrollHeight>p.clientHeight,overflow:getComputedStyle(p).overflow,rows:[...p.querySelectorAll('[data-device]')].map(r=>r.getBoundingClientRect().height),pageOverflow:document.documentElement.scrollWidth>width,openerVisible:button.getBoundingClientRect().height>0};},{mode,width,scale});
 assert.equal(item.previewScroll,false);assert.equal(item.overflow,'visible');assert.equal(item.pageOverflow,false);assert.equal(item.openerVisible,true);assert.equal(item.rows.length,4);
 if(width>1100)assert.ok(Math.abs(item.heights[1]-item.heights[0])<1,JSON.stringify(item));
 else assert.ok(Math.abs(item.heights[1]-item.heights[0])>1,'Single-column cards retain independent content heights: '+JSON.stringify(item));
 results.push(item);
 }
 w.document.querySelector('.ngov-devices-open').click();
 await page.setContent(prefix+w.document.querySelector('.ngov-device-shade').outerHTML);
 for(const width of [1600,390]){
 await page.setViewportSize({width,height:1000});
 const panel=await page.evaluate(()=>{const p=document.querySelector('.ngov-device-panel'),r=p.getBoundingClientRect();return {width:r.width,height:r.height,rows:p.querySelectorAll('[data-device]').length};});
 assert.ok(panel.width>=(width===1600?1100:390));assert.ok(panel.height>=(width===1600?770:1000));assert.ok(panel.rows>=9);
 }
 }finally{dom.window.close();}
 }
 console.log(JSON.stringify(results,null,2));console.log('PASS: 27 real-layout measurements; 6 independent panel dimensions');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
