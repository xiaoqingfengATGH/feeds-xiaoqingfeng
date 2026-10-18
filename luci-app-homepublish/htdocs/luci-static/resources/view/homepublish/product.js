/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require baseclass';
'require rpc';
'require dom';
'require ui';
var status=rpc.declare({object:'homepublish',method:'status',expect:{},reject:true,nobatch:true});
var validate=rpc.declare({object:'homepublish',method:'validate',params:['config'],expect:{},reject:true,nobatch:true});
var save=rpc.declare({object:'homepublish',method:'save',params:['expected_revision','config'],expect:{},reject:true,nobatch:true});
var stop=rpc.declare({object:'homepublish',method:'stop',expect:{},reject:true,nobatch:true});
return baseclass.extend({
 status:status,validate:validate,save:save,stop:stop,
 ddnsProfiles:rpc.declare({object:'homepublish',method:'ddns_profiles',expect:{},reject:true,nobatch:true}),
 certificates:rpc.declare({object:'homepublish',method:'certificates',expect:{},reject:true,nobatch:true}),
 start:rpc.declare({object:'homepublish',method:'start',params:['revision','approved'],expect:{},reject:true,nobatch:true}),
 apply:rpc.declare({object:'homepublish',method:'apply',params:['revision','approved'],expect:{},reject:true,nobatch:true}),
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
 serviceType:function(type){return ({http_proxy:'HTTP 反向代理',https_proxy:'HTTPS 反向代理',tls_passthrough:'TLS 透传',ssh:'原生 SSH',ssh_shared:'原生 SSH',tcp_forward:'独立 TCP'})[type] || type || '未知';},
 actionGates:function(s,opts){
  s=s || {};opts=opts || {};var r=s.runtime || {},d=s.desired_state || {},caps=s.capabilities || {},pending=!!(s.pending_config && s.pending_config.apply_required),running=this.running(s),clean=r.cleanup==='confirmed',stable=r.phase==='stopped' || r.phase==='failed' || r.phase==='blocked';
  function gate(reason){return {allowed:!reason,reason:reason || '操作前请确认服务范围'};}
  var common=opts.busy?'操作处理中':opts.unknown?'状态未知，请先刷新':opts.dirty?'存在未保存修改，请先保存或重置':!s.saved_revision || !s.saved_config?'请先保存配置':'';
  var cleanupReason=!clean?'清理未确认，先停止并重试':'';
  return {start:gate(common || cleanupReason || (caps.start!==true?'当前通道不支持启动':!stable?'当前阶段不能启动':'')),apply:gate(common || (!running?cleanupReason:'') || (caps.apply!==true?'当前通道不支持应用':!running || d.manual_stop_latch?'当前没有可替换的运行组':!pending?'无待应用变更':'')),stop:gate(opts.busy?'操作处理中':caps.stop!==true?'当前通道不支持停止':opts.unknown || r.phase!=='stopped' || !clean || !!s.active_config || d.state==='enabled'?'':'已停止且清理完成')};
 },
 actionDialog:function(root,s,kind,updated,failed,submitting){
  var api=this,busy=false,ddns=null,config=(kind==='stop'?s.active_config:s.saved_config) || {},r=s.runtime || {};
  function button(id,text,fn){return E('button',{id:id,type:'button',class:id==='hp-edit-submit'?'btn btn-primary cbi-button cbi-button-apply':'btn btn-secondary cbi-button cbi-button-neutral',click:fn},text);}
  var diff=kind==='stop'?['停止当前整组服务，关闭已有连接并撤销发布意图']:api.diff(s.active_config,s.saved_config),alert=E('p',{role:'alert'});
  var scope=E('div',{id:'hp-confirm-scope'},[
   E('p',{},kind==='stop'?'关闭 HomePublish 并停止全部服务，保留服务配置。':'按已保存配置运行全部已启用服务；应用更改时服务会短暂中断。'),
   E('ul',{},((config.access_profile || {}).listeners || []).map(function(l){return E('li',{},'监听 '+api.endpoint(l.address,l.port || l.internal_port)+' · '+l.family+' · 网络 '+(l.network || l.interface || '未知'));})),
   E('ul',{},(config.services || []).filter(function(v){return v.enabled!==false;}).map(function(v){return E('li',{},(v.name || v.service_id)+' · '+api.serviceType(v.type)+' · '+(v.hostname || (v.type==='tcp_forward'?'独立端口 '+v.listen_port:'共享入口'))+' → '+api.endpoint((v.backend || {}).host,(v.backend || {}).port)+'；证书：'+(v.type==='https_proxy'?(v.certificate_mode==='inherit'?'继承 '+(config.default_certificate_ref || '未选择'):v.certificate_ref || '未选择'):v.type==='tls_passthrough'?'后端提供':'不需要'));})),
   E('p',{},(config.publication_policy || {}).mode==='temporary'?'运行方式：限定时长 '+((config.publication_policy || {}).temporary_duration || 0)/60+' 分钟'+(kind==='apply' && r.expires_at?'（保持原停止时间）':'（启动后开始计时，到时自动停止）'):'运行方式：持续运行，直到手动关闭')
  ]);
  var submit=button('hp-edit-submit','确认',function(){
   if(busy)return;busy=true;submit.disabled=true;submit.textContent='正在处理…';alert.textContent='正在提交，请稍候…';if(submitting)submitting(true);
   return Promise.resolve().then(function(){return api.status();}).then(api.checked).then(function(current){
    if(current.saved_revision!==s.saved_revision || current.active_revision!==s.active_revision || (current.runtime || {}).generation!==r.generation)throw new Error('配置或运行状态已变化，请刷新后重新确认');
    if(!api.actionGates(current)[kind].allowed)throw new Error('当前状态不允许此操作，请刷新');
    return kind==='stop'?api.stop():api[kind](s.saved_revision,true);
   }).then(api.checked).then(function(result){ddns=result.ddns;return api.status();}).then(api.checked).then(function(st){updated(st);ui.hideModal();var outcome=api.dnsOutcome({action:kind,ddns:ddns});if(outcome)ui.addNotification(null,E('p',{},outcome));}).catch(function(e){alert.textContent=api.errorText(e)+'；请刷新并重新确认';failed(e);}).finally(function(){busy=false;submit.disabled=false;submit.textContent='确认';if(submitting)submitting(false);});
  });
  return ui.showModal(kind==='stop'?'确认停止服务':kind==='apply'?'确认应用配置':'确认启动配置',[scope,kind==='apply' && diff.length?E('details',{},[E('summary',{},'变更明细'),E('ul',{id:'hp-confirm-diff'},diff.map(function(x){return E('li',{},x);}))]):E([]),alert,E('div',{class:'right',style:'display:flex;justify-content:flex-end;gap:0.75rem'},[button('hp-edit-cancel','取消',function(){if(!busy)ui.hideModal();}),submit])]);
 },
 diff:function(before,after){
  before=before || {};after=after || {};var out=[];
  function changed(label,a,b){if(JSON.stringify(a)!==JSON.stringify(b))out.push(label+'：'+(a==null?'无':JSON.stringify(a))+' → '+(b==null?'无':JSON.stringify(b)));}
  function endpointBackend(b){var value=JSON.parse(JSON.stringify(b || {}));delete value.host_header;return value;}
  function cert(c,v){if(v.type!=='https_proxy')return v.type==='tls_passthrough'?'后端提供':'不需要';return {mode:v.certificate_mode || 'override',binding:v.certificate_mode==='inherit'?'继承入口默认':'独立指定',resolved:v.certificate_mode==='inherit'?c.default_certificate_ref:v.certificate_ref};}
  changed('入口默认证书',before.default_certificate_ref,after.default_certificate_ref);
  var old=before.services || [],next=after.services || [];
  var api=this;function identity(v){return api.serviceType(v.type)+' · '+(v.name || v.hostname || v.service_id || '未命名');}
  old.forEach(function(v){var n=next.find(function(x){return x.service_id===v.service_id;});if(!n){out.push('删除 '+identity(v)+'（应用关闭其连接，并替换整组）');return;}
   var prefix=identity(v)+' / ';changed(prefix+'DNS 选择',api.dnsSummary(v.dns),api.dnsSummary(n.dns));if(v.dns && n.dns && v.dns.mode==='ddns_go' && n.dns.mode==='ddns_go' && v.dns.profile_id!==n.dns.profile_id)out.push(prefix+'DNS 选择：更换域名服务商账号');changed(prefix+'名称',v.name,n.name);changed(prefix+'接入方式',api.serviceType(v.type),api.serviceType(n.type));changed(prefix+'独立监听端口',v.listen_port,n.listen_port);changed(prefix+'域名',v.hostname,n.hostname);changed(prefix+'后端 / 家庭网段',endpointBackend(v.backend),endpointBackend(n.backend));changed(prefix+'回源 Host',(v.backend || {}).host_header || '',(n.backend || {}).host_header || '');changed(prefix+'后端协议',v.upstream_scheme,n.upstream_scheme);changed(prefix+'后端 HTTPS 校验',v.upstream_tls,n.upstream_tls);changed(prefix+'证书绑定 / 解析证书',cert(before,v),cert(after,n));changed(prefix+'参与发布',v.enabled!==false,n.enabled!==false);changed(prefix+'业务鉴权 / 管理服务',v.authentication_review,n.authentication_review);
  });next.forEach(function(v){if(!old.some(function(x){return x.service_id===v.service_id;}))out.push('新增 '+identity(v)+'：'+(v.hostname || (v.type==='tcp_forward'?'独立端口 '+v.listen_port:'共享入口'))+' → '+api.endpoint((v.backend || {}).host,(v.backend || {}).port)+'；DNS 选择：'+api.dnsSummary(v.dns));});
  changed('监听 / 接入方式',before.access_profile,after.access_profile);changed('运行方式 / 开机恢复',before.publication_policy,after.publication_policy);return out;
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
 networkInventory:rpc.declare({object:'homepublish',method:'network_inventory',expect:{},reject:true,nobatch:true}),
 migrationPreview:rpc.declare({object:'homepublish',method:'migration_preview',params:['expected_revision'],expect:{},reject:true,nobatch:true}),
 clone:function(v){return JSON.parse(JSON.stringify(v));},
 errorText:function(e){
  var labels={REVISION_CONFLICT:'配置已被其他页面修改，请重新载入后编辑',DOMAIN_CONFLICT:'域名重复',SSH_CONFLICT:'共享入口只能配置一个 SSH 服务',PORT_CONFLICT:'监听端口冲突',ADDRESS_UNAVAILABLE:'所选地址已不可用',NETWORK_UNAVAILABLE:'网络不可用',ZONE_AMBIGUOUS:'网络区域关联不明确',STATE_UNKNOWN:'状态未知，请重试',DEPENDENCY_UNAVAILABLE:'设备缺少所需能力',INVALID_CONFIG:'配置不完整或无效'};
  e=e || {};
  var reason=String(e.error || e.message || ''),label=labels[e.error_code];
  if(/certificate expired or DNS SAN mismatch/.test(reason))label='所选证书已过期或不覆盖服务域名，请检查有效期并选择覆盖该域名的证书（或继承入口默认证书）';
  return (label || (reason && reason!=='状态读取失败或操作被拒绝'?reason:'操作失败'))+(e.field?'（'+e.field+'）':'');
 },
 checked:function(s){if(!s || s.error){var e=new Error('状态读取失败或操作被拒绝');Object.assign(e,s || {});throw e;}return s;},
 dnsSummary:function(d){return d && d.mode==='ddns_go'?'本机 ddns-go 自动维护（'+(d.record_types || []).join('、')+'）':'自行维护';},
 dnsOutcome:function(result){
  if(!result || result.action==='save' || !result.ddns)return '';
  var reasons={family_disabled:'请先在 ddns-go 中启用所选地址类型',stale_profile:'域名账号已变化，请重新选择',ambiguous_profile_name:'请在 ddns-go 中为账号设置不同名称',unavailable:'请先在 ddns-go 中配置域名服务商并启用服务',save_failed:'域名设置未能保存，请检查 ddns-go 后重试'};
  var warnings=result.ddns.warnings || [];reasons['所选账户未启用需要的地址类型，请检查 ddns-go 设置。']=reasons.family_disabled;reasons['域名更新账户已变更，请重新选择后保存。']=reasons.stale_profile;reasons['存在同名域名更新账户，请先在 ddns-go 中修改名称。']=reasons.ambiguous_profile_name;reasons['域名更新设置未能保存，请检查 ddns-go 后重试。']=reasons.save_failed;
  if(warnings.length)return '服务已应用，部分域名未能设置自动更新：'+warnings.map(function(w){return (w.hostname || '所选域名')+'（'+(reasons[w.error_code || w.error] || '请检查 ddns-go 的账号、域名权限和服务状态后重试')+'）';}).join('；');
  return (result.ddns.results || []).length?'服务已应用，域名已加入自动更新列表。':'';
 },
 dnsEligible:function(type){return ['http_proxy','https_proxy','tls_passthrough'].indexOf(type)>=0;},
 dnsParts:function(hostname){var value=String(hostname || ''),dot=value.indexOf('.');return {label:dot>0?value.slice(0,dot):'',suffix:dot>0?value.slice(dot+1):''};},
 dnsCandidates:function(domains){
  var candidates=[];
  (domains || []).forEach(function(source){
   if(typeof source!=='string')return;
   var domain=source.toLowerCase().replace(/\.$/,''),labels=domain.split('.');
   if(domain.length>253 || labels.length<2 || (labels[0]==='*' && labels.length<3) || !labels.every(function(label,i){return (i===0 && label==='*') || /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label);}))return;
   var suggested=labels.length>=3,suffix=suggested?labels.slice(1).join('.'):domain;
   var found=candidates.find(function(c){return c.suffix===suffix;});
   if(found){if(found.sources.indexOf(source)<0)found.sources.push(source);}else candidates.push({suffix:suffix,sources:[source],suggested:suggested});
  });return candidates;
 },
 dnsInventory:function(result){var api=this;return {available:!!(result && result.available),profiles:result && result.available && Array.isArray(result.profiles)?result.profiles.map(function(p){return {id:p.profile_id,name:p.name,provider:p.provider,ipv4_enabled:!!(p.a && p.a.enabled),ipv6_enabled:!!(p.aaaa && p.aaaa.enabled),candidates:api.dnsCandidates([].concat((p.a || {}).domains || [],(p.aaaa || {}).domains || []))};}):[]};},
 serviceRows:function(saved,inventory){return (saved.services || []).map(function(s){var r=JSON.parse(JSON.stringify(s)),b=s.backend || {};r.backend_host=b.host;r.backend_port=String(b.port || '');r.backend_host_header=b.host_header || '';r.tls_verify=(s.upstream_tls || {}).verify===false?'0':'1';r.tls_server_name=(s.upstream_tls || {}).server_name || '';r.enabled=s.enabled?'1':'0';var d=s.dns || {mode:'manual'},profiles=(inventory || {}).profiles || [],profile=profiles.find(function(p){return p.id===d.profile_id;}) || (profiles.length===1?profiles[0]:null);r.dns_mode=d.mode;r.dns_profile=d.profile_id || (profile?profile.id:'');var types=d.record_types || (profile?(profile.ipv4_enabled?['A']:profile.ipv6_enabled?['AAAA']:[]):[]);r.dns_a=types.indexOf('A')>=0?'1':'0';r.dns_aaaa=types.indexOf('AAAA')>=0?'1':'0';return r;});},
 zoneList:function(value){if(Array.isArray(value))return value.slice();if(typeof value==='string')return value.trim()?value.trim().split(/\s+/):[];return [];},
 firewallRules:function(config){
  var profile=config.access_profile || {},fw=profile.firewall || {},rules=[],seen={},zoneList=this.zoneList;
  (profile.listeners || []).forEach(function(l){
   (config.services || []).filter(function(s){return s.enabled!==false;}).forEach(function(s){
    var port=s.type==='tcp_forward'?Number(s.listen_port):['http_proxy','https_proxy','tls_passthrough','ssh','ssh_shared'].indexOf(s.type)>=0?Number(l.port):0;
    if(!Number.isInteger(port) || port<1 || port>65535)return;
    var destIp=l.bind_mode==='auto'?undefined:l.address;
    zoneList(fw[l.family+'_zones']).forEach(function(zone){
     var key=JSON.stringify([l.family,zone,port,destIp]),rule=seen[key];
     if(!rule){rule={family:l.family,zone:zone,protocol:'tcp',dest_port:port,services:[]};if(destIp!=null)rule.dest_ip=destIp;seen[key]=rule;rules.push(rule);}
     if(rule.services.indexOf(s.service_id)<0)rule.services.push(s.service_id);
    });
   });
  });return rules;
 },
 entryZoneDefaults:function(row,saved,zones,networks){
  var profile=saved.access_profile || {},fw=profile.firewall || {},listeners=profile.listeners || [],zoneList=this.zoneList;
  var preferred=(networks || []).some(function(n){return typeof n.network==='string' && n.network.indexOf('wan')===0 && zoneList(n.zones).indexOf('wan')>=0;})?'wan':'lan';
  ['ipv4','ipv6'].forEach(function(f){
   if(row.family!==f && row.family!=='dual')return;
   var key=f+'_zones',previouslyEnabled=listeners.some(function(l){return l.family===f;});
   if(!zoneList(row[key]).length && (!Object.prototype.hasOwnProperty.call(fw,key) || !previouslyEnabled))row[key]=zones.indexOf(preferred)>=0?[preferred]:[];
  });
  return row;
 },
 entryDraft:function(saved){
  var listeners=(saved.access_profile || {}).listeners || [],first=listeners[0],fw=(saved.access_profile || {}).firewall || {},zoneList=this.zoneList;
  var row={family:listeners.length===2?'dual':first?first.family:'ipv4',bind_mode:!listeners.length || listeners.every(function(l){return l.bind_mode==='auto';})?'auto':'address',port:String(first?first.port:8443)};
  ['ipv4','ipv6'].forEach(function(f){var l=listeners.find(function(x){return x.family===f;});row[f+'_network']=l?l.network:'';row[f+'_address']=l?l.address:'';row[f+'_zones']=zoneList(fw[f+'_zones']);});return row;
 },
 collectConfig:function(map){
  var data=map.data.data,out=this.clone(map.snapshot),p=data.cfg_policy,l=data.cfg_listener;
  if(out.schema_version!==2)throw new Error('请先预览并确认旧配置迁移');
  if(l){
   var old=out.access_profile.listeners;
   var auto=l.bind_mode==='auto';
   out.access_profile={listeners:['ipv4','ipv6'].filter(function(f){return l.family==='dual' || l.family===f;}).map(function(f){
    var existing=old.find(function(x){return x.family===f;});
    return {listener_id:existing?existing.listener_id:'shared_'+f,family:f,bind_mode:auto?'auto':'address',network:auto?'':l[f+'_network'],address:auto?(f==='ipv4'?'0.0.0.0':'::'):l[f+'_address'],port:Number(l.port)};
   }),firewall:{ipv4_zones:l.family==='ipv6'?[]:this.zoneList(l.ipv4_zones),ipv6_zones:l.family==='ipv4'?[]:this.zoneList(l.ipv6_zones)}};
  }
  if(p){
   if(p.default_certificate_ref)out.default_certificate_ref=p.default_certificate_ref;else delete out.default_certificate_ref;
   out.publication_policy={mode:p.mode,boot_restore:p.mode==='temporary'?false:(p.boot_restore==='1' || p.boot_restore===true)};
   if(p.mode==='temporary')out.publication_policy.temporary_duration=Number(p.temporary_minutes)*60;
  }
  var api=this;
  if(map.editor==='services'){
   out.services=[];
   var rows=map.data.sections(map.config,'services'),used={};
   (out.services.concat(map.snapshot.services || [],rows)).forEach(function(row){if(row.service_id)used[row.service_id]=true;});
   rows.forEach(function(row){
    if(!row.service_id){var n=1;while(used['svc_'+n])n++;row.service_id='svc_'+n;used[row.service_id]=true;}
    var host=String(row.backend_host || ''),previous=row.backend || {};
    var backend={host:host,addressFamily:host.indexOf(':')>=0?'ipv6':/^\d+\.\d+\.\d+\.\d+$/.test(host)?'ipv4':'hostname',port:Number(row.backend_port)};
    if(previous.backup)backend.backup=JSON.parse(JSON.stringify(previous.backup));
    var svc={service_id:row.service_id,name:row.name,enabled:row.enabled==='1' || row.enabled===true,type:row.type,backend:backend};
    if(row.type==='http_proxy' || row.type==='https_proxy' || row.type==='tls_passthrough')svc.hostname=row.hostname;
    if(row.type==='http_proxy' || row.type==='https_proxy'){
     svc.upstream_scheme=row.upstream_scheme || 'http';
     if(row.backend_host_header)backend.host_header=row.backend_host_header;
     if(row.type==='https_proxy'){
      svc.certificate_mode=row.certificate_mode || 'inherit';
      if(svc.certificate_mode==='override' && row.certificate_ref)svc.certificate_ref=row.certificate_ref;
     }
     if(svc.upstream_scheme==='https'){
      svc.upstream_tls={verify:row.tls_verify!=='0' && row.tls_verify!==false};
      if(row.tls_server_name)svc.upstream_tls.server_name=row.tls_server_name;
     }
    }
    svc.dns=api.dnsEligible(row.type) && row.dns_mode==='ddns_go'?{mode:'ddns_go',profile_id:row.dns_profile,record_types:['A','AAAA'].filter(function(t){return row[t==='A'?'dns_a':'dns_aaaa']==='1';})}:{mode:'manual'};
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
 enabled:function(s){return !!(s && s.desired_state && s.desired_state.state==='enabled');},
 /* Save is durable independently of lifecycle. Never retry a conflicting write. */
 saveAndApply:function(revision,config,saveOnly){
  var api=this,saved=false,action=null,savedRevision=null,savedConfig=null,ddns=null;
  return api.validate(config).then(function(v){api.checked(v);if(!v.valid)throw new Error('配置验证失败');savedConfig=api.clone(v.config);return api.save(revision,v.config);}).then(function(receipt){
   api.checked(receipt);saved=true;savedRevision=receipt.saved_revision;
   return api.status().then(api.checked).then(function(current){
    if(current.saved_revision!==receipt.saved_revision){var e=new Error('保存后配置已被其他页面修改');e.error_code='REVISION_CONFLICT';throw e;}
    if(saveOnly || !api.enabled(current))return {state:current,action:'save'};
    action=api.running(current)?'apply':'start';
    function lifecycleChecked(s){api.checked(s);var r=s.runtime;if(r && (r.phase!=='running' || r.active_verified!==true)){var e=new Error('服务未成功运行');e.error=r.last_error || r.reason || '服务未成功运行，请检查运行状态';e.stage=r.stage;throw e;}return s;}
    return api[action](current.saved_revision,true).then(lifecycleChecked).then(function(result){ddns=result.ddns;return api.status();}).then(lifecycleChecked).then(function(state){return {state:state,action:action,ddns:ddns};});
   });
  }).catch(function(e){
   e.configurationSaved=saved;e.lifecycleAction=action;e.savedRevision=savedRevision;e.savedConfig=savedConfig;
   if(!saved)throw e;
   // A rejected lifecycle RPC must not suppress the final read or the original error.
   return api.status().then(api.checked).then(function(s){e.latestState=s;},function(){}).then(function(){throw e;});
  });
 },
 actionBar:function(node,state,opts){
  var api=this,map=opts.map,busy=false,dirty=false,blocked=false,message=E('p',{id:'hp-message',role:'status','aria-live':'polite'}),holder=E('div',{},[node]),bar=E('div',{class:'cbi-page-actions'});
  var initialDraft=JSON.stringify(api.collectConfig(map)),failure=null;
  function comparable(v){if(Array.isArray(v))return v.map(comparable);if(v && typeof v==='object'){var o={};Object.keys(v).sort().forEach(function(k){o[k]=comparable(v[k]);});return o;}return v;}
  var recover=E('button',{id:'hp-recover',type:'button',class:'cbi-button cbi-button-action',hidden:true,click:function(){
   if(busy || !failure)return;busy=true;recover.disabled=true;reset.disabled=true;
   message.textContent='正在核对已保存配置，保留当前编辑…';
   return api.status().then(api.checked).then(function(current){
    if(current.saved_revision!==failure.savedRevision || JSON.stringify(comparable(current.saved_config))!==JSON.stringify(comparable(failure.savedConfig))){var conflict=new Error('配置已被其他页面修改，当前草稿仍保留；请先核对后重新载入');conflict.error_code='REVISION_CONFLICT';throw conflict;}
    map.snapshot=api.clone(current.saved_config);map.snapshotRevision=current.saved_revision;state=current;blocked=false;recover.hidden=true;
    message.textContent='配置仍已保存；当前编辑已保留，可修改后仅保存或再次保存并应用。';
   }).catch(function(e){message.textContent=api.errorText(e)+'；当前草稿已保留，未重试应用。';}).finally(function(){busy=false;recover.disabled=false;reset.disabled=false;saveButton.disabled=applyButton.disabled=blocked;});
  }},'核对已保存配置并继续编辑');
  function leave(e){var changed=dirty;try{changed=changed || JSON.stringify(api.collectConfig(map))!==initialDraft;}catch(err){changed=true;}if(changed){e.preventDefault();e.returnValue='';}}
  window.addEventListener('beforeunload',leave);
  holder.addEventListener('change',function(){dirty=true;});holder.addEventListener('input',function(){dirty=true;});
  function persist(saveOnly){
   if(busy || blocked)return;busy=true;saveButton.disabled=applyButton.disabled=reset.disabled=true;
   // Keep feedback outside the Map: map.save() renders its contents again.
   var button=saveOnly?saveButton:applyButton,label=button.textContent;
   var progress=saveOnly || !api.enabled(state)?'正在保存…':'正在保存并应用…';
   button.classList.add('spinning');button.textContent=progress;
   holder.setAttribute('aria-busy','true');message.textContent=progress;
   return Promise.resolve().then(function(){return map.save();}).then(function(){return api.saveAndApply(map.snapshotRevision,api.collectConfig(map),saveOnly);}).then(function(result){dirty=false;window.removeEventListener('beforeunload',leave);var outcome=api.dnsOutcome(result);if(outcome){map.snapshot=api.clone(result.state.saved_config);map.snapshotRevision=result.state.saved_revision;state=result.state;initialDraft=JSON.stringify(api.collectConfig(map));message.textContent=outcome;}else location.reload();}).catch(function(e){
    message.textContent=(e.configurationSaved?'配置已保存；'+(e.lifecycleAction==='start'?'启动失败':e.lifecycleAction==='apply'?'应用失败':'状态核验失败')+'：':'保存失败：')+api.errorText(e);
    if(e.configurationSaved || e.error_code==='REVISION_CONFLICT'){blocked=true;failure=e;recover.hidden=!e.configurationSaved;message.append(e.configurationSaved?'；草稿保留，请核对已保存配置后继续编辑。':'；草稿保留，请重新载入后检查。');}
    if(e.field){var path=e.field.replace(/services\[(\d+)\]/,'services');holder.querySelectorAll('[data-field]').forEach(function(n){if(n.dataset.field.endsWith('.'+path.split('.').pop())){n.setAttribute('aria-invalid','true');n.title=api.errorText(e);}});}
   }).finally(function(){busy=false;button.classList.remove('spinning');button.textContent=label;holder.removeAttribute('aria-busy');reset.disabled=false;saveButton.disabled=applyButton.disabled=blocked;});
  }
  var applyButton=E('button',{id:'hp-save-apply',type:'button',class:'cbi-button cbi-button-apply important',click:function(){return persist(false);}},'保存并应用');
  var saveButton=E('button',{id:'hp-save',type:'button',class:'cbi-button cbi-button-save',click:function(){return persist(true);}},'仅保存');
  var reset=E('button',{id:'hp-reset',type:'button',class:'cbi-button cbi-button-reset',click:function(){ui.showModal('重新载入已保存配置',[E('p',{},'放弃当前页面草稿？'),E('div',{class:'right'},[E('button',{class:'cbi-button',click:ui.hideModal},'取消'),E('button',{class:'cbi-button cbi-button-reset',click:function(){dirty=false;window.removeEventListener('beforeunload',leave);location.reload();}},'重新载入')])]);}},'重置');
  var help=E('details',{class:'cbi-value-description',style:'text-align:left;margin-top:0.75em'},[E('summary',{style:'cursor:pointer'},'保存与应用说明'),E('p',{},'总开关启用时使配置生效，停用时只保存；应用会短暂中断连接，不延长限定时长的截止时间。')]);
  bar.append(applyButton,saveButton,recover,reset);holder.append(message,bar,help);return holder;
 }
});
