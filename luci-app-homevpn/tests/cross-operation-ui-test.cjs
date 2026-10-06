const fs=require('fs'),assert=require('assert/strict'),path=require('path');
const dir=path.join(__dirname,'..');
const src=fs.readFileSync(path.join(dir,'htdocs/luci-static/resources/view/homevpn/overview.js'),'utf8');
const adapter=fs.readFileSync(path.join(__dirname,'selfsigned-ui-test.cjs'),'utf8');
const {E,all}=new Function(adapter.slice(adapter.indexOf('class Node'),adapter.indexOf('const tick'))+';return {E,all};')();
String.prototype.format=function(...a){let i=0;return this.replace(/%s/g,()=>a[i++]);};
const actual={enabled:true,running:true,mode:'import',remote:'vpn.example.com',pki_ready:true,conn_loaded:true};
let statusResolve,provisions=0,statusCalls=0;
const rpc={declare:d=>(...a)=>{
 if(d.method==='set_enabled')return Promise.resolve({ok:true});
 if(d.method==='status'){statusCalls++;return new Promise(r=>statusResolve=r);}
 if(d.method==='provision'){provisions++;return Promise.resolve({ok:false,error:'fixture'});}
 return Promise.resolve({});
}};
const ui={createHandlerFn:(_,fn)=>fn,addNotification(){},showModal(){},hideModal(){}};
const view=new Function('view','rpc','ui','E','_','location','history','document',src)({extend:x=>x},rpc,ui,E,x=>x,{hash:'',reload(){}},{},{createTextNode:x=>x});
const root=view.render([actual,{users:[]},{cert_mode:'import',remote:'vpn.example.com'}]);
const nodes=all(root),toggle=nodes.find(n=>n.attrs.id==='homevpn-toggle'),provision=nodes.find(n=>n.attrs.id==='homevpn-provision');
(async()=>{
 const pending=toggle.listeners.click();await new Promise(r=>setTimeout(r,0));
 assert.equal(statusCalls,1);assert(toggle.disabled);assert(provision.disabled);
 await provision.listeners.click();
 assert.equal(provisions,0,'provision must be blocked through toggle status readback');
 statusResolve({...actual,enabled:false,running:false});await pending;
 assert(!provision.disabled);
 console.log('PASS cross-operation gate includes full toggle/readback cycle');
})().catch(e=>{console.error(e);process.exitCode=1;});
