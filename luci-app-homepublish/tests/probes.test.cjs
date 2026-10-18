'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const file=path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish/probes.js');
function load(){return new Function('baseclass',fs.readFileSync(file,'utf8'))({extend:o=>o});}
test('probe queue bounds concurrency and handles individual failure without blocking other services',async()=>{
 const mod=load();let active=0,max=0;const states={};
 const queue=mod.create(async id=>{active++;max=Math.max(max,active);await new Promise(r=>setTimeout(r,5));active--;if(id==='b')throw Error('后端连接超时');return {ok:true,summary:'连接成功'};},(id,s)=>states[id]=s);
 await queue.run(['a','b','c']);assert.equal(max,2);assert.equal(states.a.summary,'连接成功');assert.equal(states.b.summary,'后端连接超时');assert.equal(states.c.ok,true);assert.equal(queue.pending(),false);
});
