const {test}=require('node:test');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const base=path.resolve(__dirname,'..'),dir=path.join(base,'htdocs/luci-static/resources/view/homestun');
const target=fs.readFileSync(path.resolve(base,'../docs/artifacts/luci-target-assets/www/luci-static/resources/form.js'),'utf8');
// Run the actual target methods, not reimplementations of their lifecycle.
function method(start,end){const i=target.indexOf(start);assert(i>=0,start);const j=target.indexOf(end,i);assert(j>i,end);return new Function('ui','E','_',`return ({${target.slice(i,j)}})` )({showModal(){}},()=>{},x=>x)[start.split('(')[0]];}
const handleAdd=method('handleAdd(ev,name){',',handleRemove(');
const save=method('save(cb,silent){',',reset(');
const parse=method('parse(){const tasks=[];',',save(');
const schema=new Function('baseclass',fs.readFileSync(path.join(dir,'schema.js'),'utf8'))({extend:v=>v});
function setup(){
 const calls=[],rows={h1:{name:'a.example',upstream:'http://10.0.0.1:8080'}},main={enabled:'1',exposure_approved:'1',ttl:'60',port:'18443',bind_port:'18444',stun_server:'stun.example',http_server:'example.com'};
 class Map {
  constructor(config){this.config=config;this.children=[];this.data={add:()=>{rows.h2={};calls.push('add');return 'h2';},save:async()=>calls.push('stage')};}
  section(type){const hosts=type==='typed';const section={map:this,sectiontype:hosts?'host':'service',cfgsections:()=>Object.keys(rows),formvalue:(id,k)=>(hosts?rows[id]:main)[k],option:()=>({depends(){}}),parse:async()=>{},handleAdd};this.children.push(section);return section;}
  checkDepends(){} load(){return Promise.resolve();} renderContents(){calls.push('render');return Promise.resolve({});} render(){return this.renderContents();}
 }
 Map.prototype.save=save;Map.prototype.parse=parse;
 const rpc={declare:d=>(...args)=>{calls.push([d.object,d.method,...args]);return Promise.resolve(d.method==='status'?{state:'configured'}:0);}};
 const v=new Function('view','form','rpc','uci','schema','E','_',fs.readFileSync(path.join(dir,'settings.js'),'utf8'))({extend:v=>v},{Map,NamedSection:'named',TypedSection:'typed',Flag:'flag',Value:'value',DummyValue:'dummy'},rpc,{},schema,()=>({textContent:''}),x=>x);
 return {v,rows,main,calls};
}
test('actual target TypedSection adds an editable row while enabled; final Save rejects incomplete row and commits valid rows',async()=>{
 const {v,rows,calls}=setup();await v.render([{state:'configured'}]);calls.length=0;
 await v.map.children[1].handleAdd();assert.deepEqual(calls,['add','stage','render']);assert.deepEqual(rows.h2,{});
 await assert.rejects(()=>v.handleSave());assert(!calls.some(c=>Array.isArray(c)&&c[1]==='commit'));
 rows.h2={name:'b.example',upstream:'http://10.0.0.2:8080'};await v.handleSave();assert.deepEqual(calls.filter(Array.isArray),[['uci','commit','homestun'],['homestun','status']]);
});
test('final Save still rejects duplicate hostnames and missing exposure approval without commit',async()=>{
 const {v,rows,main,calls}=setup();await v.render([{}]);rows.h2={...rows.h1};await assert.rejects(()=>v.handleSave());delete rows.h2;main.exposure_approved='0';await assert.rejects(()=>v.handleSave());assert(!calls.some(c=>Array.isArray(c)&&c[1]==='commit'));assert(!calls.includes('stage'));
});
