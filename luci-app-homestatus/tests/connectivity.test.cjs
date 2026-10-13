const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'dom.test.cjs'),'utf8');
const mount=new Function('require','__dirname',source.slice(0,source.indexOf('module.exports='))+';return mountDashboard;')(require,__dirname);
test('global success colors healthy Internet and generic KPI text and dot after generated census',async()=>{
 const css=process.env.HOMESTATUS_CONNECTIVITY_BASELINE ? require('node:child_process').execFileSync('git',['show','20d8b58:luci-app-homestatus/htdocs/luci-static/resources/view/homestatus/overview.css'],{encoding:'utf8'}) : fs.readFileSync(path.join(__dirname,'../htdocs/luci-static/resources/view/homestatus/overview.css'),'utf8');
 const theme=process.env.HOMESTATUS_THEME;
 const {chromium}=require(process.env.HOMESTATUS_PLAYWRIGHT);
 const browser=await chromium.launch({channel:'msedge',headless:true});
 try {
 assert.ok(theme,'set HOMESTATUS_THEME');
 for(const [palette,expected] of [['luminousblue','rgb(112, 214, 176)'],['luminousblue-light','rgb(22, 114, 79)'],['blackgold',null],['canyon',null]]){
 const {dom,w}=await mount();try{
 w.document.body.setAttribute('data-if-palette',palette);
 const sheet=w.document.createElement('style');sheet.textContent=css;w.document.head.appendChild(sheet);
 const generated=w.document.createElement('style');generated.textContent=fs.readFileSync(path.join(theme,'htdocs/luci-static/infinityfreedom-ng/assets/css/palette-'+palette+'.min.css'),'utf8');w.document.head.appendChild(generated);
 const card=w.document.querySelector('.ngov-kpi-internet'),value=card.querySelector('.state'),dot=card.querySelector('.ngov-dot');
 const page=await browser.newPage();await page.setContent(w.document.documentElement.outerHTML);
 const colors=await page.evaluate(()=>{const card=document.querySelector('.ngov-kpi-internet'),v=card.querySelector('.state'),dot=card.querySelector('.ngov-dot');const read=()=>({text:getComputedStyle(v).color,dot:getComputedStyle(dot).backgroundColor,weight:getComputedStyle(v).fontWeight});const healthy=read(),bad={};card.classList.remove('ngov-kpi-internet');const globalHealthy=read();card.classList.add('ngov-kpi-internet');for(const tone of ['w','r','m']){v.className='ngov-kpi-v state '+tone;dot.className='ngov-dot '+tone;const scoped=read();card.classList.remove('ngov-kpi-internet');bad[tone]={scoped,unscoped:read()};card.classList.add('ngov-kpi-internet');}return {healthy,globalHealthy,bad};});
 assert.deepEqual(colors.healthy,colors.globalHealthy);
 if(expected){assert.equal(colors.healthy.text,expected);assert.equal(colors.healthy.dot,expected);assert.equal(colors.healthy.weight,'600');}else assert.notEqual(colors.healthy.text,'rgb(112, 214, 176)');
 for(const item of Object.values(colors.bad))assert.deepEqual(item.scoped,item.unscoped);await page.close();

 }finally{dom.window.close();}
 }
 }finally{await browser.close();}
});
test('Internet KPI has a dedicated stable scope without changing reachability semantics',async()=>{
 for(const [probe,tone,text] of [[{cn:{ok:true},intl:{ok:true}},'g','已接通'],[{cn:{ok:true},intl:{ok:false}},'w','部分接通'],[{cn:{ok:false},intl:{ok:false}},'w','未接通'],[{},'w','未接通']]){
 const {dom,w,intervals}=await mount({netprobe:{ok:true,result:probe}});
 try {for(let i=0;i<2;i++) {const card=w.document.querySelector('.ngov-kpi-internet');assert.ok(card,'dedicated Internet KPI class missing');assert.equal(card.querySelector('.state').textContent,text);assert.ok(card.querySelector('.state.'+tone));assert.ok(card.querySelector('.ngov-dot.'+tone));assert.equal(w.document.querySelectorAll('.ngov-kpi-internet').length,1);intervals[0].fn();await new Promise(r=>setTimeout(r,30));}}finally{dom.window.close();}
 }
});
