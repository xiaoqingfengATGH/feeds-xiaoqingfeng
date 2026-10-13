// SPDX-License-Identifier: Apache-2.0
const HOSTS=new Map([['/go/nas','nas-stun-test.innonext.win'],['/go/files','files-stun-test.innonext.win']]);
const reply=(text,status,extra={})=>new Response(text,{status,headers:{'Cache-Control':'no-store','Referrer-Policy':'no-referrer',...extra}});
const expiry=n=>Number.isSafeInteger(n)&&n>Date.now()&&n<=Date.now()+120000;
const validSession=s=>s&&Number.isSafeInteger(s.generation)&&s.generation>0&&typeof s.session==='string'&&/^[a-f0-9]{32}$/.test(s.session)&&expiry(s.expiresAt);
function validIP(ip){
 if(typeof ip!=='string'||!/^\d{1,3}(\.\d{1,3}){3}$/.test(ip))return false;
 const p=ip.split('.');return p.every(n=>String(Number(n))===n&&Number(n)<=255)&&Number(p[0])>0&&Number(p[0])<224&&Number(p[0])!==127;
}
const validLease=s=>validSession(s)&&Object.keys(s).length===6&&validIP(s.mappedIP)&&Number.isInteger(s.port)&&s.port>=1024&&s.port<=65535&&Number.isSafeInteger(s.sequence)&&s.sequence>0;
async function body(request){
 if(request.headers.get('Content-Type')!=='application/json')return null;
 const reader=request.body?.getReader();if(!reader)return null;
 let size=0,chunks=[];
 for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>512){await reader.cancel();return null;}chunks.push(value);}
 try{const bytes=new Uint8Array(size);let n=0;for(const c of chunks){bytes.set(c,n);n+=c.length;}return JSON.parse(new TextDecoder().decode(bytes));}catch{return null;}
}
export default {async fetch(request,env){try{return await env.PORTAL.get(env.PORTAL.idFromName('homepublish')).fetch(request);}catch{return reply('Unavailable',503);}}};
export class LeasePortal{
 constructor(ctx,env){this.ctx=ctx;this.env=env;}
 async fetch(request){
 const e=this.env;
 if(typeof e.ROUTER_TOKEN!=='string'||e.ROUTER_TOKEN.length<32||typeof e.VIEW_TOKEN!=='string'||e.VIEW_TOKEN.length<32||e.ROUTER_TOKEN===e.VIEW_TOKEN)return reply('Unavailable',503);
 const url=new URL(request.url);
 if(url.origin!=='https://stun-test.innonext.win'||url.search)return reply('Not found',404);
 const mutation=url.pathname==='/lease'||url.pathname==='/session';
 if(request.headers.get('Authorization')!=='Bearer '+(mutation?e.ROUTER_TOKEN:e.VIEW_TOKEN))return reply('Unauthorized',401);
 try{
  if(mutation){
   if(request.method!=='POST')return reply('Method not allowed',405);
   const value=await body(request);
   if(url.pathname==='/session'){
    if(!validSession(value)||Object.keys(value).length!==3)return reply('Invalid session',400);
    const accepted=await this.ctx.storage.transaction(async tx=>{
     const high=await tx.get('generation');if(high!==undefined&&value.generation<=high)return false;
     await tx.put('generation',value.generation);await tx.put('session',value);await tx.delete('lease');return true;
    });return reply(null,accepted?204:409);
   }
   if(!validLease(value))return reply('Invalid lease',400);
   const accepted=await this.ctx.storage.transaction(async tx=>{
    const current=await tx.get('session'),old=await tx.get('lease');
    if(!validSession(current)||current.generation!==value.generation||current.session!==value.session||current.expiresAt!==value.expiresAt||(old&&value.sequence<=old.sequence))return false;
    await tx.put('lease',value);return true;
   });return reply(null,accepted?204:409);
  }
  const host=HOSTS.get(url.pathname);if(request.method!=='GET'||!host)return reply('Not found',404);
  const lease=await this.ctx.storage.get('lease');if(!validLease(lease))return reply('Closed',410);
  return reply(null,302,{Location:`https://${host}:${lease.port}/`});
 }catch{return reply('Unavailable',503);}
 }
}

