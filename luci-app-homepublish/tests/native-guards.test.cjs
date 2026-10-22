/* REQ-012: device/browser acceptance scripts named *.test.cjs must skip
 * gracefully when their runtime prerequisites (device LuCI, playwright,
 * evidence fixtures) are absent, so `node --test` stays green offline.
 * These are acceptance scripts, not unit tests; the guard itself is tested. */
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const NATIVE=[
 'backend-host-header-native.test.cjs',
 'backend-host-header-page-save-native.test.cjs',
 'services-dns-add-native.test.cjs',
 'services-dns-default-suffix.test.cjs',
 'services-dns-edge-native.test.cjs',
 'services-dns-fallback-native.test.cjs',
 'services-dns-native.test.cjs',
 'services-dns-suffix-candidates.test.cjs',
 'services-dns-warning-native.test.cjs',
 'services-save-loading-native.test.cjs',
 'services-save-native.test.cjs',
 'unchecked-tls-native.test.cjs'
];
const GUARD=/HP_DEVICE_URL|hp\.skip|prerequisite/i;
test('every native acceptance script declares a prerequisite guard',()=>{
 for(const f of NATIVE){
  const src=fs.readFileSync(path.join(__dirname,f),'utf8');
  assert.match(src,GUARD,f+' must reference HP_DEVICE_URL/HP_PLAYWRIGHT guard');
  assert.match(src,/skip/i,f+' must call t.skip() when prerequisites are absent');
 }
});
test('native acceptance scripts exit 0 without environment (graceful skip, no crash)',()=>{
 for(const f of NATIVE){
  const r=cp.spawnSync(process.execPath,[path.join(__dirname,f)],{encoding:'utf8',timeout:60000});
  assert.equal(r.status,0,f+' standalone exit code: '+(r.status==null?'signal/'+r.signal:('stderr tail: '+String(r.stderr).slice(-200))));
 }
});
