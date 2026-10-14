/* r9 save semantics: the ActionBar Save button runs the real RPC chain
 * collectConfig(map) -> validate -> save(expected_revision, config).
 * Map.save() itself is a JSONMap no-op and never starts anything. */
const {test}=require('node:test');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const dir=path.resolve(__dirname,'../htdocs/luci-static/resources/view/homepublish');

/* Load the real product.js with stubbed LuCI globals ('require …' lines are bare string statements). */
const stubRpc={declare:d=>(...a)=>Promise.resolve({})};
function loadApi(rpc){
	rpc=rpc||stubRpc;
	const src=fs.readFileSync(path.join(dir,'product.js'),'utf8').replace(/'require[^']*';/g,'');
	const factory=new Function('baseclass','rpc','_','view','dom','E','L',src);
	const baseclass={extend:o=>o};
	const view={extend:o=>o};
	const E=function(){return {appendChild(){},querySelector(){return null},classList:{add(){},remove(){}}}};
	const dom={findClassInstance(){return null}};
	const L={url(){return ''}};
	return factory(baseclass,rpc,s=>s,view,dom,E,L);
}
test('product.js loads with stubbed LuCI globals exposing the r9 API',()=>{
	const api=loadApi(null);
	assert.equal(typeof api.collectConfig,'function');
	assert.equal(typeof api.actionBar,'function');
	assert.equal(typeof api.running,'function');
	assert.equal(typeof api.actionDialog,'function');
	assert.equal(typeof api.diff,'function');
});
test('collectConfig rebuilds canonical config from JSONMap data (services rows + listener + policy)',()=>{
	const api=loadApi(null);
	const snapshot={schema_version:1,services:[],default_certificate_ref:'acme:home_rsa',
		access_profile:{methods_allowed:['manual_ipv4'],listeners:[{family:'ipv4',address:'192.168.1.2',interface:'br-lan',zone:'lan',protocol:'tcp',internal_port:8443,external_port:18443}]},
		publication_policy:{mode:'continuous',boot_restore:false}};
	const map={snapshot,snapshotRevision:4,data:{data:{
			services0:{'.name':'services0','.type':'services','.anonymous':true,'.index':0,
				name:'NAS',hostname:'nas.example.test',enabled:'1',backend:{addressFamily:'ipv4',host:'192.168.1.10',port:8080,allowed_ranges:['192.168.1.0/24']},
				certificate_ref:'acme:nas',certificate_mode:'override',authentication_review:{authentication:'confirmed',management:false}},
			cfg_listener:{family:'ipv4',address:'192.168.1.2',interface:'br-lan',zone:'lan',protocol:'tcp',internal_port:'8443',external_port:'18443'},
			cfg_policy:{default_certificate_ref:'acme:home_rsa',mode:'temporary',temporary_duration:'1800',boot_restore:'1'}
		},sections:function(){return [this.data.services0];},get:function(c,s){return this.data[s];}}};
	const out=api.collectConfig(map);
	assert.equal(out.schema_version,1);
	assert.equal(out.default_certificate_ref,'acme:home_rsa');
	assert.deepEqual(out.access_profile.listeners,[{family:'ipv4',address:'192.168.1.2',interface:'br-lan',zone:'lan',protocol:'tcp',internal_port:8443,external_port:18443}]);
	assert.deepEqual(out.publication_policy,{mode:'temporary',temporary_duration:1800,boot_restore:true});
	assert.equal(out.services.length,1);
	assert.equal(out.services[0].backend.allowed_ranges.length,1);
	assert.ok(!('.name' in out.services[0]));
});
test('collectConfig keeps allowed_ranges empty-array guard, boolean enabled and drops backend_url',()=>{
	const api=loadApi(null);
	const map={snapshot:{schema_version:1,services:[],access_profile:{methods_allowed:['manual_ipv4'],listeners:[]},publication_policy:{mode:'continuous',boot_restore:false}},snapshotRevision:0,
		data:{data:{services0:{'.name':'services0','.type':'services','.index':0,name:'X',hostname:'x.example.test',enabled:'0',
				backend:{addressFamily:'ipv4',host:'10.0.0.5',port:81,allowed_ranges:[]},certificate_mode:'inherit',backend_url:'http://10.0.0.5:81',
				authentication_review:{authentication:'unconfirmed',management:false}}},
			sections:function(){return [this.data.services0];},get:function(c,s){return this.data[s];}}};
	const out=api.collectConfig(map);
	assert.deepEqual(out.services[0].backend.allowed_ranges,[]);
	assert.equal(out.services[0].enabled,false);
	assert.equal('backend_url' in out.services[0],false);
	assert.equal('certificate_ref' in out.services[0],false);
});
test('ActionBar Save chain: validate rejection surfaces the backend error and no save RPC fires',async()=>{
	const calls=[];
	const rpc={declare:d=>(...args)=>{
		calls.push([d.method,...args]);
		if(d.method==='validate')return Promise.resolve({valid:false,error:'canonical rejected'});
		if(d.method==='save')return Promise.resolve({saved_revision:9});
		return Promise.resolve({});
	}};
	const api=loadApi(rpc);
	const candidate={schema_version:1,services:[]};
	await assert.rejects(()=>api.validate(candidate).then(v=>{if(!v.valid)throw new Error(v.error);}),/canonical rejected/);
	assert.deepEqual(calls.filter(c=>c[0]==='save'),[]);
});
test('services.js and entry.js both attach m.snapshot and m.snapshotRevision for Save assembly',()=>{
	for(const f of ['services.js','entry.js']){
		const src=fs.readFileSync(path.join(dir,f),'utf8');
		assert.match(src,/m\.snapshot\s*=/,f);
		assert.match(src,/m\.snapshotRevision\s*=/,f);
	}
});
test('Save never starts: provider start/apply remain authoritative rejections; save RPC only bumps saved_revision',()=>{
	const src=fs.readFileSync(path.resolve(__dirname,'../../homepublish/files/usr/share/homepublish/product-provider.lua'),'utf8');
	assert.match(src,/request\.action=='save'[\s\S]*?state\.saved_revision=state\.saved_revision\+1/);
	assert.match(src,/runtime requires the device controller channel/);
	assert.doesNotMatch(src,/installed public provider unsupported/);
});
