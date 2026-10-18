import {test} from 'node:test';
import assert from 'node:assert/strict';
import {fixture as sessionFixture,session,lease as mapping} from './publication-fixture.mjs';

test('Worker entry uses one Durable Object and fails closed on binding errors',async()=>{
 const {default:worker}=await import('../files/usr/share/homepublish/worker/worker.mjs');
 assert.equal((await worker.fetch(req('/go/nas'),{})).status,503);
 let name;
 const res=await worker.fetch(req('/go/nas'),{PORTAL:{idFromName:n=>{name=n;return 'id';},get:()=>({fetch:async()=>new Response('Closed',{status:410})})}});
 assert.equal(name,'homepublish'); assert.equal(res.status,410);
});

test('portal fails closed when authentication secrets are absent', async()=>{
 const {LeasePortal}=await import('../files/usr/share/homepublish/worker/worker.mjs');
 const portal=new LeasePortal({storage:{}},{});
 const res=await portal.fetch(new Request('https://stun-test.innonext.win/go/nas'));
 assert.equal(res.status,503);
 assert.equal(res.headers.get('Location'),null);
});

async function fixture(){
 const {LeasePortal}=await import('../files/usr/share/homepublish/worker/worker.mjs');
 return sessionFixture();
}
const req=(path,token,body)=>new Request('https://stun-test.innonext.win'+path,{method:body?'POST':'GET',headers:token?{Authorization:'Bearer '+token,'Content-Type':'application/json'}:{},body:body?JSON.stringify(body):undefined});

test('expired, corrupted and absent leases block links; revoke closes portal',async()=>{
 const {portal,data}=await fixture();
 assert.equal((await portal.fetch(req('/go/nas','v'.repeat(32)))).status,410);
 for(const value of [{port:23456,expiresAt:Date.now()-1},{port:'443/evil',expiresAt:Date.now()+60000},{port:23456,expiresAt:Date.now()+999999}]){
  data.set('lease',value);
  const res=await portal.fetch(req('/go/nas','v'.repeat(32)));
  assert.equal(res.status,410); assert.equal(res.headers.get('Location'),null);
 }
 data.set('lease',{port:23456,expiresAt:Date.now()+60000});
 const revoke=new Request('https://stun-test.innonext.win/lease',{method:'DELETE',headers:{Authorization:'Bearer '+'r'.repeat(32)}});
 assert.equal((await portal.fetch(revoke)).status,405);
 data.delete('lease'); // Unconditional revoke is deliberately unsupported; expiry closes links.
 assert.equal((await portal.fetch(req('/go/nas','v'.repeat(32)))).status,410);
});
test('publisher cannot supply arbitrary targets, invalid ports, expired or unbounded leases',async()=>{
 const {portal,data}=await fixture();
 const now=Date.now();
 for(const value of [null,{}, {port:443,expiresAt:now+60000},{port:65536,expiresAt:now+60000},{port:23456,expiresAt:now-1},{port:23456,expiresAt:now+121000},{port:23456,expiresAt:now+60000,target:'https://evil.example'}, {port:'23456',expiresAt:now+60000}]){
  const r=new Request('https://stun-test.innonext.win/lease',{method:'POST',headers:{Authorization:'Bearer '+'r'.repeat(32),'Content-Type':'application/json'},body:JSON.stringify(value)});
  assert.equal((await portal.fetch(r)).status,400);
 }
 assert.equal(data.size,0);
 for(const path of ['/go/evil','/go/__proto__','/go/nas?target=https://evil.example']) assert.equal((await portal.fetch(req(path,'v'.repeat(32)))).status,404);
});
test('malformed JSON, oversized body, wrong origin and storage failure fail closed',async()=>{
 const {portal}=await fixture();
 for(const body of ['{', 'x'.repeat(513)]) {
  const r=new Request('https://stun-test.innonext.win/lease',{method:'POST',headers:{Authorization:'Bearer '+'r'.repeat(32),'Content-Type':'application/json'},body});
  assert.equal((await portal.fetch(r)).status,400);
 }
 assert.equal((await portal.fetch(new Request('https://evil.example/go/nas',{headers:{Authorization:'Bearer '+'v'.repeat(32)}}))).status,404);
 portal.ctx.storage.get=async()=>{throw new Error('unavailable')};
 assert.equal((await portal.fetch(req('/go/nas','v'.repeat(32)))).status,503);
});

test('only router role can publish bounded fixed-host lease; viewer gets no-store redirect',async()=>{
 const {portal}=await fixture();
 const s=session();
 assert.equal((await portal.fetch(req('/session','r'.repeat(32),s))).status,204);
 const lease=mapping(s);
 assert.equal((await portal.fetch(req('/lease',null,lease))).status,401);
 assert.equal((await portal.fetch(req('/lease','v'.repeat(32),lease))).status,401);
 assert.equal((await portal.fetch(req('/lease','r'.repeat(32),lease))).status,204);
 const res=await portal.fetch(req('/go/nas','v'.repeat(32)));
 assert.equal(res.status,302);
 assert.equal(res.headers.get('Location'),'https://nas-stun-test.innonext.win:23456/');
 assert.equal(res.headers.get('Cache-Control'),'no-store');
 assert.equal((await portal.fetch(req('/go/files','v'.repeat(32)))).headers.get('Location'),'https://files-stun-test.innonext.win:23456/');
});
