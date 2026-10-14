/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require baseclass';
'require rpc';
'require dom';
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
 actionDialog:function(root,s,kind,updated,failed){
  var api=this,d=E('dialog'),busy=false;
  function button(id,text,fn){return E('button',{id:id,type:'button',class:'cbi-button',click:fn},text);}
  var config=kind==='stop'?s.active_config:s.saved_config;
  var diff=kind==='stop'?['停止当前整组服务；关闭所有已建立连接，撤销发布意图。']:api.diff(s.active_config,s.saved_config);
  d.append(E('h3',{},kind==='stop'?'停止全部服务':kind==='apply'?'整组应用变更':'开启已保存服务'),E('ul',{id:'hp-confirm-diff'},(diff.length?diff:['整个已保存运行组']).map(function(x){return E('li',{},x);})),E('p',{},'整组连接将关闭 / 替换，应用存在短暂停机；临时截止不延长：'+((s.runtime || {}).expires_at || '首次开启建立截止')),E('p',{},'监听与接入范围：'+JSON.stringify(config && config.access_profile || {})),E('p',{role:'alert'}),button('hp-edit-cancel','取消',function(){if(!busy)d.close();}),button('hp-edit-submit','确认',function(){
   if(busy)return;busy=true;d.querySelector('#hp-edit-submit').disabled=true;
   return Promise.resolve().then(function(){return kind==='stop'?api.stop():api[kind](s.saved_revision,true);}).then(api.checked).then(function(){return api.status();}).then(api.checked).then(function(st){updated(st);d.close();}).catch(function(e){d.querySelector('[role=alert]').textContent='操作失败 / 状态未知：'+e.message;failed(e);}).finally(function(){busy=false;var submit=d.querySelector('#hp-edit-submit');if(submit)submit.disabled=false;});
  }));root.appendChild(d);d.addEventListener('close',function(){d.remove();});d.showModal();return d;
 },
 diff:function(before,after){
  before=before || {};after=after || {};var out=[];
  function changed(label,a,b){if(JSON.stringify(a)!==JSON.stringify(b))out.push(label+'：'+(a==null?'无':JSON.stringify(a))+' → '+(b==null?'无':JSON.stringify(b)));}
  function cert(c,v){return {mode:v.certificate_mode || 'override',binding:v.certificate_mode==='inherit'?'继承入口默认':'独立指定',resolved:v.certificate_mode==='inherit'?c.default_certificate_ref:v.certificate_ref};}
  changed('入口默认证书',before.default_certificate_ref,after.default_certificate_ref);
  var old=before.services || [],next=after.services || [];
  old.forEach(function(v){var n=next.find(function(x){return x.service_id===v.service_id;});if(!n){out.push('删除 '+v.hostname+'（应用关闭其连接，并替换整组）');return;}
   var prefix=v.hostname+' / ';changed(prefix+'名称',v.name,n.name);changed(prefix+'域名',v.hostname,n.hostname);changed(prefix+'后端 / 家庭网段',v.backend,n.backend);changed(prefix+'证书绑定 / 解析证书',cert(before,v),cert(after,n));changed(prefix+'参与发布',v.enabled!==false,n.enabled!==false);changed(prefix+'业务鉴权 / 管理服务',v.authentication_review,n.authentication_review);
  });next.forEach(function(v){if(!old.some(function(x){return x.service_id===v.service_id;}))out.push('新增 '+v.hostname+'：'+JSON.stringify(v)+'；证书 '+JSON.stringify(cert(after,v)));});
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
 collectConfig:function(map){
  /* 从 JSONMap 数据重建 canonical 配置：services 行 + 单 listener + 策略 NamedSection 的选项写入。
     视图把 listener/policy 字段写到 map.data 的独立 section 上，由 product.js 统一组装。 */
  var data=map.data.data,out=JSON.parse(JSON.stringify(map.snapshot || {}));
  out.schema_version=1;
  var section=function(name){return data[name] && typeof data[name]==='object' ? data[name] : null;};
  /* 入口 listener（cfg_listener）：端口字符串数值化 */
  var l=section('cfg_listener');
  if(l){
   var ln={};
   ['family','address','interface','zone'].forEach(function(k){if(l[k]!=null && l[k]!=='')ln[k]=l[k];});
   ln.protocol='tcp';
   ['internal_port','external_port'].forEach(function(k){if(l[k]!=null && l[k]!=='')ln[k]=Number(l[k]);});
   out.access_profile=out.access_profile || {};
   out.access_profile.methods_allowed=out.access_profile.methods_allowed || ['manual_ipv4'];
   out.access_profile.listeners=[ln];
  }
  /* 默认证书与发布策略（cfg_policy） */
  var p=section('cfg_policy');
  if(p){
   if(p.default_certificate_ref)out.default_certificate_ref=p.default_certificate_ref;
   else delete out.default_certificate_ref;
   var policy={mode:p.mode || 'continuous'};
   if(p.mode==='temporary' && p.temporary_duration!=null && p.temporary_duration!=='')policy.temporary_duration=Number(p.temporary_duration);
   policy.boot_restore=p.boot_restore==='1' || p.boot_restore===true;
   out.publication_policy=policy;
  }
  out.services=[];
  map.data.sections(map.config,'services').forEach(function(row){
   var svc=JSON.parse(JSON.stringify(row));
   /* GridSection 新行无既有 service_id：用行 ID（.name）补齐，canonical 校验依赖 service_id */
   if(!svc.service_id && svc['.name'])svc.service_id=svc['.name'];
   delete svc['.type'];delete svc['.name'];delete svc['.index'];delete svc['.anonymous'];
   if(svc.enabled==='0'||svc.enabled===false)svc.enabled=false;else if(svc.enabled!=null)svc.enabled=svc.enabled==='1'||svc.enabled===true;
   if(!svc.authentication_review)svc.authentication_review={authentication:'unconfirmed',management:false};
   if(svc.management!=null){svc.authentication_review.management=svc.management==='1'||svc.management===true;delete svc.management;}
   if(!svc.certificate_mode)svc.certificate_mode=svc.certificate_ref?'override':'inherit';
   if(svc.certificate_mode==='inherit')delete svc.certificate_ref;
   if(svc.backend_url!=null)delete svc.backend_url;
   out.services.push(svc);
  });
  return out;
 },
 actionBar:function(node,state,opts){
  opts=opts || {};
  var api=this,s=state || {},bar=E('div',{class:'hp-actions'});
  /* node 是外层容器（含 .cbi-map）；actionBar/message 挂在 map 外，
     避免任何 map 重渲染（modal Save / renderContents dom.content 清空）洗掉操作条 */
  var mapHolder=E('div',{});
  var message=E('p',{id:'hp-message','aria-live':'polite'});
  function refreshButtons(st,dirty){
   var r=(st || s).runtime || {},pending=!!((st || s).pending_config && (st || s).pending_config.apply_required);
   var running=api.running(st || s);
   var canStart=!!(st || s).saved_revision && !running && r.cleanup!=='unknown' && !dirty;
   var canApply=pending && running && !dirty;
   start.disabled=!canStart;apply.disabled=!canApply;stop.disabled=!running;
   /* 仅更新按钮使能；文案交给调用方（Save 成功/失败各有专属消息，不能被此处覆盖） */
  }
  var start=E('button',{id:'hp-start',type:'button',class:'cbi-button',click:function(){
   return api.actionDialog(node,s,'start',function(st){s=st;refreshButtons(st);},function(e){message.textContent='操作失败 / 状态未知：'+e.message;refreshButtons(s);});
  }},_('开启已保存配置'));
  var apply=E('button',{id:'hp-apply',type:'button',class:'cbi-button',click:function(){
   return api.actionDialog(node,s,'apply',function(st){s=st;refreshButtons(st);},function(e){message.textContent='操作失败 / 状态未知：'+e.message;refreshButtons(s);});
  }},_('应用已保存变更'));
  var stop=E('button',{id:'hp-stop',type:'button',class:'cbi-button',click:function(){
   return api.actionDialog(node,s,'stop',function(st){s=st;refreshButtons(st);},function(e){message.textContent='操作失败 / 状态未知：'+e.message;refreshButtons(s);});
  }},_('停止全部'));
  var save=E('button',{id:'hp-save',type:'button',class:'cbi-button cbi-button-save important',click:function(){
   var mapNode=node.querySelector('.cbi-map'),map=mapNode?dom.findClassInstance(mapNode):null;
   if(!map)return Promise.resolve();
   var dirty=true;
   return Promise.resolve().then(function(){
    var candidate=api.collectConfig(map);
    return api.validate(candidate);
   }).then(function(v){
    if(!v.valid)throw new Error(v.error);
    return api.save(map.snapshotRevision!=null?map.snapshotRevision:s.saved_revision,v.config);
   }).then(api.checked).then(function(st){
    dirty=false;s=st;
    return map.render().then(function(){refreshButtons(st);message.textContent='已保存 revision '+st.saved_revision+'，不启动 / 未应用';return api.status().then(api.checked).then(function(latest){s=latest;refreshButtons(latest);});});
   }).catch(function(e){
    message.textContent='保存失败：'+e.message;refreshButtons(s,dirty);
   });
  }},_('保存配置（不启动）'));
  bar.append(save,start,apply,stop);
  var wrap=E('div',{},[bar,message]);
  /* node 为外层容器：先把 map 包进 mapHolder 与 actionBar 分离，
     再把 mapHolder+wrap 一起放回 node，这样任何 map 重渲染都不会洗掉操作条 */
  var mapNode=node.querySelector('.cbi-map');
  if(mapNode){mapHolder.append(mapNode);node.append(mapHolder);}
    node.append(wrap);
    refreshButtons(s,false);
    /* 初始文案：与 refreshButtons 拆分后由此处统一给出 */
    message.textContent=s.pending_config && s.pending_config.apply_required?'已保存待应用；保存不启动':'已保存；保存不启动';
    return node;
 }
});
