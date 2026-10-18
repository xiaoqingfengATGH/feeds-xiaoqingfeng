const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const dir=path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish');
test('service access method labels and five non-editable scenario lines',()=>{
 const s=fs.readFileSync(path.join(dir,'services.js'),'utf8'),o=fs.readFileSync(path.join(dir,'overview.js'),'utf8'),p=fs.readFileSync(path.join(dir,'product.js'),'utf8');
 assert.ok(s.includes("'type','接入方式'"));assert.ok(o.includes("['kind','接入方式']"));assert.ok(p.includes("changed(prefix+'接入方式'"));
 for(const src of [s,o,p])assert.equal(src.includes('服务类型'),false);
 assert.ok(s.includes("form.DummyValue,'access_method_help'"));assert.ok(s.includes('o.modalonly=true'));
 for(const text of ['http://域名:共享端口','路由器无需配置证书','https://域名:共享端口','后端使用HTTPS时全链路加密','加密连接直达后端','由后端提供证书','SSH 客户端','不共用入口端口'])assert.ok(s.includes(text),text);
 assert.equal(s.includes('form.TextValue'),false);
});
