/* SPDX-License-Identifier: Apache-2.0 */
/* HomePublish r9 certificates — 本机已申请证书的只读表；申请与续期在 ACME 中管理 */

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
		var state = data[1];
		var saved = (state && state.saved_config) ? state.saved_config : null;
		/* 被使用的证书靠前（排序与下拉一致，见 product.js sortInventory） */
		var inventory = api.sortInventory(Array.isArray(data[0].certificates) ? data[0].certificates : [], saved);
		var m, s, o;

		/* 计算每张证书被谁使用：入口默认 + 各服务绑定（继承→入口默认） */
		var usage = {};
		var users = function(ref) {
			if (!usage[ref]) {
				var list = [];
				if (saved && saved.default_certificate_ref === ref)
					list.push(_('入口默认'));
				(Array.isArray(saved && saved.services) ? saved.services : []).forEach(function(svc) {
					var bound = svc.certificate_mode === 'inherit' ? saved.default_certificate_ref : svc.certificate_ref;
					if (bound === ref) list.push(svc.hostname);
				});
				usage[ref] = list;
			}
			return usage[ref];
		};

		m = new form.JSONMap({ certificates: inventory }, _('HomePublish — 证书'),
			_('列出可使用的证书列表（来自ACME）'));

		/* 只读表：每张证书一行（同域名 RSA/ECC 为两行） */
		s = m.section(form.GridSection, 'certificates', _('已有证书'));
		s.readonly = true;
		s.modalizable = false;
		s.addremove = false;
		s.anonymous = true;
		s.nodescriptions = true;
		/* 只读库存表：表头与数据行均不生成操作列。 */
		s.renderHeaderRows = function() {
			return form.TableSection.prototype.renderHeaderRows.call(this, false);
		};
		s.renderRowActions = function() { return E([]); };

		var statusText = {
			within_validity: _('有效'),
			expired: _('已过期'),
			not_yet_valid: _('未生效'),
			unavailable: _('读取失败'),
			missing: _('文件缺失')
		};

		o = s.option(form.DummyValue, 'domain', _('证书域名'));
		o = s.option(form.DummyValue, 'key_type', _('密钥类型'));
		o.textvalue = function(sid) {
			var cert = this.map.data.get(this.map.config, sid);
			return cert ? String(cert.key_type || '').toUpperCase() : '-';
		};
		o = s.option(form.DummyValue, 'sans', _('包含域名（SAN）'));
		o.textvalue = function(sid) {
			var cert = this.map.data.get(this.map.config, sid);
			return (cert && Array.isArray(cert.sans) && cert.sans.length) ? cert.sans.join(', ') : '-';
		};
		o = s.option(form.DummyValue, 'not_after', _('有效期至'));
		o = s.option(form.DummyValue, 'status', _('状态'));
		o.textvalue = function(sid) {
			var cert = this.map.data.get(this.map.config, sid);
			return cert ? (statusText[cert.status] || cert.status || '-') : '-';
		};
		o = s.option(form.DummyValue, 'used_by', _('被哪些服务使用'));
		o.textvalue = function(sid) {
			var cert = this.map.data.get(this.map.config, sid);
			if (!cert) return '-';
			var list = users(cert.certificate_ref);
			return list.length ? list.join(', ') : _('未被使用');
		};

		return m.render();
	}
});
