import {test} from 'node:test';
import assert from 'node:assert/strict';
import {fixture,req,session,lease} from './publication-fixture.mjs';
const viewer='v'.repeat(32);
test('authenticated session reserves generation before mapping and fixed-host redirect',async()=>{
 const {portal}=fixture();const s=session();
 assert.equal((await portal.fetch(req('/session',s,viewer))).status,401);
 assert.equal((await portal.fetch(req('/session',s))).status,204);
 assert.equal((await portal.fetch(req('/go/nas',null,viewer))).status,410);
 assert.equal((await portal.fetch(req('/lease',lease(s)))).status,204);
 const res=await portal.fetch(req('/go/nas',null,viewer));
 assert.equal(res.status,302);assert.equal(res.headers.get('Location'),'https://nas-stun-test.innonext.win:23456/');
});

test('old sessions, delayed begins and out-of-order callbacks cannot overwrite or revive',async()=>{
 const {portal,data}=fixture();const a=session(),b={...a,generation:a.generation+1,session:'b'.repeat(32)};
 await portal.fetch(req('/session',a));await portal.fetch(req('/lease',lease(a)));
 await portal.fetch(req('/session',b));await portal.fetch(req('/lease',lease(b,2,34567)));
 for(const [path,v] of [['/session',a],['/session',b],['/lease',lease(a,99)],['/lease',lease(b,1)],['/lease',lease(b,2)],['/lease',{...lease(b,3),expiresAt:b.expiresAt+1}]])assert.equal((await portal.fetch(req(path,v))).status,409);
 assert.equal(data.get('lease').port,34567);
 data.set('session',{...b,expiresAt:Date.now()-1});data.set('lease',{...lease(b,3),expiresAt:Date.now()-1});
 const r=await portal.fetch(req('/go/nas',null,viewer));assert.equal(r.status,410);assert.equal(r.headers.get('Location'),null);
});

