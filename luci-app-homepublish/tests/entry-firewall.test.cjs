const {test}=require('node:test');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const dir=path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish');
const api=new Function('baseclass','rpc','dom','ui',fs.readFileSync(path.join(dir,'product.js'),'utf8'))({extend:o=>o},{declare:()=>()=>{}},{},{});
const saved={schema_version:2,services:[],access_profile:{listeners:[]}};
test('zone lists tolerate Lua empty objects and LuCI string values',()=>{
 const cfg={schema_version:2,services:[],access_profile:{listeners:[],firewall:{ipv4_zones:{},ipv6_zones:{}}}};
 const row=api.entryDraft(cfg);assert.deepEqual(row.ipv4_zones,[]);assert.deepEqual(row.ipv6_zones,[]);
 row.family='dual';row.ipv4_zones='lan wan';row.ipv6_zones={};
 const out=api.collectConfig({snapshot:cfg,data:{data:{cfg_listener:row}}});
 assert.deepEqual(out.access_profile.firewall,{ipv4_zones:['lan','wan'],ipv6_zones:[]});
 assert.deepEqual(api.firewallRules(cfg),[]);
});
test('new listeners default to automatic without requiring a live network; legacy binds remain explicit',()=>{
 assert.equal(api.entryDraft(saved).bind_mode,'auto');
 const legacy={...saved,access_profile:{listeners:[{listener_id:'old',family:'ipv4',network:'wan',address:'198.51.100.2',port:8443}]}};
 const row=api.entryDraft(legacy);assert.equal(row.bind_mode,'address');assert.equal(row.ipv4_address,'198.51.100.2');
 row.ipv4_zones=['wan'];
 const collected=api.collectConfig({snapshot:legacy,data:{data:{cfg_listener:row}}});
 assert.equal(collected.access_profile.listeners[0].address,'198.51.100.2');
 row.bind_mode='auto';row.family='dual';row.ipv6_zones=['lan'];
 const auto=api.collectConfig({snapshot:legacy,data:{data:{cfg_listener:row}}});
 assert.deepEqual(auto.access_profile.listeners.map(l=>[l.bind_mode,l.address,l.network]),[['auto','0.0.0.0',''],['auto','::','']]);
 assert.deepEqual(auto.access_profile.firewall,{ipv4_zones:['wan'],ipv6_zones:['lan']});
 assert.equal(legacy.access_profile.listeners[0].address,'198.51.100.2');
});
test('preview deduplicates shared/dedicated rules, tracks services and excludes disabled services',()=>{
 const config={access_profile:{listeners:[{family:'ipv4',port:8443},{family:'ipv6',port:8443}],firewall:{ipv4_zones:['wan','wan','lan'],ipv6_zones:['wan']}},services:[{service_id:'web',type:'https_proxy',enabled:true},{service_id:'ssh',type:'ssh',enabled:true},{service_id:'off',type:'tcp_forward',enabled:false,listen_port:9000},{service_id:'tcp',type:'tcp_forward',enabled:true,listen_port:9443}]};
 const original=JSON.stringify(config),rules=api.firewallRules(config);
 assert.equal(rules.length,6);assert.deepEqual(rules[0],{family:'ipv4',zone:'wan',protocol:'tcp',dest_port:8443,services:['web','ssh']});
 assert.ok(!rules.some(r=>r.dest_port===9000));assert.equal(JSON.stringify(config),original);
 config.services=config.services.filter(s=>s.type==='tcp_forward');assert.equal(api.firewallRules(config).length,3);
 config.services=[];assert.deepEqual(api.firewallRules(config),[]);
});
test('fixed destination scope remains distinct for shared and dedicated ports; auto omits dest_ip',()=>{
 const config={access_profile:{listeners:[
  {family:'ipv4',bind_mode:'address',address:'198.51.100.8',port:8443},
  {family:'ipv4',address:'198.51.100.9',port:8443},
  {family:'ipv4',bind_mode:'address',address:'198.51.100.8',port:8443},
  {family:'ipv6',bind_mode:'address',address:'2001:db8::8',port:8443},
  {family:'ipv6',bind_mode:'auto',address:'::',port:8443}
 ],firewall:{ipv4_zones:['wan','wan'],ipv6_zones:['wan']}},services:[
  {service_id:'ssh',type:'ssh',enabled:true},{service_id:'web',type:'https_proxy',enabled:true},
  {service_id:'tcp',type:'tcp_forward',enabled:true,listen_port:9443},
  {service_id:'off',type:'tcp_forward',enabled:false,listen_port:9000}
 ]};
 const before=JSON.stringify(config),rules=api.firewallRules(config);
 assert.equal(rules.length,8);
 for(const address of ['198.51.100.8','198.51.100.9','2001:db8::8']){
  assert.deepEqual(rules.filter(r=>r.dest_ip===address).map(r=>[r.dest_port,r.services]),[[8443,['ssh','web']],[9443,['tcp']]]);
 }
 const automatic=rules.filter(r=>r.family==='ipv6' && !Object.hasOwn(r,'dest_ip'));
 assert.equal(automatic.length,2);assert.equal(JSON.stringify(config),before);
});
test('automatic listeners have a clear network-independent overview label',()=>{
 const source=fs.readFileSync(path.join(dir,'overview.js'),'utf8');
 assert.match(source,/network:l.bind_mode==='auto'\?'自动（不绑定网络）'/);
 assert.match(source,/poll.add/);assert.match(source,/'全部测试'/);assert.match(source,/'测试'/);
});
function renderEntry(config=saved,inventory={networks:[],zones:['wan','isolated']}){
 const options=[],events={},previews=[];
 const form={NamedSection:class {},ListValue:class {},Value:class {},DummyValue:class {},MultiValue:class {},JSONMap:class {
  constructor(data){this.data={data};this.sections=[];}
  section(type,id){const s={option(type,name,title){const o={type,name,title,formvalue(){return undefined;},getUIElement(){return null;},keylist:[],deps:[],value(k,v){this.keylist.push(k);},depends(...args){this.deps.push(args);}};options.push(o);return o;}};this.sections.push(s);return s;}
  lookupOption(name){const found=options.filter(o=>o.name===name);return found.length?found:null;}
  append(){} addEventListener(name,fn){events[name]=fn;}
  render(){this.data.data.cfg_listener['.name']='cfg_listener';return Promise.resolve(this);}
 }};
 const element=(tag,attrs,children)=>({tag,attrs,children});
 const view=new Function('form','view','ui','dom','api','E',fs.readFileSync(path.join(dir,'entry.js'),'utf8'))(form,{extend:o=>o},{},{content(node,children){previews.push(children);}},{...api,actionBar:node=>node},element);
 return view.render([{saved_config:config,saved_revision:1},{certificates:[]},inventory]).then(map=>({map,options,form,events,previews}));
}
test('advanced bind draft can select an available address without rewriting an automatic saved bind',async()=>{
 const config={...saved,access_profile:{listeners:[{family:'ipv4',bind_mode:'auto',network:'',address:'0.0.0.0',port:8443}]}};
 const {map}=await renderEntry(config,{zones:['wan'],networks:[{network:'wan',up:true,zones:['wan'],addresses:[{family:'ipv4',address:'198.51.100.8'}]}]});
 assert.equal(map.data.data.cfg_listener.ipv4_network,'wan');assert.equal(map.data.data.cfg_listener.ipv4_address,'198.51.100.8');
 assert.equal(config.access_profile.listeners[0].address,'0.0.0.0');
});
test('preview redraw reads draft widgets without mutating saved config or applying rules',async()=>{
 const config={...saved,services:[{service_id:'ssh',type:'ssh',enabled:true}],access_profile:{listeners:[{family:'ipv4',bind_mode:'auto',network:'',address:'0.0.0.0',port:8443}],firewall:{ipv4_zones:['wan'],ipv6_zones:[]}}};
 const before=JSON.stringify(config),{options,events,previews}=await renderEntry(config);
 assert.ok(JSON.stringify(previews.at(-1)).includes('8443'));assert.ok(JSON.stringify(previews.at(-1)).includes('保存并应用后生效'));
 options.find(o=>o.name==='port').formvalue=()=> '9443';events.input();
 assert.ok(JSON.stringify(previews.at(-1)).includes('9443'));assert.equal(JSON.stringify(config),before);
 assert.ok(!JSON.stringify(previews.at(-1)).includes('协调规则'));
});
test('draft preview displays fixed destination addresses and updates to automatic scope without saving',async()=>{
 const config={...saved,services:[{service_id:'ssh',type:'ssh',enabled:true}],access_profile:{listeners:[{family:'ipv4',bind_mode:'address',network:'wan',address:'198.51.100.8',port:8443},{family:'ipv6',bind_mode:'address',network:'wan',address:'2001:db8::8',port:8443}],firewall:{ipv4_zones:['wan'],ipv6_zones:['wan']}}};
 const before=JSON.stringify(config),{options,events,previews}=await renderEntry(config);
 let preview=JSON.stringify(previews.at(-1));
 assert.ok(preview.includes('目标地址'));assert.ok(preview.includes('198.51.100.8'));assert.ok(preview.includes('2001:db8::8'));
 options.find(o=>o.name==='ipv4_address').formvalue=()=> '198.51.100.9';events.change();
 preview=JSON.stringify(previews.at(-1));assert.ok(preview.includes('198.51.100.9'));assert.ok(!preview.includes('198.51.100.8'));
 options.find(o=>o.name==='bind_mode').formvalue=()=> 'auto';events.change();
 preview=JSON.stringify(previews.at(-1));assert.ok(preview.includes('自动监听（所有本机地址）'));assert.ok(!preview.includes('198.51.100.9'));assert.ok(!preview.includes('2001:db8::8'));
 assert.equal(JSON.stringify(config),before);
});
test('all dependencies remain in the LuCI directive preamble',()=>{
 for(const file of ['entry.js','product.js','overview.js']){
  const source=fs.readFileSync(path.join(dir,file),'utf8');
  const requires=[...source.matchAll(/^'require [^']+';/gm)];assert.ok(requires.length);
  assert.ok(requires.every(r=>r.index<source.indexOf(file==='product.js'?'var status=':file==='overview.js'?'var probeService=':'return view.extend')));
 }
});
test('configured wan membership selects wan; otherwise lan, with no arbitrary-zone inference',async()=>{
 for(const [zones,expected] of [[['lan','wan'],['wan']],[[{name:'lan'}],[]],[['guest'],[]],[[],[]]]){
  const before=JSON.stringify(saved),{map}=await renderEntry(saved,{zones,networks:[{network:'wan',zones:['wan']}]});
  assert.deepEqual(map.data.data.cfg_listener.ipv4_zones,expected);
  assert.deepEqual(map.data.data.cfg_listener.ipv6_zones,[]);
  const out=api.collectConfig(map);assert.deepEqual(out.access_profile.firewall,{ipv4_zones:expected,ipv6_zones:[]});
  assert.equal(JSON.stringify(saved),before);
 }
});
test('explicit custom, disappeared and empty saved selections are preserved',async()=>{
 for(const value of [['guest'],['gone'],[],{}]){
  const cfg={...saved,access_profile:{listeners:[{family:'ipv4',bind_mode:'auto',port:8443}],firewall:{ipv4_zones:value,ipv6_zones:[]}}};
  const {map,options}=await renderEntry(cfg,{zones:['wan','lan','guest'],networks:[]});
  assert.deepEqual(map.data.data.cfg_listener.ipv4_zones,api.zoneList(value));
  if(value[0]==='gone')assert.match(options.find(o=>o.name==='ipv4_zones').validate('',value),/已不存在/);
 }
});
test('dual switching defaults only newly enabled families, persists and clears absent families',async()=>{
 const cfg={...saved,access_profile:{listeners:[{family:'ipv4',bind_mode:'auto',port:8443}],firewall:{ipv4_zones:['guest'],ipv6_zones:{}}}};
 const {map,options}=await renderEntry(cfg,{zones:['wan','guest'],networks:[{network:'wan6',zones:['wan'],up:false,addresses:[]}]});
 const family=options.find(o=>o.name==='family');family.onchange(null,'cfg_listener','dual');
 assert.deepEqual(map.data.data.cfg_listener.ipv4_zones,['guest']);assert.deepEqual(map.data.data.cfg_listener.ipv6_zones,['wan']);
 assert.deepEqual(api.collectConfig(map).access_profile.firewall,{ipv4_zones:['guest'],ipv6_zones:['wan']});
 family.onchange(null,'cfg_listener','ipv6');
 assert.deepEqual(api.collectConfig(map).access_profile.firewall,{ipv4_zones:[],ipv6_zones:['wan']});
 family.onchange(null,'cfg_listener','dual');assert.deepEqual(map.data.data.cfg_listener.ipv4_zones,['guest']);
 const reloaded=await renderEntry(api.collectConfig(map),{zones:['lan'],networks:[]});
 assert.deepEqual(reloaded.map.data.data.cfg_listener.ipv6_zones,['wan']);
});
test('new family uses configured interface membership rather than opposite-family widget',async()=>{
 const cfg={...saved,access_profile:{listeners:[{family:'ipv4',bind_mode:'auto',port:8443}],firewall:{ipv4_zones:['wan'],ipv6_zones:{}}}};
 const {map,options}=await renderEntry(cfg,{zones:['wan','lan','guest'],networks:[]});
 const v4=options.find(o=>o.name==='ipv4_zones'),v6=options.find(o=>o.name==='ipv6_zones');
 let six=[];v4.getUIElement=()=>({getValue:()=>['lan','guest']});v6.getUIElement=()=>({getValue:()=>six,setValue:value=>{six=value;}});
 options.find(o=>o.name==='family').onchange(null,'cfg_listener','dual');
 assert.deepEqual(six,['lan']);assert.deepEqual(map.data.data.cfg_listener.ipv6_zones,['lan']);
 assert.deepEqual(cfg.access_profile.firewall.ipv4_zones,['wan']);
});
test('recommended dual defaults survive the normal save/apply payload without mutating the source',async()=>{
 const cfg={...saved,access_profile:{listeners:[{listener_id:'v4',family:'ipv4',bind_mode:'auto',port:8443},{listener_id:'v6',family:'ipv6',bind_mode:'auto',port:8443}]}};
 const before=JSON.stringify(cfg),{map}=await renderEntry(cfg,{zones:['lan','wan'],networks:[{network:'wan',zones:['wan'],up:false}]});
 const config=api.collectConfig(map),writes=[];
 assert.deepEqual(config.access_profile.firewall,{ipv4_zones:['wan'],ipv6_zones:['wan']});
 const fake={...api,validate:async value=>({valid:true,config:value}),save:async(rev,value)=>{writes.push(value);return {saved_revision:2};},status:async()=>({saved_revision:2,desired_state:{state:'enabled'},runtime:{phase:'running',active_verified:true}}),apply:async()=>({})};
 await fake.saveAndApply(1,config,false);
 assert.deepEqual(writes[0].access_profile.firewall,{ipv4_zones:['wan'],ipv6_zones:['wan']});assert.equal(JSON.stringify(cfg),before);
});
test('preview follows installed LuCI standard section and table markup',async()=>{
 const {previews}=await renderEntry();const preview=JSON.stringify(previews.at(-1));
 for(const cls of ['table cbi-section-table','thead cbi-section-thead','tbody cbi-section-tbody','tr cbi-section-table-titles','th cbi-section-table-cell'])assert.ok(preview.includes(cls));
 assert.match(fs.readFileSync(path.join(dir,'entry.js'),'utf8'),/id:'hp-firewall-preview',class:'cbi-section'/);
});
test('services-only saves leave legacy firewall absent',()=>{
 const out=api.collectConfig({snapshot:saved,editor:'services',config:'x',data:{data:{},sections:()=>[]}});
 assert.ok(!Object.hasOwn(out.access_profile,'firewall'));assert.deepEqual(out.access_profile,saved.access_profile);
});
test('automatic hides fixed binds; inbound zones are independent multiselects from all zones',async()=>{
 const {options,form}=await renderEntry();
 const mode=options.find(o=>o.name==='bind_mode');assert.ok(mode);assert.deepEqual(mode.keylist,['auto','address']);
 for(const f of ['ipv4','ipv6']){
  const zones=options.find(o=>o.name===f+'_zones');assert.equal(zones.type,form.MultiValue);assert.deepEqual(zones.keylist,['isolated','wan']);
  assert.equal(zones.validate('cfg_listener',[]),'请选择至少一个入站区域');
  assert.equal(zones.validate('cfg_listener',['isolated']),true);assert.equal(zones.validate('cfg_listener','isolated wan'),true);
  assert.match(zones.description,/作为主路由使用时，建议选择 wan/);assert.match(zones.description,/作为旁路由使用时，建议选择 lan/);
  for(const name of ['network','address'])assert.deepEqual(options.find(o=>o.name===f+'_'+name).deps,[[{family:f,bind_mode:'address'}],[{family:'dual',bind_mode:'address'}]]);
 }
});
