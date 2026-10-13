import {LeasePortal} from '../files/usr/share/homestun/worker/worker.mjs';
const router='r'.repeat(32), viewer='v'.repeat(32);
export function fixture(){
 const data=new Map(); let tail=Promise.resolve();
 const storage={get:async k=>data.get(k),put:async(k,v)=>data.set(k,v),delete:async k=>data.delete(k)};
 storage.transaction=fn=>{const job=tail.then(()=>fn(storage));tail=job.catch(()=>{});return job;};
 return {data,portal:new LeasePortal({storage},{ROUTER_TOKEN:router,VIEW_TOKEN:viewer})};
}
export const req=(path,body,token=router)=>new Request('https://stun-test.innonext.win'+path,{method:body?'POST':'GET',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
export const session=()=>({generation:Date.now(),session:'a'.repeat(32),expiresAt:Date.now()+60000});
export const lease=(s,sequence=1,port=23456)=>({...s,sequence,port,mappedIP:'198.51.100.7'});
