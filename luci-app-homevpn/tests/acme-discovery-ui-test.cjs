const fs = require('fs');
const assert = require('assert/strict');
const src = fs.readFileSync(process.argv[2], 'utf8');
new Function(src);
class Node {
 constructor(tag, attrs = {}, kids = []) {
  this.tag = tag; this.attrs = attrs; this.style = {}; this.listeners = {};
  this.value = attrs.value || ''; this.children = []; this.textContent = '';
  if (attrs.click) this.listeners.click = attrs.click;
  (Array.isArray(kids) ? kids : [kids]).forEach(k => this.appendChild(k));
  if (tag === 'select') { const opt = this.children.find(k => k.attrs.selected) || this.children[0]; this.value = opt ? opt.value : ''; }
 }
 appendChild(k) { this.children.push(k); if (k && typeof k === 'object') k.parent = this; return k; }
 setAttribute(k,v) { this.attrs[k] = v; }
 addEventListener(k,fn) { this.listeners[k] = fn; }
 closest() { return this.parent; }
 get firstChild() { return this.children[0]; }
 removeChild(k) { this.children.splice(this.children.indexOf(k),1); }
}
const E = (t,a,k) => new Node(t,a,k);
const all = n => n && typeof n === 'object' ? [n,...n.children.flatMap(all)] : [];
const tick = () => new Promise(r => setTimeout(r, 0));
async function main() {
 const requests = [], saves = [], notes = [];
 let deferSave = false, finishSave;

 const rpc = {declare: def => (...args) => {
  if (def.method === 'discover_acme') return new Promise((resolve,reject) => requests.push({args,resolve,reject}));
  if (def.method === 'set_settings') { saves.push(args); return deferSave ? new Promise(r=>{finishSave=r;}) : Promise.resolve({ok:true,precheck_ok:true}); }
  return Promise.resolve({});
 }};
 const ui = {createHandlerFn: (_,fn) => fn, addNotification: (...n) => notes.push(n)};
 if (!String.prototype.format) String.prototype.format = function(...args) { let i=0; return this.replace(/%s/g,()=>args[i++]); };
 const view = new Function('view','rpc','ui','E','_','location','history','document', src)(
  {extend: x=>x}, rpc, ui, E, x=>x, {hash:'',reload(){}}, {}, {createTextNode:x=>x});
 const root = view.render([{}, {}, {cert_mode:'acme',acme_domain:'both.example',acme_key_type:'ecc'}]);
 const nodes = all(root), byId = id => nodes.find(n=>n.attrs.id===id);
 const domain = byId('homevpn-acme-domain');
 assert(domain, 'domain-driven discovery controls must exist');
 const selector = byId('homevpn-acme-type'), single = byId('homevpn-acme-single'), hint = byId('homevpn-acme-hint');
 const save = nodes.find(n=>n.tag==='button' && n.children.includes('Save and apply'));
 const apply = nodes.find(n=>n.tag==='button' && n.children.includes('Apply IP settings'));
 await tick();
 assert.equal(requests.length,1,'initial domain queried');
 await save.listeners.click(); await apply.listeners.click();
 assert.equal(saves.length,0,'both save entrances blocked while querying');
 requests[0].resolve({ok:true,domain:'both.example',types:['rsa','ecc']}); await tick();
 assert.equal(selector.style.display,''); assert.equal(selector.value,'ecc','preserve existing valid choice');
 console.log('PASS: initial query, both-save gating and retained dual-type selection');
 const edit = async value => { domain.value=value; domain.listeners.input(); await new Promise(r=>setTimeout(r,320)); return requests.at(-1); };
 const resolve = async (r,types) => { r.resolve({ok:true,domain:r.args[0],types}); await tick(); };
 let r = await edit('rsa.example'); await resolve(r,['rsa']);
 assert.equal(selector.style.display,'none'); assert.match(single.textContent,/RSA/);
 await save.listeners.click(); assert.deepEqual(saves.at(-1).slice(3,5),['rsa.example','rsa']);
 r = await edit('ecc.example'); await resolve(r,['ecc']);
 assert.equal(selector.style.display,'none'); assert.match(single.textContent,/ECC/);
 await apply.listeners.click(); assert.deepEqual(saves.at(-1).slice(3,5),['ecc.example','ecc']);
 console.log('PASS: RSA-only and ECC-only static display and actual payloads through both saves');
 let count=saves.length;
 r=await edit('none.example'); await resolve(r,[]);
 assert.match(hint.textContent,/No usable local certificate/); assert.equal(single.style.display,'none');
 await save.listeners.click(); await apply.listeners.click(); assert.equal(saves.length,count);
 r=await edit('both-new.example'); await resolve(r,['rsa','ecc']);
 assert.equal(selector.value,'rsa','fallback to RSA when no valid previous selection');
 selector.value='ecc'; selector.listeners.change();
 await save.listeners.click(); assert.equal(saves.at(-1)[4],'ecc');
 count=saves.length;
 const older=await edit('older.example');
 const newer=await edit('newer.example');
 await resolve(newer,['rsa']); await resolve(older,['ecc']);
 assert.match(single.textContent,/RSA/,'late success must not overwrite newer result');
 domain.value='not-queried.example';
 await save.listeners.click(); await apply.listeners.click(); assert.equal(saves.length,count,'programmatic stale domain blocked');
 const failure=await edit('failure.example'); failure.reject(new Error('transport')); await tick();
 assert.match(hint.textContent,/query failed/); await save.listeners.click(); assert.equal(saves.length,count);
 const lateError=await edit('late-error.example'); const good=await edit('good.example');
 await resolve(good,['ecc']); lateError.reject(new Error('late')); await tick();
 assert.match(single.textContent,/ECC/,'late failure ignored');
 const emptyRace=await edit('empty-race.example'); domain.value=''; domain.listeners.input();
 await resolve(emptyRace,['rsa','ecc']); assert.match(hint.textContent,/Enter the domain/);
 await save.listeners.click(); await apply.listeners.click(); assert.equal(saves.length,count);
 const before=requests.length; domain.value='a.example'; domain.listeners.input(); domain.value='b.example'; domain.listeners.input();
 await new Promise(r=>setTimeout(r,320)); assert.equal(requests.length,before+1,'debounce issues only latest request');
 r=requests.at(-1); r.resolve({ok:false,error:'resolver unavailable'}); await tick();
 assert.match(hint.textContent,/query failed/);
 r=await edit('bad-response.example'); r.resolve({ok:true,domain:'wrong.example',types:['rsa']}); await tick();
 assert.match(hint.textContent,/query failed/); await apply.listeners.click(); assert.equal(saves.length,count);
 console.log('PASS: zero, RSA default, changed selection, stale success/failure, empty, debounce, errors and save gating');
 r=await edit('snapshot.example'); await resolve(r,['ecc']); deferSave=true;
 const pending=save.listeners.click();
 assert.deepEqual(saves.at(-1).slice(3,5),['snapshot.example','ecc']);
 domain.value='edited-during-save.example'; domain.listeners.input();
 await apply.listeners.click(); assert.equal(saves.length,count+1,'in-flight submission cannot be duplicated');
 finishSave({ok:true,precheck_ok:true}); await pending; deferSave=false;
 await save.listeners.click(); assert.equal(saves.length,count+1,'edited domain remains gated after save');
 domain.value=''; domain.listeners.input();
 console.log('PASS: immutable submission snapshot, duplicate suppression and post-save stale-domain gate');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
