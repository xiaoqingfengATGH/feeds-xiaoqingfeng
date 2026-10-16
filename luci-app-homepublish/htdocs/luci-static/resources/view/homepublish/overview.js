/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require view';
'require form';
'require poll';
'require dom';
'require view.homepublish.product as api';
return view.extend({
 load:function(){return api.status().then(api.checked).then(function(s){return {state:s};}).catch(function(e){return {error:e.message};});},
 render:function(data){
  var state=data.state,unknown=data.error,root=E('div',{id:'hp-overview'}),body=E('div'),message=E('p',{id:'hp-message',role:'status','aria-live':'polite'}),raw=E('pre'),busy=false,actionBusy=false,epoch=0,renderEpoch=0;
  var details=E('details',{id:'hp-overview-diagnostics'},[E('summary',{},'内部状态与失败 / 清理详情'),raw]);
  root.append(E('style',{},'#hp-overview{min-width:0;overflow-wrap:anywhere}#hp-overview .hp-table-viewport{max-width:100%;overflow-x:auto}#hp-overview .hp-table-viewport table{min-width:800px}#hp-overview pre{white-space:pre-wrap}'),message,body,details);
  function readonlyGrid(map,type,title,columns){
   var section=map.section(form.GridSection,type,title);section.anonymous=true;section.addremove=false;section.sortable=false;
   section.renderRowActions=function(){return E([]);};section.renderHeaderRows=function(){return form.TableSection.prototype.renderHeaderRows.call(this,false);};
   var render=section.render;section.render=function(){return Promise.resolve(render.apply(this,arguments)).then(function(node){return E('div',{class:'hp-table-viewport',tabindex:0,'aria-label':title},node);});};
   columns.forEach(function(c){var o=section.option(form.DummyValue,c[0],c[1]);o.optional=true;});return section;
  }
  function text(node,value){value=String(value == null?'':value);if(node && node.textContent!==value)node.textContent=value;}
  function updateRow(node,row,columns){
   var outputs=node.querySelectorAll('output'),inputs=node.querySelectorAll('input[type="hidden"]');
   if(!outputs.length){Array.from(node.children).forEach(function(cell,i){text(cell,row[columns[i]]);});return;}
   columns.forEach(function(key,i){text(outputs[i],row[key]);if(inputs[i] && inputs[i].value!==String(row[key] || ''))inputs[i].value=row[key] || '';});
  }
  function syncGrid(section,type,items,columns,rendering){
   var table=body.querySelector('#cbi-json-'+type+' table'),tbody=table.querySelector('tbody'),old=Array.from(tbody.querySelectorAll('tr:not(.placeholder)')),keys=items.map(function(row){return row._key;});
   if(old.length===keys.length && old.every(function(row,i){return row.dataset.hpKey===keys[i];})){
    old.forEach(function(row,i){updateRow(row,items[i],columns);});return Promise.resolve();
   }
   // Native GridSection renders only when membership/order changes; retain the
   // installed table, header, viewport and every surviving stable-ID row.
   return section.load().then(function(){return section.render();}).then(function(node){
    if(rendering!==renderEpoch)return;
    var fresh=Array.from(node.querySelectorAll('tbody tr:not(.placeholder)')),retained={};old.forEach(function(row){retained[row.dataset.hpKey]=row;});
    var desired=items.map(function(item,i){var row=retained[item._key] || fresh[i];row.dataset.hpKey=item._key;updateRow(row,item,columns);return row;});
    if(!desired.length)desired=Array.from(node.querySelectorAll('tbody tr.placeholder'));
    Array.from(tbody.children).forEach(function(row){if(desired.indexOf(row)<0)row.remove();});
    desired.forEach(function(row,i){if(tbody.children[i]!==row)tbody.insertBefore(row,tbody.children[i] || null);});
   });
  }
  function draw(){
   var rendering=++renderEpoch,s=state || {},r=s.runtime || {},saved=s.saved_config || {},active=s.active_config || {},gates=api.actionGates(s,{unknown:!!unknown,busy:busy || actionBusy}),rows={summary:{'.type':'summary'},actions:{'.type':'actions'}};
   var pending=!!(s.pending_config && s.pending_config.apply_required);
   rows.summary.publication=unknown?'状态未知（不是已停止）':({running:api.running(s)?'运行中（本机已验证）':'运行未验证',stopped:'未发布',starting:'启动中',stopping:'停止中',failed:'失败',blocked:'已阻止'}[r.phase] || '状态未知');
   rows.summary.config='已保存：'+(s.saved_revision==null?'未知':s.saved_revision)+'；运行：'+(s.active_revision==null?'无':s.active_revision)+'；'+(pending?'已保存待应用':'无待应用变更');
   var policy=saved.publication_policy || {};rows.summary.policy=(policy.mode==='temporary'?'临时发布':policy.mode==='continuous'?'持续直到停止':'未配置')+'；截止：'+(r.expires_at || '未开始')+'；开机恢复：'+(policy.boot_restore?'开启':'关闭');
   rows.summary.external='IPv4 / IPv6 公网未验证；本机就绪不代表公网可达';
   var ids={};(active.services || []).concat(saved.services || []).forEach(function(v){ids[v.service_id]=true;});
   Object.keys(ids).forEach(function(id,i){
    var a=(active.services || []).find(function(v){return v.service_id===id;}),v=(saved.services || []).find(function(v){return v.service_id===id;}),shown=a || v,b=shown.backend || {},ready=(r.services || {})[id];
    rows['service_'+i]={'.type':'services',_key:id,identity:(shown.name || id)+'（'+id+'）',kind:api.serviceType(shown.type),match:shown.hostname || (shown.type==='tcp_forward'?'TCP '+shown.listen_port:'共享 SSH 入口'),backend:api.endpoint(b.host,b.port),path:((active.access_profile || saved.access_profile || {}).listeners || []).map(function(l){return l.family;}).join(' / ')+' → '+(b.addressFamily==='hostname'?'待解析':b.addressFamily || '未知'),saved:v?(v.enabled===false?'不参与下次发布':'参与下次发布')+(JSON.stringify(a)!==JSON.stringify(v)?'；待应用':''):'已保存删除；待应用',readiness:!a?'未运行':unknown?'状态未知':api.running(s) && r.generation!=null && r.generation!=='' && ready && ready.ready===true && ready.generation===r.generation?'内部已就绪':ready && ready.generation!==r.generation?'旧运行结果，不计就绪':'未确认就绪'};
   });
   var listeners=(active.access_profile || {}).listeners || [],next=(saved.access_profile || {}).listeners || [];
   listeners.concat(next.filter(function(l){return !listeners.some(function(a){return a.listener_id===l.listener_id;});})).forEach(function(l,i){var isActive=listeners.indexOf(l)>=0;rows['entry_'+i]={'.type':'entries',_key:l.listener_id || 'entry_'+i,identity:l.listener_id || '共享入口',endpoint:api.endpoint(l.address,l.port || l.internal_port),family:l.family,network:l.network || l.interface || '未知',status:isActive?'运行快照（逐服务就绪另验）':'仅已保存，未运行',external:'公网未验证'};});
   rows.services=Object.keys(rows).filter(function(k){return k.indexOf('service_')===0;}).map(function(k){var v=rows[k];delete rows[k];return v;});
   rows.entries=Object.keys(rows).filter(function(k){return k.indexOf('entry_')===0;}).map(function(k){var v=rows[k];delete rows[k];return v;});
   var m=new form.JSONMap(rows,'家庭服务直连发布');m.readonly=false;
   var section=m.section(form.NamedSection,'summary','summary','发布状态');
   [['publication','发布状态'],['config','配置状态'],['policy','发布策略'],['external','公网入口']].forEach(function(c){section.option(form.DummyValue,c[0],c[1]);});
   var entrySection=readonlyGrid(m,'entries','入口状态',[['identity','入口'],['endpoint','本机监听'],['family','地址族'],['network','关联网络'],['status','配置来源'],['external','公网验证']]);
   var serviceSection=readonlyGrid(m,'services','服务发布状态',[['saved','已保存配置'],['identity','名称'],['kind','发布方式'],['match','匹配 / 端口'],['backend','家庭后端'],['path','地址族路径'],['readiness','当前运行状态']]);
   section=m.section(form.NamedSection,'actions','actions','发布操作');
   ['start','apply','stop','retry'].forEach(function(kind){var o=section.option(form.Button,kind,({start:'启动发布',apply:'应用变更',stop:'停止发布',retry:'刷新 / 重试'})[kind]);o.inputtitle=o.title;o.inputstyle=kind==='stop'?'reset':'action';o.readonly=kind==='retry'?busy || actionBusy:!gates[kind].allowed;o.description=kind==='retry'?'':gates[kind].reason;
    var render=o.renderWidget;o.renderWidget=function(){var n=render.apply(this,arguments);var button=n.matches && n.matches('button,input')?n:n.querySelector('button,input');if(button)button.id='hp-'+kind;return n;};
    o.onclick=function(){if(kind==='retry')return reload();if(!api.actionGates(state,{unknown:!!unknown,busy:busy || actionBusy})[kind].allowed)return;return api.actionDialog(root,state,kind,function(st){++epoch;state=st;unknown=null;draw();},function(e){++epoch;unknown=api.errorText(e);draw();},function(pending){actionBusy=pending;++epoch;draw();});};
   });
   var link=section.option(form.DummyValue,'edit','配置');link.renderWidget=function(){return E('a',{href:L.url('admin','services','homepublish','services')},'编辑发布服务');};
   text(message,unknown?'状态读取失败，请重试；不能判定已停止':pending?'已保存待应用；旧运行配置不会随保存切换':'');
   text(raw,JSON.stringify({error:unknown || null,runtime:r,desired_state:s.desired_state,saved_revision:s.saved_revision,active_revision:s.active_revision,pending_config:s.pending_config},null,2));
   if(body.querySelector('.cbi-map')){
    updateRow(body.querySelector('#cbi-json-summary'),rows.summary,['publication','config','policy','external']);
    ['start','apply','stop','retry'].forEach(function(kind){
     var button=body.querySelector('#hp-'+kind),disabled=kind==='retry'?busy || actionBusy:!gates[kind].allowed;
     if(button.disabled!==disabled)button.disabled=disabled;
     var field=body.querySelector('#cbi-json-actions-'+kind+' .cbi-value-field'),description=field.querySelector('.cbi-value-description'),reason=kind==='retry'?'':gates[kind].reason || '';
     if(!description && reason){description=E('div',{class:'cbi-value-description'});field.appendChild(description);}text(description,reason);
    });
    return Promise.all([syncGrid(entrySection,'entries',rows.entries,['identity','endpoint','family','network','status','external'],rendering),syncGrid(serviceSection,'services',rows.services,['saved','identity','kind','match','backend','path','readiness'],rendering)]);
   }
   return m.render().then(function(node){if(rendering!==renderEpoch)return;dom.content(body,node);['entries','services'].forEach(function(type){body.querySelectorAll('#cbi-json-'+type+' tbody tr:not(.placeholder)').forEach(function(row,i){row.dataset.hpKey=rows[type][i]._key;});});});
  }
  function reload(){if(busy || actionBusy)return;busy=true;var request=++epoch;return api.status().then(api.checked).then(function(s){if(request===epoch){state=s;unknown=null;}}).catch(function(e){if(request===epoch)unknown=api.errorText(e);}).finally(function(){busy=false;if(request===epoch)return draw();});}
  poll.add(function(){if(unknown && document.querySelector('#modal_overlay [role="dialog"]'))return;return reload();},2);return draw().then(function(){return root;});
 },handleSave:null,handleSaveApply:null,handleReset:null
});
