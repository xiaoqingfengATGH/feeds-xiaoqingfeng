const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),env=require('./env.cjs');
const id=crypto.randomUUID(),storeRoot='/root/homepublish-lua-store/browser-'+id,remoteRoot='/tmp/homepublish-browser-'+id,remoteScript=remoteRoot+'/device-tcp-p2-ui.lua';
const paths='/etc/homepublish/product/state /etc/config/homepublish /etc/config/network /etc/config/firewall /tmp/homepublish-runtime/nginx.conf';let before,stable,created=false;
function state(ssh){const s=JSON.parse(ssh('ubus call homepublish status'));return {saved_revision:s.saved_revision,active_revision:s.active_revision,intent_revision:s.intent_revision,desired_state:s.desired_state,phase:s.runtime.phase,generation:s.runtime.generation,active_verified:s.runtime.active_verified};}
function verify(ssh){const now=ssh('sha256sum '+paths);if(before)assert.equal(now,before,'PRODUCTION BYTES CHANGED');if(stable)assert.deepEqual(state(ssh),stable,'PRODUCTION STATE CHANGED');console.log('PRODUCTION_UNCHANGED',now,JSON.stringify(state(ssh)));}
function prepare(ssh){
 before=ssh('sha256sum '+paths);stable=state(ssh);fs.writeFileSync(path.join(env.evidence,'baseline-'+(process.env.HP_CASE||'base')+'.json'),JSON.stringify({hashes:before,state:stable,storeRoot,remoteRoot},null,2));
 for(const name of ['product-provider.lua','product-store.lua','product-store-core.lua']){const installed=ssh('sha256sum /usr/share/homepublish/'+name).split(/\s+/)[0];assert.equal(installed,env.pins[name],'unreviewed installed '+name);console.log('PINNED_INSTALLED',name,installed);}
 let bytes=fs.readFileSync(path.join(__dirname,'device-tcp-p2-ui.lua'),'utf8').replaceAll('__BASELINE__',before.split(/\s+/)[0]).replaceAll('__PRIVATE_ROOT__',storeRoot);
 assert(!bytes.includes('__BASELINE__')&&!bytes.includes('__PRIVATE_ROOT__'));
 ssh('set -e; umask 077; test ! -L /root/homepublish-lua-store; test ! -e '+storeRoot+'; test ! -e '+remoteRoot+'; mkdir -p /root/homepublish-lua-store; mkdir '+storeRoot+' '+remoteRoot);created=true;
 ssh('umask 077; cat > '+remoteScript,bytes);assert.equal(ssh('sha256sum '+remoteScript).split(/\s+/)[0],crypto.createHash('sha256').update(bytes).digest('hex'));
 console.log(ssh('lua '+remoteScript+' seed-v1'));console.log(ssh('lua '+remoteScript+' test-preview'));verify(ssh);
}
function cleanup(ssh){try{verify(ssh);}finally{if(created){ssh('rm -rf '+storeRoot+' '+remoteRoot+'; test ! -e '+storeRoot+'; test ! -e '+remoteRoot);console.log('PRIVATE_FIXTURE_CLEANED',storeRoot,remoteRoot);}}}
module.exports={prepare,verify,cleanup,remoteScript};
