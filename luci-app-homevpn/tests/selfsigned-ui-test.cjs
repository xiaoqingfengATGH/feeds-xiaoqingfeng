const fs=require('fs'),assert=require('assert/strict');
const src=fs.readFileSync(process.argv[2],'utf8');
class Node {
 constructor(tag,attrs={},kids=[]){this.tag=tag;this.attrs=attrs;this.style={};this.listeners={};this.disabled=Object.prototype.hasOwnProperty.call(attrs,'disabled');this.value=attrs.value||'';this.children=[];this.textContent='';if(attrs.click)this.listeners.click=attrs.click;(Array.isArray(kids)?kids:[kids]).forEach(k=>this.appendChild(k));if(tag==='select'){let o=this.children.find(n=>n.attrs.selected)||this.children[0];this.value=o?o.value:'';}}
 appendChild(n){this.children.push(n);if(n&&typeof n==='object')n.parent=this;return n;}
 removeChild(n){this.children.splice(this.children.indexOf(n),1);}
 querySelectorAll(selector){return all(this).slice(1).filter(n=>n.tag===selector);}
 get firstChild(){return this.children[0];} setAttribute(k,v){this.attrs[k]=v;} addEventListener(k,f){this.listeners[k]=f;} closest(){return this.parent;} focus(){this.focused=true;} scrollIntoView(){this.scrolled=true;}
}
const E=(t,a,k)=>new Node(t,a,k),all=n=>n&&typeof n==='object'?[n,...n.children.flatMap(all)]:[],text=n=>typeof n==='string'?n:n&&typeof n==='object'?n.textContent+n.children.map(text).join(''):'';
const tick=()=>new Promise(r=>setTimeout(r,0));
String.prototype.format=function(...a){let i=0;return this.replace(/%s/g,()=>a[i++]);};
async function run(mode='selfsigned'){
 let actual={enabled:false,mode,remote:'',selfsigned:{ca_valid:true,leaf_state:'remote_required',fingerprint:'AA',notafter:'2030'}};
 const calls=[],saves=[],modals=[];let finishSave,finishCA;
 const rpc={declare:d=>(...args)=>{calls.push([d.method,args]);if(d.method==='ensure_selfsigned_ca')return new Promise(r=>finishCA=r);if(d.method==='set_settings'){saves.push(args);return new Promise(r=>finishSave=r);}if(d.method==='status')return Promise.resolve(actual);if(d.method==='get_settings')return Promise.resolve({cert_mode:mode,remote:''});if(d.method==='list_users')return Promise.resolve({users:[]});return Promise.resolve({});}};
 const ui={createHandlerFn:(_,fn)=>fn,addNotification(){},showModal(t,k){modals.push(E('div',{},[t,...k]));},hideModal(){}};
 const view=new Function('view','rpc','ui','E','_','location','history','document',src)({extend:x=>x},rpc,ui,E,x=>x,{hash:'',reload(){throw Error('draft-destroying reload');}}, {},{createTextNode:x=>x});
 const root=view.render([actual,{users:[]},{cert_mode:mode,remote:''}]);let nodes=all(root),id=x=>nodes.find(n=>n.attrs.id===x);
 assert(id('homevpn-selfsigned'),'selfsigned lifecycle panel missing');
 await tick();
 if(mode==='selfsigned'){assert.equal(calls.filter(x=>x[0]==='ensure_selfsigned_ca').length,1);finishCA({ok:true});await tick();await tick();}
 else assert.equal(calls.filter(x=>x[0]==='ensure_selfsigned_ca').length,0);
 return {calls,saves,modals,id,nodes,actual,setActual:x=>actual=x,finishSave:r=>finishSave(r),finishCA:r=>finishCA(r)};
}
(async()=>{
 let h=await run();assert(h.id('homevpn-pki-details').querySelectorAll('button').every(b=>!b.disabled),'CA actions must be enabled after preparation (real DOM disabled attribute semantics)');assert.match(text(h.id('homevpn-selfsigned')),/address|Address/);
 const remote=h.id('homevpn-remote'),hint=h.id('homevpn-pki-draft'),mode=h.id('homevpn-cert-mode');
 remote.value='vpn.example.com';remote.listeners.input();assert.match(text(hint),/unsaved changes/);
 assert.equal(h.calls.filter(x=>x[0]==='set_settings').length,0,'typing cannot mutate');
 const save=h.nodes.find(n=>n.tag==='button'&&n.children.includes('Save and apply'));
 const apply=h.nodes.find(n=>n.tag==='button'&&n.children.includes('Apply IP settings'));
 assert(save&&apply);
 remote.value='https://vpn.example.com';remote.listeners.input();await save.listeners.click();await apply.listeners.click();assert.equal(h.saves.length,0);assert.equal(remote.attrs['aria-invalid'],'true');assert(remote.focused&&h.id('homevpn-remote-error').scrolled);
 remote.value='vpn.example.com';remote.listeners.input();let pending=save.listeners.click();await tick();assert.equal(h.saves.length,1);
 assert(h.id('homevpn-pki-details').querySelectorAll('button').every(b=>b.disabled),'CA controls must stay disabled throughout save/readback');
 remote.value='new.example.com';remote.listeners.input();await apply.listeners.click();assert.equal(h.saves.length,1);assert.equal(h.saves[0][0],'vpn.example.com');
 h.setActual({...h.actual,remote:'vpn.example.com',pki_ready:true,selfsigned:{ca_valid:true,leaf_state:'ready',fingerprint:'AA'}});
 h.finishSave({ok:true,precheck_ok:true,saved:true,applied:true});await pending;
 assert.equal(remote.value,'new.example.com');assert.match(text(hint),/unsaved changes/);assert.equal(h.id('homevpn-provision').disabled,true);
 // Unsaved mode changes do not create trust assets.
 h=await run('import');mode.value='import';const m=h.id('homevpn-cert-mode');m.value='selfsigned';m.listeners.change();await tick();assert.equal(h.calls.filter(x=>x[0]==='ensure_selfsigned_ca').length,0);
 console.log('PASS: saved-mode-only CA initialization, draft/deployment split, both-save validation, snapshot, duplicate suppression, no reload and disabled provision');
})().catch(e=>{console.error(e);process.exitCode=1;});
