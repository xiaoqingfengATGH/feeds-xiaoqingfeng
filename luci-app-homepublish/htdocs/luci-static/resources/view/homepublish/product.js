/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require baseclass';
'require rpc';
'require dom';
'require ui';
var status=rpc.declare({object:'homepublish',method:'status',expect:{},reject:true});
var validate=rpc.declare({object:'homepublish',method:'validate',params:['config'],expect:{},reject:true});
var save=rpc.declare({object:'homepublish',method:'save',params:['expected_revision','config'],expect:{},reject:true});
var stop=rpc.declare({object:'homepublish',method:'stop',expect:{},reject:true});
return baseclass.extend({
 status:status,validate:validate,save:save,stop:stop,
 certificates:rpc.declare({object:'homepublish',method:'certificates',expect:{},reject:true}),
 start:rpc.declare({object:'homepublish',method:'start',params:['revision','approved'],expect:{},reject:true}),
 apply:rpc.declare({object:'homepublish',method:'apply',params:['revision','approved'],expect:{},reject:true}),
 checked:function(s){if(!s || s.error)throw new Error(s && s.error || 'State unavailable');return s;},
 /* 证书下拉/列表排序：被本应用使用的靠前（入口默认 + 各服务绑定，继承按入口默认算），
     未使用的排后面；同组内按域名、密钥类型排序 */
 sortInventory:function(inventory,saved){
  var usage={};
  var users=function(ref){
   if(!usage[ref]){
    var list=[];
    if(saved && saved.default_certificate_ref===ref)list.push('entry');
    (Array.isArray(saved && saved.services) ? saved.services : []).forEach(function(svc){
     if(svc.type && svc.type!=='https_proxy')return;
     var bound=svc.certificate_mode==='inherit'?saved.default_certificate_ref:svc.certificate_ref;
     if(bound===ref)list.push(svc.hostname || svc.service_id);
    });
    usage[ref]=list;
   }
   return usage[ref];
  };
  return inventory.slice().sort(function(a,b){
   var ua=users(a.certificate_ref).length>0,ub=users(b.certificate_ref).length>0;
   if(ua!==ub)return ua?-1:1;
   if(a.domain!==b.domain)return a.domain<b.domain?-1:1;
   return a.key_type<b.key_type?-1:1;
  });
 },
 endpoint:function(host,port){return (String(host || '').indexOf(':')>=0?'['+host+']':host || '未知')+':'+(port || '未知');},
 serviceType:function(type){return ({https_proxy:'HTTPS 反向代理',tls_passthrough:'TLS 透传',ssh:'原生 SSH',ssh_shared:'原生 SSH',tcp_forward:'独立 TCP'})[type] || type || '未知';},
 actionGates:function(s,opts){
  s=s || {};opts=opts || {};var r=s.runtime || {},d=s.desired_state || {},caps=s.capabilities || {},pending=!!(s.pending_config && s.pending_config.apply_required),running=this.running(s),clean=r.cleanup==='confirmed',stable=r.phase==='stopped' || r.phase==='failed' || r.phase==='blocked';
  function gate(reason){return {allowed:!reason,reason:reason || '需确认发布范围'};}
  var common=opts.busy?'操作处理中':opts.unknown?'状态未知，请先刷新':opts.dirty?'存在未保存修改，请先保存或重置':!s.saved_revision || !s.saved_config?'请先保存配置':'';
  var cleanupReason=!clean?'清理未确认，先停止并重试':'';
  return {start:gate(common || cleanupReason || (caps.start!==true?'当前通道不支持启动':!stable?'当前阶段不能启动':'')),apply:gate(common || (!running?cleanupReason:'') || (caps.apply!==true?'当前通道不支持应用':!running || d.manual_stop_latch?'当前没有可替换的运行组':!pending?'无待应用变更':'')),stop:gate(opts.busy?'操作处理中':caps.stop!==true?'当前通道不支持停止':opts.unknown || r.phase!=='stopped' || !clean || !!s.active_config || d.state==='enabled'?'':'已停止且清理完成')};
 },
 actionDialog:function(root,s,kind,updated,failed,submitting){
  var api=this,busy=false,config=(kind==='stop'?s.active_config:s.saved_config) || {},r=s.runtime || {};
  function button(id,text,fn){return E('button',{id:id,type:'button',class:'cbi-button',click:fn},text);}
  var diff=kind==='stop'?['停止当前整组服务，关闭已有连接并撤销发布意图']:api.diff(s.active_config,s.saved_config),alert=E('p',{role:'alert'});
  var scope=E('div',{id:'hp-confirm-scope'},[
   E('p',{},'配置版本：'+(kind==='stop'?s.active_revision:s.saved_revision)+'；整组操作，应用有短暂停机，不延长原临时截止。'),
   E('ul',{},((config.access_profile || {}).listeners || []).map(function(l){return E('li',{},'监听 '+api.endpoint(l.address,l.port || l.internal_port)+' · '+l.family+' · 网络 '+(l.network || l.interface || '未知'));})),
   E('ul',{},(config.services || []).filter(function(v){return v.enabled!==false;}).map(function(v){return E('li',{},(v.name || v.service_id)+' · '+api.serviceType(v.type)+' · '+(v.hostname || (v.type==='tcp_forward'?'独立端口 '+v.listen_port:'共享入口'))+' → '+api.endpoint((v.backend || {}).host,(v.backend || {}).port)+'；证书：'+(v.type==='https_proxy'?(v.certificate_mode==='inherit'?'继承 '+(config.default_certificate_ref || '未选择'):v.certificate_ref || '未选择'):v.type==='tls_passthrough'?'后端提供':'不需要'));})),
   E('p',{},'策略：'+((config.publication_policy || {}).mode==='temporary'?'临时 '+((config.publication_policy || {}).temporary_duration || 0)+' 秒':'持续直到停止')+'；原截止：'+(r.expires_at || '首次启动后建立'))
  ]);
  var submit=button('hp-edit-submit','确认',function(){
   if(busy)return;busy=true;submit.disabled=true;if(submitting)submitting(true);
   return Promise.resolve().then(function(){return api.status();}).then(api.checked).then(function(current){
    if(current.saved_revision!==s.saved_revision || current.active_revision!==s.active_revision || (current.runtime || {}).generation!==r.generation)throw new Error('配置或运行状态已变化，请刷新后重新确认');
    if(!api.actionGates(current)[kind].allowed)throw new Error('当前状态不允许此操作，请刷新');
    return kind==='stop'?api.stop():api[kind](s.saved_revision,true);
   }).then(api.checked).then(function(){return api.status();}).then(api.checked).then(function(st){updated(st);ui.hideModal();}).catch(function(e){alert.textContent=api.errorText(e)+'；请刷新并重新确认';failed(e);}).finally(function(){busy=false;submit.disabled=false;if(submitting)submitting(false);});
  });
  return ui.showModal(kind==='stop'?'停止全部服务':kind==='apply'?'整组应用变更':'开启已保存服务',[scope,E('details',{},[E('summary',{},'变更明细'),E('ul',{id:'hp-confirm-diff'},diff.map(function(x){return E('li',{},x);}))]),alert,E('div',{class:'right'},[button('hp-edit-cancel','取消',function(){if(!busy)ui.hideModal();}),submit])]);
 },
 diff:function(before,after){
  before=before || {};after=after || {};var out=[];
  function changed(label,a,b){if(JSON.stringify(a)!==JSON.stringify(b))out.push(label+'：'+(a==null?'无':JSON.stringify(a))+' → '+(b==null?'无':JSON.stringify(b)));}
  function cert(c,v){return {mode:v.certificate_mode || 'override',binding:v.certificate_mode==='inherit'?'继承入口默认':'独立指定',resolved:v.certificate_mode==='inherit'?c.default_certificate_ref:v.certificate_ref};}
  changed('入口默认证书',before.default_certificate_ref,after.default_certificate_ref);
  var old=before.services || [],next=after.services || [];
  var api=this;function identity(v){return api.serviceType(v.type)+' · '+(v.name || v.hostname || v.service_id || '未命名')+'（'+(v.service_id || '未知 ID')+'）';}
  old.forEach(function(v){var n=next.find(function(x){return x.service_id===v.service_id;});if(!n){out.push('删除 '+identity(v)+'（应用关闭其连接，并替换整组）');return;}
   var prefix=identity(v)+' / ';changed(prefix+'名称',v.name,n.name);changed(prefix+'发布方式',api.serviceType(v.type),api.serviceType(n.type));changed(prefix+'独立监听端口',v.listen_port,n.listen_port);changed(prefix+'域名',v.hostname,n.hostname);changed(prefix+'后端 / 家庭网段',v.backend,n.backend);changed(prefix+'证书绑定 / 解析证书',cert(before,v),cert(after,n));changed(prefix+'参与发布',v.enabled!==false,n.enabled!==false);changed(prefix+'业务鉴权 / 管理服务',v.authentication_review,n.authentication_review);
  });next.forEach(function(v){if(!old.some(function(x){return x.service_id===v.service_id;}))out.push('新增 '+identity(v)+'：'+JSON.stringify(v)+'；证书 '+JSON.stringify(cert(after,v)));});
  changed('监听 / 接入方式',before.access_profile,after.access_profile);changed('发布策略 / 开机恢复',before.publication_policy,after.publication_policy);return out;
 },
 text:function(s){
  if(!s || s.error || !s.runtime || !s.desired_state)return 'State unavailable / unknown; not running';
  var r=s.runtime, running=r.phase==='running' && r.active_verified===true && s.desired_state.state==='enabled' && !s.desired_state.manual_stop_latch;
  return 'saved: '+s.saved_revision+'; active: '+(s.active_revision || 'none')+'; pending: '+!!(s.pending_config && s.pending_config.apply_required)+'; desired: '+s.desired_state.state+'; manual stop: '+s.desired_state.manual_stop_latch+'; runtime: '+r.phase+'; verified running: '+running+'; attempted: '+(s.attempted_revision || 'none')+'; stage: '+(r.stage || 'none')+'; error: '+(r.last_error || 'none')+'; cleanup: '+(r.cleanup || 'unknown');
 },
 layers:function(s){
  s=s || {};var r=s.runtime || {},d=s.desired_state || {},saved=s.saved_config && s.saved_config.publication_policy,active=s.active_config && s.active_config.publication_policy;
  var verified=r.phase==='running' && r.active_verified===true && d.state==='enabled' && !d.manual_stop_latch;
  function line(id,title,text){return E('section',{id:'hp-layer-'+id},[E('h3',{},title),E('p',{},text)]);}
  return E('div',{},[
   line('config','配置与应用','saved: '+(s.saved_revision==null?'unknown':s.saved_revision)+'; active: '+(s.active_revision || 'none')+'; pending: '+!!(s.pending_config && s.pending_config.apply_required)+'; attempted: '+(s.attempted_revision || 'none')+'; candidate: '+(s.candidate_revision || 'none')),
   line('runtime','内部运行（不是公网证明）','phase: '+(r.phase || 'unknown')+'; verified running: '+verified+'; generation: '+(r.generation || 'none')+'; stage: '+(r.stage || 'none')+'; cleanup: '+(r.cleanup || 'unknown')+'; error: '+(r.last_error || 'none')),
   line('recovery','恢复与退避','attempts: '+(r.attempt_count || 0)+' / 3; next retry: '+(r.next_retry || 'none')+'; reason / blocked reason: '+(r.reason || r.last_error || 'none')+'; desired: '+(d.state || 'unknown')+'; manual stop: '+!!d.manual_stop_latch),
   line('policy','期限与开机恢复','saved policy: '+(saved?saved.mode:'none')+'; deadline: '+(r.expires_at || 'not started')+'; saved boot_restore: '+(saved?!!saved.boot_restore:'unknown')+'; active boot_restore: '+(active?!!active.boot_restore:'none')+'; restore stage: '+(r.stage || 'none')+'; clock trusted: '+(r.clock_trusted==null?'unknown':r.clock_trusted)+'; boot id: '+(r.boot_id || 'unknown')),
   line('services','逐服务内部就绪',JSON.stringify(r.services || {})),
   line('external','外网可达性：未验证','IPv4 / IPv6 外网均未验证；配置预检不探测网络。DNS / TLS / INPUT / 映射无独立证据，不能据 saved、pending 或内部运行判断公网成功。')
  ]);
 },
 defaults:function(){return {schema_version:1,services:[{service_id:'nas',name:'NAS',hostname:'nas.example.test',backend:{addressFamily:'ipv4',host:'192.168.1.10',port:8080,allowed_ranges:['192.168.1.0/24']},certificate_ref:'acme:nas',authentication_review:{authentication:'unconfirmed',management:false}}],access_profile:{methods_allowed:['manual_ipv4'],listeners:[{family:'ipv4',address:'192.168.1.2',interface:'wan',zone:'wan',protocol:'tcp',internal_port:8443,external_port:18443}]},publication_policy:{mode:'continuous',boot_restore:false}};},
 /* r9 语义 Save：form.Map(JSONMap) 的本地 data.save 为 no-op；提交走 RPC save（pending 不启动）。
	    handleSaveApply：Save 后弹确认对话框展示 api.diff 具体差异与整组影响 → 确认才 api.apply(approved=true)。
	    按钮使能只由 saved_revision / running / pending / cleanup 真实状态驱动，无能力假门控。 */
 running:function(s){var r=(s || {}).runtime || {},d=(s || {}).desired_state || {};return r.phase==='running' && r.active_verified===true && d.state==='enabled' && !d.manual_stop_latch;},
 addressEqual:function(a,b){if(a===b)return true;try{return new URL('http://['+a+']/').hostname===new URL('http://['+b+']/').hostname;}catch(e){return false;}},
 networkInventory:rpc.declare({object:'homepublish',method:'network_inventory',expect:{},reject:true}),
 migrationPreview:rpc.declare({object:'homepublish',method:'migration_preview',params:['expected_revision'],expect:{},reject:true}),
 clone:function(v){return JSON.parse(JSON.stringify(v));},
 errorText:function(e){
  var labels={REVISION_CONFLICT:'配置已被其他页面修改，请重新载入后编辑',DOMAIN_CONFLICT:'域名重复',SSH_CONFLICT:'共享入口只能配置一个 SSH 服务',PORT_CONFLICT:'监听端口冲突',ADDRESS_UNAVAILABLE:'所选地址已不可用',NETWORK_UNAVAILABLE:'网络不可用',ZONE_AMBIGUOUS:'网络区域关联不明确',STATE_UNKNOWN:'状态未知，请重试',DEPENDENCY_UNAVAILABLE:'设备缺少所需能力',INVALID_CONFIG:'配置不完整或无效'};
  return (labels[e.error_code] || '操作失败')+(e.field?'（'+e.field+'）':'');
 },
 checked:function(s){if(!s || s.error){var e=new Error('状态读取失败或操作被拒绝');Object.assign(e,s || {});throw e;}return s;},
 serviceRows:function(saved){return (saved.services || []).map(function(s){var r=JSON.parse(JSON.stringify(s)),b=s.backend || {};r.backend_host=b.host;r.backend_port=String(b.port || '');r.allowed_ranges=b.allowed_ranges || [];r.tls_server_name=(s.upstream_tls || {}).server_name || '';r.management=(s.authentication_review || {}).management?'1':'0';r.authentication=(s.authentication_review || {}).authentication || 'unconfirmed';r.enabled=s.enabled?'1':'0';return r;});},
 collectConfig:function(map){
  var data=map.data.data,out=this.clone(map.snapshot),p=data.cfg_policy,l=data.cfg_listener;
  if(out.schema_version!==2)throw new Error('请先预览并确认旧配置迁移');
  if(l){
   var old=out.access_profile.listeners;
   out.access_profile={listeners:['ipv4','ipv6'].filter(function(f){return l.family==='dual' || l.family===f;}).map(function(f){
    var existing=old.find(function(x){return x.family===f;});
    return {listener_id:existing?existing.listener_id:'shared_'+f,family:f,network:l[f+'_network'],address:l[f+'_address'],port:Number(l.port)};
   })};
  }
  if(p){
   if(p.default_certificate_ref)out.default_certificate_ref=p.default_certificate_ref;else delete out.default_certificate_ref;
   out.publication_policy={mode:p.mode,boot_restore:p.boot_restore==='1' || p.boot_restore===true};
   if(p.mode==='temporary')out.publication_policy.temporary_duration=Number(p.temporary_minutes)*60;
  }
  if(map.editor==='services'){
   out.services=[];
   var rows=map.data.sections(map.config,'services'),used={};
   (out.services.concat(map.snapshot.services || [],rows)).forEach(function(row){if(row.service_id)used[row.service_id]=true;});
   rows.forEach(function(row){
    if(!row.service_id){var n=1;while(used['svc_'+n])n++;row.service_id='svc_'+n;used[row.service_id]=true;}
    var host=String(row.backend_host || ''),previous=row.backend || {};
    var backend={host:host,addressFamily:host.indexOf(':')>=0?'ipv6':/^\d+\.\d+\.\d+\.\d+$/.test(host)?'ipv4':'hostname',port:Number(row.backend_port),allowed_ranges:row.allowed_ranges || []};
    if(previous.backup)backend.backup=JSON.parse(JSON.stringify(previous.backup));
    var svc={service_id:row.service_id,name:row.name,enabled:row.enabled==='1' || row.enabled===true,type:row.type,backend:backend,authentication_review:{authentication:row.authentication || 'unconfirmed',management:row.management==='1' || row.management===true}};
    if(row.type==='https_proxy' || row.type==='tls_passthrough')svc.hostname=row.hostname;
    if(row.type==='https_proxy'){
     svc.upstream_scheme=row.upstream_scheme || 'http';svc.certificate_mode=row.certificate_mode || 'inherit';
     if(svc.certificate_mode==='override' && row.certificate_ref)svc.certificate_ref=row.certificate_ref;
     if(svc.upstream_scheme==='https')svc.upstream_tls={verify:true,server_name:row.tls_server_name};
    }
    if(row.type==='tcp_forward')svc.listen_port=Number(row.listen_port);
    out.services.push(svc);
   });
  }
  return out;
 },
 loadEditor:function(withNetworks){
  var api=this;
  return Promise.all([api.status().then(function(s){return api.checked(s);}),api.certificates().then(function(s){return api.checked(s);}),withNetworks?api.networkInventory().then(function(s){return api.checked(s);}):Promise.resolve(null)]).catch(function(){return [{error:'状态读取失败，请重试'}, {certificates:[]}, null];});
 },
 editorUnavailable:function(state){
  return E('div',{class:'cbi-map'},[E('h2',{},'HomePublish'),E('p',{role:'alert'},state.error || '配置读取失败，不能保存'),E('button',{class:'cbi-button',click:function(){location.reload();}},'重新载入')]);
 },
 migrationPanel:function(state){
  var api=this,preview=null,busy=false,box=E('div',{class:'cbi-map'}),message=E('div',{role:'alert'});
  box.append(E('h2',{},'旧版配置需要确认迁移'),E('p',{},'读取不会修改配置。预览保留全部入口与服务；确认保存前备份旧配置，不启动发布。'),message,
   E('button',{id:'hp-migration-preview',class:'cbi-button',click:function(){if(busy)return;busy=true;return api.migrationPreview(state.saved_revision).then(function(p){api.checked(p);preview=p;message.replaceChildren(E('pre',{},JSON.stringify({warnings:p.warnings,blocking_issues:p.blocking_issues,proposed_config:p.proposed_config},null,2)));confirm.disabled=!p.proposed_config || (p.blocking_issues || []).length>0;}).catch(function(e){message.textContent=api.errorText(e);}).finally(function(){busy=false;});}},'预览迁移'));
  var confirm=E('button',{id:'hp-migration-confirm',class:'cbi-button cbi-button-save',disabled:true,click:function(){
   ui.showModal('确认迁移并保存',[E('p',{},'将按当前版本保存预览配置并备份原始配置；不启动发布。'),E('div',{class:'right'},[E('button',{class:'cbi-button',click:ui.hideModal},'取消'),E('button',{class:'cbi-button cbi-button-save',click:function(){if(busy)return;busy=true;return api.save(state.saved_revision,preview.proposed_config).then(function(s){api.checked(s);return api.status();}).then(function(s){api.checked(s);if(s.saved_config.schema_version!==2)throw new Error('迁移读取核验失败');location.reload();}).catch(function(e){message.textContent=api.errorText(e);ui.hideModal();}).finally(function(){busy=false;});}},'确认保存')])]);
  }},'确认迁移');box.append(confirm);return box;
 },
 actionBar:function(node,state,opts){
  var api=this,map=opts.map,busy=false,dirty=false,blocked=false,message=E('p',{id:'hp-message',role:'status','aria-live':'polite'},'保存只更新本应用配置，不启动发布'),holder=E('div',{},[node]),bar=E('div',{class:'cbi-page-actions'});
  var initialDraft=JSON.stringify(api.collectConfig(map));
  function leave(e){var changed=dirty;try{changed=changed || JSON.stringify(api.collectConfig(map))!==initialDraft;}catch(err){changed=true;}if(changed){e.preventDefault();e.returnValue='';}}
  window.addEventListener('beforeunload',leave);
  holder.addEventListener('change',function(){dirty=true;});holder.addEventListener('input',function(){dirty=true;});
  var saveButton=E('button',{id:'hp-save',type:'button',class:'cbi-button cbi-button-save important',click:function(){
   if(busy || blocked)return;busy=true;saveButton.disabled=true;
   return Promise.resolve().then(function(){return map.save();}).then(function(){return api.validate(api.collectConfig(map));}).then(function(v){if(!v.valid){api.checked(v);throw new Error('配置验证失败');}return api.save(map.snapshotRevision,v.config);}).then(function(s){api.checked(s);return api.status();}).then(function(s){api.checked(s);dirty=false;window.removeEventListener('beforeunload',leave);location.reload();}).catch(function(e){
    message.textContent=api.errorText(e);if(e.error_code==='REVISION_CONFLICT'){blocked=true;message.append('；当前草稿保留，重置后再编辑。');}
    if(e.field){var path=e.field.replace(/services\[(\d+)\]/,'services');holder.querySelectorAll('[data-field]').forEach(function(n){if(n.dataset.field.endsWith('.'+path.split('.').pop())){n.setAttribute('aria-invalid','true');n.title=api.errorText(e);}});}
   }).finally(function(){busy=false;saveButton.disabled=blocked;});
  }},'保存');
  var reset=E('button',{id:'hp-reset',type:'button',class:'cbi-button cbi-button-reset',click:function(){ui.showModal('重新载入已保存配置',[E('p',{},'放弃当前页面草稿？'),E('div',{class:'right'},[E('button',{class:'cbi-button',click:ui.hideModal},'取消'),E('button',{class:'cbi-button cbi-button-reset',click:function(){dirty=false;window.removeEventListener('beforeunload',leave);location.reload();}},'重新载入')])]);}},'重置');
  bar.append(saveButton,reset);holder.append(message,bar);return holder;
 }
});
