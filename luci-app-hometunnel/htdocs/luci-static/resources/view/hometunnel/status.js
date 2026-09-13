/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright (C) 2026 xiaoqingfeng <xiaoqingfeng@yeah.net> */
/* hometunnel status — 状态页 + 外网开/关 */

'use strict';
'require fs';
'require poll';
'require rpc';
'require uci';
'require view';
'require view.hometunnel.ui as htui';

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

/* 后端 status（含控制面 JSON） */
function getBackendStatus() {
	return fs.exec('/usr/share/hometunnel/hometunnel.sh', ['status']).then(function (res) {
		return (res.code === 0 && res.stdout) ? res.stdout : '';
	}).catch(function () { return ''; });
}

function parseCtlJson(text) {
	var m = (text || '').match(/control:\s+(\{.*\})/);
	if (!m) return null;
	try { return JSON.parse(m[1]); } catch (e) { return null; }
}

/* 后端 status 的 cf-tunnel 行: exists|missing|auth-failed|unknown:* */
function parseCfState(text) {
	var m = (text || '').match(/cf-tunnel:\s+(\S+)/);
	return m ? m[1] : '';
}

return view.extend({
	load: function () {
		/* uci.load 仅预载缓存；render 里用全局 uci.get() 读取 */
		return uci.load('hometunnel');
	},

	render: function () {
		return Promise.all([
			getServiceRunning('hometunnel'),
			getServiceRunning('hometunnel-ctl'),
			getBackendStatus(),
			fs.read('/etc/hometunnel/ctl.key').catch(function () { return null; })
		]).then(L.bind(function (data) {
			var tunnelRunning = data[0],
			    ctlRunning = data[1],
			    backendStatus = data[2] || '',
			    ctlKey = (data[3] || '').trim();

			var mode = uci.get('hometunnel', 'global', 'mode') || 'ondemand';
			var domain = uci.get('hometunnel', 'global', 'domain') || '';
			var ctlHost = uci.get('hometunnel', 'global', 'ctl_hostname') || 'ctl';
			var ctlUrl = domain ? ('https://' + ctlHost + '.' + domain) : '';
			var defaultTtl = uci.get('hometunnel', 'global', 'default_ttl') || '45';
			var configured = !!uci.get('hometunnel', 'global', 'tunnel_id');

			var ctlJson = parseCtlJson(backendStatus);
			var cfState = parseCfState(backendStatus);

			var descrChildren = [
				E('span', { 'class': 'dripicons-cloud', 'style': 'font-size:16px;margin-right:8px;vertical-align:-2px;color:#348cd4' }),
				_('HomeLede intranet exposure via a free Cloudflare Tunnel.')
			];
			if (ctlUrl) {
				descrChildren.push(E('span', { 'class': 'mx-1' }, '·'));
				descrChildren.push(E('a', {
					'href': ctlUrl, 'target': '_blank', 'rel': 'noopener',
					'style': 'text-decoration:underline'
				}, ctlUrl));
			}

			var container = htui.apply(E('div', {}, [
				E('h2', {}, _('HomeTunnel')),
				E('div', {
					'class': 'd-flex align-items-center flex-wrap',
					'style': 'gap:.5rem;padding:.6rem 1rem;border-radius:.5rem;'
						+ 'background:linear-gradient(rgba(52,140,212,.14),rgba(52,140,212,.14)),rgba(54,64,74,.9);'
						+ 'border:1px solid rgba(52,140,212,.3);'
						+ 'color:inherit'
				}, descrChildren)
			]));

			if (!configured) {
				container.appendChild(E('div', { 'class': 'alert-message warning' }, [
					E('p', {}, _('Setup is not complete. Open Access to run setup.')),
					E('a', { 'class': 'btn cbi-button cbi-button-apply important', 'href': L.url('admin', 'services', 'hometunnel', 'wizard') }, _('Open Access'))
				]));
				return container;
			}

			/* ---- CF 侧隧道异常横幅（被删/凭据失效）---- */
		if (cfState === 'missing' || cfState === 'auth-failed') {
			container.appendChild(E('div', { 'class': 'alert-message warning' }, [
				E('p', {}, cfState === 'missing'
					? _('The tunnel was deleted on Cloudflare. Open Access — unbind will guide you through re-setup.')
					: _('Cloudflare rejected the saved certificate. Open Access — unbind will guide you through re-setup.')),
				E('a', { 'class': 'btn cbi-button cbi-button-apply important', 'href': L.url('admin', 'services', 'hometunnel', 'wizard') }, _('Open Access'))
			]));
		}

		/* ---- 状态表 ---- */
			var label = function (ok, text) {
				return E('span', { 'class': ok ? 'label success' : 'label' }, text || (ok ? _('running') : _('stopped')));
			};

			var rows = [
				E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td left', 'width': '30%' }, E('strong', {}, _('Tunnel Mode'))),
					E('td', { 'class': 'td left' }, mode === 'ondemand' ? _('on-demand (remote switch)') : _('always-on'))
				])
				];

				if (mode === 'ondemand') {
				rows.push(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td left', 'width': '30%' }, E('strong', {}, _('Remote switch state'))),
					E('td', { 'class': 'td left', 'id': 'ht-ctl-state' }, this.fmtCtlState(ctlJson))
				]));
				}

				rows.push(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td left', 'width': '30%' }, E('strong', {}, _('Tunnel service'))),
					E('td', { 'class': 'td left' }, label(tunnelRunning))
				]));

				if (mode === 'ondemand') {
				rows.push(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td left', 'width': '30%' }, E('strong', {}, _('Switch daemon'))),
					E('td', { 'class': 'td left', 'id': 'ht-ctl-svc' }, label(ctlRunning))
				]));
				}

				rows.push(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td left', 'width': '30%' }, E('strong', {}, _('Tunnel on Cloudflare'))),
					E('td', { 'class': 'td left', 'id': 'ht-cf-state' }, E('span', { 'class': cfState === 'exists' ? 'label success' : 'label' },
						cfState === 'exists' ? _('ok')
						: cfState === 'missing' ? _('deleted on Cloudflare')
						: cfState === 'auth-failed' ? _('certificate rejected')
						: cfState ? cfState : _('unknown')))
				]));

				var table = E('table', { 'class': 'table', 'id': 'ht-status-table' }, rows);
			container.appendChild(E('div', { 'class': 'cbi-section' }, [E('div', {}, table)]));

			/* ---- on-demand: 开/关 + 书签 ---- */
			if (mode === 'ondemand' && ctlUrl && ctlKey) {
				var onUrl = ctlUrl + '/on?key=' + encodeURIComponent(ctlKey);
				var offUrl = ctlUrl + '/off?key=' + encodeURIComponent(ctlKey);

				var resultDiv = E('div', { 'id': 'ht-action-result', 'style': 'margin-top:8px' });

				/* Worker 返回 JSON → 人类可读 */
				var fmtResult = function (action, res) {
					var raw = (res.stdout || res.stderr || '').trim();
					var data = null;
					try { data = JSON.parse(raw); } catch (e) { /* not JSON */ }
					if (!data) return raw || _('done');

					if (action === 'on') {
						if (data.state === 'on' && data.expires_at) {
							var expDate = new Date(data.expires_at);
							var remainMin = Math.max(0, Math.round((expDate - Date.now()) / 60000));
							return _('Tunnel is on. Valid for %d minute(s), until %s.')
								.format(remainMin, expDate.toLocaleString());
						}
						return raw;
					}
					if (action === 'off') {
						if (data.state === 'off') return _('Tunnel is off.');
						return raw;
					}
					return raw;
				};

				var doAction = function (action, ev) {
					ev.preventDefault();
					ev.target.disabled = true;
					resultDiv.textContent = _('Please wait…');
					fs.exec('/usr/share/hometunnel/hometunnel.sh', ['ctl', action]).then(function (res) {
						resultDiv.textContent = fmtResult(action, res);
						ev.target.disabled = false;
					}).catch(function () {
						resultDiv.textContent = _('failed');
						ev.target.disabled = false;
					});
				};

				var btnOn = E('button', {
					'class': 'btn cbi-button cbi-button-apply important',
					'click': doAction.bind(this, 'on')
				}, _('Turn On (%d min)').format(defaultTtl));

				var btnOff = E('button', {
					'class': 'btn cbi-button cbi-button-reset negative',
					'click': doAction.bind(this, 'off')
				}, _('Turn Off'));

				/* 书签 URL（含 key）——复制按钮 */
				var copyBtn = function (url, ev) {
					ev.preventDefault();
					if (navigator.clipboard && navigator.clipboard.writeText)
						navigator.clipboard.writeText(url);
					var btnEl = ev.target;
					btnEl.classList.add('spinning');
					window.setTimeout(function () { btnEl.classList.remove('spinning'); }, 600);
				};

				container.appendChild(E('div', { 'class': 'cbi-section' }, [
					E('h3', {}, _('Remote Switch')),
					E('div', { 'style': 'display:flex;gap:8px;flex-wrap:wrap' }, [btnOn, btnOff]),
					resultDiv,
					E('h3', {}, _('Switch Bookmarks')),
					E('div', { 'class': 'cbi-section-descr' },
						_('Save these as bookmarks on any device to open/close the tunnel from anywhere:')),
					E('div', { 'style': 'display:flex;gap:8px;flex-wrap:wrap;margin-top:6px' }, [
						E('button', { 'class': 'btn cbi-button', 'click': copyBtn.bind(this, onUrl) }, _('Copy "ON" link')),
						E('button', { 'class': 'btn cbi-button', 'click': copyBtn.bind(this, offUrl) }, _('Copy "OFF" link'))
					]),
					E('div', { 'style': 'margin-top:6px;word-break:break-all;font-size:12px' }, [
						E('div', {}, onUrl),
						E('div', {}, offUrl)
					])
				]));
			}

			/* ---- 守护日志 ---- */
			var logDiv = E('pre', { 'class': 'cbi-input-textarea', 'style': 'overflow:auto;max-height:220px;font-size:12px', 'id': 'ht-log' }, _('loading…'));
			container.appendChild(E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Recent switch daemon log')),
				logDiv
			]));

			this.refreshLog(logDiv);

			/* 定时刷新（控制面状态 + 日志 + CF 状态），不整页重绘 */
			var self = this;
			poll.add(function () {
				return Promise.all([
					getBackendStatus(),
					fs.exec('/sbin/logread', ['-e', 'hometunnel']).catch(function () { return { stdout: '' }; })
				]).then(function (res) {
					var cj = parseCtlJson(res[0]);
					var stateEl = document.getElementById('ht-ctl-state');
					if (stateEl) {
						stateEl.innerHTML = '';
						stateEl.appendChild(self.fmtCtlState(cj));
					}
					var cfEl = document.getElementById('ht-cf-state');
					if (cfEl) {
						cfEl.innerHTML = '';
						var cfs = parseCfState(res[0]);
						cfEl.appendChild(E('span', { 'class': cfs === 'exists' ? 'label success' : 'label' },
							cfs === 'exists' ? _('ok')
							: cfs === 'missing' ? _('deleted on Cloudflare')
							: cfs === 'auth-failed' ? _('certificate rejected')
							: cfs ? cfs : _('unknown')));
					}
					var logText = (res[1].stdout || '').trim().split('\n');
					logDiv.textContent = logText.slice(-15).join('\n') || _('(empty)');
				});
			}, 10);

			return container;
		}, this));
	},

	fmtCtlState: function (cj) {
		if (!cj) return E('span', { 'class': 'label' }, _('unreachable'));
		if (cj.on === true && cj.exp) {
			var remainMin = Math.max(0, Math.round((cj.exp - Date.now()) / 60000));
			return E('span', {}, [
				E('span', { 'class': 'label success' }, _('on')),
				' — ' + _('TTL remaining: %d min').format(remainMin) +
				(cj.last_bump ? ' · ' + _('auto-renewed') : '')
			]);
		}
		return E('span', { 'class': 'label' }, _('off'));
	},

	refreshLog: function (el) {
		fs.exec('/sbin/logread', ['-e', 'hometunnel']).then(function (res) {
			var lines = (res.stdout || '').trim().split('\n');
			el.textContent = lines.slice(-15).join('\n') || _('(empty)');
		}).catch(function () { el.textContent = _('(log unavailable)'); });
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
