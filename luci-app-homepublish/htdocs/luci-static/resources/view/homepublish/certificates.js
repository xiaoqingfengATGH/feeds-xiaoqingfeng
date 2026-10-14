/* SPDX-License-Identifier: Apache-2.0 */
/* HomePublish r9 certificates — 证书库存只读表（certificates RPC；不显示私钥） */

'use strict';
'require form';
'require view';
'require view.homepublish.product as api';

return view.extend({
	load: function() {
		return Promise.all([
			api.certificates().then(api.checked),
			api.status().then(api.checked)
		]).catch(function(e) { return [{ certificates: [], error: e.message }, { error: e.message }]; });
	},

	render: function(data) {
		var inventory = Array.isArray(data[0].certificates) ? data[0].certificates : [];
		var state = data[1];
		var saved = (state && state.saved_config) ? state.saved_config : null;
		var m, s, o;

		m = new form.JSONMap({ certificates: inventory }, _('HomePublish — 证书库存'),
			_('证书身份、SAN、有效期与被哪些服务使用。库存只证明 SAN 覆盖和有效期，不代表完整 TLS / CA 链验收；不显示私钥。'));
		m.readonly = true;

		/* 只读表：每张证书一行 */
		s = m.section(form.GridSection, 'certificates', _('已有证书'));
		s.readonly = true;
		s.addremove = false;
		s.anonymous = true;
		s.nodescriptions = true;

		o = s.option(form.DummyValue, 'domain', _('身份（ACME 域名）'));
		o = s.option(form.DummyValue, 'sans', _('SAN'));
		o.textvalue = function(sid) {
			var cert = this.map.data.get(this.map.config, sid);
			return (cert && Array.isArray(cert.sans)) ? cert.sans.join(', ') : '-';
		};
		o = s.option(form.DummyValue, 'key_type', _('密钥类型'));
		o.textvalue = function(sid) {
			var cert = this.map.data.get(this.map.config, sid);
			return cert ? String(cert.key_type || '').toUpperCase() : '-';
		};
		o = s.option(form.DummyValue, 'not_after', _('有效期至'));
		o = s.option(form.DummyValue, 'status', _('库存状态'));
		o = s.option(form.DummyValue, 'used_by', _('被哪些服务使用'));
		o.textvalue = function(sid) {
			var cert = this.map.data.get(this.map.config, sid);
			if (!cert || !saved) return '-';
			var ref = cert.certificate_ref, users = [];
			if (saved.default_certificate_ref === ref)
				users.push(_('入口默认'));
			(saved.services || []).forEach(function(svc) {
				var bound = svc.certificate_mode === 'inherit' ? saved.default_certificate_ref : svc.certificate_ref;
				if (bound === ref) users.push(svc.hostname);
			});
			return users.length ? users.join(', ') : _('未被使用');
		};

		return m.render();
	}
});
