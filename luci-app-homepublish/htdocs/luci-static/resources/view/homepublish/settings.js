/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require view';
'require view.homepublish.product as api';
return view.extend({
 api:api,
 load:function(){return api.status().then(api.checked);},
 render:function(s){
  var self=this,c=JSON.parse(JSON.stringify(s.saved_config || api.defaults())),fields=[],root=E('div'),message=E('p',{id:'hp-message'},api.text(s));
  this.revision=s.saved_revision;
  root.appendChild(E('h2',{},_('HomePublish services')));root.appendChild(E('p',{},_('Canonical configuration only. Save persists this application without starting or applying. Stop is separate. Access profile is explicit JSON until the access wizard is implemented.')));root.appendChild(message);
  function field(container,key,label,value,type,assign){var input=E(type==='textarea'?'textarea':'input',{'data-field':key,type:type==='checkbox'?'checkbox':'text'});if(type==='checkbox')input.checked=!!value;else input.value=value;fields.push(function(){assign(type==='checkbox'?input.checked:input.value);});container.appendChild(E('label',{},[label,input]));container.appendChild(E('br'));return input;}
  c.services.forEach(function(service){var box=E('fieldset',{},E('legend',{},service.service_id));root.appendChild(box);
   ['service_id','name','hostname','certificate_ref'].forEach(function(k){field(box,k,k,service[k],null,function(v){service[k]=v;});});
   ['addressFamily','host','port'].forEach(function(k){field(box,'backend_'+k,'Backend '+k,service.backend[k],null,function(v){service.backend[k]=k==='port'?Number(v):v;});});
   field(box,'ranges','Allowed backend ranges (JSON)',JSON.stringify(service.backend.allowed_ranges),'textarea',function(v){service.backend.allowed_ranges=JSON.parse(v);});
   field(box,'backup','Optional backup (JSON or empty)',service.backend.backup?JSON.stringify(service.backend.backup):'','textarea',function(v){if(v.trim())service.backend.backup=JSON.parse(v);else delete service.backend.backup;});
   field(box,'authentication','Authentication review: confirmed / unconfirmed',service.authentication_review.authentication,null,function(v){service.authentication_review.authentication=v;});
   field(box,'management','Management service',service.authentication_review.management,'checkbox',function(v){service.authentication_review.management=v;});
  });
  field(root,'access_profile','Access profile (canonical JSON)',JSON.stringify(c.access_profile,null,2),'textarea',function(v){c.access_profile=JSON.parse(v);});
  field(root,'mode','Publication policy: continuous / temporary',c.publication_policy.mode,null,function(v){c.publication_policy.mode=v;});
  var duration=field(root,'temporary_duration','Temporary duration seconds (60–86400; ignored for continuous)',c.publication_policy.temporary_duration || 1800,null,function(v){if(c.publication_policy.mode==='temporary')c.publication_policy.temporary_duration=Number(v);else delete c.publication_policy.temporary_duration;});
  field(root,'boot_restore','Boot restore (default off; production activation unsupported)',c.publication_policy.boot_restore,'checkbox',function(v){c.publication_policy.boot_restore=v;});
  var button=E('button',{id:'hp-save',class:'cbi-button cbi-button-save',click:function(){return self.handleSave();}},_('Save configuration'));root.appendChild(button);
  this.handleSave=function(){button.disabled=true;var committed=false;return Promise.resolve().then(function(){fields.forEach(function(f){f();});return api.validate(c);}).then(function(v){api.checked(v);if(!v.valid)throw new Error('Invalid configuration');return api.save(self.revision,v.config);}).then(function(st){api.checked(st);committed=true;self.revision=st.saved_revision;return api.status();}).then(function(st){api.checked(st);message.textContent='Saved revision '+self.revision+' (not applied). '+api.text(st);}).catch(function(e){message.textContent=(committed?'Save committed; status refresh failed: ':'Save failed: ')+e.message;}).finally(function(){button.disabled=false;});};
  return root;
 },handleSaveApply:null,handleReset:null
});
