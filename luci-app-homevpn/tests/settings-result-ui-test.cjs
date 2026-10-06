const fs=require('fs'),assert=require('assert/strict'),path=require('path');
const src=fs.readFileSync(path.join(__dirname,'../htdocs/luci-static/resources/view/homevpn/overview.js'),'utf8');
const adapter=fs.readFileSync(path.join(__dirname,'acme-discovery-ui-test.cjs'),'utf8');
const {Node,E,all}=new Function(adapter.slice(adapter.indexOf('class Node'),adapter.indexOf('const tick'))+'; return {Node,E,all};')();
Node.prototype.removeAttribute=function(k){delete this.attrs[k];};
String.prototype.format=function(...args){let i=0;return this.replace(/%s/g,()=>args[i++]);};
const text=n=>typeof n==='string'?n:((n.textContent||'')+n.children.map(text).join(' '));
const results=process.argv[2]?JSON.parse(fs.readFileSync(process.argv[2],'utf8')).stdout.trim().split('\n').map(l=>JSON.parse(l.slice(l.indexOf('{')))):[{ok:true,saved:true,precheck_ok:true,output:'applied'},{ok:false,saved:true,precheck_ok:false,error:'Settings saved, but application failed.',output:'precheck refused fixture'},{ok:false,saved:true,precheck_ok:false,error:'Settings saved, but application failed.',output:'runtime failed fixture'}];
(async()=>{
for(const entry of ['Apply IP settings','Save settings'])for(const response of results){
 const modals=[],notes=[];let reloads=0;
 const rpc={declare:d=>()=>Promise.resolve(d.method==='set_settings'?response:{})};
 const ui={createHandlerFn:(_,fn)=>fn,addNotification:(...a)=>notes.push(a),showModal:(...a)=>modals.push(a),hideModal(){}};
 const view=new Function('view','rpc','ui','E','_','location','history','document',src)({extend:x=>x},rpc,ui,E,x=>x,{hash:'',reload(){reloads++;}},{},{createTextNode:x=>x});
 const root=view.render([{}, {}, {ip_mode:'subnet',cert_mode:'selfsigned'}]),nodes=all(root);
 const cidr=nodes.find(n=>n.attrs.placeholder==='10.100.1.0/24'),button=nodes.find(n=>n.tag==='button'&&n.children.includes(entry));
 cidr.value='10.123.0.0/24';await button.listeners.click();
 if(response.ok){assert.equal(reloads,1);assert.equal(modals.length,0);}else{
  assert.equal(reloads,0);assert.equal(cidr.value,'10.123.0.0/24');assert.equal(modals.length,1);
  const message=modals[0][1].map(text).join(' ');assert(message.includes(response.output),'failure modal must include actual apply output: '+message);
  assert(!notes.some(a=>JSON.stringify(a).includes('Applied.')));
 }
 console.log('PASS '+entry+' '+response.output);
}
})().catch(e=>{console.error(e);process.exitCode=1;});
