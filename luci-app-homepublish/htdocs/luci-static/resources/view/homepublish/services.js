/* SPDX-License-Identifier: Apache-2.0 */
/* HomePublish r9 services — 接入服务（form.Map + GridSection，JSONMap 承载 RPC saved_config） */

'use strict';
'require form';
'require view';
'require view.homepublish.product as api';

return view.extend({
	load: function() {
		/* 证书库存 + 已保存配置都在 render 时经 JSONMap 呈现；status 提供 saved_config */
		return Promise.all([
			api.status().then(api.checked),
			api.certificates().then(api.checked)
		]).catch(function(e) { return [{ error: e.message }, { certificates: [] }]; });
	},

	render: function(data) {
		var state = data[0], inventory = api.sortInventory(Array.isArray(data[1].certificates) ? data[1].certificates : [], (state && state.saved_config) || null);
		var saved = (state && state.saved_config) ? JSON.parse(JSON.stringify(state.saved_config)) : api.defaults();
		var m, s, o;

		/* JSONMap 数据面：services 数组为 GridSection 行；其余 canonical 字段不进表单，
		   由 m.snapshot 承载，Save 时经 collectConfig() 重组为 canonical 提交 RPC save。 */
		var mapData = { services: (Array.isArray(saved.services) ? saved.services : []).map(function(svc) {
			var row = JSON.parse(JSON.stringify(svc));
			row.backend_url = (svc.backend && svc.backend.port != null)
				? ((svc.backend.addressFamily === 'ipv6' ? '[' + svc.backend.host + ']' : svc.backend.host) + ':' + svc.backend.port)
				: '';
			if (svc.certificate_mode === 'inherit' || !svc.certificate_ref)
				row.certificate_ref = '';
			row.management = !!(svc.authentication_review && svc.authentication_review.management);
			return row;
		}) };

		m = new form.JSONMap(mapData, _('HomePublish — 接入服务'),
			_('参与下次发布仅修改配置；保存不启动，应用时整组短暂停机。后端保持权威校验。'));

		/* canonical 基底 + 修订号：Save 组装与 revision 冲突检测必需（JSONMap 本身无此语义） */
		m.snapshot = saved;
		m.snapshotRevision = (state && state.saved_revision != null) ? state.saved_revision : null;

		s = m.section(form.GridSection, 'services', _('服务规则'));
		s.addremove = true;
		s.anonymous = true;
		s.sortable = true;
		s.nodescriptions = true;
		s.modalizable = true;
		s.modaltitle = function(sid) {
			var svc = this.map.data.get(this.map.config, sid);
			return (svc && svc.hostname) ? svc.hostname : _('新服务');
		};

		o = s.option(form.Flag, 'enabled', _('参与发布'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'name', _('名称'));
		o.placeholder = 'NAS';
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.Value, 'hostname', _('域名'));
		o.placeholder = 'nas.example.test';
		o.datatype = 'hostname';
		o.rmempty = false;

		o = s.option(form.Value, 'backend_url', _('家庭 HTTP 后端'));
		o.placeholder = 'http://192.168.1.10:8080';
		o.rmempty = false;
		o.description = _('仅支持无凭据的 HTTP 根地址，如 http://192.168.1.10:8080');
		/* 表格列显示 host:port；modal 编辑原始 URL */
		o.cfgvalue = function(sid) {
			var svc = this.map.data.get(this.map.config, sid);
			if (!svc || !svc.backend) return '';
			var b = svc.backend;
			return (b.addressFamily === 'ipv6' ? '[' + b.host + ']' : b.host) + ':' + b.port;
		};
		o.textvalue = function(sid) { return this.cfgvalue(sid); };
		o.write = function(sid, value) {
			var u;
			try { u = new URL(value); } catch (e) { throw new TypeError(_('后端应为 HTTP 根地址')); }
			if (u.protocol !== 'http:' || u.username || u.password || u.pathname !== '/' || u.search || u.hash)
				throw new TypeError(_('仅支持无凭据的 HTTP 根地址'));
			var h = u.hostname.replace(/^\[|\]$/g, '');
			var svc = this.map.data.get(this.map.config, sid);
			svc.backend = {
				addressFamily: h.includes(':') ? 'ipv6' : (/^\d+\.\d+\.\d+\.\d+$/.test(h) ? 'ipv4' : 'hostname'),
				host: h,
				port: Number(u.port || 80),
				/* allowed_ranges 空数组守卫：未填写时不携带，交给后端 canonical 校验 */
				allowed_ranges: (svc.backend && Array.isArray(svc.backend.allowed_ranges)) ? svc.backend.allowed_ranges : []
			};
		};
		o.remove = function() {};

		/* r8 既有字段：允许的家庭网段（每行/逗号分隔 CIDR）；canonical 要求至少 1 条 */
		o = s.option(form.Value, 'allowed_ranges', _('允许的家庭网段'));
		o.placeholder = '192.168.1.0/24, fd00::/64';
		o.rmempty = false;
		o.modalonly = true;
		o.description = _('允许访问此服务的来源网段，每行或逗号分隔的 CIDR；后端保持权威校验。');
		o.cfgvalue = function(sid) {
			var svc = this.map.data.get(this.map.config, sid);
			return (svc && svc.backend && Array.isArray(svc.backend.allowed_ranges)) ? svc.backend.allowed_ranges.join(', ') : '';
		};
		o.write = function(sid, value) {
			var svc = this.map.data.get(this.map.config, sid);
			if (!svc.backend) svc.backend = { addressFamily: 'ipv4', host: '', port: 80, allowed_ranges: [] };
			svc.backend.allowed_ranges = String(value || '').split(/[\n,]+/).map(function(x) { return x.trim(); }).filter(Boolean);
		};
		o.remove = function() {};

		o = s.option(form.ListValue, 'certificate_ref', _('证书'));
		o.value('', _('继承入口默认'));
		for (var i = 0; i < inventory.length; i++)
			o.value(inventory[i].certificate_ref,
				inventory[i].domain + ' · ' + String(inventory[i].key_type || '').toUpperCase() + ' · ' + (inventory[i].not_after || '日期未知'));
		o.rmempty = true;
		/* 行内只读展示解析后的证书；写入仍落到行数据 */
		o.textvalue = function(sid) {
			var svc = this.map.data.get(this.map.config, sid);
			var ref = svc ? (svc.certificate_mode === 'inherit' || !svc.certificate_ref ? '' : svc.certificate_ref) : '';
			if (!ref) return _('继承入口默认');
			var c = null;
			for (var j = 0; j < inventory.length; j++)
				if (inventory[j].certificate_ref === ref) { c = inventory[j]; break; }
			return c ? (c.domain + ' · ' + String(c.key_type || '').toUpperCase()) : ref;
		};
		o.write = function(sid, value) {
			var svc = this.map.data.get(this.map.config, sid);
			if (value) { svc.certificate_ref = value; svc.certificate_mode = 'override'; }
			else { delete svc.certificate_ref; svc.certificate_mode = 'inherit'; }
		};

		o = s.option(form.Flag, 'management', _('管理服务'));
		o.rmempty = false;
		o.modalonly = true;
		o.cfgvalue = function(sid) {
			var svc = this.map.data.get(this.map.config, sid);
			return (svc && svc.authentication_review && svc.authentication_review.management) ? '1' : '0';
		};
		o.write = function(sid, value) {
			var svc = this.map.data.get(this.map.config, sid);
			/* 同步行上的 management，collectConfig 以行数据为准 */
			svc.management = value;
			svc.authentication_review = {
				authentication: 'confirmed',
				management: value === '1'
			};
		};

		return m.render().then(function(node) {
			/* wrap 外层容器：map 与 actionBar 分层，map 重渲染不会洗掉操作条 */
			var holder = E('div', {}, [ node ]);
			return api.actionBar(holder, state, { save: true });
		});
	}
});
