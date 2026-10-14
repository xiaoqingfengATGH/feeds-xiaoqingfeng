/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require view';
'require poll';
'require view.homepublish.product as api';
return view.extend({
 load:function(){return api.status().catch(function(){return {};});},
 render:function(s){
  var node=E('p',{id:'hp-overview-status'},api.text(s));
  function refresh(){return api.status().then(function(st){node.textContent=api.text(st);}).catch(function(){node.textContent=api.text({});});}
  poll.add(refresh,2);
  var stop=E('button',{id:'hp-stop',class:'cbi-button cbi-button-negative',click:function(){stop.disabled=true;return api.stop().then(api.checked).then(refresh).catch(function(e){node.textContent='Stop failed: '+e.message;}).finally(function(){stop.disabled=false;});}},_('Stop publication'));
  return E('div',{},[E('h2',{},_('HomePublish overview')),node,E('p',{},_('Saved changes remain pending; Save does not start, renew or apply. External reachability: unverified.')),E('p',{},s.saved_config ? 'Policy: '+s.saved_config.publication_policy.mode+(s.saved_config.publication_policy.mode==='continuous'?' — until stopped':' — original deadline '+(s.runtime.expires_at || 'not started'))+'; boot restore: '+s.saved_config.publication_policy.boot_restore:'No saved configuration'),E('pre',{},JSON.stringify(s.saved_config && s.saved_config.services || [],null,2)),E('button',{id:'hp-start',disabled:true,title:api.reason},_('Start')),E('button',{disabled:true,title:api.reason},_('Apply pending')),E('p',{},api.reason),stop]);
 },handleSave:null,handleSaveApply:null,handleReset:null
});
