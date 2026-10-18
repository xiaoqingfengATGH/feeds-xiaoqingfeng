const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const dir=path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish');
const api=new Function('baseclass','rpc','dom','ui',fs.readFileSync(path.join(dir,'product.js'),'utf8'))({extend:o=>o},{declare:()=>()=>{}},{},{});
test('both proxy types preserve explicit false and default to verification',()=>{
 for(const type of ['http_proxy','https_proxy'])for(const verify of [undefined,false,true]){
 const service={service_id:'web',name:'web',type,enabled:true,hostname:'web.test',upstream_scheme:'https',upstream_tls:{server_name:'back.test',...(verify===undefined?{}:{verify})},backend:{host:'192.168.1.8',port:8443}};
 const base={schema_version:2,services:[service]},row=api.serviceRows(base)[0];assert.equal(row.tls_verify,verify===false?'0':'1');
 const collect=()=>api.collectConfig({snapshot:base,editor:'services',config:'x',data:{data:{},sections:()=>[row]}}).services[0];
 assert.equal(collect().upstream_tls.verify,verify!==false);
 row.tls_verify='0';row.tls_server_name='';assert.deepEqual(collect().upstream_tls,{verify:false});
 row.tls_verify=false;assert.equal(collect().upstream_tls.verify,false);
 }
});
test('UI exposes secure-default checkbox and conditional hostname validation',()=>{
 const options={};function option(_,cls,key,label){return options[key]={label,value(){},depends(){}};}
 const section={tab(){},taboption:option};class Map{constructor(data){this.data=data;}section(){return section;}render(){return Promise.resolve({querySelectorAll:()=>[]});}}
 const view=new Function('form','view','api',fs.readFileSync(path.join(dir,'services.js'),'utf8'))({JSONMap:Map,Value:'value',Flag:'flag',ListValue:'list',DummyValue:'dummy'}, {extend:o=>o},{...api,sortInventory:()=>[],actionBar:n=>n});
 view.render([{saved_config:{schema_version:2,services:[]}}, {certificates:[]}]);
 assert.equal(options.tls_verify.label,'验证后端证书');assert.equal(options.tls_verify.default,'1');assert.equal(options.tls_verify.description,'关闭后可连接自签名证书的内网服务。');
 const name=options.tls_server_name;name.map={lookupOption:()=>[{formvalue:()=> '1'}]};assert.notEqual(name.validate('x',''),true);name.map.lookupOption=()=>[{formvalue:()=> '0'}];assert.equal(name.validate('x',''),true);assert.equal(name.validate('x','back.test'),true);
});
