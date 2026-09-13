/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright (C) 2026 xiaoqingfeng <xiaoqingfengatgm@gmail.com> */
/* hometunnel diagram — 配置驱动的实时拓扑图（控制面/数据面双带） */

'use strict';
'require fs';
'require poll';
'require rpc';
'require uci';
'require view';
'require view.hometunnel.ui as htui';

var HT = '/usr/share/hometunnel/hometunnel.sh';

var callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

function getServiceRunning(name) {
	return L.resolveDefault(callServiceList(name), {}).then(function (res) {
		try {
			return res[name].instances[name].running;
		} catch (e) {
			return false;
		}
	});
}

function getBackendStatus() {
	return fs.exec(HT, ['status']).then(function (res) {
		return (res.code === 0 && res.stdout) ? res.stdout : '';
	}).catch(function () { return ''; });
}

function parseCtlJson(text) {
	var m = (text || '').match(/control:\s+(\{.*\})/);
	if (!m) return null;
	try { return JSON.parse(m[1]); } catch (e) { return null; }
}

/* ---------- SVG helpers ---------- */

function esc(s) {
	return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
		.replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/* 大号云朵（约 164x102）：先整组描边再整组填充，内部弧线被覆盖只留外轮廓 */
function cloud(cx, cy, fill, stroke) {
	var shapes = function (f, st, w) {
		var s = (st ? ' stroke="' + st + '" stroke-width="' + w + '"' : '');
		return '<circle cx="-52" cy="12" r="30" fill="' + f + '"' + s + '/>' +
			'<circle cx="0" cy="-18" r="42" fill="' + f + '"' + s + '/>' +
			'<circle cx="52" cy="12" r="30" fill="' + f + '"' + s + '/>' +
			'<rect x="-70" y="0" width="140" height="38" rx="19" fill="' + f + '"' + s + '/>';
	};
	return '<g transform="translate(' + cx + ',' + cy + ')">' +
		shapes(stroke, stroke, 3) + shapes(fill, null, 0) + '</g>';
}

function badge(x, y, w, text, fill, color) {
	return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="22" rx="11" fill="' + fill + '"/>' +
		'<text x="' + (x + w / 2) + '" y="' + (y + 15) + '" text-anchor="middle" font-size="11.5" font-weight="600" fill="' + color + '">' + esc(text) + '</text>';
}

/* cloudflared service URL -> "host:port" 显示形式 */
function svcHost(svc) {
	var m = String(svc || '').match(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^\/]+)/);
	return m ? m[1] : String(svc || '');
}

/* ---------- 拓扑 SVG 生成（配置 + 状态驱动） ---------- */

function buildSvg(cfg, st) {
	var always = (cfg.mode === 'alwayson');
	var active = !!(st.on || always);
	var GREEN = '#059669', GRAY = '#94a3b8', BLUE = '#2563eb';
	var dataColor = active ? GREEN : GRAY;

	var s = '<svg viewBox="0 0 1060 620" xmlns="http://www.w3.org/2000/svg">'
		+ '<defs>'
		+ '<marker id="dg-aB" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="' + BLUE + '"/></marker>'
		+ '<marker id="dg-aG" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="' + dataColor + '"/></marker>'
		+ '</defs>';

	/* 背景双带 */
	var ctlOp = always ? ' opacity="0.38"' : '';
	s += '<rect x="16" y="46" width="1028" height="234" rx="12" fill="#eff6ff"' + ctlOp + '/>';
	s += '<rect x="16" y="336" width="1028" height="268" rx="12" fill="#ecfdf5"/>';
	s += '<text x="34" y="72" font-size="13" font-weight="700" fill="#60a5fa">' + esc(_('Remote Switch')) + '</text>';
	s += '<text x="34" y="362" font-size="13" font-weight="700" fill="#34d399">' + esc(_('Data traffic')) + '</text>';
	if (always)
		s += '<text x="530" y="72" font-size="12" fill="#94a3b8" text-anchor="middle">' + esc(_('Always-on mode · remote switch not used')) + '</text>';

	/* 手机（控制面入口，任意设备书签） */
	s += '<g' + (always ? ' opacity="0.38"' : '') + '>'
		+ '<rect x="60" y="102" width="84" height="138" rx="13" fill="#fff" stroke="#334155" stroke-width="2"/>'
		+ '<rect x="68" y="114" width="68" height="96" rx="4" fill="#f1f5f9"/>'
		+ '<text x="102" y="132" text-anchor="middle" font-size="11" fill="#64748b">' + esc(_('Bookmark')) + '</text>'
		+ '<rect x="72" y="142" width="60" height="22" rx="11" fill="#059669"/>'
		+ '<text x="102" y="157" text-anchor="middle" font-size="11.5" font-weight="700" fill="#fff">⚡ ON</text>'
		+ '<rect x="72" y="170" width="60" height="22" rx="11" fill="#e2e8f0"/>'
		+ '<text x="102" y="185" text-anchor="middle" font-size="11.5" font-weight="700" fill="#64748b">⏹ OFF</text>'
		+ '<text x="102" y="262" text-anchor="middle" font-size="12.5" fill="#475569">' + esc(_('Any device · no app needed')) + '</text>'
		+ '</g>';

	/* Worker 云 */
	s += cloud(438, 168, '#fff', always ? GRAY : BLUE);
	s += '<text x="438" y="102" text-anchor="middle" font-size="13" font-weight="700" fill="#334155">' + esc(_('Remote switch service')) + '</text>';
	s += '<text x="438" y="176" text-anchor="middle" font-size="13.5" font-weight="700" fill="' + (always ? GRAY : BLUE) + '">' + esc(cfg.ctlDomain) + '</text>';
	if (!always) {
		var btxt = st.on ? _('ON · %d min left').format(st.remainMin) : 'OFF';
		s += badge(380, 216, 116, btxt, st.on ? '#d1fae5' : '#f1f5f9', st.on ? '#065f46' : '#64748b');
	}

	/* 路由器（跨两带） */
	s += '<rect x="662" y="108" width="206" height="352" rx="16" fill="#fff" stroke="#334155" stroke-width="2"/>'
		+ '<line x1="694" y1="108" x2="678" y2="80" stroke="#334155" stroke-width="2"/><circle cx="678" cy="78" r="4" fill="#334155"/>'
		+ '<line x1="836" y1="108" x2="852" y2="80" stroke="#334155" stroke-width="2"/><circle cx="852" cy="78" r="4" fill="#334155"/>'
		+ '<text x="765" y="136" text-anchor="middle" font-size="13.5" font-weight="700" fill="#334155">' + esc(_('OpenWrt router')) + '</text>'
		+ '<rect x="682" y="152" width="166" height="60" rx="8" fill="#eff6ff" stroke="#93c5fd" stroke-width="1.5"/>'
		+ '<text x="765" y="176" text-anchor="middle" font-size="12.5" font-weight="700" fill="#1d4ed8">' + esc(_('Switch controller')) + '</text>'
		+ '<text x="765" y="196" text-anchor="middle" font-size="11" fill="#64748b">' + esc(_('Polls commands every %ds').format(cfg.pollIv)) + '</text>';

	var cfStroke = active ? GREEN : '#cbd5e1',
	    cfFill = active ? '#d1fae5' : '#f8fafc',
	    cfText = active ? '#065f46' : '#94a3b8';
	s += '<g' + (active ? ' class="dg-pulse"' : '') + '>'
		+ '<rect x="682" y="384" width="166" height="60" rx="8" fill="' + cfFill + '" stroke="' + cfStroke + '" stroke-width="2"/></g>'
		+ '<text x="765" y="408" text-anchor="middle" font-size="12.5" font-weight="700" fill="' + cfText + '">cloudflared</text>'
		+ '<text x="765" y="428" text-anchor="middle" font-size="11" fill="' + cfText + '">' + esc(_('Tunnel process')) + '</text>'
		+ '<line x1="765" y1="216" x2="765" y2="378" stroke="#94a3b8" stroke-width="1.5" stroke-dasharray="4 4" marker-end="url(#dg-aG)"/>'
		+ '<text x="776" y="300" font-size="11" fill="#64748b">' + esc(_('start / stop')) + '</text>';

	/* ①② 控制信令 */
	if (!always) {
		s += '<line x1="150" y1="170" x2="346" y2="170" stroke="' + BLUE + '" stroke-width="2.5" marker-end="url(#dg-aB)"/>'
			+ '<text x="248" y="158" text-anchor="middle" font-size="12.5" font-weight="700" fill="' + BLUE + '">' + esc(_('① Bookmark ON / OFF')) + '</text>'
			+ '<text x="248" y="190" text-anchor="middle" font-size="10.5" fill="#64748b">/on?key=… · /off?key=…</text>'
			+ '<line x1="528" y1="170" x2="654" y2="170" stroke="' + BLUE + '" stroke-width="2" stroke-dasharray="6 5" marker-end="url(#dg-aB)" marker-start="url(#dg-aB)"/>'
			+ '<text x="592" y="158" text-anchor="middle" font-size="12" font-weight="600" fill="' + BLUE + '">' + esc(_('② Poll commands')) + '</text>';
	}

	/* 数据面：外网设备 */
	s += '<rect x="62" y="408" width="112" height="72" rx="6" fill="#fff" stroke="#334155" stroke-width="2"/>'
		+ '<text x="118" y="440" text-anchor="middle" font-size="12.5" fill="#475569">' + esc(_('Browser')) + '</text>'
		+ '<polygon points="52,480 184,480 194,496 42,496" fill="#e2e8f0" stroke="#94a3b8"/>'
		+ '<text x="118" y="516" text-anchor="middle" font-size="12.5" fill="#475569">' + esc(_('Any external device')) + '</text>';

	/* 数据面：CF 边缘 */
	s += cloud(438, 442, '#fff', '#34d399');
	s += '<text x="438" y="376" text-anchor="middle" font-size="13" font-weight="700" fill="#334155">' + esc(_('Cloudflare edge network')) + '</text>';
	var hostList = cfg.ingress.map(function (r) { return r.host; });
	var hostText = hostList.join('  ');
	if (hostText.length > 26)
		hostText = _('%d domains').format(hostList.length);
	s += '<text x="438" y="448" text-anchor="middle" font-size="11.5" fill="#059669" font-weight="600">' + esc(hostText || '—') + '</text>';

	/* ③④ 数据流（三段） */
	var dash = active ? '' : ' stroke-dasharray="7 6"';
	var flowCls = active ? ' class="dg-flow"' : '';
	var seg = function (x1, x2, arrow) {
		return '<line' + flowCls + ' x1="' + x1 + '" y1="446" x2="' + x2 + '" y2="446" stroke="' + dataColor + '" stroke-width="3"' + dash + (arrow ? ' marker-end="url(#dg-aG)"' : '') + '/>';
	};
	s += seg(196, 346, false) + seg(528, 654, true) + seg(872, 896, true);
	s += '<text x="438" y="502" text-anchor="middle" font-size="11.5" fill="' + (active ? GREEN : '#94a3b8') + '">'
		+ (active ? esc(_('Auto-renew +%d min on traffic').format(cfg.ttl)) : esc(_('Tunnel off · unreachable'))) + '</text>';
	s += '<text x="252" y="434" text-anchor="middle" font-size="11.5" fill="' + (active ? GREEN : '#94a3b8') + '">' + esc(_('③ HTTPS')) + '</text>';

	/* 内网 LAN 容器（最多 3 条 + 溢出计数） */
	s += '<rect x="900" y="352" width="140" height="244" rx="10" fill="#fff" stroke="#94a3b8" stroke-width="1.5" stroke-dasharray="5 4"/>'
		+ '<text x="970" y="374" text-anchor="middle" font-size="12" font-weight="700" fill="#64748b">' + esc(_('LAN')) + '</text>';
	var y = 386, shown = 0;
	cfg.ingress.forEach(function (r) {
		if (shown >= 3) return;
		s += '<g opacity="' + (active ? '1' : '0.5') + '">'
			+ '<rect x="910" y="' + y + '" width="120" height="58" rx="6" fill="' + (active ? '#ecfdf5' : '#f8fafc') + '" stroke="' + (active ? '#6ee7b7' : '#e2e8f0') + '" stroke-width="1.5"/>'
			+ '<text x="970" y="' + (y + 20) + '" text-anchor="middle" font-size="11.5" font-weight="700" fill="#334155">' + esc(r.name) + '</text>'
			+ '<text x="970" y="' + (y + 36) + '" text-anchor="middle" font-size="10" fill="#059669">' + esc(r.host) + '</text>'
			+ '<text x="970" y="' + (y + 51) + '" text-anchor="middle" font-size="10.5" fill="#64748b">→ ' + esc(r.to) + '</text>'
			+ '</g>';
		y += 68;
		shown++;
	});
	if (!cfg.ingress.length)
		s += '<text x="970" y="420" text-anchor="middle" font-size="11" fill="#94a3b8">' + esc(_('No ingress rules yet')) + '</text>';
	else if (cfg.ingress.length > 3)
		s += '<text x="970" y="' + (y + 4) + '" text-anchor="middle" font-size="11" fill="#64748b">' + esc(_('+%d more').format(cfg.ingress.length - 3)) + '</text>';

	s += '</svg>';
	return s;
}

function placeholderSvg() {
	return '<svg viewBox="0 0 1060 620" xmlns="http://www.w3.org/2000/svg">'
		+ '<rect x="16" y="46" width="1028" height="558" rx="12" fill="#f8fafc" stroke="#e2e8f0"/>'
		+ '<g opacity="0.35">'
		+ '<rect x="120" y="140" width="84" height="130" rx="13" fill="#fff" stroke="#94a3b8" stroke-width="2"/>'
		+ cloud(430, 180, '#fff', '#94a3b8')
		+ '<rect x="600" y="120" width="200" height="330" rx="16" fill="#fff" stroke="#94a3b8" stroke-width="2"/>'
		+ cloud(430, 440, '#fff', '#94a3b8')
		+ '</g>'
		+ '<rect x="330" y="250" width="400" height="120" rx="12" fill="#fff" stroke="#f59e0b" stroke-width="2"/>'
		+ '<text x="530" y="296" text-anchor="middle" font-size="16" font-weight="700" fill="#b45309">' + esc(_('Wizard incomplete - topology pending')) + '</text>'
		+ '<text x="530" y="326" text-anchor="middle" font-size="12.5" fill="#92400e">' + esc(_('Finish the wizard to see your live topology here.')) + '</text>'
		+ '</svg>';
}

/* ---------- 视图 ---------- */

return view.extend({
	load: function () {
		return uci.load('hometunnel');
	},

	render: function () {
		var self = this;

		var domain = uci.get('hometunnel', 'global', 'domain') || '';
		var ctlHost = uci.get('hometunnel', 'global', 'ctl_hostname') || 'ctl';
		var mode = uci.get('hometunnel', 'global', 'mode') || 'ondemand';
		var configured = !!uci.get('hometunnel', 'global', 'tunnel_id');

		var container = htui.apply(E('div', {}, [
			E('h2', {}, _('HomeTunnel')),
			E('div', {
				'class': 'd-flex align-items-center flex-wrap',
				'style': 'gap:.5rem;padding:.6rem 1rem;border-radius:.5rem;'
					+ 'background:linear-gradient(rgba(52,140,212,.14),rgba(52,140,212,.14)),rgba(54,64,74,.9);'
					+ 'border:1px solid rgba(52,140,212,.3);'
					+ 'color:inherit'
			}, [
				E('span', { 'class': 'dripicons-graph-line', 'style': 'font-size:16px;margin-right:8px;color:#348cd4' }),
				_('Live topology generated from your configuration.')
			])
		]));

		/* 动画样式（数据流滚动 + cloudflared 呼吸） */
		container.appendChild(E('style', {}, ''
			+ '.dg-flow{stroke-dasharray:9 7;animation:dgdash 1.1s linear infinite}'
			+ '@keyframes dgdash{to{stroke-dashoffset:-16}}'
			+ '.dg-pulse{animation:dgp 1.8s ease-in-out infinite}'
			+ '@keyframes dgp{50%{opacity:.5}}'));

		if (!configured) {
			container.appendChild(E('div', { 'class': 'alert-message warning' }, [
				E('p', {}, _('Setup is not complete. Run the wizard first.')),
				E('a', {
					'class': 'btn cbi-button cbi-button-apply important',
					'href': L.url('admin', 'services', 'hometunnel', 'wizard')
				}, _('Open Wizard'))
			]));
			var phWrap = E('div', { 'style': 'overflow-x:auto' });
			container.appendChild(E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Tunnel Topology')),
				phWrap
			]));
			phWrap.innerHTML = placeholderSvg();
			return container;
		}

		/* 配置快照 */
		var ctlDomain = ctlHost + '.' + domain;
		var cfg = {
			domain: domain,
			ctlDomain: ctlDomain,
			mode: mode,
			ttl: parseInt(uci.get('hometunnel', 'global', 'default_ttl') || '45', 10),
			hardCapH: Math.round(parseInt(uci.get('hometunnel', 'global', 'hard_cap') || '14400', 10) / 3600),
			pollIv: parseInt(uci.get('hometunnel', 'global', 'poll_interval') || '10', 10),
			ingress: uci.sections('hometunnel', 'ingress').filter(function (sec) {
				return sec.enabled !== '0';
			}).map(function (sec) {
				return {
					name: sec.name || sec.subdomain || '?',
					host: (sec.subdomain || '') + '.' + domain,
					to: svcHost(sec.service)
				};
			})
		};

		var capText = cfg.hardCapH > 0
			? _('auto-off after %dh hard cap').format(cfg.hardCapH)
			: _('no hard cap');

		/* 拓扑区 */
		var wrap = E('div', { 'style': 'overflow-x:auto' });
		container.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Tunnel Topology')),
			wrap,
			E('div', {
				'style': 'display:flex;gap:16px;flex-wrap:wrap;margin-top:8px;font-size:12px;color:#64748b'
			}, [
				E('span', {}, [E('b', { 'style': 'color:#2563eb' }, '●'), ' ' + _('Switch signaling')]),
				E('span', {}, [E('b', { 'style': 'color:#059669' }, '●'), ' ' + _('Traffic (HTTPS)')]),
				E('span', {}, '↻ ' + _('Auto-renew +%d min on traffic').format(cfg.ttl)),
				E('span', {}, '⏹ ' + capText)
			])
		]));

		return Promise.all([
			getServiceRunning('hometunnel'),
			getServiceRunning('hometunnel-ctl'),
			getBackendStatus(),
			fs.read('/etc/hometunnel/ctl.key').catch(function () { return null; })
		]).then(L.bind(function (data) {
			var ctlKey = (data[3] || '').trim();
			var ctlJson = parseCtlJson(data[2]);

			/* 外网开关 URL 区（ondemand + key） */
			if (mode === 'ondemand' && ctlKey) {
				var onUrl = 'https://' + ctlDomain + '/on?key=' + encodeURIComponent(ctlKey);
				var offUrl = 'https://' + ctlDomain + '/off?key=' + encodeURIComponent(ctlKey);

				var mkUrlRow = function (url, label) {
					var code = E('code', {
						'style': 'background:rgba(0,0,0,.3);border:1px solid rgba(255,255,255,.12);border-radius:4px;' +
							'padding:4px 8px;font-size:12.5px;word-break:break-all;display:inline-block;max-width:100%;color:#a9b7c6'
					}, url);
					var btn = E('button', { 'class': 'btn cbi-button' }, label);
					btn.addEventListener('click', function (ev) {
						ev.preventDefault();
						if (navigator.clipboard && navigator.clipboard.writeText)
							navigator.clipboard.writeText(url);
						var old = btn.textContent;
						btn.textContent = _('Copied ✓');
						window.setTimeout(function () { btn.textContent = old; }, 900);
					});
					return E('div', {
						'style': 'display:flex;align-items:center;gap:8px;margin:6px 0;flex-wrap:wrap'
					}, [code, btn]);
				};

				container.appendChild(E('div', { 'class': 'cbi-section' }, [
					E('h3', {}, _('Remote Switch')),
					E('div', { 'class': 'cbi-section-descr' },
						_('Save these as bookmarks on any device to open/close the tunnel from anywhere:')),
					mkUrlRow(onUrl, _('Copy "ON" link')),
					mkUrlRow(offUrl, _('Copy "OFF" link'))
				]));
			}

			/* 状态驱动的 SVG（sig 变化才重绘，避免动画每 10s 重启） */
			var lastSig = null;
			var apply = function (tunnelRunning, ctlRunning, cj) {
				var on = (mode === 'alwayson') ? true : !!(cj && cj.on === true);
				var st = {
					on: on,
					tunnelRunning: tunnelRunning,
					ctlRunning: ctlRunning,
					remainMin: (cj && cj.exp) ? Math.max(0, Math.round((cj.exp - Date.now()) / 60000)) : 0
				};
				var sig = JSON.stringify([on, tunnelRunning, ctlRunning, st.remainMin, cfg.ingress.length]);
				if (sig === lastSig) return;
				lastSig = sig;
				wrap.innerHTML = buildSvg(cfg, st);
			};
			apply(data[0], data[1], ctlJson);

			poll.add(function () {
				return Promise.all([
					getServiceRunning('hometunnel'),
					getServiceRunning('hometunnel-ctl'),
					getBackendStatus()
				]).then(function (d) {
					apply(d[0], d[1], parseCtlJson(d[2]));
				});
			}, 10);

			return container;
		}, this));
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
