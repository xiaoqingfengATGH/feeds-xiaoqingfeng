/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require form';
'require view';
'require validation';
'require dom';
'require ui';
'require view.homepublish.product as api';
return view.extend({
 handleSave:null,handleSaveApply:null,handleReset:null,
 load:function(){return Promise.all([api.loadEditor(false),api.ddnsProfiles().catch(function(){return {available:false,profiles:[]};})]).then(function(results){return results[0].concat([api.dnsInventory(results[1])]);});},
 render:function(data){
  var state=data[0];if(state.error)return api.editorUnavailable(state);
  if(!state.saved_config)return api.editorUnavailable({error:'请先在设置页保存监听设置'});
  if(state.saved_config.schema_version===1)return api.migrationPanel(state);
  var dns=data[3],profiles=dns.profiles;
  var saved=state.saved_config,inventory=api.sortInventory(data[1].certificates || [],saved);
  var m=new form.JSONMap({services:api.serviceRows(saved,dns)},'HomePublish — 服务');
  m.snapshot=api.clone(saved);m.snapshotRevision=state.saved_revision;m.editor='services';
  var s=m.section(form.GridSection,'services','服务规则'),o;
  s.addremove=true;s.anonymous=true;s.sortable=false;s.nodescriptions=true;s.modalizable=true;
  s.tab('general','基本设置');s.tab('access','接入设置');s.tab('backend','后端设置');
  s.modaltitle=function(sid){var r=this.map.data.get(this.map.config,sid);return r && r.name || '新服务';};
  s.renderMoreOptionsModal=function(){
   return Promise.resolve(form.GridSection.prototype.renderMoreOptionsModal.apply(this,arguments)).then(function(result){
    var modal=document.querySelector('#modal_overlay .modal'),button=modal && modal.querySelector('.button-row .cbi-button-positive');
    if(button)button.textContent='填写完毕';
    if(modal && !modal.querySelector('.hp-modal-draft-notice'))modal.insertBefore(E('p',{class:'hp-modal-draft-notice'},'填写完毕仅更新当前页面草稿；请点击页面底部“仅保存”或“保存并应用”，才会存储配置。'),modal.querySelector('.button-row'));
    return result;
   });
  };
  s.handleModalSave=function(modalMap,ev){
   var section=this,mapNode=this.getActiveModalMap(),activeMap=dom.findClassInstance(mapNode),saveTasks=activeMap.save(null,true),modal=document.querySelector('body.modal-overlay-active > #modal_overlay .cbi-modal'),alert=modal && modal.querySelector('.hp-modal-validation-alert');
   if(!alert && modal){alert=E('p',{class:'hp-modal-validation-alert',role:'alert','aria-live':'assertive'});var buttons=modal.querySelector('.button-row');modal.insertBefore(alert,buttons || null);}
   return saveTasks.then(function(){var map=activeMap;while(map.parent){map=map.parent;saveTasks=saveTasks.then(L.bind(map.load,map)).then(L.bind(map.reset,map));}return saveTasks;}).then(L.bind(section.handleModalCancel,section,modalMap,ev,true)).catch(function(e){
    var invalid=modal && Array.from(modal.querySelectorAll('.cbi-input-invalid')).find(function(input){return input.offsetParent!==null;});
    if(invalid){invalid.setAttribute('aria-invalid','true');var pane=invalid.closest('[data-tab]'),menu=pane && pane.parentNode && pane.parentNode.previousElementSibling,tab=pane && menu && menu.querySelector('[data-tab="'+pane.getAttribute('data-tab')+'"] a');if(tab)tab.click();window.requestAnimationFrame(function(){invalid.focus();invalid.scrollIntoView({block:'center'});});}
    if(alert){alert.textContent=(invalid && (invalid.getAttribute('data-tooltip') || invalid.title)) || (e && e.message) || '请检查输入';if(invalid){var field=invalid.closest('.cbi-value-field') || invalid.parentNode;field.appendChild(alert);invalid.setAttribute('aria-describedby','hp-modal-validation-error');alert.id='hp-modal-validation-error';window.requestAnimationFrame(function(){alert.scrollIntoView({block:'center'});});}}
    return Promise.reject(e);
   });
  };
  function field(tab,cls,key,label,modal){var v=s.taboption(tab,cls,key,label);if(modal!==undefined)v.modalonly=modal;if(cls===form.DummyValue){v.modalonly=false;v.optional=true;}v.rmempty=cls===form.DummyValue;return v;}
  o=field('general',form.Flag,'enabled','启用');o.default='1';o.editable=true;
  o=field('general',form.Value,'name','名称');
  o=field('general',form.ListValue,'type','接入方式');o.value('http_proxy','HTTP 反向代理');o.value('https_proxy','HTTPS 反向代理');o.value('tls_passthrough','TLS 透传');o.value('ssh','SSH 远程登录共入口');o.value('rdp','RDP 远程桌面共入口');o.value('tcp_forward','独立端口 TCP 转发');o.default='https_proxy';o.textvalue=function(sid){return api.serviceType(this.map.data.get(this.map.config,sid).type);};
  function portHint(type){return type==='ssh'?'SSH 通常使用 22':type==='rdp'?'RDP 通常使用 3389':'请输入后端端口';}
  o.onchange=function(ev,sid,value){var option=this.map.lookupOption('backend_port',sid)[0],root=document.getElementById(option.cbid(sid)),control=root && (root.matches('input')?root:root.querySelector('input'));if(control)control.placeholder=portHint(value);};
  o=field('general',form.DummyValue,'access_method_help','适用场景');o.modalonly=true;
  o.renderWidget=function(){return E('ul',{},[
   E('li',{},[E('strong',{},'HTTP 反向代理：'),'外网通过http://域名:共享端口 访问的内网服务；路由器无需配置证书，安全性较低，只在特殊场景使用。']),
   E('li',{},[E('strong',{},'HTTPS 反向代理：'),'外网通过https://域名:共享端口 访问的内网服务；使用本应用配置的证书，外网访问加密，适合绝大多数开放HTTP协议内网服务的场景，支持内网服务使用HTTP或HTTPS；后端使用HTTPS时全链路加密。']),
   E('li',{},[E('strong',{},'TLS 透传：'),'加密连接直达后端，由后端提供证书；路由器无需配置证书。适合已有HTTPS的网站、NAS或管理面板、要求客户端证书的双向认证服务，以及直接使用TLS的MQTT、邮件等TCP服务。客户端须使用域名连接并发送对应域名（SNI），才能与其他服务共用入口端口。需要先建立明文连接再升级加密的STARTTLS，以及UDP服务，不适用此方式。']),
   E('li',{},[E('strong',{},'SSH 远程登录共入口：'),'使用普通 SSH 客户端连接共享入口地址和端口，自动识别后转发至后端（通常为 22 端口），无需网页终端或专用客户端。全局最多配置一条 SSH 规则（停用的规则也计入），可与 RDP 及网站服务共用入口；无需单独域名或入口证书，加密、主机密钥校验与账号认证由 SSH 客户端和后端负责。']),
   E('li',{},[E('strong',{},'RDP 远程桌面共入口：'),'远程桌面客户端连接共享入口地址和端口，自动识别后转发至后端（默认 3389）。全局最多配置一条 RDP 规则（停用的规则也计入），可与 SSH 及网站服务共用入口，无需单独域名或入口证书；加密、证书与身份验证由后端负责。仅支持 TCP，不转发 RDP UDP。']),
   E('li',{},[E('strong',{},'独立端口 TCP 转发：'),'适合任意 TCP 服务，使用单独的监听端口，不共用入口端口。'])
  ]);};
  o=field('access',form.DummyValue,'match_summary','匹配 / 端口');o.textvalue=function(sid){var r=this.map.data.get(this.map.config,sid);return r.type==='tcp_forward'?'TCP '+(r.listen_port || '待填写'):r.hostname || '共享入口端口';};
  function hostnameOnly(v){['http_proxy','https_proxy','tls_passthrough'].forEach(function(type){v.depends('type',type);});v.retain=true;return v;}
  function automatic(v){['http_proxy','https_proxy','tls_passthrough'].forEach(function(type){v.depends({type:type,dns_mode:'ddns_go'});});v.retain=true;return v;}
  function row(sid){return m.data.get(m.config,sid);}
  function selected(sid,map){if(profiles.length===1 && (!row(sid).dns_profile || row(sid).dns_profile===profiles[0].id))return profiles[0];var option=map.root && map.lookupOption('dns_profile',sid),value=option && (option[0].getUIElement(sid)?option[0].formvalue(sid):option[0].cfgvalue(sid));if(value==null)value=row(sid).dns_profile || (profiles.length===1?profiles[0].id:'');return profiles.find(function(p){return p.id===value;});}
  o=hostnameOnly(field('access',form.ListValue,'dns_mode','DNS 维护方式',true));o.value('manual','自行维护');o.value('ddns_go','本机 ddns-go 自动维护');o.default=dns.available && profiles.length?'ddns_go':'manual';
  o.description='自动创建或更新此域名的解析记录。所选账号需要有权管理此域名。停用或删除服务不会删除已有解析记录。改为自行维护不会移除原有自动更新设置。';
  o.validate=function(sid,value){return value!=='ddns_go' || profiles.length || (row(sid).dns || {}).mode==='ddns_go'?true:'请先在 ddns-go 中配置域名服务商并启用服务。';};
  var profileOption=automatic(field('access',form.ListValue,'dns_profile','域名服务商',true));profileOption.value('','请选择域名服务商');
  profiles.forEach(function(p){profileOption.value(p.id,(p.name || '域名账号')+' · '+p.provider);});
  (saved.services || []).forEach(function(svc){var d=svc.dns;if(d && d.mode==='ddns_go' && !profiles.some(function(p){return p.id===d.profile_id;}))profileOption.value(d.profile_id,'原有账号（暂时无法读取）');});
  profileOption.cfgvalue=function(sid){var r=row(sid);if(!r.dns_profile && profiles.length===1)r.dns_profile=profiles[0].id;return r.dns_profile || '';};
  profileOption.formvalue=function(sid){return profiles.length===1 && (!row(sid).dns_profile || row(sid).dns_profile===profiles[0].id)?profiles[0].id:form.ListValue.prototype.formvalue.call(this,sid);};
  profileOption.renderWidget=function(sid,index,value){var widget=form.ListValue.prototype.renderWidget.call(this,sid,index,value || (profiles.length===1?profiles[0].id:''));if(profiles.length===1 && (!value || value===profiles[0].id))return E('div',{},[E('span',{},(profiles[0].name || '域名账号')+' · '+profiles[0].provider),E('div',{hidden:true},[widget])]);return widget;};
  profileOption.validate=function(sid,value){return value?true:'请选择域名服务商';};
  if(!profiles.length)profileOption.description='请先在 ddns-go 中配置域名服务商并启用服务。已有选择仍保留，也可以改为自行维护。';
  // Discovery completes before this editor is rendered; defaults never race a user's choice.
  function input(sid,key,map){var options=map.lookupOption(key,sid),option=options && options[0];return option && option.getUIElement(sid);}
  function setInput(sid,key,value,map){var widget=input(sid,key,map);if(widget)widget.setValue(value);}
  function compose(sid,map){var label=input(sid,'dns_label',map),suffix=input(sid,'dns_suffix',map);if(label && suffix)setInput(sid,'hostname',label.getValue() && suffix.getValue()?label.getValue()+'.'+suffix.getValue():'',map);}
  function candidates(sid,map){var p=selected(sid,map);return p?p.candidates:[];}
  function fillCandidates(select,sid,map){
   var list=candidates(sid,map),current=input(sid,'dns_suffix',map),r=row(sid),value=current?current.getValue():r.dns_suffix!=null?r.dns_suffix:api.dnsParts(r.hostname).suffix || (list.length===1?list[0].suffix:'');
   select.replaceChildren(E('option',{value:''},list.length?'请选择参考后缀，或在下方填写':'没有可用参考，请在下方填写'));
   list.forEach(function(c){select.appendChild(E('option',{value:c.suffix},c.suffix+'（来源：'+c.sources.join('、')+'）'));});
   select.value=list.some(function(c){return c.suffix===value;})?value:'';
  }
  o=automatic(field('access',form.DummyValue,'dns_suffix_choices','参考后缀',true));o.modalonly=true;
  o.renderWidget=function(sid){var map=this.map,select=E('select',{'data-dns-candidates':sid,'aria-label':'参考后缀',change:function(){if(this.value){setInput(sid,'dns_suffix',this.value,map);compose(sid,map);}}});fillCandidates(select,sid,map);return E('div',{},[select,E('p',{},'仅根据 ddns-go 已配置域名去掉最左一段作为参考；两段域名保留原样。不是域名权限范围，请确认或修改后缀。')]);};
  o=automatic(field('access',form.Value,'dns_label','主机名',true));o.rmempty=true;
  o.cfgvalue=function(sid){return row(sid).dns_label!=null?row(sid).dns_label:api.dnsParts(row(sid).hostname).label;};
  o.validate=function(sid,value){return !value || /^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/.test(value)?true:'请填写一段主机名，不含点或协议';};
  o.onchange=function(ev,sid){compose(sid,this.map);};
  o=automatic(field('access',form.Value,'dns_suffix','域名后缀（可修改）',true));o.datatype='hostname';o.rmempty=true;
  o.cfgvalue=function(sid){var r=row(sid),parts=api.dnsParts(r.hostname),list=candidates(sid,this.map);return r.dns_suffix!=null?r.dns_suffix:parts.suffix || (list.length===1?list[0].suffix:'');};
  o.onchange=function(ev,sid){compose(sid,this.map);var select=document.querySelector('select[data-dns-candidates="'+sid+'"]');if(select)fillCandidates(select,sid,this.map);};
  o=field('access',form.Value,'hostname','完整域名（精确匹配）',true);o.datatype='hostname';o.depends('type','http_proxy');o.depends('type','https_proxy');o.depends('type','tls_passthrough');o.retain=true;
  o.description='填写主机名和后缀会生成完整域名，也可以直接填写完整域名。自行维护时保留此域名。';
  o.onchange=function(ev,sid,value){var parts=api.dnsParts(value);setInput(sid,'dns_label',parts.label,this.map);setInput(sid,'dns_suffix',parts.suffix,this.map);};
  function family(key,label,family){
   var v=automatic(field('access',form.Flag,key,label,true));v.default='0';v.rmempty=false;
   v.cfgvalue=function(sid){var value=row(sid)[key],p=selected(sid,this.map);return value!=null?value:p && (family==='ipv4_enabled'?p.ipv4_enabled:!p.ipv4_enabled && p.ipv6_enabled)?'1':'0';};
   v.renderWidget=function(sid,index,value){var p=selected(sid,this.map);this.readonly=!!p && !p[family];return form.Flag.prototype.renderWidget.call(this,sid,index,value);};
   v.validate=function(sid){var p=selected(sid,this.map),a=this.map.lookupOption('dns_a',sid)[0].formvalue(sid)==='1',aaaa=this.map.lookupOption('dns_aaaa',sid)[0].formvalue(sid)==='1';if(!a && !aaaa)return '请至少选择一种解析记录';if(p && ((a && !p.ipv4_enabled) || (aaaa && !p.ipv6_enabled)))return '请只选择该账号已启用的地址类型';return true;};
   return v;
  }
  family('dns_a','A（IPv4）','ipv4_enabled');family('dns_aaaa','AAAA（IPv6）','ipv6_enabled');
  profileOption.onchange=function(ev,sid){var map=this.map,p=selected(sid,map),list=p?p.candidates:[],select=document.querySelector('select[data-dns-candidates="'+sid+'"]');if(select){if(list.length && !row(sid).service_id){setInput(sid,'dns_suffix',list.length===1?list[0].suffix:'',map);compose(sid,map);}fillCandidates(select,sid,map);}['dns_a','dns_aaaa'].forEach(function(key){var option=map.lookupOption(key,sid)[0],widget=option.getUIElement(sid),enabled=!!p && p[key==='dns_a'?'ipv4_enabled':'ipv6_enabled'];if(widget)widget.setValue(enabled && (key==='dns_a' || !p.ipv4_enabled)?'1':'0');var root=document.getElementById(option.cbid(sid)),input=root && (root.matches('input')?root:root.querySelector('input[type="checkbox"]'));if(input)input.disabled=!enabled;});};
  o=field('access',form.Value,'listen_port','独立 TCP 监听端口',true);o.datatype='range(1024,65535)';o.depends('type','tcp_forward');o.retain=true;
  o=field('access',form.ListValue,'certificate_mode','HTTPS 证书模式',true);o.value('inherit','继承入口默认证书');o.value('override','独立指定');o.default='inherit';o.depends('type','https_proxy');o.retain=true;
  o=field('access',form.ListValue,'certificate_ref','独立证书',true);o.value('','未选择');o.rmempty=true;o.depends({type:'https_proxy',certificate_mode:'override'});o.retain=true;
  inventory.forEach(function(c){o.value(c.certificate_ref,c.domain+' · '+String(c.key_type).toUpperCase());});
  (saved.services || []).forEach(function(svc){if(svc.certificate_ref && !inventory.some(function(c){return c.certificate_ref===svc.certificate_ref;}))o.value(svc.certificate_ref,svc.certificate_ref+'（不可用）');});
  o=field('access',form.DummyValue,'certificate_summary','证书');o.textvalue=function(sid){var r=this.map.data.get(this.map.config,sid);return r.type==='https_proxy'?(r.certificate_mode==='override'?r.certificate_ref || '未选择':'继承入口默认'):r.type==='tls_passthrough'?'由后端提供':'不需要';};
  o=field('backend',form.DummyValue,'backend_summary','后端地址');o.textvalue=function(sid){var r=this.map.data.get(this.map.config,sid),h=r.backend_host || '';return (h.includes(':')?'['+h+']':h)+':'+(r.backend_port || '');};
  o=field('backend',form.Value,'backend_host','后端地址',true);o.description='填写主机名或裸 IP 地址，不含协议、路径及端口。';
  o.validate=function(sid,value){
   var error='请填写有效的后端地址：主机名或裸 IP 地址，不含协议、路径及端口。';
   if(!value)return error;
   if(value.indexOf(':')>=0)return validation.parseIPv6(value)?true:error;
   if(/^[0-9.]+$/.test(value))return validation.parseIPv4(value)?true:error;
   return value.length<=253 && value.split('.').every(function(label){return /^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/.test(label);})?true:error;
  };
  o=field('backend',form.Value,'backend_port','后端端口',true);o.datatype='port';
  o.cfgvalue=function(sid){return row(sid).backend_port;};
  o.renderWidget=function(sid,index,value){
   var node=form.Value.prototype.renderWidget.call(this,sid,index,value),input=node.querySelector('input');
   if(input){var type=row(sid).type;input.placeholder=type==='ssh'?'SSH 通常使用 22':type==='rdp'?'RDP 通常使用 3389':'请输入后端端口';}
   return node;
  };
  o=field('backend',form.ListValue,'upstream_scheme','后端协议',true);o.value('http','HTTP');o.value('https','HTTPS');o.default='http';o.depends('type','http_proxy');o.depends('type','https_proxy');o.retain=true;
  o=field('backend',form.Value,'backend_host_header','回源 Host',true);o.rmempty=true;o.depends('type','http_proxy');o.depends('type','https_proxy');o.retain=true;o.description='指定后端网站使用的域名，留空使用外网访问域名。后端按域名区分网站时填写。';
  o.validate=function(sid,value){
   if(!value)return true;
   var match=value.match(/^(?:\[([0-9a-fA-F:.]+)\]|([^:\[\]]+))(?::([0-9]+))?$/),error='请填写有效的域名或 IP 地址，可附带端口，不含协议和路径。';
   if(!match || (match[3] && (!/^[1-9][0-9]{0,4}$/.test(match[3]) || Number(match[3])>65535)))return error;
   if(match[1])return validation.parseIPv6(match[1])?true:error;
   var host=match[2];
   if(/^[0-9.]+$/.test(host))return validation.parseIPv4(host)?true:error;
   return host.length<=253 && host.split('.').every(function(label){return /^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/.test(label);})?true:error;
  };
  o=field('backend',form.Flag,'tls_verify','验证后端证书',true);o.default='1';o.depends({type:'http_proxy',upstream_scheme:'https'});o.depends({type:'https_proxy',upstream_scheme:'https'});o.description='关闭后可连接自签名证书的内网服务。';o.retain=true;
  o=field('backend',form.Value,'tls_server_name','后端 HTTPS 域名（SNI）',true);o.datatype='hostname';o.rmempty=true;o.depends({type:'http_proxy',upstream_scheme:'https'});o.depends({type:'https_proxy',upstream_scheme:'https'});o.description='验证证书时必填，须与后端证书域名一致；关闭验证时可留空。';o.retain=true;
  o.validate=function(sid,value){var verify=this.map.lookupOption('tls_verify',sid)[0].formvalue(sid);return verify!=='0' && verify!==false && !value?'请填写后端证书域名':true;};
  o=field('backend',form.Value,'read_timeout','后端响应超时（秒）',true);o.rmempty=true;o.placeholder='300';o.datatype='and(uinteger,min(1),max(3600))';o.depends('type','http_proxy');o.depends('type','https_proxy');o.retain=true;o.description='等待后端响应的最长时间，范围 1–3600 秒，留空默认 300。后端为 LLM 等长响应/流式服务时可调大。';
  return m.render().then(function(node){
   node.querySelectorAll('table.cbi-section-table').forEach(function(table){
    var viewport=E('div',{style:'max-width:100%;overflow-x:auto',tabindex:0,'aria-label':'服务列表，可横向滚动'});
    table.parentNode.insertBefore(viewport,table);viewport.appendChild(table);
   });
   return api.actionBar(node,state,{map:m});
  });
 }
});
