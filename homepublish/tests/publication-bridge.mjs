import readline from 'node:readline';
import {LeasePortal} from '../files/usr/share/homepublish/worker/worker.mjs';
const data=new Map();const storage={get:async k=>data.get(k),put:async(k,v)=>data.set(k,v),delete:async k=>data.delete(k)};storage.transaction=fn=>fn(storage);
const portal=new LeasePortal({storage},{ROUTER_TOKEN:'r'.repeat(32),VIEW_TOKEN:'v'.repeat(32)});
console.log('READY');
for await(const line of readline.createInterface({input:process.stdin})){
 const q=JSON.parse(line);const r=await portal.fetch(new Request('https://stun-test.innonext.win'+q.path,{method:q.method,headers:q.headers,body:q.body||undefined}));
 console.log(JSON.stringify({status:r.status,location:r.headers.get('Location')}));
}
