const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish/product.js'),'utf8');
const api=new Function('baseclass','rpc','dom','ui',source)({extend:x=>x},{declare:()=>()=>Promise.resolve({})},{},{});
test('suffix references strip exactly one label, never infer registrable domains, and retain all sources',()=>{
 assert.deepEqual(api.dnsCandidates(['home.iwonderful.top','camera.iwonderful.top','host.region.example.co.uk','example.org']),[
  {suffix:'iwonderful.top',sources:['home.iwonderful.top','camera.iwonderful.top'],suggested:true},
  {suffix:'region.example.co.uk',sources:['host.region.example.co.uk'],suggested:true},
  {suffix:'example.org',sources:['example.org'],suggested:false}
 ]);
});
test('unsafe, malformed and incomplete domain records are not suffix references',()=>{
 assert.deepEqual(api.dnsCandidates(['*.top','localhost','https://home.example.test','a..example','-bad.example.test','<img>.example.test',null,{},'a'.repeat(64)+'.example.test']),[]);
 assert.deepEqual(api.dnsCandidates(['*.example.test','HOME.Example.Test.']),[{suffix:'example.test',sources:['*.example.test','HOME.Example.Test.'],suggested:true}]);
});
test('loaded services missing DNS remain manual without changing the exact saved hostname',()=>{
 const saved={services:[{service_id:'old',enabled:true,type:'tls_passthrough',hostname:'preserved.nested.example.test'}]},copy=JSON.stringify(saved);
 const inventory=api.dnsInventory({available:true,profiles:[{profile_id:'one',a:{enabled:true,domains:['home.iwonderful.top']},aaaa:{enabled:false,domains:[]}}]});
 const row=api.serviceRows(saved,inventory)[0];assert.equal(row.dns_mode,'manual');assert.equal(row.hostname,'preserved.nested.example.test');assert.equal(JSON.stringify(saved),copy);
 assert.deepEqual(api.dnsParts(row.hostname),{label:'preserved',suffix:'nested.example.test'});
});
test('SSH and TCP serialize manual even with retained automatic UI fields',()=>{
 for(const type of ['ssh','tcp_forward']){
  const row={service_id:'svc',type,dns_mode:'ddns_go',dns_profile:'one',dns_label:'nas',dns_suffix:'example.test',hostname:'nas.example.test',dns_a:'1',dns_aaaa:'1',backend_host:'192.0.2.1',backend_port:'22',listen_port:'2222'};
  const result=api.collectConfig({snapshot:{schema_version:2,services:[]},editor:'services',config:'json',data:{data:{},sections:()=>[row]}}).services[0];
  assert.deepEqual(result.dns,{mode:'manual'});assert.equal(result.hostname,undefined);assert.equal(result.dns_suffix,undefined);
 }
});
