/* Explicit installed-resource harness manifest; never a production lifecycle runner. */
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{execFileSync,spawnSync}=require('node:child_process'),env=require('./env.cjs');
const ssh=cmd=>execFileSync('ssh',['-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-i',env.key,'-p',env.port,env.target,cmd],{encoding:'utf8',timeout:45000});
const protectedPaths='/etc/homepublish/product/state /etc/config/homepublish /etc/config/network /etc/config/firewall /tmp/homepublish-runtime/nginx.conf /usr/share/homepublish/product-provider.lua /usr/share/homepublish/product-store.lua /usr/share/homepublish/product-store-core.lua /www/luci-static/resources/view/homepublish/product.js /www/luci-static/resources/view/homepublish/services.js /www/luci-static/resources/view/homepublish/entry.js /www/luci-static/resources/view/homepublish/certificates.js /www/luci-static/resources/form.js /www/luci-static/resources/ui.js';
function snapshot(){const s=JSON.parse(ssh('ubus call homepublish status'));return {hashes:ssh('sha256sum '+protectedPaths),saved_revision:s.saved_revision,active_revision:s.active_revision,intent_revision:s.intent_revision,desired_state:s.desired_state,runtime:{phase:s.runtime.phase,generation:s.runtime.generation,active_verified:s.runtime.active_verified}};}
const before=snapshot();fs.writeFileSync(path.join(env.evidence,'production-before.json'),JSON.stringify(before,null,2));
for(const [name,remote] of [['installed-form.js','/www/luci-static/resources/form.js'],['installed-ui.js','/www/luci-static/resources/ui.js'],['installed-services.js','/www/luci-static/resources/view/homepublish/services.js']])fs.writeFileSync(path.join(env.evidence,name),ssh('cat '+remote));
const manifest=[
 ['base','tcp-ingress-device-probe.cjs',{HP_CASE:'base'}],
 ['extended','tcp-ingress-device-probe.cjs',{HP_CASE:'extended'}],
 ['host-caught-parse','backend-host-header-native.test.cjs',{HP_HOST_NEGATIVE_MODE:'caught-parse'}],
 ['host-click','backend-host-header-native.test.cjs',{HP_HOST_NEGATIVE_MODE:'click'}],
 ['host-page-save','backend-host-header-page-save-native.test.cjs',{}],
 ['services-loading','services-save-loading-native.test.cjs',{}],
 ['services-dns','services-dns-native.test.cjs',{}]
];
const results=[];
for(const [name,file,extra] of manifest){
 const childEnv={...process.env};delete childEnv.HP_CASE;delete childEnv.HP_HOST_NEGATIVE_MODE;
 const r=spawnSync(process.execPath,[path.join(__dirname,file)],{env:{...childEnv,...extra},encoding:'utf8',timeout:240000,maxBuffer:32*1024*1024});
 const output=(r.stdout||'')+(r.stderr||'')+(r.error?'\n'+r.error.stack:'');const log=path.join(env.evidence,name+'.log');fs.writeFileSync(log,output);
 const objects=output.split(/\r?\n/).filter(s=>s.startsWith('{')).flatMap(s=>{try{return [JSON.parse(s)];}catch{return [];}});
 const final=objects.at(-1);let verified=r.status===0&&!!final&&!/\bSKIP\b/.test(output);
 if(name==='base'||name==='extended')verified=verified&&final.deviceLoader==='PASS'&&final.entryPersistence==='PASS'&&final.extended===(name==='extended'?'PASS':'NOT_RUN')&&output.includes('PRIVATE_FIXTURE_CLEANED')&&output.includes('INSTALLED_FOUR_UNCHANGED_NO_WRITES');
 const item={name,exit_code:r.status,status:verified?'PASS':'FAIL',log,result:final||null};results.push(item);console.log(JSON.stringify(item));
}
const after=snapshot();fs.writeFileSync(path.join(env.evidence,'production-after.json'),JSON.stringify(after,null,2));let unchanged=true;try{assert.deepEqual(after,before);}catch{unchanged=false;}
const summary={status:results.every(r=>r.status==='PASS')&&unchanged?'PASS':'FAIL',results,productionUnchanged:unchanged,productionWrites:false,ordinaryProductionLifecycle:'NOT_RUN',boundary:'Installed LuCI loader/form via local HTTP: base/extended private device Lua store; other probes fixture RPC. Native host-click product defect is not waived.'};
fs.writeFileSync(path.join(env.evidence,'summary.json'),JSON.stringify(summary,null,2));console.log(JSON.stringify(summary));if(summary.status!=='PASS')process.exitCode=1;
