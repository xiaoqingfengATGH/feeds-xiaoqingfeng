const assert=require('node:assert/strict'),cp=require('node:child_process');
const ssh=(cmd,input)=>cp.execFileSync('ssh',['-o','ProxyCommand=none','-o','ProxyJump=none','-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-i','D:/DevPortal/CloudHosts/HomePri.key','root@192.168.1.2',cmd],{encoding:'utf8',input,timeout:45000});
const support=require('./p2-lua-support.cjs');
const call=(m,a={})=>JSON.parse(ssh('lua /tmp/homepublish-p2-ui/device-tcp-p2-ui.lua '+m,JSON.stringify(a)));
try{
 support.prepare(ssh);
 const before=call('status');assert.equal(before.saved_revision,1);assert.equal(before.saved_config.schema_version,1);
 const preview=call('migration_preview',{expected_revision:1});assert.equal(preview.proposed_config.schema_version,2);assert.equal(call('status').saved_revision,1);
 console.log('PREVIEW',JSON.stringify(preview));
 const saved=call('save',{expected_revision:1,config:preview.proposed_config});console.log('SAVE',JSON.stringify(saved));
 const after=call('status');assert.equal(after.saved_revision,2);assert.equal(after.saved_config.schema_version,2);assert.equal(after.desired_state.state,'disabled');assert.equal(after.active_revision,undefined);
 assert.equal(call('save',{expected_revision:1,config:preview.proposed_config}).error_code,'REVISION_CONFLICT');assert.equal(call('status').saved_revision,2);
 const privateHash=ssh('sha256sum /root/homepublish-lua-store/p2-ui-store/state');
 let rejected=false;try{ssh('lua /tmp/homepublish-p2-ui/device-tcp-p2-ui.lua start','{}');}catch{rejected=true;}assert(rejected);assert.equal(ssh('sha256sum /root/homepublish-lua-store/p2-ui-store/state'),privateHash);
 console.log('P2_PRIVATE_LUA_PREVIEW_SAVE_READBACK_CONFLICT_LIFECYCLE_REJECT_GREEN');
}finally{support.verify(ssh);}
