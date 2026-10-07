const fs=require('fs'),assert=require('assert/strict'),path=require('path');
const base=path.resolve(__dirname,'..');
const src=fs.readFileSync(path.join(base,'htdocs/luci-static/resources/view/homevpn/overview.js'),'utf8');
const adapter=fs.readFileSync(path.join(__dirname,'acme-discovery-ui-test.cjs'),'utf8');
const {Node,E,all}=new Function(adapter.slice(adapter.indexOf('class Node'),adapter.indexOf('const tick'))+'; return {Node,E,all};')();
Node.prototype.scrollIntoView=function(){};Node.prototype.focus=function(){};
String.prototype.format=function(...args){let i=0;return this.replace(/%s/g,()=>args[i++]);};
async function run(){
 const sent=[];const rpc={declare:d=>(...args)=>{if(d.method==='set_settings')sent.push(args);return Promise.resolve({ok:true,saved:true});}};
 const ui={createHandlerFn:(_,fn)=>fn,addNotification(){},showModal(){},hideModal(){}};
 const view=new Function('view','rpc','ui','E','_','location','history','document',src)({extend:x=>x},rpc,ui,E,x=>x,{hash:'',reload(){}},{},{createTextNode:x=>x});
 const root=view.render([{}, {}, {cert_mode:'import',traffic_scope:'full'}]),nodes=all(root);
 const scope=nodes.find(n=>n.attrs.id==='homevpn-traffic-scope');
 assert(scope,'global traffic scope selector must render');
 assert.equal(scope.value,'full','saved full mode must load');
 const provision=nodes.find(n=>n.attrs.id==='homevpn-provision');
 assert.equal(provision.disabled,false,'saved scope must not be dirty');
 scope.value='lan';scope.listeners.change();
 assert.equal(provision.disabled,true,'changed scope blocks reapply saved settings');
 const save=nodes.find(n=>n.tag==='button'&&n.children.includes('Save and apply'));
 await save.listeners.click();
 assert.equal(sent.length,1);assert.equal(sent[0][10],'lan');
 assert.equal(provision.disabled,false,'successful save resets dirty baseline');
 console.log('PASS traffic scope UI load, dirty, payload, save baseline');
}
run().catch(e=>{console.error(e);process.exitCode=1;});
