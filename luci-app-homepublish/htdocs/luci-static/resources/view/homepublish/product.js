/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require baseclass';
'require rpc';
var status=rpc.declare({object:'homepublish',method:'status',expect:{},reject:true});
var validate=rpc.declare({object:'homepublish',method:'validate',params:['config'],expect:{},reject:true});
var save=rpc.declare({object:'homepublish',method:'save',params:['expected_revision','config'],expect:{},reject:true});
var stop=rpc.declare({object:'homepublish',method:'stop',expect:{},reject:true});
return baseclass.extend({
 status:status,validate:validate,save:save,stop:stop,
 checked:function(s){if(!s || s.error)throw new Error(s && s.error || 'State unavailable');return s;},
 text:function(s){
  if(!s || s.error || !s.runtime || !s.desired_state)return 'State unavailable / unknown; not running';
  var r=s.runtime, running=r.phase==='running' && r.active_verified===true && s.desired_state.state==='enabled' && !s.desired_state.manual_stop_latch;
  return 'saved: '+s.saved_revision+'; active: '+(s.active_revision || 'none')+'; pending: '+!!(s.pending_config && s.pending_config.apply_required)+'; desired: '+s.desired_state.state+'; manual stop: '+s.desired_state.manual_stop_latch+'; runtime: '+r.phase+'; verified running: '+running+'; attempted: '+(s.attempted_revision || 'none')+'; stage: '+(r.stage || 'none')+'; error: '+(r.last_error || 'none')+'; cleanup: '+(r.cleanup || 'unknown');
 },
 reason:'Production Start / Apply unsupported: activation_ready=false. Internal host-test controller is not a client-selectable provider.',
 defaults:function(){return {schema_version:1,services:[{service_id:'nas',name:'NAS',hostname:'nas.example.test',backend:{addressFamily:'ipv4',host:'192.168.1.10',port:8080,allowed_ranges:['192.168.1.0/24']},certificate_ref:'acme:nas',authentication_review:{authentication:'unconfirmed',management:false}}],access_profile:{methods_allowed:['manual_ipv4'],listeners:[{family:'ipv4',address:'192.168.1.2',interface:'wan',zone:'wan',protocol:'tcp',internal_port:8443,external_port:18443}]},publication_policy:{mode:'continuous',boot_restore:false}};}
});
