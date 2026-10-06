const fs=require('fs'),assert=require('assert/strict');
const path=require('path'),base=path.resolve(__dirname,'..');
const src=fs.readFileSync(process.argv[2]||path.join(base,'htdocs/luci-static/resources/view/homevpn/overview.js'),'utf8');
const adapter=fs.readFileSync(path.join(__dirname,'acme-discovery-ui-test.cjs'),'utf8');
const {Node,E,all}=new Function(adapter.slice(adapter.indexOf('class Node'),adapter.indexOf('const tick'))+'; return {Node,E,all};')();
Node.prototype.scrollIntoView=function(){this.scrolled=true;};
Node.prototype.focus=function(){this.focused=true;};
Node.prototype.removeAttribute=function(k){delete this.attrs[k];};
String.prototype.format=function(...args){let i=0;return this.replace(/%s/g,()=>args[i++]);};
const text=n=>typeof n==='string'?n:((n.textContent||'')+n.children.map(text).join(' '));
async function main(){
for(const entry of ['Apply IP settings','Save settings']){
 const saves=[],modals=[],notes=[];let response={ok:true,precheck_ok:true},reject=false;
 const rpc={declare:d=>(...a)=>{if(d.method==='set_settings'){saves.push(a);return reject?Promise.reject(new Error('transport failure')):Promise.resolve(response);}return Promise.resolve({});}};
 const ui={createHandlerFn:(_,fn)=>fn,addNotification:(...a)=>notes.push(a),showModal:(...a)=>modals.push(a),hideModal(){}};
 const view=new Function('view','rpc','ui','E','_','location','history','document',src)({extend:x=>x},rpc,ui,E,x=>x,{hash:'',reload(){}},{},{createTextNode:x=>x});
 const root=view.render([{}, {}, {ip_mode:'subnet',cert_mode:'selfsigned'}]),nodes=all(root);
 const cidr=nodes.find(n=>n.attrs.placeholder==='10.100.1.0/24'),button=nodes.find(n=>n.tag==='button'&&n.children.includes(entry));
 for(const value of ['', '   ', 'garbage','999.1.1.0/24','10.1.0.0/33']){
  cidr.value=value;await button.listeners.click();assert.equal(saves.length,0);
  assert.equal(cidr.attrs['aria-invalid'],'true','invalid CIDR must be marked at the field, not just notified above the viewport');
  assert(cidr.focused,'invalid CIDR focused');assert(nodes.find(n=>n.attrs.id==='homevpn-cidr-error').scrolled,'error explicitly scrolled into view');assert.match(text(root),/required|valid IPv4 CIDR/);
 }
 cidr.value='10.100.1.0/24';await button.listeners.click();assert.equal(saves.length,1);assert.equal(saves[0][8],cidr.value);
 response={ok:false,error:'backend refusal'};await button.listeners.click();assert(modals.length,'API refusal visibly displayed');
 reject=true;await button.listeners.click();assert(modals.some(a=>a.map(x=>Array.isArray(x)?x.map(text).join(' '):String(x)).join(' ').includes('transport failure')),'rejected RPC visibly displayed');
 console.log('PASS '+entry+': empty/whitespace/invalid/valid CIDR, inline focus, API refusal and transport failure');
}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
