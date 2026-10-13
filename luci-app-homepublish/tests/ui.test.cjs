const {test}=require('node:test');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const base=path.resolve(__dirname,'..');
const schemaPath=path.join(base,'htdocs/luci-static/resources/view/homepublish/schema.js');
function schema(){assert(fs.existsSync(schemaPath),'HomePublish validation module exists');return new Function('baseclass',fs.readFileSync(schemaPath,'utf8'))({extend:v=>v});}
test('hostname and upstream reject public, management, injection and ambiguous inputs',()=>{
 const s=schema();
 for(const v of ['nas.example.com','a-b.example'])assert.equal(s.hostname(v),true,v);
 for(const v of ['localhost','EXAMPLE.com','a..com','-a.com','a.com;id','a'.repeat(64)+'.com'])assert.equal(s.hostname(v),false,v);
 for(const v of ['http://127.0.0.1:18081','http://192.168.1.5:8080','http://172.16.0.2:1024'])assert.equal(s.upstream(v),true,v);
 for(const v of ['http://8.8.8.8:8080','http://192.168.1.5:80','https://10.0.0.1:8080','http://010.0.0.1:8080','http://10.0.0.1:8080/path','http://172.32.0.1:8080','http://127.0.0.1:65536'])assert.equal(s.upstream(v),false,v);
});
test('independent menu and least-privilege ACL permit only homepublish UCI and status',()=>{
 const aclPath=path.join(base,'root/usr/share/rpcd/acl.d/luci-app-homepublish.json');
 assert(fs.existsSync(aclPath),'HomePublish ACL exists');
 const acl=JSON.parse(fs.readFileSync(aclPath))['luci-app-homepublish'];
 assert.deepEqual(acl.read,{uci:['homepublish'],ubus:{homepublish:['status']}});
 assert.deepEqual(acl.write,{uci:['homepublish'],ubus:{uci:['commit']}});
 const menu=JSON.parse(fs.readFileSync(path.join(base,'root/usr/share/luci/menu.d/luci-app-homepublish.json')));
 assert.equal(menu['admin/services/homepublish'].action.path,'homepublish/settings');
 assert.deepEqual(menu['admin/services/homepublish'].depends.acl,['luci-app-homepublish']);
 const rpc=fs.readFileSync(path.join(base,'root/usr/libexec/rpcd/homepublish'),'utf8');
 assert.match(rpc,/config-cli\.lua status/);
 assert(!/eval|cat |token|exec.*\$/.test(rpc));
});
test('settings render disabled flags, safe fields, honest status and no activation controls',async()=>{
 const file=path.join(base,'htdocs/luci-static/resources/view/homepublish/settings.js');
 assert(fs.existsSync(file),'HomePublish settings view exists');
 const src=fs.readFileSync(file,'utf8'),options=[];
 const E=(tag,attrs,children)=>({tag,attrs,children});
 const form={Map:class {section(){return {option(type,name,label,description){const o={type,name,label,description,depends(){}};options.push(o);return o;}};}render(){return Promise.resolve(E('form',{},[]));}},NamedSection:'named',TypedSection:'typed',Flag:'flag',Value:'value',DummyValue:'dummy'};
 const calls=[];const rpc={declare(d){calls.push(d);return ()=>Promise.resolve({state:'disabled',publication:'disabled',mapped:'unknown',reachable:'unverified'});}};
 const v=new Function('view','form','rpc','uci','schema','E','_',src)({extend:v=>v},form,rpc,{load:()=>Promise.resolve()},schema(),E,x=>x);
 const node=await v.render(await v.load());
 assert.deepEqual(calls,[{object:'homepublish',method:'status',expect:{}},{object:'uci',method:'commit',params:['config'],reject:true}]);
 const text=JSON.stringify(node);assert.match(text,/unknown/);assert.match(text,/unverified/);assert.match(text,/not observed/);
 for(const key of ['enabled','exposure_approved','publication_enabled'])assert.equal(options.find(o=>o.name===key).default,'0');
 for(const key of ['name','upstream','ttl','bind_port','port','stun_server','http_server'])assert(options.find(o=>o.name===key),key);
 assert(!options.some(o=>/token|password/.test(o.name)),'no secret input');
 assert.equal(v.handleSaveApply,null,'Save only, no apply/start');
 assert(!/fs\.exec|service\.set|start_service|restart|uptime/.test(src));
 const upstream=options.find(o=>o.name==='upstream');assert.equal(upstream.validate('host1','http://10.0.0.1:8080'),true);assert.notEqual(upstream.validate('host1','http://1.1.1.1:8080'),true);
 const errorNode=await v.render([{state:'unavailable'}]);assert.match(JSON.stringify(errorNode),/unavailable/);assert.match(JSON.stringify(errorNode),/unverified/);
});
test('package depends independently on core and LuCI, without activation hooks',()=>{
 const file=path.join(base,'Makefile');assert(fs.existsSync(file),'LuCI package recipe exists');
 const src=fs.readFileSync(file,'utf8');assert.match(src,/LUCI_DEPENDS:=\+homepublish/);assert.match(src,/luci.mk/);
 assert(!/postinst|init.d|uci-defaults|enable|start/.test(src));
 for(const v of ['turn.cloudflare.com','stun.example:3478'])assert.equal(schema().server(v),true);
 for(const v of ['',':3478','x:0','a..com','x:65536','x;id'])assert.equal(schema().server(v),false);
});
