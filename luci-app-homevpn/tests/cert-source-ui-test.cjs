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
function run(source, mode='selfsigned') {
 const actual={enabled:false,mode,remote:'test.example',cert:{source,subject:'CN=test.example',fingerprint:'AA'},selfsigned:{ca_valid:true}};
 const rpc={declare:d=>()=>Promise.resolve(d.method==='status'?actual:{ok:true})};
 const ui={createHandlerFn:(_,fn)=>fn,addNotification(){}};
 const view=new Function('view','rpc','ui','E','_','location','history','document',src)({extend:x=>x},rpc,ui,E,x=>x,{hash:'',reload(){}},{},{createTextNode:x=>x,body:new Node('body')});
 const root=view.render([actual,{users:[]},{cert_mode:mode,remote:'test.example'}]);
 const nodes=all(root),id=x=>nodes.find(n=>n.attrs.id===x);
 const select=nodes.find(n=>n.tag==='select'&&n.children.some(c=>c.value==='import'));
 select.value='import';select.listeners.change();
 return {root,nodes,id};
}
for (const source of ['selfsigned','acme','unknown',undefined,'import']) {
 const h=run(source);
 assert(h.nodes.some(n=>n.tag==='strong'&&text(n)==='Currently deployed certificate'),'neutral deployed title');
 const box=h.id('homevpn-import-upload');assert(box,'upload reachable');
 assert.equal(box.style.display,source==='import'?'none':'','only genuine import may collapse upload');
 const info=h.id('homevpn-deployed-certificate');assert.equal(info.style.display,'');
 assert.match(text(info),/Certificate source/);assert.match(text(info),/SHA-256 fingerprint/);
 if(source==='selfsigned') assert.match(text(info),/Selecting import mode does not replace/);
 assert(!text(info).includes('Imported certificate'));
}
console.log('PASS: neutral deployed title, explicit fingerprint/source, mode-switch warning and visible non-import upload');
