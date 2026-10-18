/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require view';
'require form';
'require poll';
'require dom';
'require rpc';
'require view.homepublish.probes as probes';
'require view.homepublish.product as api';
var probeService=rpc.declare({object:'homepublish',method:'probe',params:['service_id'],expect:{},reject:true,nobatch:true});
return view.extend({
 load:function(){return api.status().then(api.checked).then(function(s){return {state:s};}).catch(function(e){return {error:e.message};});},
 render:function(data){
  var state=data.state,unknown=data.error,root=E('div',{id:'hp-overview'}),body=E('div'),message=E('p',{id:'hp-message',role:'status','aria-live':'polite'}),busy=false,actionBusy=false,epoch=0,renderEpoch=0;
  root.append(E('style',{},'#hp-overview{min-width:0;overflow-wrap:anywhere}#hp-overview .hp-table-viewport{max-width:100%;overflow-x:auto}#hp-overview .hp-table-viewport table{min-width:800px}#hp-overview pre{white-space:pre-wrap}'),message,body);
  var probeResults={},probeQueue=probes.create(function(id){return probeService(id).then(api.checked).then(function(result){
   var labels={CONNECTED:'连接成功',OK:'连接成功',CONNECTION_REFUSED:'后端拒绝连接',TIMEOUT:result.phase==='resolve'?'域名解析超时':'后端连接超时',NETWORK_UNREACHABLE:'网络不可达',HOST_UNREACHABLE:'目标主机不可达',PERMISSION_DENIED:'路由器策略拒绝连接',RESOLVE_FAILED:'后端域名解析失败',ADDRESS_NOT_ALLOWED:'解析地址不在允许范围',SERVICE_DISABLED:'服务未启用',SERVICE_NOT_FOUND:'服务不存在',STATE_UNAVAILABLE:'无法读取已保存配置',PROBE_UNAVAILABLE:'探测进程不可用',PROBE_FAILED:'探测执行失败'};
   result.summary=result.ok?'连接成功':labels[result.reason] || '探测失败：'+(result.reason || result.summary);
   return result;
  });},function(id,result){
   probeResults[id]=result;refreshProbes();
  });
  var probeAll=E('button',{type:'button',class:'btn btn-secondary cbi-button cbi-button-neutral',click:function(){
   return probeQueue.run(((state || {}).saved_config || {}).services.map(function(s){return s.service_id;}));
  }},'全部测试');
  var probeHelp=E('div',{class:'cbi-value-description'},[E('p',{},'连通性由路由器发起，按需探测已保存的后端配置，不影响服务启停。'),probeAll]);
  function refreshProbes(){
   root.querySelectorAll('[data-hp-probe]').forEach(function(cell){var id=cell.getAttribute('data-hp-probe'),result=probeResults[id];
    var button=cell.querySelector('button'),label=cell.querySelector('span');button.disabled=!!(result && result.pending);
    text(label,result?result.summary:'未测试');
   });
   probeAll.disabled=probeQueue.pending() || !((((state || {}).saved_config || {}).services || []).length);
  }
  function readonlyGrid(map,type,title,columns){
   var section=map.section(form.GridSection,type,title);section.anonymous=true;section.addremove=false;section.sortable=false;
   section.renderRowActions=function(){return E([]);};section.renderHeaderRows=function(){return form.TableSection.prototype.renderHeaderRows.call(this,false);};
   var render=section.render;section.render=function(){return Promise.resolve(render.apply(this,arguments)).then(function(node){return E('div',{class:'hp-table-viewport',tabindex:0,'aria-label':title},node);});};
   columns.forEach(function(c){var o=section.option(form.DummyValue,c[0],c[1]);o.optional=true;if(c[0]==='public_entry')o.textvalue=function(sid){return publicEntryContent(this.cfgvalue(sid));};});return section;
  }
  function publicEntries(service,config){
   // Keep the service and listener from the same snapshot as the displayed backend.
   // A shared SSH entry uses the shared listener, not the SSH backend's port.
   var host=service.hostname || ((config.services || []).find(function(v){return v.enabled!==false && v.hostname;}) || {}).hostname;
   var scheme=service.type==='http_proxy'?'http://':service.type==='https_proxy'?'https://':'',values=[];
   function publicAddress(address){
    if(/^[23][0-9a-f]{3}:[0-9a-f:]+$/i.test(address || ''))return address;
    var parts=String(address || '').split('.').map(Number);
    if(parts.length!==4 || parts.some(function(p){return !Number.isInteger(p) || p<0 || p>255;}))return null;
    if(parts[0]===0 || parts[0]===10 || parts[0]===127 || parts[0]>=224 || parts[0]===169 && parts[1]===254 || parts[0]===172 && parts[1]>=16 && parts[1]<=31 || parts[0]===192 && parts[1]===168 || parts[0]===100 && parts[1]>=64 && parts[1]<=127)return null;
    return address;
   }
   ((config.access_profile || {}).listeners || []).forEach(function(l){
    var address=host || (l.bind_mode!=='auto' && publicAddress(l.address)),port=service.type==='tcp_forward'?service.listen_port:l.port || l.internal_port;
    if(!address || !port)return;
    address=String(address);if(address.indexOf(':')>=0 && address.charAt(0)!=='[')address='['+address+']';
    var value=scheme+address+':'+port;if(values.indexOf(value)<0)values.push(value);
   });
   return values.length?values:['公网域名或IP待配置'];
  }
  function publicEntryContent(value){
   var children=[];String(value || '').split('；').forEach(function(entry,i){
    if(i)children.push(document.createTextNode('；'));
    children.push(/^https?:\/\/(?:[a-z0-9.-]+|\[[0-9a-f:]+\]):[0-9]+$/i.test(entry)?E('a',{href:entry,target:'_blank',rel:'noopener noreferrer'},entry):document.createTextNode(entry));
   });return E('span',{},children);
  }
  function text(node,value){value=String(value == null?'':value);if(node && node.textContent!==value)node.textContent=value;}
  function updateRow(node,row,columns){
   var outputs=node.querySelectorAll('output'),inputs=node.querySelectorAll('input[type="hidden"]');
   if(!outputs.length){columns.forEach(function(key,i){if(key==='public_entry'){if(node.children[i].textContent!==row[key])dom.content(node.children[i],publicEntryContent(row[key]));}else text(node.children[i],row[key]);});return;}
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
   rows.summary.publication=unknown?'状态未知（不是已停止）':({running:api.running(s)?'运行中':'运行状态未确认',stopped:'已停止',starting:'启动中',stopping:'停止中',failed:pending?'应用失败':'启动失败',blocked:'启动失败'}[r.phase] || '状态未知');
   var failure=r.last_error || r.reason;
   if(!unknown && (r.phase==='blocked' || r.phase==='failed' || r.phase==='stopped' && r.cleanup!=='confirmed')){
    if(r.cleanup!=='confirmed')rows.summary.publication='停止失败';
    if(failure)rows.summary.publication+='：'+(typeof failure==='string'?failure:api.errorText(failure));
   }
   // Only the controller's firewall observation establishes automatic INPUT state.
   // Running components and saved zone selections are not evidence of installed rules.
   var firewall=s.firewall || {},firewallLabels={open:'已放行',closed:'未放行',unmanaged:'未托管（手动管理）',update_failed:'更新失败',cleanup_failed:'清理失败'};
   rows.summary.firewall=unknown?'状态未知':firewallLabels[firewall.state] || '状态未知';
   if(!unknown){
    if(firewall.state==='open'){
     var details=[];
     if(Number.isInteger(firewall.rule_count) && firewall.rule_count>=0)details.push(firewall.rule_count+' 条规则');
     if(details.length)rows.summary.firewall+='（'+details.join('；')+'）';
    }
    if(firewall.state==='update_failed' || firewall.state==='cleanup_failed'){
     if(firewall.error)rows.summary.firewall+='：'+(typeof firewall.error==='string'?firewall.error:api.errorText(firewall.error));
    }
    else if(!firewallLabels[firewall.state]){
     var configured=s.saved_config || s.active_config;
     if(!configured)rows.summary.firewall+='（未配置）';
     else if(!(configured.access_profile || {}).firewall)rows.summary.firewall+='（旧配置，手动管理）';
    }
   }
   rows.summary.config=pending?'有待应用变更':'无待应用变更';
   var policy=saved.publication_policy || {};rows.summary.policy=(policy.mode==='temporary'?'限定时长':policy.mode==='continuous'?'持续运行':'未配置')+(policy.mode==='temporary'?'；截止：'+(r.expires_at || '未开始'):'');
   var ids={};(active.services || []).concat(saved.services || []).forEach(function(v){ids[v.service_id]=true;});
   Object.keys(ids).forEach(function(id,i){
    var a=(active.services || []).find(function(v){return v.service_id===id;}),v=(saved.services || []).find(function(v){return v.service_id===id;}),shown=v || a,b=shown.backend || {},ready=(r.services || {})[id];
    rows['service_'+i]={'.type':'services',_key:id,identity:shown.name || id,kind:api.serviceType(shown.type),public_entry:publicEntries(shown,v?saved:active).join('；'),match:shown.hostname || (shown.type==='tcp_forward'?'TCP '+shown.listen_port:'共享入口端口'),backend:api.endpoint(b.host,b.port),path:((active.access_profile || saved.access_profile || {}).listeners || []).map(function(l){return l.family;}).join(' / ')+' → '+(b.addressFamily==='hostname'?'待解析':b.addressFamily || '未知'),saved:v?(v.enabled===false?'否':'是'):'已删除',readiness:unknown?'状态未知':!a || r.phase==='stopped'?'未运行':api.running(s) && r.generation!=null && r.generation!=='' && ready && ready.ready===true && ready.generation===r.generation?'运行中':ready && ready.generation!==r.generation?'状态更新中':'未就绪'};
   });
   // Retained active endpoints describe the running configuration, never a
   // saved-but-not-applied replacement. With no active snapshot, show saved
   // endpoints as inactive. Only enabled services create actual ingress sockets.
   var entryConfig=s.active_config || saved,entryListeners=(entryConfig.access_profile || {}).listeners || [],entryServices=(entryConfig.services || []).filter(function(v){return v.enabled!==false;}),entries={};
   entryListeners.forEach(function(l){
    function add(port,purpose){
     var address=l.bind_mode==='auto'?(l.family==='ipv6'?'::':'0.0.0.0'):l.address;
     if(!address || !port)return;
     var key=JSON.stringify([l.family,address,Number(port)]),row=entries[key];
     if(row){if(row.purposes.indexOf(purpose)<0)row.purposes.push(purpose);row.identity=row.purposes.join('；');return;}
     entries[key]={'.type':'entries',_key:key,purposes:[purpose],identity:purpose,endpoint:api.endpoint(address,port),family:l.family,network:l.bind_mode==='auto'?'自动（不绑定网络）':l.network || l.interface || '未知',status:unknown?'状态未知':s.active_config && api.running(s)?'运行中':r.phase==='stopped'?'未运行':'未生效'};
    }
    if(entryServices.some(function(v){return ['http_proxy','https_proxy','tls_passthrough','ssh'].indexOf(v.type)>=0;}))add(l.port || l.internal_port,'共享入口');
    entryServices.filter(function(v){return v.type==='tcp_forward';}).forEach(function(v){add(v.listen_port,(v.name || '独立 TCP 转发')+'（TCP）');});
   });
   Object.keys(entries).forEach(function(key,i){rows['entry_'+i]=entries[key];});
   rows.services=Object.keys(rows).filter(function(k){return k.indexOf('service_')===0;}).map(function(k){var v=rows[k];delete rows[k];return v;});
   rows.entries=Object.keys(rows).filter(function(k){return k.indexOf('entry_')===0;}).map(function(k){var v=rows[k];delete rows[k];return v;});
   var m=new form.JSONMap(rows,'HomePublish','提供内网服务开放到公网统一入口，支持多协议共享端口。');m.readonly=false;
   var section=m.section(form.NamedSection,'summary','summary','运行状态');
   var enabled=(s.desired_state || {}).state==='enabled',toggleKind=enabled?'stop':'start';
   var enable=section.option(form.DummyValue,'enable','启用');
   enable.renderWidget=function(){return E('input',{id:'hp-enable',type:'checkbox',checked:enabled,disabled:!gates[toggleKind].allowed,'aria-label':'启用',change:function(ev){
    ev.target.checked=(state.desired_state || {}).state==='enabled';
    var kind=ev.target.checked?'stop':'start';
    if(!api.actionGates(state,{unknown:!!unknown,busy:busy || actionBusy})[kind].allowed)return;
    return api.actionDialog(root,state,kind,function(st){++epoch;state=st;unknown=null;draw();},function(e){++epoch;unknown=api.errorText(e);draw();},function(pending){actionBusy=pending;++epoch;draw();});
   }});};
   [['publication','运行状态'],['firewall','入站防火墙'],['config','配置状态'],['policy','运行策略']].forEach(function(c){section.option(form.DummyValue,c[0],c[1]);});
   var entrySection=readonlyGrid(m,'entries','入口状态',[['identity','名称 / 用途'],['endpoint','本机监听'],['family','地址族'],['network','关联网络'],['status','运行状态']]);
   var serviceSection=readonlyGrid(m,'services','服务运行状态',[['saved','启用'],['identity','名称'],['kind','接入方式'],['public_entry','公网入口地址'],['match','匹配 / 端口'],['backend','后端地址'],['path','入口 → 后端'],['readiness','运行状态']]);
   var probeColumn=serviceSection.option(form.DummyValue,'probe','后端连通性');probeColumn.editable=true;
   probeColumn.renderWidget=function(sid){var item=m.data.get(m.config,sid),id=item._key;
    return E('div',{'data-hp-probe':id,style:'display:flex;gap:0.5rem;align-items:center;flex-wrap:wrap'},[
     E('button',{type:'button',class:'btn btn-secondary cbi-button cbi-button-neutral',disabled:!(saved.services || []).some(function(v){return v.service_id===id;}),click:function(){return probeQueue.run([id]);}},'测试'),E('span',{},'未测试')]);
   };
   text(message,unknown?'状态读取失败，请重试；不能判定已停止':pending?'已保存待应用；旧运行配置不会随保存切换':'');
   if(body.querySelector('.cbi-map')){
    updateRow(body.querySelector('#cbi-json-summary'),rows.summary,['publication','firewall','config','policy']);
    var toggle=body.querySelector('#hp-enable');toggle.disabled=!gates[toggleKind].allowed;toggle.checked=enabled;
    return Promise.all([syncGrid(entrySection,'entries',rows.entries,['identity','endpoint','family','network','status'],rendering),syncGrid(serviceSection,'services',rows.services,['saved','identity','kind','public_entry','match','backend','path','readiness'],rendering)]).then(refreshProbes);
   }
   return m.render().then(function(node){if(rendering!==renderEpoch)return;dom.content(body,node);['entries','services'].forEach(function(type){body.querySelectorAll('#cbi-json-'+type+' tbody tr:not(.placeholder)').forEach(function(row,i){row.dataset.hpKey=rows[type][i]._key;});});body.querySelector('#cbi-json-services').append(probeHelp);refreshProbes();});
  }
  function reload(){if(busy || actionBusy)return;busy=true;var request=++epoch;return api.status().then(api.checked).then(function(s){if(request===epoch){state=s;unknown=null;}}).catch(function(e){if(request===epoch)unknown=api.errorText(e);}).finally(function(){busy=false;if(request===epoch)return draw();});}
  poll.add(function(){if(unknown && document.querySelector('#modal_overlay [role="dialog"]'))return;return reload();},2);return draw().then(function(){return root;});
 },handleSave:null,handleSaveApply:null,handleReset:null
});
