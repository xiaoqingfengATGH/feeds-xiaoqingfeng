const {test}=require('node:test');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const dir=path.resolve(__dirname,'../htdocs/luci-static/resources/view/homepublish');
function setup(fail){
 const calls=[], node={textContent:''}; let view;
 const map={save:async()=>{calls.push('save');if(fail==='save')throw Error('invalid');}};
 const rpc={declare:d=>(...args)=>{calls.push([d.method,...args]);if(fail===d.method)return Promise.reject(Error('rpc failed'));return Promise.resolve(d.method==='status'?{state:'configured',publication:'disabled'}:0);}};
 view=new Function('view','rpc','uci','form','schema','E','_',fs.readFileSync(path.join(dir,'settings.js'),'utf8'))({extend:v=>v},rpc,{}, {}, {},()=>{},x=>x);
 view.map=map;view.statusNode=node;return {view,calls,node};
}
test('Save stages then commits homepublish only and refreshes committed status',async()=>{
 const {view,calls,node}=setup();assert.equal(typeof view.handleSave,'function');
 await view.handleSave();assert.deepEqual(calls,['save',['commit','homepublish'],['status']]);assert.match(node.textContent,/configured/);
});
test('failed save or commit cannot claim refreshed committed status',async()=>{
 for(const failure of ['save','commit']){const {view,calls,node}=setup(failure);await assert.rejects(()=>view.handleSave());assert.equal(node.textContent,'');assert(!calls.some(c=>Array.isArray(c)&&c[0]==='status'));}
});
