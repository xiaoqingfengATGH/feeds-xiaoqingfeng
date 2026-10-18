const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const source=fs.readFileSync(path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish/product.js'),'utf8');
const api=new Function('baseclass','rpc','dom','ui',source)({extend:x=>x},{declare:()=>()=>Promise.resolve({})},{},{});
(async()=>{
 assert.deepEqual(api.dnsInventory({available:true,profiles:[{profile_id:'opaque',name:'家用',provider:'DNSPod',a:{enabled:true,domains:[]},aaaa:{enabled:false,domains:[]}}]}).profiles[0],{id:'opaque',name:'家用',provider:'DNSPod',ipv4_enabled:true,ipv6_enabled:false,candidates:[]});
 const config={schema_version:2,services:[]},state={saved_revision:2,saved_config:config,desired_state:{state:'enabled'},runtime:{phase:'running',active_verified:true}};
 api.validate=async()=>({valid:true,config});api.save=async()=>({saved_revision:2});api.status=async()=>state;api.apply=async()=>({ddns:{results:[],warnings:[{hostname:'new.example.test',error_code:'family_disabled'}]}});
 const result=await api.saveAndApply(1,config,false);
 assert.deepEqual(result.ddns.warnings,[{hostname:'new.example.test',error_code:'family_disabled'}]);
 assert.equal(api.dnsOutcome(result),'服务已应用，部分域名未能设置自动更新：new.example.test（请先在 ddns-go 中启用所选地址类型）');
 assert.equal(api.dnsOutcome({action:'apply',ddns:{warnings:[{hostname:'new.example.test',error:'所选账户未启用需要的地址类型，请检查 ddns-go 设置。'}]}}),'服务已应用，部分域名未能设置自动更新：new.example.test（请先在 ddns-go 中启用所选地址类型）');
 assert.equal(api.dnsOutcome({action:'save',ddns:result.ddns}),'');
 const before={services:[{service_id:'secret-id',name:'网站',type:'http_proxy',dns:{mode:'manual'}}]},after=api.clone(before);after.services[0].dns={mode:'ddns_go',profile_id:'secret-profile',record_types:['A']};
 const diff=api.diff(before,after).join('');assert.ok(diff.includes('DNS 选择'));assert.ok(!diff.includes('secret-profile'));assert.ok(!diff.includes('secret-id'));
 console.log(JSON.stringify({profileContract:true,warningsRetained:true,plainDiff:true,saveOnlyNoDnsSuccess:true}));
})().catch(e=>{console.error(e);process.exitCode=1;});
