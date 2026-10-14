/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require view';
'require poll';
'require view.homepublish.product as api';
return view.extend({
 load:function(){return api.status().catch(function(){return {};});},
 render:function(s){
  var node=E('p',{id:'hp-overview-status'},api.text(s)),layers=E('div',{id:'hp-overview-layers'},api.layers(s));
  function refresh(){return api.status().then(function(st){node.textContent=api.text(st);layers.replaceChildren(api.layers(st));}).catch(function(){node.textContent=api.text({});layers.replaceChildren(api.layers({}));});}
  poll.add(refresh,2);
  var stop=E('button',{id:'hp-stop',class:'cbi-button cbi-button-negative',click:function(){stop.disabled=true;return api.stop().then(api.checked).then(refresh).catch(function(e){node.textContent='Stop failed: '+e.message;}).finally(function(){stop.disabled=false;});}},_('Stop publication'));
  return E('div',{},[E('h2',{},_('HomePublish overview')),node,layers,E('a',{href:L.url('admin','services','homepublish','settings')},'访问配置向导 / 编辑服务'),E('button',{id:'hp-start',disabled:true,title:api.reason},_('Start')),E('button',{disabled:true,title:api.reason},_('Apply pending')),E('p',{},api.reason),stop]);
 },handleSave:null,handleSaveApply:null,handleReset:null
});
