/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require view';
'require view.homepublish.product as api';
return view.extend({
 api:api,load:function(){return api.status().then(api.checked);},
 render:function(s){
  var self=this,c=JSON.parse(JSON.stringify(s.saved_config || api.defaults())),root=E('div'),message=E('p',{id:'hp-message'},api.text(s)),readers=[];
  self.revision=s.saved_revision;
  root.appendChild(E('h2',{},'家庭服务与接入配置'));root.appendChild(E('p',{},'保存只更新本应用，不启动、不应用、不修改防火墙或 UPnP。运行中修改保持待应用。多个服务目前仅支持配置保存，生产开启与多服务运行尚未接入。'));root.appendChild(message);
  function field(box,key,label,value,options,assign){
   var input=E(options==='checkbox'?'input':Array.isArray(options)?'select':options==='lines'?'textarea':'input',{'data-field':key,type:options==='checkbox'?'checkbox':'text'});
   if(Array.isArray(options))options.forEach(function(o){input.appendChild(E('option',{value:o[0]},o[1]));});
   if(options==='checkbox')input.checked=!!value;else input.value=value==null?'':value;
   readers.push({box:box,read:function(){assign(options==='checkbox'?input.checked:input.value);}});
   box.appendChild(E('label',{},[label+' ',input]));box.appendChild(E('br'));return input;
  }
  function sync(){readers.forEach(function(r){if(root.contains(r.box))r.read();});}
  function action(box,label,attrs,fn){box.appendChild(E('button',Object.assign({type:'button',class:'cbi-button',click:fn},attrs),label));}
  var families=[['ipv4','IPv4（默认优先）'],['ipv6','IPv6'],['hostname','主机名（运行时优先 IPv4）']];
  var services=E('div');root.appendChild(services);
  function endpoint(box,b,prefix){field(box,prefix+'addressFamily','后端地址类型',b.addressFamily || 'ipv4',families,function(v){b.addressFamily=v;});field(box,prefix+'host','后端地址 / 主机名',b.host,null,function(v){b.host=v;});field(box,prefix+'port','后端端口',b.port,null,function(v){b.port=Number(v);});}
  function serviceRow(service){
   var box=E('fieldset',{'data-service':true},E('legend',{},'Web 服务'));services.appendChild(box);
   [['service_id','唯一服务标识'],['name','显示名称'],['hostname','直连域名（不含协议或端口）'],['certificate_ref','证书引用（acme:标识 / import:标识，不填私钥）']].forEach(function(k){field(box,k[0],k[1],service[k[0]],null,function(v){service[k[0]]=v;});});
   endpoint(box,service.backend,'backend_');
   field(box,'ranges','允许的家庭后端网段（CIDR，每行一个）',service.backend.allowed_ranges.join('\n'),'lines',function(v){service.backend.allowed_ranges=v.split(/[\n,]+/).map(function(x){return x.trim();}).filter(Boolean);});
   var backup=service.backend.backup || {addressFamily:'ipv4',host:'',port:8080};
   field(box,'backup_enabled','使用备用后端（不重放请求）',!!service.backend.backup,'checkbox',function(v){if(v)service.backend.backup=backup;else delete service.backend.backup;});endpoint(box,backup,'backup_');
   field(box,'authentication','业务鉴权确认',service.authentication_review.authentication,[['unconfirmed','尚未确认'],['confirmed','已确认服务自身有鉴权']],function(v){service.authentication_review.authentication=v;});
   field(box,'management','这是管理服务（不绕过运行校验）',service.authentication_review.management,'checkbox',function(v){service.authentication_review.management=v;});
   action(box,'删除此服务（保存后生效，停止运行需单独操作）',{'data-action':'remove-service'},function(){sync();c.services.splice(c.services.indexOf(service),1);box.remove();});
  }
  c.services.forEach(serviceRow);
  action(root,'添加服务',{id:'hp-add-service'},function(){sync();var service=JSON.parse(JSON.stringify(api.defaults().services[0]));service.service_id='service'+(c.services.length+1);service.name='新服务';service.hostname=service.service_id+'.example.test';service.certificate_ref='acme:'+service.service_id;c.services.push(service);serviceRow(service);});
  root.appendChild(E('h3',{},'接入方式与监听范围'));root.appendChild(E('p',{},'这里只保存配置，不检测公网、不添加映射、不开放端口。IPv4 固定转发由上级路由配置；IPv6 需要路由和入站许可，不使用 DNAT，内外端口必须相同。'));
  var a=c.access_profile,selected={};a.methods_allowed.forEach(function(m){selected[m]=true;});
  [['manual_ipv4','手动 IPv4 / 上级固定转发'],['direct_ipv6','直接 IPv6'],['upnp_ipv4','UPnP IPv4（仅配置，适配器未接入）'],['stun_experimental','高级 STUN（仅配置，有界实验）']].forEach(function(m){field(root,m[0],m[1],selected[m[0]],'checkbox',function(v){selected[m[0]]=v;});});
  field(root,'gateway_ref','UPnP 网关标识（选择 UPnP 时必填）',a.gateway_ref || '',null,function(v){if(v)a.gateway_ref=v;else delete a.gateway_ref;});
  var listeners=E('div');root.appendChild(listeners);
  function listenerRow(l){var box=E('fieldset',{'data-listener':true},E('legend',{},'专用 TCP 监听'));listeners.appendChild(box);
   field(box,'listener_family','入站地址族',l.family,[['ipv4','IPv4'],['ipv6','IPv6']],function(v){l.family=v;});
   [['address','明确监听地址'],['interface','网络接口'],['zone','防火墙区域'],['internal_port','专用内网端口（1024–65535）'],['external_port','对外端口（IPv6 与内网端口相同）']].forEach(function(k){field(box,'listener_'+k[0],k[1],l[k[0]],null,function(v){l[k[0]]=k[0].indexOf('port')>=0?Number(v):v;});});
   action(box,'删除监听（保存后生效）',{'data-action':'remove-listener'},function(){sync();a.listeners.splice(a.listeners.indexOf(l),1);box.remove();});
  }
  a.listeners.forEach(listenerRow);action(root,'添加监听',{id:'hp-add-listener'},function(){sync();var l={family:'ipv4',address:'',interface:'wan',zone:'wan',protocol:'tcp',internal_port:8443,external_port:18443};a.listeners.push(l);listenerRow(l);});
  root.appendChild(E('h3',{},'发布策略'));
  field(root,'mode','发布期限',c.publication_policy.mode,[['continuous','持续发布直到停用（默认）'],['temporary','临时限时发布']],function(v){c.publication_policy.mode=v;});
  field(root,'temporary_duration','临时期限（秒，60–86400；持续时忽略）',c.publication_policy.temporary_duration || 1800,null,function(v){if(c.publication_policy.mode==='temporary')c.publication_policy.temporary_duration=Number(v);else delete c.publication_policy.temporary_duration;});
  field(root,'boot_restore','开机恢复（默认关闭，生产激活未支持）',c.publication_policy.boot_restore,'checkbox',function(v){c.publication_policy.boot_restore=v;});
  var button=E('button',{id:'hp-save',type:'button',class:'cbi-button cbi-button-save',click:function(){return self.handleSave();}},'保存配置');root.appendChild(button);
  self.handleSave=function(){button.disabled=true;var committed=false;return Promise.resolve().then(function(){sync();a.methods_allowed=Object.keys(selected).filter(function(m){return selected[m];});return api.validate(c);}).then(function(v){api.checked(v);if(!v.valid)throw new Error(v.error || 'Invalid configuration');return api.save(self.revision,v.config);}).then(function(st){api.checked(st);committed=true;self.revision=st.saved_revision;return api.status();}).then(function(st){api.checked(st);message.textContent='Saved revision '+self.revision+' (not applied). 已保存，未应用。 '+api.text(st);}).catch(function(e){message.textContent=(committed?'Save committed; status refresh failed: ':'Save failed: ')+e.message;}).finally(function(){button.disabled=false;});};
  return root;
 },handleSaveApply:null,handleReset:null
});
