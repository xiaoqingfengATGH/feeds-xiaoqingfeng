const {chromium}=require(process.env.HP_PLAYWRIGHT || 'D:/DevPortal/homelede/artifacts/palette-switch-cache/test-deps/node_modules/playwright');
const {execFileSync}=require('node:child_process');
const http=require('node:http');
const assert=require('node:assert/strict');
const ssh=cmd=>execFileSync('ssh',['-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','-p','222','root@127.0.0.1',cmd],{encoding:'utf8',timeout:45000});
const call=(o,m,a={})=>{const out=ssh(`ubus call ${o} ${m} '${JSON.stringify(a).replace(/'/g,"'\\''")}'`);return out.trim()?JSON.parse(out):null;};
(async()=>{let server,browser,sid;try{
sid=call('session','create',{timeout:300}).ubus_rpc_session;
call('session','grant',{ubus_rpc_session:sid,scope:'ubus',objects:[['homepublish','status'],['homepublish','certificates'],['uci','get']]});
/* rpcd uci 插件二层 ACL：scope 'uci' + 配置名 + read */
call('session','grant',{ubus_rpc_session:sid,scope:'uci',objects:[['luci','read']]});
call('session','grant',{ubus_rpc_session:sid,scope:'ubus',objects:[['uci','changes']]});
assert.equal(call('session','access',{ubus_rpc_session:sid,scope:'ubus',object:'uci',function:'get'}).access,true,'uci get granted');
server=http.createServer(async(req,res)=>{try{
if(req.url==='/certificates'||req.url==='/'){res.setHeader('Content-Type','text/html');res.end(`<!doctype html><html><body><div id="maincontent"><div id="view"></div></div><script>window._=s=>s;window.cbi_init=()=>{};</script><script src="/luci-static/resources/cbi.js"></script><script src="/luci-static/resources/luci.js"></script><script>window.L=Object.create(LuCI.prototype);Object.assign(L.env,{base_url:'/luci-static/resources',resource:'/luci-static/resources',scriptname:'/cgi-bin/luci',cgi_base:'/cgi-bin',requestpath:[],documentroot:'/www',ubuspath:'/ubus',sessionid:'${sid}',apply_display:0});L.loaded=true;window.result={};L.probeRPCBaseURL().then(()=>L.require('ui')).then(()=>L.require('view.homepublish.certificates')).then(v=>v.load().then(d=>v.render(d))).then(n=>{document.querySelector('#view').replaceChildren(n);L.Poll.start();result.loader='PASS';}).catch(e=>{result.loader='FAIL';result.error=e.message;});</script></body></html>`);return;}
let chunks=[];for await(const chunk of req)chunks.push(chunk);const data=Buffer.concat(chunks);
const upstream=await fetch('http://127.0.0.1:1081'+req.url,{method:req.method,headers:{'Content-Type':'application/json'},...(req.method==='POST'?{body:data}:{})});
res.statusCode=upstream.status;res.setHeader('Content-Type',upstream.headers.get('content-type')||'text/javascript');res.end(Buffer.from(await upstream.arrayBuffer()));
}catch(e){res.statusCode=500;res.end(e.message);}});
await new Promise(r=>server.listen(18996,'127.0.0.1',r));
browser=await chromium.launch({channel:'chrome',headless:true});
const page=await browser.newPage(),errors=[];
page.on('pageerror',e=>errors.push(e.message));
await page.goto('http://127.0.0.1:18996/certificates');
await page.waitForFunction(()=>window.result.loader,{timeout:20000});
assert.equal(await page.evaluate(()=>result.loader),'PASS',await page.evaluate(()=>result.error));
await page.waitForSelector('tr.cbi-section-table-row',{timeout:20000});
const dbg=await page.evaluate(async()=>{try{const r=await window.L.Request.post(L.env.ubuspath+'/call',{data:JSON.stringify({jsonrpc:'2.0',id:1,method:'call',params:[L.env.sessionid,'homepublish','certificates',{}]})});return {status:r.status,text:(await r.text()).slice(0,400)};}catch(e){return {error:e.message};}});
console.log('RPC-DEBUG:',JSON.stringify(dbg));
console.log('PAGE-ERRORS:',JSON.stringify(errors));
/* 造数：备份 state → save default=acme:home.iwonderful.top(RSA) → reload 验证已用靠前 → finally 还原 */
ssh('cp -a /etc/homepublish/product /tmp/hp-cert-probe-backup');
const saveOut=call('homepublish','save',{expected_revision:0,config:{schema_version:1,default_certificate_ref:'acme:home.iwonderful.top',services:[],access_profile:{methods_allowed:['manual_ipv4'],listeners:[{family:'ipv4',address:'192.168.220.48',interface:'wan',zone:'wan',protocol:'tcp',internal_port:49284,external_port:49284}]},publication_policy:{mode:'continuous',boot_restore:false}}});
assert.equal(saveOut.error,undefined,'probe save failed: '+JSON.stringify(saveOut));
console.log('probe saved default ref:', saveOut.saved_config && saveOut.saved_config.default_certificate_ref);
await page.reload();
await page.waitForFunction(()=>window.result.loader,{timeout:20000});
assert.equal(await page.evaluate(()=>result.loader),'PASS',await page.evaluate(()=>result.error));
await page.waitForSelector('tr.cbi-section-table-row',{timeout:20000});
const rows=await page.$$eval('tr.cbi-section-table-row',rs=>rs.map(r=>Array.from(r.querySelectorAll('td')).map(td=>td.textContent.trim())));
console.log('ROWS:');
rows.forEach((r,i)=>console.log(` [${i}] `+r.join(' | ')));
const texts=rows.map(r=>r.join(' | '));
assert.equal(rows.length,2,'expect 2 cert rows (RSA+ECC independent), got '+rows.length);
assert.ok(texts.some(t=>t.includes('RSA')),'RSA row present');
assert.ok(texts.some(t=>t.includes('ECC')),'ECC row present');
assert.ok(texts.every(t=>t.includes('有效')||t.includes('已过期')||t.includes('未生效')),'Chinese status labels, got: '+texts.join(' ; '));
assert.ok(texts.every(t=>!t.includes('免责')&&!t.includes('不代表')&&!t.includes('不显示私钥')),'no disclaimer copy');
/* RSA 已被入口默认使用 → RSA 行必须排第一 */
assert.ok(texts[0].includes('RSA')&&texts[0].includes('入口默认'),'used-first: RSA row first with 入口默认 usage, got: '+texts[0]);
assert.ok(texts[1].includes('ECC')&&texts[1].includes('未被使用'),'unused ECC second, got: '+texts[1]);
assert.ok(texts.every(t=>!/Edit/.test(t)),'readonly rows must have no Edit buttons: '+texts.join(' ; '));
assert.equal((await page.textContent('.cbi-map-descr')).trim(),'列出可使用的证书列表（来自ACME）','map description');
const desc=await page.textContent('.cbi-map-descr').catch(()=>'' ) || '';
assert.ok(!desc.includes('不代表')&&!desc.includes('私钥'),'map description user-facing');

assert.deepEqual(errors,[]);
console.log('CERTIFICATE-TAB PASS: 2 rows RSA/ECC, Chinese status, no disclaimers, sorted used-first');
}finally{
try{ssh('test ! -e /tmp/hp-cert-probe-backup || { rm -rf /etc/homepublish/product; cp -a /tmp/hp-cert-probe-backup /etc/homepublish/product; rm -rf /tmp/hp-cert-probe-backup; }');}catch(e){console.error('RESTORE FAILED:',e.message);}
if(browser)await browser.close();if(server)await new Promise(r=>server.close(r));if(sid)ssh(`ubus call session destroy '{"ubus_rpc_session":"${sid}"}'`);}
})().catch(e=>{console.error(e);process.exitCode=1;});
