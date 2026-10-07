const fs=require('fs'),assert=require('assert/strict');
const base=fs.readFileSync(__dirname+'/cert-source-ui-test.cjs','utf8').split("for (const source of")[0].replace("select.value='import';select.listeners.change();","").replace('return {root,nodes,id};','return {root,nodes,id,select};').replace("fingerprint:'AA'","fingerprint:'AA',san:'test.example',notafter:'2030',key_matches:true");
eval(base+`
for(const source of ['selfsigned','acme','unknown','import']) {
 const h=run(source);let deployed;
 for(const mode of ['selfsigned','acme','import','selfsigned']) {
  h.select.value=mode;h.select.listeners.change();
  const info=h.id('homevpn-deployed-certificate');
  assert.equal(info.style.display,'','deployed certificate is shared in '+mode);
  const table=info.children.find(n=>n.attrs&&n.attrs.class==='table');
  deployed??=text(table);assert.equal(text(table),deployed,'mode draft must not change actual certificate');
  assert.match(text(table),/test.example/);assert.match(text(table),/AA/);assert.match(text(table),/matches the certificate/);
  assert.equal(h.id('homevpn-import-source-hint').style.display,mode==='import'?'':'none');
  assert.equal(h.id('homevpn-import-replace').style.display,mode==='import'?'':'none');
  if(mode!=='import')assert.equal(h.id('homevpn-import-upload').style.display,'none');
 }
 assert.match(text(h.root),/ACME candidates are not deployed/);
 const pki=h.id('homevpn-selfsigned');assert(pki,'selfsigned panel exists');
 assert(!text(pki).includes('Deployed certificate SAN'),'selfsigned must not duplicate deployed leaf details');
}
console.log('PASS shared deployed certificate and mode-only operations');
`);
const emptyBase=base.replace("cert:{source,subject:'CN=test.example',fingerprint:'AA',san:'test.example',notafter:'2030',key_matches:true}","cert:null");
eval(emptyBase+`
 const h=run('acme','acme');
 for(const mode of ['selfsigned','acme','import']) {
  h.select.value=mode;h.select.listeners.change();
  const info=h.id('homevpn-deployed-certificate');
  assert.equal(info.style.display,'');
  assert.match(text(info),/No certificate deployed/);
  assert(!text(info).includes(' — valid'));
  assert.equal(h.id('homevpn-import-replace').style.display,'none');
 }
 console.log('PASS explicit empty deployment across all modes');
`);
const candidateBase=emptyBase.replace("d.method==='status'?actual:{ok:true}","d.method==='status'?actual:d.method==='discover_acme'?{ok:true,domain:'test.example',types:['rsa','ecc']}:{ok:true}").replace("{cert_mode:mode,remote:'test.example'}","{cert_mode:mode,remote:'test.example',acme_domain:'test.example'}");
eval(candidateBase+`
(async()=>{
 const h=run('acme','acme');
 await new Promise(r=>setTimeout(r,30));
 assert.match(text(h.root),/Local certificate found/,'successful candidate discovery exercised');
 assert.match(text(h.id('homevpn-deployed-certificate')),/No certificate deployed yet/,'candidate discovery must not manufacture deployment');
 console.log('PASS successful dual ACME discovery remains candidate-only with no deployed certificate');
})().catch(e=>{console.error(e);process.exitCode=1;});
`);
