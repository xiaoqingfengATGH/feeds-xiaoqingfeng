const {test}=require('node:test');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish/overview.js'),'utf8');
async function render(state,error){
 const maps=[],calls=[];
 function E(tag,attrs,children){return {tag,attrs:attrs||{},children,append(){},appendChild(){},querySelector(s){return s==='#cbi-json-services'?{append(){}}:null},querySelectorAll(){return []},textContent:''};}
 class Map{constructor(rows,title){this.rows=rows;this.title=title;this.sections=[];maps.push(this);}section(type,id,kind,title){const s={id,title,options:[],option(type,key,title){const o={key,title,renderWidget(){return E('button');}};this.options.push(o);return o;}};this.sections.push(s);return s;}render(){return Promise.resolve(E('div'));}}
 const api={running:s=>s.runtime?.phase==='running'&&s.runtime.active_verified===true&&s.desired_state?.state==='enabled',actionGates:(s,o={})=>Object.fromEntries(['start','stop','apply'].map(k=>[k,{allowed:!o.busy&&!o.unknown,reason:''}])),serviceType:s=>s,endpoint:(h,p)=>h+':'+p,errorText:e=>e.message,actionDialog:(...a)=>{calls.push(a);},status:()=>Promise.resolve(state),checked:s=>s};
 const view=new Function('view','form','poll','dom','api','E','L','rpc','probes',source)({extend:o=>o},{JSONMap:Map,GridSection:function(){},TableSection:{prototype:{}},NamedSection:function(){},DummyValue:function(){},Button:function(){}},{add(){}},{content(){}},api,E,{url:()=>'/services'},{declare:()=>()=>Promise.resolve({ok:true,summary:'成功'})},{create:()=>({pending:()=>false,run:()=>Promise.resolve()})});
 await view.render({state,error});return {map:maps[0],calls};
}
function fixture(){return {saved_revision:17,active_revision:16,desired_state:{state:'enabled'},runtime:{phase:'running',cleanup:'confirmed',active_verified:true,generation:'g',services:{a:{ready:true,generation:'g'}}},saved_config:{services:[{service_id:'a',name:'A',enabled:true}]},active_config:{services:[{service_id:'a',name:'A'}]},pending_config:{apply_required:true}};}
test('overview hides revisions and public reachability from ordinary fields',async()=>{const {map}=await render(fixture());assert.equal(map.rows.summary.config,'有待应用变更');assert.equal(map.rows.summary.external,undefined);assert.ok(map.sections.every(s=>s.options.every(o=>o.key!=='external')));assert.equal(map.rows.summary.publication,'运行中');});
test('master control uses desired intent and existing confirmation, not separate start/stop buttons',async()=>{const {map,calls}=await render(fixture());const actions=map.sections.find(s=>s.id==='summary');assert.equal(map.sections.some(s=>s.id==='actions'),false);const control=actions.options.find(o=>o.key==='enable').renderWidget();assert.equal(control.attrs.type,'checkbox');assert.equal(control.attrs.checked,true);control.attrs.change({target:control.attrs});assert.equal(calls[0][2],'stop');const stopped=fixture();stopped.desired_state.state='disabled';stopped.runtime.phase='stopped';const next=await render(stopped);const c=next.map.sections.find(s=>s.id==='summary').options.find(o=>o.key==='enable').renderWidget();c.attrs.change({target:c.attrs});assert.equal(next.calls[0][2],'start');});
test('stopped runtime never reports service ready from retained active snapshot',async()=>{const s=fixture();s.runtime.phase='stopped';const {map}=await render(s);assert.equal(map.rows.services[0].readiness,'未运行');assert.equal(map.rows.summary.publication,'已停止');});
test('unknown status blocks master changes and does not claim stopped',async()=>{const {map,calls}=await render(fixture(),'offline');const control=map.sections.find(s=>s.id==='summary').options.find(o=>o.key==='enable').renderWidget();assert.equal(control.attrs.disabled,true);control.attrs.change({target:control.attrs});assert.equal(calls.length,0);assert.match(map.rows.summary.publication,/未知/);});
test('firewall runtime uses the top-level contract and exposes read-only rule and lease status',async()=>{const s=fixture();s.firewall={state:'open',rule_count:3,lease_seconds:10};const {map}=await render(s);assert.equal(map.rows.summary.firewall,'已放行（3 条规则）');assert.doesNotMatch(map.rows.summary.firewall,/租约|10 秒/);const field=map.sections.find(s=>s.id==='summary').options.find(o=>o.key==='firewall');assert.equal(field.title,'入站防火墙');assert.equal(field.editable,undefined);});
test('firewall distinguishes closed, unmanaged, legacy, unconfigured and unknown without inferring from running',async()=>{
 const s=fixture();s.saved_config.access_profile={firewall:{ipv4_zones:['wan'],ipv6_zones:[]}};
 for(const [firewall,expected] of [[{state:'closed'},'未放行'],[{state:'unmanaged'},'未托管（手动管理）'],[undefined,'状态未知'],[{state:'future'},'状态未知']]){s.firewall=firewall;assert.equal((await render(s)).map.rows.summary.firewall,expected);}
 delete s.saved_config.access_profile;s.firewall=undefined;assert.equal((await render(s)).map.rows.summary.firewall,'状态未知（旧配置，手动管理）');
 delete s.saved_config;delete s.active_config;assert.equal((await render(s)).map.rows.summary.firewall,'状态未知（未配置）');
 s.firewall={state:'open',rule_count:1,lease_seconds:10};assert.equal((await render(s,'offline')).map.rows.summary.firewall,'状态未知');
});
test('firewall update and cleanup failures retain concrete backend error without claiming open',async()=>{
 for(const [state,label] of [['update_failed','更新失败'],['cleanup_failed','清理失败']]){const s=fixture();s.firewall={state,error:'input_wan: TCP 443 atomic update failed',rule_count:3,lease_seconds:10};assert.equal((await render(s)).map.rows.summary.firewall,label+'：input_wan: TCP 443 atomic update failed');delete s.firewall.error;assert.equal((await render(s)).map.rows.summary.firewall,label);}
});
test('firewall metadata never displays missing, malformed or negative counts and leases',async()=>{
 const s=fixture();for(const metadata of [{},{rule_count:-1,lease_seconds:'ten'},{rule_count:2.5,lease_seconds:0}]){s.firewall={state:'open',...metadata};assert.equal((await render(s)).map.rows.summary.firewall,'已放行');}
 s.firewall={state:'open',rule_count:2};assert.equal((await render(s)).map.rows.summary.firewall,'已放行（2 条规则）');
});
test('firewall field participates in retained summary polling updates',()=>{assert.match(source,/updateRow\(body\.querySelector\('#cbi-json-summary'\),rows\.summary,\['publication','firewall','config','policy'\]\)/);});
test('SSH summary names the shared entry port without changing other match values',async()=>{
 const s=fixture();
 s.saved_config.services=[{service_id:'ssh',type:'ssh'},{service_id:'web',type:'https_proxy',hostname:'web.test'},{service_id:'tcp',type:'tcp_forward',listen_port:9443}];
 s.active_config.services=[];
 const {map}=await render(s);
 assert.deepEqual(map.rows.services.map(r=>r.match),['共享入口端口','web.test','TCP 9443']);
 assert.doesNotMatch(source,/共享 SSH 入口/);
});
module.exports={render,fixture};
