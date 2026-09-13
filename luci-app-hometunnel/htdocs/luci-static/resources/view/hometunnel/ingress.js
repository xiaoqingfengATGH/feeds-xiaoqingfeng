/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright (C) 2026 xiaoqingfeng <xiaoqingfengatgm@gmail.com> */
/* hometunnel ingress — 接入规则（UCI → config.yml） */

'use strict';
'require form';
'require fs';
'require uci';
'require view';
'require view.hometunnel.ui as htui';

return view.extend({
	render: function () {
		var m, s, o;

		m = new form.Map('hometunnel', _('HomeTunnel — Ingress Rules'),
			_('Each rule exposes one intranet service as <code>subdomain.domain</code> via the tunnel. Unmatched hostnames/paths always return 404.'));

		s = m.section(form.GridSection, 'ingress', _('Rules'));
		s.addremove = true;
		s.anonymous = true;
		s.sortable = true;
		s.nodescriptions = true;

		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'name', _('Name'));
		o.placeholder = 'nas';
		o.rmempty = false;

		o = s.option(form.Value, 'subdomain', _('Subdomain'));
		o.placeholder = 'nas';
		o.datatype = 'and(minlength(1),hostname)';
		o.rmempty = false;

		/* 公网入口: 本行规则对外的完整访问路径（协议+域名+路径正则）。
		   GridSection 行内单元格走 renderTextValue→textvalue()→E('td',…,value)，
		   字符串一律转义（rawhtml 不在这条路径上）——返回 DOM 节点才能携带链接/样式。
		   http/https 服务 = 可点击 https 链接; ssh/tcp 等显示主机名+协议徽标
		   （需 cloudflared Access/WARP 客户端，浏览器打不开）; path 正则第二行展示;
		   已停用规则半透明标注（入口未发布）。UCI 值一律经 textContent 赋值（天然转义）。 */
		o = s.option(form.DummyValue, '_public_entry', _('Public entry'));
		/* modal 编辑视图走 renderWidget→cfgvalue（纯文本）; 表格行内走 textvalue（DOM） */
		o.cfgvalue = function (sid) {
			var sub = uci.get('hometunnel', sid, 'subdomain');
			if (!sub) return '';
			var domain = uci.get('hometunnel', 'global', 'domain') || '';
			var pregex = uci.get('hometunnel', sid, 'path') || '';
			return (domain ? sub + '.' + domain : sub) + (pregex ? '  (path: ' + pregex + ')' : '');
		};
		o.textvalue = function (sid) {
			var sub = uci.get('hometunnel', sid, 'subdomain');
			if (!sub) return E('em', {}, '-');
			var svc = uci.get('hometunnel', sid, 'service') || '';
			var pregex = uci.get('hometunnel', sid, 'path') || '';
			var off = uci.get('hometunnel', sid, 'enabled') === '0';
			var domain = uci.get('hometunnel', 'global', 'domain') || '';
			var wrap = E('div', {});
			var main = off ? E('div', { 'style': 'opacity:.5' }) : wrap;
			if (off) wrap.appendChild(main);
			if (domain) {
				var host = sub + '.' + domain;
				if (/^https?:\/\//.test(svc))
					main.appendChild(E('a', { 'href': 'https://' + host, 'target': '_blank', 'rel': 'noopener', 'style': 'word-break:break-all' }, host));
				else {
					var scheme = svc.split(':')[0] || 'tcp';
					main.appendChild(E('span', { 'class': 'label', 'style': 'margin-right:6px;text-transform:uppercase' }, scheme));
					var hn = E('span', { 'style': 'word-break:break-all' }, host);
					hn.title = _('Non-HTTP service: connect with a cloudflared Access or WARP client using this hostname.');
					main.appendChild(hn);
				}
			} else {
				var em = E('span', {}, sub);
				main.appendChild(em);
				main.appendChild(E('div', { 'style': 'font-size:11px;opacity:.7' }, _('reachable after setup completes')));
			}
			if (pregex)
				main.appendChild(E('div', { 'style': 'font-family:monospace;font-size:11px;opacity:.8;word-break:break-all' }, 'path: ' + pregex));
			if (off)
				main.appendChild(E('div', { 'style': 'font-size:11px' }, _('Disabled — not published')));
			return wrap;
		};

		o = s.option(form.Value, 'service', _('Service URL'),
			_('cloudflared service syntax, e.g. <code>http://192.168.1.10:5000</code>, <code>ssh://192.168.1.10:22</code>, <code>tcp://…</code>'));
		o.placeholder = 'http://192.168.1.10:5000';
		o.rmempty = false;

		o = s.option(form.Value, 'path', _('Path regex'),
			_('Optional. Only forward matching paths, e.g. <code>^/api(/.*)?$</code>'));
		o.placeholder = '^/api(/.*)?$';
		o.rmempty = true;

		o = s.option(form.Value, 'http_host_header', _('Origin Host header'),
			_('Optional. Rewrite the Host header sent to the origin (needed behind a name-based reverse proxy).'));
		o.placeholder = 'nas.local';
		o.rmempty = true;

		o = s.option(form.Flag, 'no_tls_verify', _('Skip TLS verify'),
			_('Skip certificate verification for https origins (self-signed certs).'));
		o.rmempty = true;

		o = s.option(form.Value, 'connect_timeout', _('Connect timeout (s)'));
		o.placeholder = '30';
		o.datatype = 'uinteger';
		o.rmempty = true;

		/* form.Map 页: Save&Apply 下拉等元素也缺主题样式, 包一层挂作用域 */
		return m.render().then(function (node) { return htui.apply(node); });
	},

	/* 保存并应用后: 增量发布 DNS CNAME → 重建 config.yml → 平滑重启数据面。
	   uci-applied 由 ui.js apply 轮询成功时派发（apply_display 秒后整页刷新，
	   窗口内执行）; route 幂等，已有 CNAME 跳过 */
	load: function () {
		var HT = '/usr/share/hometunnel/hometunnel.sh';
		var self = this;
		document.addEventListener('uci-applied', function () {
			/* 绑定完成才有远端可发布; 未绑定时只 regen（向导会在部署时统一发布） */
			fs.exec(HT, ['probe']).then(function (res) {
				var st = null;
				try { st = JSON.parse((res.stdout || '').trim()); } catch (e) {}
				if (st && st.bound) {
					fs.exec(HT, ['job', 'route', HT, 'route']);
				}
				return fs.exec(HT, ['regen']);
			}).catch(function () {});
		});
		return uci.load('hometunnel');
	}
});
