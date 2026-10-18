const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../..');
test('P2 private transport has no native store or old host mapping',()=>{
 for(const file of ['homepublish/tests/device-tcp-p2-ui.lua','luci-app-homepublish/tests/tcp-ingress-device-probe.cjs']){
 const text=fs.readFileSync(path.join(root,file),'utf8');
 assert(!/package\.cpath|LUA_CPATH|require\('homepublish_store'\)|root@127\.0\.0\.1/.test(text),file);
 }
});
