#!/usr/bin/env node
'use strict';
const fs=require('fs'),assert=require('assert/strict'),path=require('path');
const src=fs.readFileSync(process.argv[2]||path.join(__dirname,'../htdocs/luci-static/resources/view/homevpn/overview.js'),'utf8');
const adapter=fs.readFileSync(path.join(__dirname,'acme-discovery-ui-test.cjs'),'utf8');
const {Node,E,all}=new Function(adapter.slice(adapter.indexOf('class Node'),adapter.indexOf('const tick'))+'; return {Node,E,all};')();
String.prototype.format=function(...a){let i=0;return this.replace(/%s/g,()=>a[i++]);};
async function main(){
 const requests=[],downloads=[],blobs=[],notes=[];
 let response={ok:true,sswan:'{"name":"中文"}',mobileconfig:'<plist>fixture</plist>',ca:'fixture PEM'};
 Node.prototype.click=function(){downloads.push(this.attrs.download);};
 const rpc={declare:d=>(...a)=>{assert.equal(d.method,'download');requests.push(a);return Promise.resolve(response);}};
 const ui={createHandlerFn:(_,fn)=>fn,addNotification:(...a)=>notes.push(a)};
 const document={createTextNode:x=>x,body:new Node('body')};
 const URL={createObjectURL:b=>{blobs.push(b);return 'blob:fixture';},revokeObjectURL(){}};
 const view=new Function('view','rpc','ui','E','_','location','history','document','URL','Blob',src)({extend:x=>x},rpc,ui,E,x=>x,{hash:'',reload(){}},{},document,URL,Blob);
 const root=view.render([{}, {users:[{name:'alice'}]}, {cert_mode:'selfsigned'}]);
 const click=async label=>{const button=all(root).find(n=>n.tag==='button'&&n.children.includes(label));assert(button,label);await button.listeners.click();};
 for(const [label,user,type,extension,mime,key] of [
  ['Android .sswan','alice','sswan','alice.sswan','application/vnd.strongswan.profile','sswan'],
  ['iOS/macOS profile','alice','mobileconfig','alice.mobileconfig','application/x-apple-aspen-config','mobileconfig'],
  ['Download CA certificate','','ca','homevpn-ca.crt','application/x-x509-ca-cert','ca']]){
  await click(label);assert.deepEqual(requests.at(-1),[user,type]);assert.equal(downloads.at(-1),extension);
  assert.equal(blobs.at(-1).type,mime);assert.equal(await blobs.at(-1).text(),response[key]);
 }
 const before=blobs.length;response={ok:false,error:'fixture refusal'};await click('Android .sswan');assert.equal(blobs.length,before);assert(notes.length);
 const text=all(root).flatMap(n=>n.children.filter(x=>typeof x==='string')).join(' ');
 assert.match(text,/strongSwan App/);assert.match(text,/system VPN settings/);assert.match(text,/file picker/);
 console.log('PASS: executed real view Android/iOS/CA buttons; RPC, Blob MIME/bytes, extension, refusal and guidance');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
