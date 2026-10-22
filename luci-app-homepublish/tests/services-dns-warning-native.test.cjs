/* Native Save/Apply renders structured DNS warnings without claiming DNS success. */

/* REQ-012 prerequisite guard: this file is a real-device/browser acceptance
 * script, not a self-contained unit test. When the device LuCI (HP_DEVICE_URL,
 * default http://192.168.1.2) or the local playwright install is unreachable,
 * skip gracefully so `node --test` stays green offline. */
{
 const device=(process.env.HP_DEVICE_URL||'http://192.168.1.2').replace(/\/$/,'');
 const pw=process.env.HP_PLAYWRIGHT||process.env.LOCALAPPDATA+'/hermes/cache/scratch/hp-p2-browser-deps/node_modules/playwright';
 let ok=true;
 try{require.resolve(pw);}catch(e){ok=false;}
 if(ok){try{require('node:child_process').execSync('curl -s -m 2 -o /dev/null '+device,{stdio:'ignore'});}catch(e){ok=false;}}
 if(!ok){console.log('SKIP: device LuCI ('+device+') or playwright ('+pw+') unavailable; this is a real-device acceptance script.');process.exit(0);}
}
const fs=require('node:fs'),path=require('node:path');
let code=fs.readFileSync(path.join(__dirname,'upstream-tls-form-probe.cjs'),'utf8');
code=code.replace("(async()=>{let browser,server;try{", "let writes=[],payload;\n(async()=>{let browser,server;try{");
const start=code.indexOf(" if(req.method==='POST')"),end=code.indexOf(' const local=',start);
code=code.slice(0,start)+`
 if(req.method==='POST'){
  let b='';for await(const c of req)b+=c;const raw=JSON.parse(b);
  const reply=q=>{const p=q.params||[],m=p[2];let data={};
   if(p[1]==='homepublish'){
    if(m==='status')data={saved_config:payload||config,saved_revision:payload?2:1,desired_state:{state:'enabled'},runtime:{phase:'running',active_verified:true,cleanup:'confirmed'}};
    else if(m==='certificates')data={certificates:[]};else if(m==='ddns_profiles')data={available:false,profiles:[]};
    else if(m==='validate'){payload=p[3].config;data={valid:true,config:payload};}
    else if(m==='save'){writes.push(m);data={saved_revision:2};}
    else if(m==='apply'){writes.push(m);data={ddns:{results:[{ok:false,hostname:'same.example.test'}],warnings:[{hostname:'same.example.test',error:'所选账户未启用需要的地址类型，请检查 ddns-go 设置。'}]}};}
    else throw Error('unexpected RPC '+m);
   }else if(m==='get')data={values:{}};else if(m==='changes')data={changes:{}};
   return {jsonrpc:'2.0',id:q.id,result:[0,data]};
  };res.setHeader('Content-Type','application/json');return res.end(JSON.stringify(Array.isArray(raw)?raw.map(reply):reply(raw)));
 }
`+code.slice(end);
const testStart=code.indexOf(" await page.getByRole('button',{name:'Edit'"),testEnd=code.indexOf(' }finally{',testStart);
code=code.slice(0,testStart)+`
 await page.locator('#hp-save-apply').click();
 await page.waitForFunction(()=>document.querySelector('#hp-message').textContent.includes('部分域名未能设置自动更新'));
 assert.equal(await page.locator('#hp-message').textContent(),'服务已应用，部分域名未能设置自动更新：same.example.test（请先在 ddns-go 中启用所选地址类型）');
 assert.equal(await page.locator('#hp-save-apply').isDisabled(),false);
 assert.deepEqual(writes,['save','apply']);assert.deepEqual(errors,[]);
 await page.evaluate(async()=>{const api=await L.require('view.homepublish.product'),ui=await L.require('ui');api.actionGates=()=>({apply:{allowed:true}});ui.addNotification=(title,node)=>window.dialogOutcome=node.textContent;const state=await api.status();api.actionDialog(document.body,state,'apply',()=>window.dialogUpdated=true,e=>window.dialogFailed=String(e));});
 await page.locator('#hp-edit-submit').click();await page.waitForFunction(()=>window.dialogUpdated && window.dialogOutcome);assert.ok((await page.evaluate(()=>window.dialogOutcome)).includes('部分域名未能设置自动更新'));assert.equal(await page.evaluate(()=>window.dialogFailed),undefined);
 console.log(JSON.stringify({nativeWarningVisible:true,noDnsSuccessClaim:true,editorUsable:true,productionWrites:false}));
`+code.slice(testEnd);
const Module=require('node:module'),m=new Module(__filename,module);m.filename=__filename;m.paths=module.paths;m._compile(code,__filename);
