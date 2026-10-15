/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require form';
'require view';
'require view.homepublish.product as api';
return view.extend({
 handleSave:null,handleSaveApply:null,handleReset:null,
 load:function(){return api.loadEditor(false);},
 render:function(data){
  var state=data[0];if(state.error)return api.editorUnavailable(state);
  if(!state.saved_config)return api.editorUnavailable({error:'请先在发布入口设置保存监听设置'});
  if(state.saved_config.schema_version===1)return api.migrationPanel(state);
  var saved=state.saved_config,inventory=api.sortInventory(data[1].certificates || [],saved);
  var m=new form.JSONMap({services:api.serviceRows(saved)},'HomePublish — 发布服务','参与下次发布仅修改配置；页面保存不会启动服务。更改类型时，不适用字段不会写入配置。');
  m.snapshot=api.clone(saved);m.snapshotRevision=state.saved_revision;m.editor='services';
  var s=m.section(form.GridSection,'services','服务规则'),o;
  s.addremove=true;s.anonymous=true;s.sortable=false;s.nodescriptions=true;s.modalizable=true;
  s.tab('general','基本设置');s.tab('access','接入设置');s.tab('backend','后端设置');s.tab('advanced','高级设置');
  s.modaltitle=function(sid){var r=this.map.data.get(this.map.config,sid);return r && r.name || '新服务';};
  function field(tab,cls,key,label,modal){var v=s.taboption(tab,cls,key,label);if(modal!==undefined)v.modalonly=modal;v.rmempty=cls===form.DummyValue;return v;}
  o=field('general',form.Flag,'enabled','参与发布');o.default='1';o.editable=true;
  o=field('general',form.Value,'name','名称');
  o=field('general',form.ListValue,'type','发布方式');o.value('https_proxy','HTTPS 反向代理');o.value('tls_passthrough','TLS 透传');o.value('ssh','原生 SSH 共入口');o.value('tcp_forward','独立端口 TCP 转发');o.default='https_proxy';
  o=field('access',form.DummyValue,'match_summary','域名 / 独立端口');o.textvalue=function(sid){var r=this.map.data.get(this.map.config,sid);return r.type==='tcp_forward'?String(r.listen_port || '待填写'):r.hostname || '继承共享入口';};
  o=field('access',form.Value,'hostname','域名（精确匹配）',true);o.datatype='hostname';o.depends('type','https_proxy');o.depends('type','tls_passthrough');o.retain=true;
  o=field('access',form.Value,'listen_port','独立 TCP 监听端口',true);o.datatype='range(1024,65535)';o.depends('type','tcp_forward');o.retain=true;
  o=field('access',form.ListValue,'certificate_mode','HTTPS 证书模式',true);o.value('inherit','继承入口默认证书');o.value('override','独立指定');o.default='inherit';o.depends('type','https_proxy');o.retain=true;
  o=field('access',form.ListValue,'certificate_ref','独立证书',true);o.value('','未选择');o.rmempty=true;o.depends({type:'https_proxy',certificate_mode:'override'});o.retain=true;
  inventory.forEach(function(c){o.value(c.certificate_ref,c.domain+' · '+String(c.key_type).toUpperCase());});
  (saved.services || []).forEach(function(svc){if(svc.certificate_ref && !inventory.some(function(c){return c.certificate_ref===svc.certificate_ref;}))o.value(svc.certificate_ref,svc.certificate_ref+'（不可用）');});
  o=field('access',form.DummyValue,'certificate_summary','证书');o.textvalue=function(sid){var r=this.map.data.get(this.map.config,sid);return r.type==='https_proxy'?(r.certificate_mode==='override'?r.certificate_ref || '未选择':'继承入口默认'):r.type==='tls_passthrough'?'由后端提供':'不需要';};
  o=field('backend',form.DummyValue,'backend_summary','后端');o.textvalue=function(sid){var r=this.map.data.get(this.map.config,sid),h=r.backend_host || '';return (h.includes(':')?'['+h+']':h)+':'+(r.backend_port || '');};
  o=field('backend',form.Value,'backend_host','后端地址',true);o.datatype='host';o.description='填写主机名或裸 IP 地址，不含协议、路径及端口。';
  o=field('backend',form.Value,'backend_port','后端端口',true);o.datatype='port';
  o=field('backend',form.ListValue,'upstream_scheme','后端协议',true);o.value('http','HTTP');o.value('https','HTTPS（系统 CA 验证）');o.default='http';o.depends('type','https_proxy');o.retain=true;
  o=field('backend',form.Value,'tls_server_name','后端 HTTPS 校验域名',true);o.datatype='hostname';o.depends({type:'https_proxy',upstream_scheme:'https'});o.description='始终验证证书，使用系统 CA；即使后端是 IP 也需填写校验域名。';o.retain=true;
  o=field('advanced',form.DynamicList,'allowed_ranges','允许连接的后端网段',true);o.datatype='cidr';o.description='限制本应用可以连接的后端地址范围，不是允许访问服务的客户端来源网段。';
  o=field('advanced',form.ListValue,'authentication','业务鉴权确认',true);o.value('unconfirmed','尚未确认');o.value('confirmed','已确认后端业务鉴权');o.default='unconfirmed';
  o=field('advanced',form.Flag,'management','管理服务',true);o.default='0';
  return m.render().then(function(node){
   node.querySelectorAll('table.cbi-section-table').forEach(function(table){
    var viewport=E('div',{style:'max-width:100%;overflow-x:auto',tabindex:0,'aria-label':'服务列表，可横向滚动'});
    table.parentNode.insertBefore(viewport,table);viewport.appendChild(table);
   });
   return api.actionBar(node,state,{map:m});
  });
 }
});
