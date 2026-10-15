/* SPDX-License-Identifier: Apache-2.0 */
/* HomePublish r9 entry — 入口设置（form.Map + NamedSection：监听端口 / 默认证书 / 发布策略） */

'use strict';
'require form';
'require view';
'require view.homepublish.product as api';

return view.extend({
	load: function() {
		return Promise.all([
			api.status().then(api.checked),
			api.certificates().then(api.checked)
		]).catch(function(e) { return [{ error: e.message }, { certificates: [] }]; });
	},

	render: function(data) {
		var state = data[0], inventory = api.sortInventory(Array.isArray(data[1].certificates) ? data[1].certificates : [], (state && state.saved_config) || null);
		var saved = (state && state.saved_config) ? JSON.parse(JSON.stringify(state.saved_config)) : api.defaults();
		saved.services = Array.isArray(saved.services) ? saved.services : [];
		var listener = saved.access_profile.listeners[0] || { family: 'ipv4', address: '192.168.1.2', interface: 'br-lan', zone: 'lan', protocol: 'tcp', internal_port: 8443, external_port: 18443 };
		saved.access_profile.listeners = [listener];
		var m, s, o;

		/* JSONMap 数据面：listener / policy 各一 NamedSection；其余 canonical 字段由 m.snapshot 承载 */
		var mapData = {
			cfg_listener: JSON.parse(JSON.stringify(listener)),
			cfg_policy: {
				default_certificate_ref: saved.default_certificate_ref || '',
				mode: (saved.publication_policy || {}).mode || 'continuous',
				temporary_duration: String((saved.publication_policy || {}).temporary_duration != null ? saved.publication_policy.temporary_duration : 1800),
				boot_restore: (saved.publication_policy || {}).boot_restore ? '1' : '0'
			}
		};

		m = new form.JSONMap(mapData, _('HomePublish — 入口设置'),
			_('专用 Nginx 入口监听与默认证书；无独立入口端口字段，内网端口即监听端口。保存不启动。'));

		/* canonical 基底 + 修订号：Save 组装与 revision 冲突检测必需（JSONMap 本身无此语义） */
		m.snapshot = saved;
		m.snapshotRevision = (state && state.saved_revision != null) ? state.saved_revision : null;

		/* listener 单条以 NamedSection 承载 */
		s = m.section(form.NamedSection, 'cfg_listener', 'listener', _('入口监听'));
		s.addremove = false;

		s.option(form.ListValue, 'family', _('地址族')).value('ipv4', 'IPv4');
		s.children[s.children.length - 1].value('ipv6', 'IPv6');
		s.children[s.children.length - 1].rmempty = false;

		o = s.option(form.Value, 'address', _('监听地址'));
		o.placeholder = '192.168.1.2';
		o.rmempty = false;
		o.description = _('IPv4 公网内网地址或 IPv6 全局地址；不填公网地址即未发布');

		o = s.option(form.Value, 'interface', _('接口'));
		o.placeholder = 'br-lan';
		o.rmempty = false;

		o = s.option(form.Value, 'zone', _('防火墙区域'));
		o.placeholder = 'lan';
		o.rmempty = false;

		o = s.option(form.Value, 'internal_port', _('内网端口（监听端口）'));
		o.placeholder = '8443';
		o.datatype = 'port';
		o.rmempty = false;

		o = s.option(form.Value, 'external_port', _('外网端口'));
		o.placeholder = '18443';
		o.datatype = 'port';
		o.rmempty = false;

		/* 默认证书与发布策略 */
		s = m.section(form.NamedSection, 'cfg_policy', 'policy', _('默认证书与发布策略'));

		o = s.option(form.ListValue, 'default_certificate_ref', _('入口默认已有证书'));
		o.value('', _('未选择'));
		for (var i = 0; i < inventory.length; i++)
			o.value(inventory[i].certificate_ref,
				inventory[i].domain + ' · ' + String(inventory[i].key_type || '').toUpperCase() + ' · ' + (inventory[i].not_after || '日期未知'));
		o.description = _('证书来自本机 ACME 已申请的证书。多个服务可共用同一张证书。');

		o = s.option(form.ListValue, 'mode', _('发布期限'));
		o.value('continuous', _('长期：直到停止'));
		o.value('temporary', _('临时：原截止不续延'));
		o.default = 'continuous';
		o.rmempty = false;

		o = s.option(form.Value, 'temporary_duration', _('临时时长（秒）'));
		o.placeholder = '1800';
		o.datatype = 'range(60,86400)';
		o.depends({ mode: 'temporary' });
		o.rmempty = false;

		o = s.option(form.Flag, 'boot_restore', _('开机恢复（默认关闭）'));
		o.default = '0';
		o.rmempty = false;
		o.description = _('开启后开机重新验证再恢复；手动停止锁与不确定的临时剩余时间始终阻止恢复');

		return m.render().then(function(node) {
			/* wrap 外层容器：map 与 actionBar 分层，map 重渲染不会洗掉操作条 */
			var holder = E('div', {}, [ node ]);
			return api.actionBar(holder, state, { save: true });
		});
	}
});
