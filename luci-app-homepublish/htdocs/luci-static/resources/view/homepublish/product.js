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
 reason:'Production Start / Apply unsupported: activation_ready=false. Internal host-test controller is not a client-selectable provider.',
 defaults:function(){return {schema_version:1,services:[{service_id:'nas',name:'NAS',hostname:'nas.example.test',backend:{addressFamily:'ipv4',host:'192.168.1.10',port:8080,allowed_ranges:['192.168.1.0/24']},certificate_ref:'acme:nas',authentication_review:{authentication:'unconfirmed',management:false}}],access_profile:{methods_allowed:['manual_ipv4'],listeners:[{family:'ipv4',address:'192.168.1.2',interface:'wan',zone:'wan',protocol:'tcp',internal_port:8443,external_port:18443}]},publication_policy:{mode:'continuous',boot_restore:false}};}
});
