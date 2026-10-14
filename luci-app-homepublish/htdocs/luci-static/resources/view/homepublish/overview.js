/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require view';
'require poll';
'require view.homepublish.product as api';
return view.extend({
 load:function(){return Promise.all([api.status().then(api.checked),api.certificates().then(api.checked)]).then(function(d){return {state:d[0],inventory:d[1].certificates || []};}).catch(function(e){return {error:e.message};});},
 render:function(data){
  var s=data.state,inventory=data.inventory || [],unknown=data.error,root=E('div',{id:'hp-overview',class:'hp-native'}),message=E('p',{id:'hp-message','aria-live':'polite'}),sections={},buttons={};
  root.append(E('style',{},'.hp-native{overflow-wrap:anywhere}.hp-native .hp-cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:16px}.hp-native section{border:1px solid #aaa5;border-radius:6px;padding:16px;margin:12px 0}.hp-native .hp-table{overflow-x:auto}.hp-native table{width:100%;min-width:520px}.hp-native button{margin:4px}.hp-native dialog{width:560px;max-width:calc(100vw - 32px);max-height:85vh;overflow:auto;box-sizing:border-box}.hp-native [role=alert]{color:#b22}.hp-native pre{white-space:pre-wrap}'),E('h2',{},'家庭服务直连发布'),message);
  var bar=E('div');['start','apply','stop'].forEach(function(kind){buttons[kind]=E('button',{id:'hp-'+kind,type:'button',class:'cbi-button',click:function(){if(!s || unknown)return;return api.actionDialog(root,s,kind,function(st){s=st;unknown=null;refresh();},function(e){unknown=e.message;refresh();});}},({start:'开启已保存配置',apply:'应用已保存变更',stop:'停止全部服务'})[kind]);bar.appendChild(buttons[kind]);});
  bar.append(E('button',{id:'hp-retry',type:'button',class:'cbi-button',click:reload},'刷新 / 重试'),E('a',{href:L.url('admin','services','homepublish','services')},'编辑服务与入口配置'));root.appendChild(bar);
  var cards=E('div',{class:'hp-cards'});[['config','已保存配置'],['local','本机运行与 TLS'],['public','公网入口'],['policy','发布期限与恢复']].forEach(function(v){sections[v[0]]=E('div',{id:'hp-'+v[0]});cards.append(E('section',{},[E('h3',{},v[1]),sections[v[0]]]));});root.appendChild(cards);
  var table=E('div',{id:'hp-overview-services',class:'hp-table'}),entry=E('div',{id:'hp-overview-entry'}),raw=E('pre'),details=E('details',{id:'hp-overview-diagnostics'},[E('summary',{},'内部状态与失败 / 清理详情'),raw]);root.append(E('section',{},[E('h3',{},'服务发布清单'),E('p',{},'以下为已保存配置；实际运行仅以逐服务内部就绪为准。'),table]),E('section',{},[E('h3',{},'入口与证书摘要'),entry]),details);
  function cert(ref,host){var c=inventory.find(function(v){return v.certificate_ref===ref;});return ref?(c?c.domain+' · '+String(c.key_type || '').toUpperCase()+' · '+(c.status==='within_validity'?'有效期内（SAN / TLS 另验）':'有效期不可用或未知')+' · '+(c.not_after || '日期未知'):ref+'（库存未确认）'):'未选择';}
  function refresh(){
   var st=s || {},r=st.runtime || {},d=st.desired_state || {},c=st.saved_config || {},pending=!!(st.pending_config && st.pending_config.apply_required),running=!unknown && api.running(st);
   /* 按钮使能只由真实状态驱动：saved_revision / running / pending；无能力假门控 */
   buttons.start.disabled=!!unknown || !st.saved_revision || running || r.cleanup==='unknown';buttons.apply.disabled=!!unknown || !running || !pending;buttons.stop.disabled=!!unknown || !running;
   message.textContent=unknown?'状态读回失败 / 未知：'+unknown+'；不能判定已停止，请重试':pending?'已保存待应用；保存不启动，旧运行组不会随保存切换':'保存配置不启动；开启与应用均需明确确认';
   sections.config.textContent='保存版本：'+(st.saved_revision==null?'未知':st.saved_revision)+'；运行版本：'+(st.active_revision || '无')+'；'+(pending?'已保存待应用':'无待应用变更');
   sections.local.textContent=unknown?'状态未知（不是已停止）':running?'本机运行已验证；TLS 仅代表本机内部就绪，不证明公网可达':r.phase==='stopped'?'本机已停止；TLS 未运行':'本机未验证；阶段：'+({blocked:'已阻止',failed:'失败',starting:'启动中',stopping:'停止中'}[r.phase] || r.phase || '未知');
   sections.public.textContent='IPv4 / IPv6 公网未验证；DNS、INPUT、上级映射与公网 TLS 无独立探测证据。不要将本机运行视为公网成功。';
   var policy=c.publication_policy || {};sections.policy.textContent='已保存策略：'+(policy.mode==='temporary'?'临时限时':policy.mode==='continuous'?'持续直到停止':'未配置')+'；原截止：'+(r.expires_at || '未开始')+'；开机恢复：'+(policy.boot_restore?'开启':'关闭')+'；自动恢复尝试：'+(r.attempt_count || 0)+' / 3';
   table.replaceChildren(E('table',{class:'table'},[E('thead',{},E('tr',{},['名称 / 域名','家庭后端','证书绑定','参与 / 内部就绪'].map(function(t){return E('th',{},t);}))),E('tbody',{},(c.services || []).map(function(v){var readiness=(r.services || {})[v.service_id],ref=v.certificate_mode==='inherit'?c.default_certificate_ref:v.certificate_ref;return E('tr',{'data-service':v.service_id},[E('td',{},v.name+' / '+v.hostname),E('td',{},(v.backend.addressFamily==='ipv6'?'['+v.backend.host+']':v.backend.host)+':'+v.backend.port),E('td',{},(v.certificate_mode==='inherit'?'继承入口默认：':'独立指定：')+cert(ref,v.hostname)),E('td',{},(v.enabled===false?'不参与下次发布':'参与下次发布')+'；'+(running && readiness && readiness.ready===true?'内部已就绪':'未确认就绪'))]);}))]));if(!(c.services || []).length)table.appendChild(E('p',{},unknown?'服务状态未知':'尚无已保存服务，请前往配置。'));
   entry.replaceChildren(E('p',{},'入口默认证书：'+cert(c.default_certificate_ref)),E('ul',{},((c.access_profile || {}).listeners || []).map(function(l){return E('li',{},l.family+' · '+l.address+':'+l.internal_port+' → 外网端口 '+l.external_port+' · 接口 '+l.interface+' / 区域 '+l.zone);})),E('p',{},'证书库存只证明有效期与 SAN 信息，不代表完整 TLS / CA 链验收；不显示私钥。'));
   raw.textContent=JSON.stringify({error:unknown || null,state:s || null},null,2);
  }
  function reload(){return Promise.all([api.status().then(api.checked),api.certificates().then(api.checked)]).then(function(d){s=d[0];inventory=d[1].certificates || [];unknown=null;refresh();}).catch(function(e){unknown=e.message;refresh();});}
  poll.add(reload,2);refresh();return root;
 },handleSave:null,handleSaveApply:null,handleReset:null
});
