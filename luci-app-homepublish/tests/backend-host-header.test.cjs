const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const dir=path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish');
const api=new Function('baseclass','rpc','dom','ui',fs.readFileSync(path.join(dir,'product.js'),'utf8'))({extend:o=>o},{declare:()=>()=>{}},{},{});
function fixture(host){return {schema_version:2,services:[{service_id:'web',name:'web',type:'http_proxy',enabled:true,hostname:'public.test',backend:{host:'192.168.1.8',port:8080,...(host===undefined?{}:{host_header:host})},dns:{mode:'manual'}}]};}
function collect(base,row){return api.collectConfig({snapshot:base,editor:'services',config:'x',data:{data:{},sections:()=>[row]}}).services[0];}
test('optional origin Host survives editor roundtrip without changing legacy default',()=>{
 for(const value of [undefined,'','site.test:8080','[2001:db8::1]:443']){
  const base=fixture(value),row=api.serviceRows(base)[0];assert.equal(row.backend_host_header,value||'');
  const result=collect(base,row);if(value)assert.equal(result.backend.host_header,value);else assert.equal(Object.hasOwn(result.backend,'host_header'),false);
  assert.deepEqual(result.dns,{mode:'manual'});
 }
});
test('origin Host only serializes for reverse proxies, independently of SNI and DNS',()=>{
 const base=fixture('site.test:8080'),row=api.serviceRows(base)[0];row.tls_server_name='certificate.test';
 for(const type of ['http_proxy','https_proxy','tls_passthrough','ssh','tcp_forward'])for(const scheme of ['http','https']){
  row.type=type;row.upstream_scheme=scheme;const svc=collect(base,row),proxy=type==='http_proxy'||type==='https_proxy';
  assert.equal(svc.backend.host_header,proxy?'site.test:8080':undefined);assert.deepEqual(svc.dns,{mode:'manual'});
  if(proxy&&scheme==='https')assert.equal(svc.upstream_tls.server_name,'certificate.test');
 }
});
test('confirmation names origin Host without leaking raw property',()=>{
 const before=fixture(),after=fixture('site.test');const diff=api.diff(before,after).join('\n');
 assert.match(diff,/回源 Host/);assert.doesNotMatch(diff,/host_header/);
});
