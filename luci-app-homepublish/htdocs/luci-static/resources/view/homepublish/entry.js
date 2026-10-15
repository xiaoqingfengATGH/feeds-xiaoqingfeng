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
  var listeners=saved.access_profile.listeners,policy=saved.publication_policy || {},first=listeners[0];
  var row={family:listeners.length===2?'dual':first?first.family:'ipv4',port:String(first?first.port:8443)};
  var networks=net.networks || [];
  function available(n,f){return (n.addresses || []).filter(function(a){return a.family===f && n.up===true && a.address!=='0.0.0.0' && a.address!=='::';});}
  ['ipv4','ipv6'].forEach(function(f){
   var l=listeners.find(function(x){return x.family===f;});
   // A native ListValue visually picks its first network when the draft is empty,
   // but renderWidget reads this row before that DOM fallback exists. Initialize
   // only absent listeners from inventory; never replace a saved explicit bind.
   var initial=!l && networks.find(function(n){return available(n,f).length>0;});
   row[f+'_network']=l?l.network:initial?initial.network:'';
   row[f+'_address']=l?l.address:initial?available(initial,f)[0].address:'';
  });
  var m=new form.JSONMap({cfg_listener:row,cfg_policy:{default_certificate_ref:saved.default_certificate_ref || '',mode:policy.mode,temporary_minutes:String((policy.temporary_duration || 1800)/60),boot_restore:policy.boot_restore?'1':'0'}},'HomePublish — 发布入口设置','精确选择本机监听地址；保存不启动。IPv4 上级路由器需要手工转发到本机地址及端口，公网端口由上级配置决定。');
  m.snapshot=api.clone(saved);m.snapshotRevision=state.saved_revision;m.editor='entry';
  var s=m.section(form.NamedSection,'cfg_listener','listener','监听设置'),o;
  s.addremove=false;
  o=s.option(form.ListValue,'family','地址族');o.value('ipv4','IPv4');o.value('ipv6','IPv6');o.value('dual','IPv4 / IPv6 双栈');o.rmempty=false;
  ['ipv4','ipv6'].forEach(function(f){
   var n=s.option(form.ListValue,f+'_network',(f==='ipv4'?'IPv4':'IPv6')+' 网络');
   n.rmempty=false;n.retain=true;n.depends('family',f);n.depends('family','dual');
   var eligibleNetworks=networks.filter(function(x){return available(x,f).length>0;});
   eligibleNetworks.forEach(function(x){n.value(x.network,x.network+' · '+(x.device || '设备不可用'));});
   if(row[f+'_network'] && !eligibleNetworks.some(function(x){return x.network===row[f+'_network'];}))n.value(row[f+'_network'],row[f+'_network']+'（已不可用：网络未就绪或无该地址族的可发布地址）');
   if(!eligibleNetworks.length && !row[f+'_network'])n.value('','无可用网络：没有已就绪且具有可发布地址的网络');
   n.renderWidget=function(sid,index,value){return Promise.resolve(form.ListValue.prototype.renderWidget.call(this,sid,index,value)).then(function(node){Array.from(node.querySelectorAll('option')).forEach(function(o){if(!eligibleNetworks.some(function(x){return x.network===o.value;}))o.disabled=true;});return node;});};
   n.validate=function(sid,value){return eligibleNetworks.some(function(x){return x.network===value;})?true:'无可用网络，请选择已就绪且具有该地址族可发布地址的网络';};
   var a=s.option(form.ListValue,f+'_address',(f==='ipv4'?'IPv4':'IPv6')+' 地址');a.rmempty=false;a.retain=true;a.depends('family',f);a.depends('family','dual');
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
    var zoneNode=document.getElementById(z.cbid(sid));
    if(zoneNode){var text=zone(value);zoneNode.value=text;dom.content(zoneNode.parentNode.querySelector('output'),[text]);}
   };
   a.validate=function(sid,value){var network=n.formvalue(sid);return choices(network).some(function(x){return api.addressEqual(x.address,value);})?true:'地址已不可用，请选择该网络上的当前地址';};
   function zone(selected){var found=networks.find(function(x){return x.network===selected;});return found && found.zones && found.zones.length===1?found.zones[0]:'缺失或不唯一，发布前需要解决';}
   var z=s.option(form.DummyValue,f+'_zone',(f==='ipv4'?'IPv4':'IPv6')+' 防火墙区域');z.depends('family',f);z.depends('family','dual');z.cfgvalue=function(sid){return zone(row[f+'_network']);};
  });
  o=s.option(form.Value,'port','TCP 监听端口');o.datatype='range(1024,65535)';o.rmempty=false;
  s=m.section(form.NamedSection,'cfg_policy','policy','默认证书');
  o=s.option(form.ListValue,'default_certificate_ref','HTTPS 默认证书');o.value('','未选择');o.rmempty=true;
  var inventory=api.sortInventory(data[1].certificates || [],saved);inventory.forEach(function(c){o.value(c.certificate_ref,c.domain+' · '+String(c.key_type).toUpperCase()+' · '+(c.not_after || '日期未知'));});
  if(saved.default_certificate_ref && !inventory.some(function(c){return c.certificate_ref===saved.default_certificate_ref;}))o.value(saved.default_certificate_ref,saved.default_certificate_ref+'（不可用）');
  o.description='仅供 HTTPS 反代继承，TLS 透传、SSH 和 TCP 转发不需要本机证书。';
  s=m.section(form.NamedSection,'cfg_policy','policy','发布策略');
  o=s.option(form.ListValue,'mode','发布期限');o.value('continuous','持续：直到停止');o.value('temporary','临时：原截止不延长');o.rmempty=false;
  o=s.option(form.Value,'temporary_minutes','临时时长（分钟）');o.datatype='range(1,1440)';o.depends('mode','temporary');o.rmempty=false;
  o=s.option(form.Flag,'boot_restore','开机恢复');o.default='0';o.rmempty=false;o.description='手动停止或临时剩余时间不确定时不会恢复。';
  return m.render().then(function(node){return api.actionBar(node,state,{map:m});});
 }
});
