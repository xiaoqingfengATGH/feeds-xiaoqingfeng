/* SPDX-License-Identifier: Apache-2.0 */
'use strict';
'require view';
'require form';
'require rpc';
'require uci';
'require view.homestun.schema as schema';

var status = rpc.declare({object: 'homestun', method: 'status', expect: {}});
var commit = rpc.declare({object: 'uci', method: 'commit', params: ['config'], reject: true});
return view.extend({
 handleSave: function() {
  var self = this;
  return this.map.save().then(function() { return commit('homestun'); }).then(function() {
   return status().catch(function() { return {state: 'unavailable'}; });
  }).then(function(st) { self.statusNode.textContent = self.statusText(st); });
 },
 statusText: function(st) {
  var states = {disabled: _('disabled'), configured: _('configured (not proof of a running lease)'), invalid: _('invalid configuration'), unavailable: _('unavailable')};
  return _('Configuration') + ': ' + (states[st.state] || states.unavailable) + '; ' + _('Publication configuration') + ': ' + (states[st.publication] || states.unavailable);
 },
 load: function() {
  return Promise.all([status().catch(function() { return {state: 'unavailable'}; }), uci.load('homestun')]);
 },
 render: function(data) {
  var st = data[0] || {}, m = new form.Map('homestun', _('HomeSTUN — Settings'),
   _('Configuration only. Saving does not open a lease. Enabling permits a later manual service start (and boot start if separately enabled). Each lease has a fixed TTL, no automatic renewal or respawn.'));
  var service = m.section(form.NamedSection, 'main', 'service', _('Lease configuration'));
  var s = service;
  var originalParse = m.parse;
  m.parse = function() {
   var c = {}, hosts = [];
   ['enabled', 'exposure_approved', 'ttl', 'port', 'bind_port', 'stun_server', 'http_server'].forEach(function(k) { c[k] = service.formvalue('main', k); });
   hostSection.cfgsections().forEach(function(id) { hosts.push({name: hostSection.formvalue(id, 'name'), upstream: hostSection.formvalue(id, 'upstream')}); });
   var valid = schema.configuration(c, hosts);
   return valid === true ? originalParse.call(this) : Promise.reject(new Error(_(valid)));
  };
  function flag(name, label, description) {
   var o = s.option(form.Flag, name, label, description); o.default = '0'; o.rmempty = false; return o;
  }
  flag('enabled', _('Permit HomeSTUN'));
  flag('exposure_approved', _('I have reviewed direct exposure'), _('Every upstream must enforce its own authentication. Entry-page authentication and Cloudflare protection do NOT protect direct services. Do not expose router management, NAS administration or printers.'));
  flag('publication_enabled', _('Permit authenticated entry publication'), _('Publication is independent of public reachability. Provision the dedicated root-owned 0600 credential outside this UI. No token is accepted here.'));
  function value(name, label, datatype, validate) {
   var o = s.option(form.Value, name, label); o.rmempty = false; o.retain = true;
   o.depends('homestun.main.enabled', '1');
   if (validate) o.validate = function(section, v) { return validate(v) || _('Invalid or unsafe value'); };
   return o;
  }
  value('ttl', _('Fixed lease TTL (seconds)'), 'range(1,120)');
  value('port', _('Isolated loopback TLS port'), 'range(1024,65535)');
  var bind = value('bind_port', _('Dedicated NATMap bind port'), 'range(1024,65535)');
  bind.validate = function(section, v) {
   return v !== this.section.formvalue(section, 'port') || _('The two isolated ports must differ');
  };
  value('stun_server', _('STUN discovery server'), null, schema.server);
  value('http_server', _('Discovery HTTP server'), null, schema.server);
  // Fixed references are not editable file access capabilities.
  var refs = s.option(form.DummyValue, '_private_paths', _('Private file references'));
  refs.rawhtml = false;
  refs.cfgvalue = function() { return '/etc/homestun/router.token (root-owned 0600); /etc/homestun/cert.pem; /etc/homestun/key.pem; listen: 127.0.0.1'; };
  s = m.section(form.TypedSection, 'host', _('Direct services'), _('1–16 distinct lowercase fully qualified hostnames. Private IPv4 HTTP upstreams only, explicit ports 1024–65535. TLS and service authentication must be prepared independently. Backend validation remains authoritative.'));
  var hostSection = s;
  s.anonymous = true; s.addremove = true;
  value('name', _('Service hostname'), null, schema.hostname);
  value('upstream', _('Private HTTP upstream'), null, schema.upstream);
  this.map = m;
  this.statusNode = E('p', {}, this.statusText(st));
  var self = this;
  return m.render().then(function(node) {
   return E('div', {}, [
    E('h3', {}, _('Configuration status (committed configuration)')),
    self.statusNode,
    E('p', {}, _('Live lease: not observed. Mapped endpoint: unknown. Public reachability: unverified. No live integration claim is made.')),
    node
   ]);
  });
 },
 handleSaveApply: null
});
