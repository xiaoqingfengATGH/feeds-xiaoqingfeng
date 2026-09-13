/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright (C) 2026 xiaoqingfeng <xiaoqingfeng@yeah.net> */
/* hometunnel settings — 模式/TTL/守护参数 */

'use strict';
'require form';
'require fs';
'require uci';
'require view';
'require view.hometunnel.ui as htui';

return view.extend({
	render: function () {
		var m, s, o;

		m = new form.Map('hometunnel', _('HomeTunnel — Settings'),
			_('Mode and daemon parameters.'));

		s = m.section(form.NamedSection, 'global', 'hometunnel', _('General'));

		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.ListValue, 'mode', _('Mode'),
			_('Recommended. on-demand: tunnel closed by default, opened from outside via the remote switch. always-on: tunnel connected at boot.'));
		o.value('ondemand', _('on-demand (remote switch)'));
		o.value('alwayson', _('always-on'));
		o.default = 'ondemand';
		o.rmempty = false;

		o = s.option(form.Value, 'tunnel_name', _('Tunnel name'));
		o.placeholder = 'hometunnel';
		o.rmempty = false;
		o.readonly = true;

		o = s.option(form.Value, 'domain', _('Domain'));
		o.placeholder = 'example.com';
		o.datatype = 'hostname';
		o.rmempty = false;
		o.readonly = true;

		o = s.option(form.Value, 'ctl_hostname', _('Switch subdomain'),
			_('Locked after binding (falls back to editable after a router reinstall, when the Cloudflare authorization is lost). To re-choose, unbind it first.'));
		o.placeholder = 'ctl';
		o.rmempty = false;
		o.readonly = true;

		s = m.section(form.NamedSection, 'global', 'hometunnel', _('On-demand parameters'));

		o = s.option(form.Value, 'default_ttl', _('Default TTL (min)'),
			_('How long the tunnel stays open after "on". Append ?min=N to the "on" link to override, up to the max.'));
		o.placeholder = '45';
		o.datatype = 'range(1,1440)';
		o.rmempty = false;

		o = s.option(form.Value, 'max_ttl', _('Max TTL (min)'),
			_('Upper limit for how long a single open keeps the tunnel on.'));
		o.placeholder = '240';
		o.datatype = 'range(1,1440)';
		o.rmempty = false;

		o = s.option(form.Value, 'renew_ttl', _('Auto-renew amount (min)'),
			_('Renewal amount when traffic is detected near TTL expiry (in-use auto-renew).'));
		o.placeholder = '45';
		o.datatype = 'range(1,1440)';
		o.rmempty = false;

		o = s.option(form.Flag, 'auto_renew', _('Auto-renew while in use'),
			_('While the tunnel has real traffic (new requests / active streams), keep renewing the TTL. Idle → auto close.'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'hard_cap', _('Hard cap (seconds)'),
			_('Local fuse: force-stop after this many seconds of continuous run; renewals do NOT extend it. 0 = unlimited (not recommended with auto-renew).'));
		o.placeholder = '14400';
		o.datatype = 'uinteger';
		o.rmempty = false;

		o = s.option(form.Value, 'poll_interval', _('Poll interval (s)'));
		o.placeholder = '10';
		o.datatype = 'range(5,120)';
		o.rmempty = false;

		o = s.option(form.Value, 'fail_threshold', _('Fail-closed threshold'),
			_('Stop the tunnel after this many consecutive switch-service fetch failures.'));
		o.placeholder = '3';
		o.datatype = 'range(1,10)';
		o.rmempty = false;

		o = s.option(form.Value, 'metrics_port', _('cloudflared metrics port'),
			_('Local Prometheus metrics port of cloudflared (traffic signal for auto-renew).'));
		o.placeholder = '20241';
		o.datatype = 'port';
		o.rmempty = false;

		o = s.option(form.ListValue, 'protocol', _('Edge protocol'),
			_('QUIC is default; switch to http2 if UDP 7844 is degraded/blocked on your line.'));
		o.value('auto', 'auto');
		o.value('quic', 'quic');
		o.value('http2', 'http2');
		o.default = 'auto';
		o.rmempty = false;

		/* form.Map 页: Save&Apply 下拉等元素也缺主题样式, 包一层挂作用域 */
		return m.render().then(function (node) { return htui.apply(node); });
	},

	/* 保存后应用模式联动 + 重启守护（参数生效） */
	handleSaveApply: function (ev, mode) {
		var Fn = L.bind(function () {
			fs.exec('/usr/share/hometunnel/hometunnel.sh', ['apply-mode']);
			document.removeEventListener('uci-applied', Fn);
		}, this);
		document.addEventListener('uci-applied', Fn);
		return this.super('handleSaveApply', [ev, mode]);
	}
});
