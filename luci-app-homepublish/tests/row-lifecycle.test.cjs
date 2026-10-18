/* r9 row lifecycle: the services GridSection rows live in the JSONMap data
 * (CBIJSONConfig semantics from the real LuCI 24.10 form.js), and Save
 * assembles canonical rows via collectConfig(). The former version of this
 * test reached into docs/artifacts/luci-target-assets form.js which no longer
 * ships; the JSONMap semantics below mirror the shipped LuCI form.js. */
const {test}=require('node:test');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const dir=path.resolve(__dirname,'../htdocs/luci-static/resources/view/homepublish');

/* Minimal CBIJSONConfig faithful to LuCI 24.10 form.js: array-of-objects
 * sectiontype data gains .name/.type/.anonymous/.index; add() synthesizes the
 * next section id; get(section) returns the whole row object. */
class JSONConfig{
	constructor(data){
		this.data={};
		const ids=[];
		let n=0;
		for(const sectiontype in data){
			if(!Array.isArray(data[sectiontype]))continue;
			for(let i=0;i<data[sectiontype].length;i++){
				const item=data[sectiontype][i];
				if(typeof item!=='object'||item===null)continue;
				const name=(typeof item['.name']==='string')?item['.name']:(sectiontype+n);
				if(!Object.prototype.hasOwnProperty.call(this.data,name))ids.push(name);
				this.data[name]=Object.assign(item,{
					'.index':n,'.anonymous':typeof item['.name']!=='string','.name':name,'.type':sectiontype
				});
				n++;
			}
		}
		for(const id of ids)if(this.data[id]['.index']===undefined)this.data[id]['.index']=0;
	}
	get(config,section,option){
		if(section==null)return null;
		if(option==null)return this.data[section];
		if(!Object.prototype.hasOwnProperty.call(this.data,section))return null;
		const v=this.data[section][option];
		return Array.isArray(v)?v:(v!=null?String(v):null);
	}
	add(config,sectiontype,sectionname){
		let count=0,next=0;
		for(const name in this.data){
			if(this.data[name]['.type']===sectiontype)count++;
			next=Math.max(next,this.data[name]['.index']);
		}
		const id=sectionname??(sectiontype+count);
		if(!Object.prototype.hasOwnProperty.call(this.data,id))
			this.data[id]={'.name':id,'.type':sectiontype,'.anonymous':sectionname==null,'.index':next+1};
		return id;
	}
	remove(config,section){
		delete this.data[section];
	}
	sections(config,sectiontype){
		const rv=[];
		for(const id in this.data)
			if(sectiontype==null||this.data[id]['.type']===sectiontype)rv.push(this.data[id]);
		rv.sort((a,b)=>a['.index']-b['.index']);
		return rv;
	}
	save(){return Promise.resolve();}
}

/* Load real product.js collectConfig for assembly checks. */
function loadApi(){
	const rpc={declare:d=>(...a)=>Promise.resolve({})};
	const src=fs.readFileSync(path.join(dir,'product.js'),'utf8').replace(/'require[^']*';/g,'');
	return new Function('baseclass','rpc','_','view','dom','E','L',src)(
		{extend:o=>o},rpc,s=>s,{extend:o=>o},{findClassInstance(){return null}},
		function(){return {appendChild(){},querySelector(){return null}}},{url(){return ''}});
}

const savedBase={schema_version:1,services:[{
		service_id:'fixture',name:'A',hostname:'a.fixture.home',enabled:true,
		backend:{addressFamily:'ipv4',host:'127.0.0.1',port:49285,allowed_ranges:['192.168.1.0/24']},
		certificate_ref:'acme:fixture_rsa',certificate_mode:'override',
		authentication_review:{authentication:'confirmed',management:false}
	}],
	default_certificate_ref:'acme:home_rsa',
	access_profile:{methods_allowed:['manual_ipv4'],listeners:[{family:'ipv4',address:'192.168.1.2',interface:'br-lan',zone:'lan',protocol:'tcp',internal_port:49284,external_port:49284}]},
	publication_policy:{mode:'continuous',boot_restore:false}};

test('JSONMap row add: new service row lands in data and collectConfig assembles it as canonical',()=>{
	const api=loadApi();
	const cfg=new JSONConfig({services:JSON.parse(JSON.stringify(savedBase.services))});
	const sid=cfg.add('json','services');
	assert.equal(sid,'services1');
	assert.equal(cfg.data[sid]['.anonymous'],true);
	/* user fills the modal options; writes land on the row object */
	Object.assign(cfg.data[sid],{name:'B',hostname:'b.fixture.home',enabled:'1',
		backend:{addressFamily:'ipv4',host:'127.0.0.1',port:49286,allowed_ranges:[]},
		certificate_mode:'inherit',backend_url:'http://127.0.0.1:49286',
		authentication_review:{authentication:'confirmed',management:false}});
	const map={snapshot:JSON.parse(JSON.stringify(savedBase)),snapshotRevision:2,data:cfg};
	const out=api.collectConfig(map);
	assert.equal(out.services.length,2);
	assert.equal(out.services[1].service_id,'services1');
	assert.equal(out.services[1].enabled,true);
	assert.equal(out.services[1].backend.port,49286);
	assert.equal('backend_url' in out.services[1],false);
	assert.equal('certificate_ref' in out.services[1],false);
});
test('row remove: deleted service disappears from the assembled canonical config',()=>{
	const api=loadApi();
	const cfg=new JSONConfig({services:JSON.parse(JSON.stringify(savedBase.services))});
	cfg.add('json','services');
	cfg.remove('json','services0');
	const map={snapshot:JSON.parse(JSON.stringify(savedBase)),snapshotRevision:2,data:cfg};
	const out=api.collectConfig(map);
	assert.equal(out.services.length,1);
	assert.equal(out.services[0].service_id,'services1');
});
test('services view drives rows from the JSONMap data (addremove + anonymous + sortable + modalizable)',()=>{
	const src=fs.readFileSync(path.join(dir,'services.js'),'utf8');
	assert.match(src,/s\.addremove\s*=\s*true/);
	assert.match(src,/s\.anonymous\s*=\s*true/);
	assert.match(src,/s\.sortable\s*=\s*true/);
	assert.match(src,/s\.modalizable\s*=\s*true/);
});
test('certificate_ref column renders inline textvalue resolving the ACME inventory',()=>{
	const src=fs.readFileSync(path.join(dir,'services.js'),'utf8');
	assert.match(src,/form\.ListValue,\s*'certificate_ref'/);
	assert.match(src,/o\.textvalue\s*=\s*function/);
});
