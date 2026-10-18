const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../htdocs/luci-static/resources/view/homepublish/product.js'),'utf8');
function apiFor(state){
 const calls=[];let completed=false;
 const api=new Function('baseclass','rpc','dom','ui',source)({extend:o=>o},{declare:()=>()=>Promise.resolve({})},{},{});
 api.validate=async c=>{calls.push('validate');return {valid:true,config:c};};
 api.save=async (rev,c)=>{calls.push(['save',rev]);return {...state,saved_revision:8,saved_config:c};};
 api.status=async()=>{calls.push('status');return {...state,saved_revision:8,...(completed?{runtime:{phase:'running',active_verified:true}}:{})};};
 for(const action of ['apply','start'])api[action]=async(rev,approved)=>{calls.push([action,rev,approved]);completed=true;return {};};
 return {api,calls};
}
const enabled={desired_state:{state:'enabled',manual_stop_latch:false},runtime:{phase:'running',active_verified:true},saved_revision:7};
test('enabled save/apply re-reads saved revision before lifecycle',async()=>{
 const {api,calls}=apiFor(enabled);
 const result=await api.saveAndApply(7,{schema_version:2});
 assert.equal(result.action,'apply');
 assert.deepEqual(calls,['validate',['save',7],'status',['apply',8,true],'status']);
});
test('ordinary editor primary action is save/apply',()=>{
 assert.match(source,/id:'hp-save-apply'/);assert.match(source,/'保存并应用'/);
 assert.match(source,/api\.saveAndApply\(map.snapshotRevision/);
});
test('disabled saves only; enabled failure starts',async()=>{
 for(const state of [{desired_state:{state:'disabled'},runtime:{phase:'stopped'}},{desired_state:{state:'enabled'},runtime:{phase:'failed'}}]){
  const {api,calls}=apiFor(state);const isEnabled=state.desired_state.state==='enabled';
  assert.equal(api.enabled(state),isEnabled);
  const result=await api.saveAndApply(7,{});assert.equal(result.action,isEnabled?'start':'save');
  assert.equal(calls.some(c=>Array.isArray(c)&&c[0]==='start'),isEnabled);
 }
});
test('save-only stays independent even when enabled',async()=>{
 const {api,calls}=apiFor(enabled);await api.saveAndApply(7,{},true);
 assert.deepEqual(calls,['validate',['save',7],'status']);
});
test('validation/save conflict never dispatches lifecycle or retries',async()=>{
 for(const phase of ['validate','save']){
  const {api,calls}=apiFor(enabled);
  api[phase]=async()=>{calls.push(phase);return {error:'rejected',error_code:'REVISION_CONFLICT'};};
  await assert.rejects(api.saveAndApply(7,{}),e=>e.error_code==='REVISION_CONFLICT'&&!e.configurationSaved);
  assert.equal(calls.filter(c=>c===phase).length,1);assert.ok(!calls.includes('status'));
 }
});
test('concurrent save after receipt is not applied or overwritten',async()=>{
 const {api,calls}=apiFor(enabled);api.status=async()=>({...enabled,saved_revision:9});
 await assert.rejects(api.saveAndApply(7,{}),e=>e.error_code==='REVISION_CONFLICT'&&e.configurationSaved);
 assert.deepEqual(calls,['validate',['save',7]]);
});
test('blocked runtime response is a saved apply failure, not success',async()=>{
 const {api}=apiFor(enabled);api.apply=async()=>({runtime:{phase:'blocked',stage:'readiness',last_error:'nginx listener missing'}});
 await assert.rejects(api.saveAndApply(7,{}),e=>e.configurationSaved&&e.lifecycleAction==='apply'&&/nginx listener missing/.test(e.error));
});
test('transport rejection preserves cause and still reads final state',async()=>{
 const {api,calls}=apiFor(enabled);api.apply=async()=>{throw new Error('RPC transport interrupted');};
 await assert.rejects(api.saveAndApply(7,{schema_version:2}),e=>e.configurationSaved&&e.savedRevision===8&&e.latestState.saved_revision===8&&e.message==='RPC transport interrupted');
 assert.deepEqual(calls,['validate',['save',7],'status','status']);
});
test('certificate errors explain correction instead of generic failure',()=>{
 const {api}=apiFor(enabled);
 assert.match(api.errorText({error:'...lua:49: certificate expired or DNS SAN mismatch'}),/不覆盖服务域名/);
 assert.equal(api.errorText({error:'nginx configuration validation failed'}),'nginx configuration validation failed');
});
test('apply failure retains saved configuration',async()=>{
 const {api,calls}=apiFor(enabled);api.apply=async()=>({error:'failed',error_code:'PORT_CONFLICT'});
 await assert.rejects(api.saveAndApply(7,{}),e=>e.configurationSaved&&e.lifecycleAction==='apply'&&e.error_code==='PORT_CONFLICT');
 assert.deepEqual(calls,['validate',['save',7],'status','status']);
});
