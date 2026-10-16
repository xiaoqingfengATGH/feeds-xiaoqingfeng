'use strict';
'require view';
'require rpc';
'require form';
'require uci';
'require poll';

var callStatus = rpc.declare({
	object: 'homekms', method: 'status', params: []
});

var callLogs = rpc.declare({
	object: 'homekms', method: 'logs', params: []
});

return view.extend({
	refreshLogs: function() {
		var self = this;
		return callLogs().catch(function() { return null; }).then(function(reply) {
			var available = reply && reply.available === true && typeof reply.text === 'string';
			self.logNode.textContent = available ? (reply.text || _('No HomeKMS log entries.')) : _('Logs unavailable.');
			self.logNoticeNode.textContent = available && reply.truncated === true ? _('Older log content was truncated.') : '';
		});
	},
	load: function() {
		return uci.load('homekms');
	},

	refreshStatus: function() {
		var self = this;
		return Promise.all([ this.getStatus().then(function(status) {
			var text = status.state === 'running' ? _('Running') :
				(status.state === 'stopped' ? _('Stopped') : _('Unavailable'));
			if (status.state === 'running' && Number.isInteger(status.pid) && status.pid > 0)
				text += ' (PID: ' + status.pid + ')';
			self.statusNode.textContent = text;
			self.listenNode.textContent = status.state === 'unavailable' ||
				!Number.isInteger(status.port) || status.port < 1024 || status.port > 65535 ||
				typeof status.listening !== 'boolean' ? _('Unavailable') :
				(status.listening ? _('Listening') : _('Not listening')) + ' (TCP: ' + status.port + ')';
		}), this.refreshLogs() ]);
	},

	render: function() {
		var self = this;
		var m = new form.Map('homekms', _('HomeKMS'),
			_('Provides KMS services for Microsoft volume-licensed products.'));
		var s = m.section(form.NamedSection, 'main', 'homekms');
		var o = s.option(form.Flag, 'enabled', _('Enable service'), _('Save & Apply starts or stops the service.'));
		o.default = '0';
		o.rmempty = false;
		this.statusNode = E('span', {}, _('Unavailable'));
		this.listenNode = E('span', {}, _('Unavailable'));
		this.engineNode = E('span', {}, _('py-kms 1.0.1 (embedded product database)'));
		o = s.option(form.DummyValue, '_status', _('Service status'));
		o.renderWidget = function() { return self.statusNode; };
		o = s.option(form.DummyValue, '_listener', _('PID-associated TCP listener'),
			_('A listening socket is verified against the main service PID and configured port.'));
		o.renderWidget = function() { return self.listenNode; };
		o = s.option(form.DummyValue, '_engine', _('Engine'));
		o.renderWidget = function() { return self.engineNode; };
		o = s.option(form.Value, 'port', _('TCP port'));
		o.datatype = 'range(1024,65535)';
		o.default = '1688';
		o.rmempty = false;
		o = s.option(form.Flag, 'auto_discovery', _('DNS auto-discovery'), _('Disabled by default. Save & Apply publishes a DNS SRV record through system dnsmasq in the local DNS domain while the service is enabled. Compatible clients must use this router as their DNS server and search the same domain. When disabled or stopped, the HomeKMS discovery record is removed from system dnsmasq. If a DNS proxy or a separate DNS instance handles client queries, refresh its configuration after SRV record changes and verify that it serves the record. Otherwise, specify the HomeKMS address and port manually on clients. HomeKMS does not automatically refresh other DNS services.'));
		o.default = '0';
		o.rmempty = false;
		o = s.option(form.Flag, 'wan_access', _('Allow WAN access'), _('Disabled by default. Exposes this service to the WAN zone.'));
		o.default = '0';
		o.rmempty = false;
		this.logNode = E('pre', { 'style': 'white-space:pre-wrap;overflow-wrap:anywhere;max-height:24em;overflow:auto' }, _('Logs unavailable.'));
		this.logNoticeNode = E('p', {}, '');
		return m.render().then(function(formNode) {
			poll.add(self.refreshStatus.bind(self), 5);
			self.refreshStatus();
			return E('div', {}, [
				formNode,
				E('div', { 'class': 'cbi-section' }, [
					E('h3', {}, _('Recent HomeKMS logs')),
					E('p', {}, _('Latest snapshot: at most 50 lines and 16 KiB of UTF-8 text.')),
					self.logNoticeNode, self.logNode
				])
			]);
		});
	},

	getStatus: function() {
		return callStatus().then(function(reply) {
			if (!reply || reply.checked !== true || typeof reply.running !== 'boolean')
				return { state: 'unavailable', pid: null };
			return {
				state: reply.running ? 'running' : 'stopped',
				pid: reply.running && Number.isInteger(reply.pid) && reply.pid > 0 ? reply.pid : null,
				port: reply.port, listening: reply.listening
			};
		}).catch(function() { return { state: 'unavailable', pid: null }; });
	}
});
