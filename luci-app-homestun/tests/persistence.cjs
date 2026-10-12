const {chromium}=require('C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch/homestun-browser/node_modules/playwright');
(async()=>{const b=await chromium.launch({channel:'chrome',headless:true});try{const p=await b.newPage();p.on('pageerror',e=>console.log('PAGEERROR',e.message));await p.goto('http://127.0.0.1:18991/');await p.waitForFunction(()=>window.result?.loader);console.log(await p.evaluate(()=>result));
const out=await p.evaluate(async()=>{
 const rpc=await L.require('rpc');L.probeRPCBaseURL=()=>Promise.resolve('/ubus');rpc.setBaseURL('/ubus'); const u=await L.require('uci'),v=await L.require('view.homestun.settings');await new Promise(r=>setTimeout(r,1000));
 // Real target form and real RPC, no activation.
 u.set('homestun','main','enabled','1');u.set('homestun','main','exposure_approved','1');await u.save();u.unload('homestun');
 const data=await v.load();document.getElementById('view').replaceChildren(await v.render(data));
 const sections=v.map.children;sections[0].formvalue=(id,k)=>u.get('homestun',id,k);sections[1].formvalue=(id,k)=>u.get('homestun',id,k);
 // Exercise actual map.save()/parse; flags must reflect the staged enabled config.
 await v.handleSave();return {status:v.statusNode.textContent};
});console.log(JSON.stringify(out));}finally{await b.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
