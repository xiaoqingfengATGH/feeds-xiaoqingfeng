/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require form';
'require view';
'require ui';
'require dom';
'require view.homepublish.product as api';
return view.extend({
 handleSave:null,handleSaveApply:null,handleReset:null,
 load:function(){return api.loadEditor(true);},
 render:function(data){
  var state=data[0],net=data[2];
  if(state.error || !net)return api.editorUnavailable(state);
  if(state.saved_config && state.saved_config.schema_version===1)return api.migrationPanel(state);
  var saved=state.saved_config || {schema_version:2,services:[],access_profile:{listeners:[]},publication_policy:{mode:'continuous',boot_restore:false}};
  var policy=saved.publication_policy || {},row=api.entryDraft(saved);
  var networks=net.networks || [];
  function available(n,f){return (n.addresses || []).filter(function(a){return a.family===f && n.up===true && a.address!=='0.0.0.0' && a.address!=='::';});}
  // Seed only the advanced-mode draft, never change an explicit saved binding.
  ['ipv4','ipv6'].forEach(function(f){
   var existing=(saved.access_profile.listeners || []).find(function(l){return l.family===f;});
   if(existing && existing.bind_mode!=='auto')return;
   var initial=networks.find(function(n){return available(n,f).length>0;});
   row[f+'_network']=initial?initial.network:'';row[f+'_address']=initial?available(initial,f)[0].address:'';
  });
  var zones=Array.from(new Set((net.zones || []).map(function(z){return typeof z==='string'?z:z.name;}))).filter(Boolean).sort();
  api.entryZoneDefaults(row,saved,zones,networks);
  var m=new form.JSONMap({cfg_listener:row,cfg_policy:{default_certificate_ref:saved.default_certificate_ref || '',mode:policy.mode,temporary_minutes:String((policy.temporary_duration || 1800)/60),boot_restore:policy.boot_restore?'1':'0'}},'HomePublish — 设置','在这里配置统一入口监听IP地址族、地址配置、证书、运行方式。');
  m.snapshot=api.clone(saved);m.snapshotRevision=state.saved_revision;m.editor='entry';
  var s=m.section(form.NamedSection,'cfg_listener','listener','监听设置','这里配置内网服务对外开放的入口信息'),o;
  s.addremove=false;
  o=s.option(form.ListValue,'family','地址族');o.value('ipv4','IPv4');o.value('ipv6','IPv6');o.value('dual','IPv4 / IPv6 双栈');o.rmempty=false;
  var familyOption=o;
  familyOption.onchange=function(ev,sid,value){
   var previous=row.family;
   ['ipv4','ipv6'].forEach(function(f){
    if((value!==f && value!=='dual') || previous===f || previous==='dual')return;
    var option=(m.lookupOption(f+'_zones',sid) || [])[0],widget=option && option.getUIElement(sid);
    var draft={family:f};draft[f+'_zones']=widget?widget.getValue():row[f+'_zones'];
    api.entryZoneDefaults(draft,saved,zones,networks);row[f+'_zones']=draft[f+'_zones'];
    if(widget)widget.setValue(draft[f+'_zones']);
   });
   row.family=value;
  };
  o=s.option(form.ListValue,'bind_mode','监听方式');o.value('auto','自动监听（推荐）');o.value('address','指定本机地址（高级）');o.rmempty=false;o.description='自动监听 IPv4 0.0.0.0、IPv6 [::]（仅 IPv6），无需选择当前网络/IP。';
  ['ipv4','ipv6'].forEach(function(f){
   var n=s.option(form.ListValue,f+'_network',(f==='ipv4'?'IPv4':'IPv6')+' 网络');
   n.rmempty=false;n.retain=true;n.depends({family:f,bind_mode:'address'});n.depends({family:'dual',bind_mode:'address'});
   var eligibleNetworks=networks.filter(function(x){return available(x,f).length>0;});
   eligibleNetworks.forEach(function(x){n.value(x.network,x.network+' · '+(x.device || '设备不可用'));});
   if(row[f+'_network'] && !eligibleNetworks.some(function(x){return x.network===row[f+'_network'];}))n.value(row[f+'_network'],row[f+'_network']+'（已不可用：网络未就绪或无该地址族的可发布地址）');
   if(!eligibleNetworks.length && !row[f+'_network'])n.value('','无可用网络：没有已就绪且具有可发布地址的网络');
   n.renderWidget=function(sid,index,value){return Promise.resolve(form.ListValue.prototype.renderWidget.call(this,sid,index,value)).then(function(node){Array.from(node.querySelectorAll('option')).forEach(function(o){if(!eligibleNetworks.some(function(x){return x.network===o.value;}))o.disabled=true;});return node;});};
   n.validate=function(sid,value){return eligibleNetworks.some(function(x){return x.network===value;})?true:'无可用网络，请选择已就绪且具有该地址族可发布地址的网络';};
   var a=s.option(form.ListValue,f+'_address',(f==='ipv4'?'IPv4':'IPv6')+' 地址');a.rmempty=false;a.retain=true;a.depends({family:f,bind_mode:'address'});a.depends({family:'dual',bind_mode:'address'});
   function choices(network){
    var result=[];networks.filter(function(x){return x.network===network;}).forEach(function(x){available(x,f).forEach(function(v){result.push(v);});});return result;
   }
   a.renderWidget=function(sid,index,value){
    var current=row[f+'_network'],list=choices(current);this.keylist=[];this.vallist=[];
    list.forEach(function(v){this.value(v.address,v.address+(v.prefix!=null?'/'+v.prefix:'')+(v.scope==='ula'?' · 内网 IPv6，不能据此直接公网访问':''));},this);
    var missing=value && !list.some(function(v){return api.addressEqual(v.address,value);});
    if(missing)this.value(value,value+'（已不可用，请重新选择）');
    if(!list.length && !missing)this.value('','无可用地址');
    return Promise.resolve(form.ListValue.prototype.renderWidget.call(this,sid,index,value)).then(function(node){
     // Preserve disappeared saved bindings for diagnosis, not as selectable candidates.
     Array.from(node.querySelectorAll('option')).forEach(function(o){if(o.value==='' || (missing && o.value===value))o.disabled=true;});
     return node;
    });
   };
   n.onchange=function(ev,sid,value){
    var widget=a.getUIElement(sid),v=widget?widget.getValue():row[f+'_address'];
    if(widget){
     var list=choices(value),opts={};list.forEach(function(x){opts[x.address]=x.address+(x.prefix!=null?'/'+x.prefix:'')+(x.scope==='ula'?' · 内网 IPv6，不能据此直接公网访问':'');});
     var match=list.find(function(x){return api.addressEqual(x.address,v);});
     // A deliberate network change starts a new binding; never carry another network's address.
     var next=match?match.address:list.length?list[0].address:'';
     if(!list.length)opts['']='无可用地址';
     // ListValue uses ui.Select, not ui.Dropdown: retain its bound select and events.
     widget.choices=opts;
     dom.content(widget.node.querySelector('select'),Object.keys(opts).map(function(key){return E('option',{value:key,disabled:key===''?'':null},opts[key]);}));
     widget.setValue(next);widget.triggerValidation();
    }
   };
   a.validate=function(sid,value){var network=n.formvalue(sid);return choices(network).some(function(x){return api.addressEqual(x.address,value);})?true:'地址已不可用，请选择该网络上的当前地址';};
  });
  o=s.option(form.Value,'port','共享入口端口');o.datatype='range(1024,65535)';o.rmempty=false;o.description='HTTP、HTTPS、TLS 透传和 SSH 共用此端口；独立 TCP 转发使用服务中配置的端口。';
  ['ipv4','ipv6'].forEach(function(f){
   var z=s.option(form.MultiValue,f+'_zones',(f==='ipv4'?'IPv4':'IPv6')+' 入站区域（高级自定义）');z.rmempty=false;z.retain=true;z.depends('family',f);z.depends('family','dual');
   z.description='作为主路由使用时，建议选择 wan；作为旁路由使用时，建议选择 lan。可按实际接入方式修改。';
   // LuCI Dropdown requires an object even when inventory has no zones.
   z.transformChoices=function(){return form.MultiValue.prototype.transformChoices.call(this) || {};};
   zones.forEach(function(name){z.value(name,name);});
   row[f+'_zones'].filter(function(name){return zones.indexOf(name)<0;}).forEach(function(name){z.value(name,name+'（已不存在，请移除）');});
   z.validate=function(sid,value){var selected=api.zoneList(value);return !selected.length?'请选择至少一个入站区域':selected.every(function(name){return zones.indexOf(name)>=0;})?true:'所选入站区域已不存在，请重新选择';};
  });
  s=m.section(form.NamedSection,'cfg_policy','policy','默认证书');
  o=s.option(form.ListValue,'default_certificate_ref','HTTPS 默认证书');o.value('','未选择');o.rmempty=true;
  var inventory=api.sortInventory(data[1].certificates || [],saved);inventory.forEach(function(c){o.value(c.certificate_ref,c.domain+' · '+String(c.key_type).toUpperCase()+' · '+(c.not_after || '日期未知'));});
  if(saved.default_certificate_ref && !inventory.some(function(c){return c.certificate_ref===saved.default_certificate_ref;}))o.value(saved.default_certificate_ref,saved.default_certificate_ref+'（不可用）');
  o.description='仅供 HTTPS 反代 使用。HTTP 反代、TLS 透传、SSH 和 TCP 转发不需要本机证书。';
  s=m.section(form.NamedSection,'cfg_policy','policy','运行方式');
  o=s.option(form.ListValue,'mode','运行方式');o.value('continuous','持续运行');o.value('temporary','限定时长');o.rmempty=false;
  o=s.option(form.Value,'temporary_minutes','运行时长（分钟）');o.datatype='range(1,1440)';o.depends('mode','temporary');o.rmempty=false;o.description='达到设定时长后自动停止，设备重启后不恢复。';
  return m.render().then(function(node){
   var preview=E('div',{id:'hp-firewall-preview',class:'cbi-section','aria-live':'polite'});
   function refreshPreview(){
    var draft=api.clone(row);
    Object.keys(draft).forEach(function(key){var option=(m.lookupOption(key,'cfg_listener') || [])[0];if(option){var value=option.formvalue('cfg_listener');if(value!=null)draft[key]=value;}});
    var config=api.collectConfig({snapshot:saved,data:{data:{cfg_listener:draft}}}),rules=api.firewallRules(config);
    dom.content(preview,[E('h3',{},'放行端口预览'),E('p',{},'以下是按当前设置将开放的端口，保存并应用后生效。应用停用时不开放端口。'),
     E('table',{class:'table cbi-section-table'},[E('thead',{class:'thead cbi-section-thead'},[E('tr',{class:'tr cbi-section-table-titles'},['区域','地址族','目标地址','协议 / 端口','用途 / 服务 ID'].map(function(t){return E('th',{class:'th cbi-section-table-cell'},t);} ))]),E('tbody',{class:'tbody cbi-section-tbody'},rules.map(function(r){return E('tr',{class:'tr cbi-section-table-row'},[r.zone,r.family,r.dest_ip!=null?r.dest_ip:'自动监听（所有本机地址）',r.protocol.toUpperCase()+' / '+r.dest_port,r.services.map(function(id){var svc=(saved.services || []).find(function(s){return s.service_id===id;});return (svc && svc.name?svc.name+' · ':'')+id;}).join('、')].map(function(t){return E('td',{class:'td'},String(t));}));}))]),
     rules.length?E([]):E('p',{},'无待放行端口：请选择入站区域并启用需要发布的服务。')]);
   }
   node.append(preview);refreshPreview();['change','input','cbi-dropdown-change','cbi-dropdown-close'].forEach(function(event){node.addEventListener(event,refreshPreview);});
   return api.actionBar(node,state,{map:m});
  });
 }
});
