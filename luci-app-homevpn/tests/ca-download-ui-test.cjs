const fs=require('fs'),assert=require('assert/strict');
const src=fs.readFileSync(process.argv[2],'utf8');
class Node {
 constructor(tag,attrs={},kids=[]){this.tag=tag;this.attrs=attrs;this.style={};this.listeners={};this.disabled=Object.prototype.hasOwnProperty.call(attrs,'disabled');this.value=attrs.value||'';this.children=[];this.textContent='';if(attrs.click)this.listeners.click=attrs.click;(Array.isArray(kids)?kids:[kids]).forEach(k=>this.appendChild(k));if(tag==='select'){let o=this.children.find(n=>n.attrs.selected)||this.children[0];this.value=o?o.value:'';}}
 appendChild(n){this.children.push(n);if(n&&typeof n==='object')n.parent=this;return n;}
 removeChild(n){this.children.splice(this.children.indexOf(n),1);}
 querySelectorAll(selector){return all(this).slice(1).filter(n=>n.tag===selector);}
 get firstChild(){return this.children[0];} setAttribute(k,v){this.attrs[k]=v;} addEventListener(k,f){const old=this.listeners[k];this.listeners[k]=old?function(...args){old(...args);return f(...args);}:f;} click(){this.clicked=true;} closest(){return this.parent;} focus(){this.focused=true;} scrollIntoView(){this.scrolled=true;}
}
const E=(t,a,k)=>new Node(t,a,k),all=n=>n&&typeof n==='object'?[n,...n.children.flatMap(all)]:[],text=n=>typeof n==='string'?n:n&&typeof n==='object'?n.textContent+n.children.map(text).join(''):'';
const tick=()=>new Promise(r=>setTimeout(r,0));
String.prototype.format=function(...a){let i=0;return this.replace(/%s/g,()=>a[i++]);};
async function run(mode='selfsigned', extra={}, discovery={}){
 let actual={enabled:false,mode,remote:'',selfsigned:{ca_valid:true,leaf_state:'remote_required',fingerprint:'AA',notafter:'2030'}};
 const calls=[],saves=[],modals=[];let finishSave,finishCA;
 const rpc={declare:d=>(...args)=>{calls.push([d.method,args]);if(d.method==='ensure_selfsigned_ca')return new Promise(r=>finishCA=r);if(d.method==='set_settings'){saves.push(args);return new Promise(r=>finishSave=r);}if(d.method==='status')return Promise.resolve(actual);if(d.method==='get_settings')return Promise.resolve({cert_mode:mode,remote:''});if(d.method==='list_users')return Promise.resolve({users:[]});if(d.method==='discover_acme')return Promise.resolve(discovery);if(d.method==='download')return Promise.resolve({ok:true,ca:'PUBLIC CA'});return Promise.resolve({});}};
 const ui={createHandlerFn:(_,fn)=>fn,addNotification(){},showModal(t,k){modals.push(E('div',{},[t,...k]));},hideModal(){}};
 const view=new Function('view','rpc','ui','E','_','location','history','document',src)({extend:x=>x},rpc,ui,E,x=>x,{hash:'',reload(){throw Error('draft-destroying reload');}}, {},{createTextNode:x=>x,body:new Node('body')});
 const root=view.render([actual,{users:[]},{cert_mode:mode,remote:'',...extra}]);let nodes=all(root),id=x=>nodes.find(n=>n.attrs.id===x);
 assert(id('homevpn-selfsigned'),'selfsigned lifecycle panel missing');
 await tick();
 if(mode==='selfsigned'){assert.equal(calls.filter(x=>x[0]==='ensure_selfsigned_ca').length,1);finishCA({ok:true});await tick();await tick();}
 else assert.equal(calls.filter(x=>x[0]==='ensure_selfsigned_ca').length,0);
 return {calls,saves,modals,id,nodes:all(root),actual,setActual:x=>actual=x,finishSave:r=>finishSave(r),finishCA:r=>finishCA(r)};
}
(async()=>{
 for(const mode of ['selfsigned','import','acme']) {
  const h=await run(mode);
  const buttons=h.nodes.filter(n=>n.tag==='button'&&/Download.*CA/.test(text(n)));
  assert.equal(buttons.length,1,mode+': exactly one CA download entry');
  assert.equal(text(buttons[0]),'Download CA certificate');
  assert.equal(buttons[0].disabled,false,'CA-only download must not require remote');
  assert(h.nodes.some(n=>n.tag==='h3'&&text(n)==='Manual client setup (no profile)'));
  if(mode==='selfsigned') {
   assert.match(text(h.id('homevpn-pki-details')),/For manual client configuration, download and install the CA certificate below\./);
   assert.match(text(h.id('homevpn-pki-details')),/SHA-256 fingerprint/);
   assert.equal(h.id('homevpn-pki-details').querySelectorAll('button').length,1);
   assert.equal(text(h.id('homevpn-pki-details').querySelectorAll('button')[0]),'Replace root CA…');
  }
  await buttons[0].listeners.click();
  assert.deepEqual(h.calls.filter(x=>x[0]==='download').map(x=>x[1]),[['','ca']]);
  assert.equal(h.saves.length,0,'download cannot save settings');
 }
 console.log('PASS: unique shared CA entry across three modes, self-signed guidance, retained replacement/status and empty-remote CA-only download');
})().catch(e=>{console.error(e);process.exitCode=1;});
