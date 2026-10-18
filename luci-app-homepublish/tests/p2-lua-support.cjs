const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..'),baseline='19234e3e06d55ebde10f2b64fd0517c3b0a02c0dee976ccc681d71989ceb58b9';
const paths='/etc/homepublish/product/state /etc/config/homepublish /etc/config/network /etc/config/firewall';let before;
function verify(ssh){const now=ssh('sha256sum '+paths);assert.equal(now.split(/\s+/)[0],baseline);if(before)assert.equal(now,before);console.log('P2_LIVE_BASELINE_UNCHANGED '+baseline);}
function prepare(ssh){
 verify(ssh);before=ssh('sha256sum '+paths);
 const state=JSON.parse(ssh('ubus call homepublish status'));assert.equal(state.saved_revision,10);assert.equal(state.active_revision,10);assert.equal(state.runtime.phase,'stopped');
 for(const name of ['product-provider.lua','product-store.lua','product-store-core.lua']){
 const expected=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'homepublish/files/usr/share/homepublish',name))).digest('hex');
 assert.equal(ssh('sha256sum /usr/share/homepublish/'+name).split(/\s+/)[0],expected,'deployed candidate mismatch '+name);
 }
 ssh('set -e; test ! -L /root/homepublish-lua-store; test ! -L /root/homepublish-lua-store/p2-ui-store; umask 077; mkdir -p /tmp/homepublish-p2-ui /root/homepublish-lua-store; test ! -L /tmp/homepublish-p2-ui; rm -f /root/homepublish-lua-store/p2-ui-store/state /root/homepublish-lua-store/p2-ui-store/migration-v1');
 const bytes=fs.readFileSync(path.join(root,'homepublish/tests/device-tcp-p2-ui.lua'),'utf8');
 ssh('umask 077; cat > /tmp/homepublish-p2-ui/device-tcp-p2-ui.lua',bytes);
 assert.equal(ssh('sha256sum /tmp/homepublish-p2-ui/device-tcp-p2-ui.lua').split(/\s+/)[0],crypto.createHash('sha256').update(bytes).digest('hex'));
 console.log(ssh('lua /tmp/homepublish-p2-ui/device-tcp-p2-ui.lua seed-v1'));console.log(ssh('lua /tmp/homepublish-p2-ui/device-tcp-p2-ui.lua test-preview'));verify(ssh);
}
module.exports={prepare,verify};
