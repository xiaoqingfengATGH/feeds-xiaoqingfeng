const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const dir=path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish');
const api=new Function('baseclass','rpc','dom','ui',fs.readFileSync(path.join(dir,'product.js'),'utf8'))({extend:o=>o},{declare:()=>()=>{}},{},{});
test('service save discards old per-rule subnet and declarative authentication fields',()=>{
 const s={service_id:'web',name:'Web',type:'http_proxy',enabled:true,hostname:'web.test',upstream_scheme:'http',backend:{addressFamily:'ipv4',host:'192.168.1.8',port:8080,allowed_ranges:['192.168.1.0/24'],backup:{addressFamily:'ipv4',host:'192.168.1.9',port:8080}},authentication_review:{authentication:'unconfirmed',management:true}};
 const base={schema_version:2,services:[s]},row=api.serviceRows(base)[0];row.backend_host='192.168.2.8';
 const out=api.collectConfig({snapshot:base,editor:'services',config:'x',data:{data:{},sections:()=>[row]}}).services[0];
 assert.equal(out.backend.host,'192.168.2.8');assert.equal('allowed_ranges' in out.backend,false);assert.equal('authentication_review' in out,false);assert.deepEqual(out.backend.backup,s.backend.backup);
 assert.deepEqual(base.services[0],s);
});
test('advanced tab and all three declarations are absent, real TLS controls remain',()=>{
 const src=fs.readFileSync(path.join(dir,'services.js'),'utf8');
 for(const token of ["s.tab('advanced'","'allowed_ranges'","'authentication'","'management'"])assert.equal(src.includes(token),false,token);
 assert.ok(src.includes("'tls_verify'"));assert.ok(src.includes("'tls_server_name'"));
});
test('SSH rule summary displays the shared entry port label, retaining hostname and TCP values',()=>{
 const src=fs.readFileSync(path.join(dir,'services.js'),'utf8');
 const body=src.match(/'match_summary'[\s\S]*?o\.textvalue=function\(sid\)\{([\s\S]*?)\};/)[1];
 const textvalue=new Function('sid',body);
 const render=row=>textvalue.call({map:{config:'test',data:{get:()=>row}}},'ssh');
 assert.equal(render({type:'ssh'}),'共享入口端口');
 assert.equal(render({type:'https_proxy',hostname:'web.test'}),'web.test');
 assert.equal(render({type:'tcp_forward',listen_port:9443}),'TCP 9443');
 assert.equal(render({type:'tcp_forward'}),'TCP 待填写');
 assert.doesNotMatch(src,/共享 SSH 入口/);
 for(const file of ['overview','product','entry'])assert.doesNotMatch(fs.readFileSync(path.join(dir,file+'.js'),'utf8'),/共享 SSH 入口/);
});
