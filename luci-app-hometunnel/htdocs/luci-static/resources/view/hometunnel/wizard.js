/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright (C) 2026 xiaoqingfeng <xiaoqingfeng@yeah.net> */
/* hometunnel wizard — 8 步断点向导（job 异步轮询） */

'use strict';
'require fs';
'require poll';
'require rpc';
'require uci';
'require view';
'require view.hometunnel.ui as htui';

var HT = '/usr/share/hometunnel/hometunnel.sh';
var RUNDIR = '/var/run/hometunnel';
var OAUTH_JSON = '/etc/hometunnel/oauth.json';

/* job 轮询: { state: 'running'|'done', rc } */
function jobPoll(name) {
	return fs.exec(HT, ['jobstatus', name]).then(function (res) {
		var s = (res.stdout || '').trim();
		if (s.indexOf('done:') === 0)
			return { state: 'done', rc: parseInt(s.slice(5), 10) };
		if (s === 'running')
			return { state: 'running' };
		return { state: 'missing' };
	}).catch(function () { return { state: 'missing' }; });
}

function jobOut(name) {
	return fs.read_direct(RUNDIR + '/' + name + '.out').catch(function () { return ''; });
}

/* 从 login 输出提取 cloudflared 授权 URL */
function extractAuthUrl(text) {
	var m = (text || '').match(/https:\/\/dash\.cloudflare\.com\/argotunnel\?[^\s"']+/);
	return m ? m[0] : null;
}

return view.extend({
	load: function () {
		return uci.load('hometunnel');
	},

	render: function () {
		var self = this;

		return this.probeState().then(function () {
			return self.renderInner();
		});
	},

	probeState: function () {
		var self = this;
		return fs.stat('/etc/hometunnel/.cloudflared cert.pem'.replace(' cert.pem', '/cert.pem')).then(function (st) {
			self.certOk = !!(st && st.size > 0);
		}).catch(function () { self.certOk = false; }).then(function () {
			self.ingressCount = uci.sections('hometunnel', 'ingress').filter(function (s) {
				return s.enabled !== '0';
			}).length;
			/* bound = 隧道+域名+开关服务全部就位（向导走完的判定）。
			   dnsOk/ingressCount 保留给锁定态概览（规则健康用） */
			return fs.stat(RUNDIR + '/dns-routed');
		}).then(function (st) {
			self.dnsOk = !!(st && st.size > 0);
		}).catch(function () { self.dnsOk = false; }).then(function () {
			return fs.stat(OAUTH_JSON);
		}).then(function (st) {
			self.oauthOk = !!(st && st.size > 0);
		}).catch(function () { self.oauthOk = false; }).then(function () {
			return fs.stat(RUNDIR + '/worker-deployed');
		}).then(function (st) {
			self.workerOk = !!(st && st.size > 0);
		}).catch(function () { self.workerOk = false }).then(function () {
			return fs.stat(RUNDIR + '/worker-verified');
		}).then(function (st) {
			self.verifiedOk = !!(st && st.size > 0);
		}).catch(function () { self.verifiedOk = false; }).then(function () {
			/* bound = 向导走完（verifiedOk）。锁定态渲染总览而非步骤。
			   domain+worker-deployed 在但 verified 缺失 = 半程态（仍走⑥验证） */
			self.bound = !!(self.certOk
				&& uci.get('hometunnel', 'global', 'tunnel_id')
				&& uci.get('hometunnel', 'global', 'domain')
				&& self.verifiedOk);
		});
	},

	getStep: function () {
		if (!this.certOk) return 1;
		if (!uci.get('hometunnel', 'global', 'tunnel_id')) return 2;
		if (!uci.get('hometunnel', 'global', 'domain')) return 3;
		if (!this.oauthOk) return 4;
		if (!this.workerOk) return 5;
		return 6;
	},

	renderInner: function () {
		var step = this.getStep();
		var container = htui.apply(E('div', {}, [
			E('h2', {}, _('HomeTunnel Access')),
			E('div', {
				'class': 'd-flex align-items-center flex-wrap',
				'style': 'gap:.5rem;padding:.6rem 1rem;border-radius:.5rem;'
					+ 'background:linear-gradient(rgba(52,140,212,.14),rgba(52,140,212,.14)),rgba(54,64,74,.9);'
					+ 'border:1px solid rgba(52,140,212,.3);'
					+ 'color:inherit'
			}, [
				E('span', { 'class': 'dripicons-information', 'style': 'font-size:16px;margin-right:8px;color:#348cd4' }),
				this.bound ? _('The access wizard is complete. Adjust exposed intranet services in "Ingress Rules". Revoke only when you need to change the tunnel domain.')
					: _('Open a browser and log into your Cloudflare account. Then follow the steps below to set up the intranet-exposure tunnel.')
				])
				]));

		var titles = [
			_('① Cloudflare Authorization'),
			_('② Create Tunnel'),
			_('③ Choose Domain'),
			_('④ Authorize Switch Service'),
			_('⑤ Deploy Switch Service'),
			_('⑥ Verify & Finish')
		];

		/* 步骤指示器（stepper）: 已完成=绿勾徽章 / 当前=蓝胶囊 / 未到=灰。
		 * 配色对齐主题: badge-soft-success(#78c350 on 18% green) + 主题蓝 #348cd4 + 卡片深底。
		 * 标题自带 ①-⑧ 编号，不再重复加数字；箭头与后续胶囊绑成单元，换行时成对移动 */
		var stepBar = E('div', {
			'class': 'd-flex align-items-center flex-wrap',
			'style': 'gap:.3rem;padding:.5rem .65rem;border-radius:.5rem;'
				+ 'background:rgba(54,64,74,.9);border:1px solid rgba(255,255,255,.07)'
		});
		titles.forEach(function (t, i) {
			var done = i < step - 1;
			var active = i === step - 1;
			var pill = E('span', {
				'class': 'd-inline-flex align-items-center',
				'style': 'gap:.3rem;padding:.22rem .6rem;border-radius:999px;font-size:12.5px;white-space:nowrap;'
					+ (done
						? 'color:#78c350;background-color:rgba(120,195,80,.18);'
						: active
							? 'color:#fff;background-color:#348cd4;font-weight:600;'
							: 'color:rgba(148,160,173,.55);background-color:rgba(255,255,255,.05);')
			}, [
				done ? E('span', { 'class': 'dripicons-checkmark', 'style': 'font-size:12px' }) : null,
				E('span', {}, t)
			].filter(Boolean));
			if (i === 0) {
				stepBar.appendChild(pill);
			} else {
				/* 连接箭头：通向已完成步骤的段绿色，否则暗灰；与胶囊绑成整体防孤行 */
				stepBar.appendChild(E('span', { 'class': 'd-inline-flex align-items-center', 'style': 'white-space:nowrap' }, [
					E('span', {
						'class': 'dripicons-arrow-thin-right',
						'style': 'font-size:11px;margin:0 .2rem;color:' + (i < step ? '#78c350' : 'rgba(148,160,173,.35)')
					}),
					pill
				]));
			}
		});
		/* 锁定态不显示步骤条（向导已完成，步骤不再有意义） */
		if (!this.bound) container.appendChild(stepBar);

		var body = E('div', { 'class': 'cbi-section' });
		container.appendChild(body);

		/* 绑定完成 = 锁定态（不重走向导）; 向导只在未绑定时运行 */
		if (this.bound) {
			this.renderLocked(body);
		} else {
			switch (step) {
				case 1: this.step1(body); break;
				case 2: this.step2(body); break;
				case 3: this.step3(body); break;
				case 4: this.step4(body); break;
				case 5: this.step5(body); break;
				case 6: this.step6(body); break;
			}
		}

		return container;
	},


	/* ---- 锁定态: 只读配置总览 + 在线健康 + 解绑入口 ---- */
	renderLocked: function (body) {
		var self = this;

		body.appendChild(E('p', {},
			_('Access setup is locked. Revoke the authorization to reconfigure.')));

		/* 已确定的配置（只读） */
		var domain = uci.get('hometunnel', 'global', 'domain');
		var ctlHost = (uci.get('hometunnel', 'global', 'ctl_hostname') || 'ctl') + '.' + domain;
		var mode = uci.get('hometunnel', 'global', 'mode') || 'ondemand';

		var tbl = E('table', { 'class': 'table' });
		[
			[_('Authorized domain'), domain],
			[_('Tunnel switch domain'), ctlHost],
			[_('Mode'), mode === 'ondemand' ? _('on-demand (remote switch)') : _('always-on')]
		].forEach(function (row) {
			tbl.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'style': 'width:35%' }, row[0]),
				E('td', { 'class': 'td' }, String(row[1]))
			]));
		});
		body.appendChild(E('div', { 'class': 'cbi-section-node' }, [tbl]));
		/* 按需模式: 开关走 URL（无页面），书签在状态页 */
		if (mode === 'ondemand')
			body.appendChild(E('div', { 'class': 'cbi-section-descr' },
				_('Tunnel switching is done via URL, no page involved. Save the switch bookmarks from the Status page to start or stop the tunnel from any device.')));

		/* 在线健康（打开页面时查一次） */
		var health = E('div', { 'style': 'margin:10px 0' }, _('Checking online status…'));
		body.appendChild(health);
		fs.exec(HT, ['probe']).then(function (res) {
			var st = null;
			try { st = JSON.parse((res.stdout || '').trim()); } catch (e) {}
			health.innerHTML = '';
			if (!st) {
				health.appendChild(E('div', { 'class': 'alert-message warning' },
					_('Online status unavailable. Check the router log.')));
				return;
			}
			var items = [];
			var needOauth = false; /* oauth 失效时 Repair 无效，需重新授权（回向导④） */
			/* oauth */
			if (st.oauth === 'ok') items.push([_('Cloudflare authorization'), null]);
			else if (st.oauth === 'expired' || st.oauth === 'missing') {
				items.push([_('Cloudflare authorization'), _('authorization lost — click Repair and re-authorize')]);
				needOauth = true;
			}
			/* tunnel（被删 = 配置失效, 需解绑重设） */
			if (st.tunnel === 'deleted') items.push([_('Tunnel'), _('deleted on Cloudflare — revoke the authorization to re-set up')]);
			else if (st.tunnel === 'auth-failed') items.push([_('Tunnel'), _('Cloudflare rejected the saved certificate — revoke the authorization to re-set up')]);
			/* worker */
			if (st.worker === 'ok') items.push([_('Switch service'), null]);
			else if (st.worker === 'foreign') items.push([_('Switch service'), _('domain taken over by another service')]);
			else if (st.worker === 'missing') items.push([_('Switch service'), _('not deployed')]);
			else if (st.worker === 'blocked') items.push([_('Switch service'), _('DNS record conflicts')]);
			/* dns */
			if (st.dns === 'ok') items.push([_('Ingress DNS records'), null]);
			else if (st.dns && st.dns.indexOf('missing:') === 0) items.push([_('Ingress DNS records'), _('missing %s records').format(st.dns.slice(8))]);

			var bad = items.some(function (it) { return it[1] !== null; });
			if (!bad) {
				health.appendChild(E('div', { 'class': 'alert-message success' }, _('All checks passed.')));
				return;
			}
			if (needOauth) {
				/* oauth 失效 → Repair 无效（部署需 token）。内嵌重新授权卡
				   （与向导④同款; 授权成功 reload → probe 重查全部状态） */
				health.appendChild(E('div', { 'class': 'alert-message warning' },
					_('Cloudflare authorization is required to repair. Re-authorize below.')));
				var reauth = E('div', { 'style': 'margin-top:8px' });
				health.appendChild(reauth);
				self.appendOauthFlow(reauth);
				return;
			}
			var t = E('table', { 'class': 'table' });
			items.forEach(function (it) {
				t.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td', 'style': 'width:35%' }, it[0]),
					E('td', { 'class': 'td' }, it[1] === null
						? E('span', { 'style': 'color:#78c350' }, _('OK'))
						: E('span', { 'style': 'color:#e15759' }, it[1]))
				]));
			});
			health.appendChild(E('div', { 'class': 'cbi-section-node' }, [t]));
			if (bad) {
				/* 失效自愈: 重新部署按钮（幂等） */
				var fix = E('button', { 'class': 'btn cbi-button cbi-button-apply important', 'style': 'margin-top:8px' },
					_('Repair'));
				var fixOut = E('pre', { 'style': 'max-height:180px;overflow:auto;font-size:12px;margin-top:6px' }, '');
				fix.addEventListener('click', function (ev) {
					ev.preventDefault();
					fix.disabled = true;
					health.appendChild(fixOut);
					fs.exec(HT, ['job', 'oauth-deploy', HT, 'oauth-deploy']).then(function () {
						poll.add(L.bind(self.watchDeploy, self, fixOut, fix), 2);
					});
				});
				health.appendChild(fix);
			}
		}).catch(function () {
			health.innerHTML = '';
			health.appendChild(E('div', { 'class': 'alert-message warning' },
				_('Online status unavailable. Check the router log.')));
		});

		/* 解绑 */
		var unbindBtn = E('button', { 'class': 'btn cbi-button cbi-button-remove important', 'style': 'margin-top:14px' }, _('Revoke Authorization'));
		body.appendChild(E('div', { 'style': 'margin:16px 0 8px 0' }, [
			E('p', { 'class': 'cbi-section-descr' }, _('Revoking removes the tunnel, DNS records and the switch service from Cloudflare. Ingress rules are kept locally.')),
			unbindBtn
		]));
		var unbindOut = E('pre', { 'style': 'max-height:200px;overflow:auto;font-size:12px' }, '');
		body.appendChild(unbindOut);
		unbindBtn.addEventListener('click', function (ev) {
			ev.preventDefault();
			unbindBtn.disabled = true;
			unbindOut.textContent = 'unbinding…';
			/* 解绑用后台 job（删除多个远端资源，耗时几十秒） */
			fs.exec(HT, ['job', 'unbind', HT, 'unbind', 'yes']).then(function () {
				poll.add(function () {
					return jobPoll('unbind').then(function (st) {
						return jobOut('unbind').then(function (text) {
							unbindOut.textContent = text || '';
							if (st.state === 'done') {
								if (st.rc === 0) {
									unbindOut.appendChild(E('div', { 'class': 'alert-message success' }, _('Authorization revoked! Reloading…')));
									window.setTimeout(function () { location.reload(); }, 1200);
								} else {
									unbindOut.appendChild(E('div', { 'class': 'alert-message error' }, _('Revoke failed — check output above')));
									unbindBtn.disabled = false;
								}
								return Promise.reject('done');
							}
						});
					});
				}, 2);
			});
		});
	},
	/* ---- 步骤 1: cloudflared tunnel login ---- */
	step1: function (body) {
		body.appendChild(E('p', {}, [
			_('The router runs %s and shows an authorization URL.').format('cloudflared tunnel login'), ' ',
			_('Open it on any device, log into Cloudflare, pick your domain and authorize.')
		]));

		var urlBox = E('div', { 'class': 'cbi-value', 'style': 'word-break:break-all' }, _('waiting for auth URL…'));
		var startBtn = E('button', { 'class': 'btn cbi-button cbi-button-apply important' }, _('Start Login'));
		var self = this;

		startBtn.addEventListener('click', function (ev) {
			ev.preventDefault();
			startBtn.disabled = true;
			fs.exec(HT, ['job', 'login', HT, 'login']).then(function () {
				poll.add(L.bind(self.watchLogin, self, urlBox), 2);
			});
		});
		body.appendChild(E('div', { 'style': 'margin:10px 0' }, [startBtn]));
		body.appendChild(urlBox);
	},

	watchLogin: function (urlBox) {
		var self = this;
		return jobOut('login').then(function (text) {
			var url = extractAuthUrl(text);
			if (url && !urlBox.dataset.filled) {
				urlBox.dataset.filled = '1';
				urlBox.innerHTML = '';
				urlBox.appendChild(E('a', { 'href': url, 'target': '_blank' }, url));
			}
			/* 完成检测: cert.pem 出现 */
			return fs.stat('/etc/hometunnel/.cloudflared/cert.pem').then(function (st) {
				if (st && st.size > 0) {
					urlBox.appendChild(E('div', { 'class': 'alert-message success' }, _('Authorized! Loading next step…')));
					window.setTimeout(function () { location.reload(); }, 1200);
					return;
				}
				return self.reportLoginFailure(urlBox, text);
			}).catch(function () {
				return self.reportLoginFailure(urlBox, text);
			});
		});
	},

	/* job 已退出但 cert 未到 → 显示错误并停止轮询 */
	reportLoginFailure: function (urlBox, text) {
		return jobPoll('login').then(function (st) {
			if (st.state === 'done' && st.rc !== 0 && !urlBox.dataset.failed) {
				urlBox.dataset.failed = '1';
				var tail = (text || '').trim().split('\n').slice(-3).join('\n');
				urlBox.appendChild(E('div', { 'class': 'alert-message error' }, [
					E('div', {}, _('cloudflared exited before the certificate was fetched:')),
					E('pre', { 'style': 'white-space:pre-wrap;margin:4px 0;font-size:12px' }, tail),
					E('div', {}, _('Fix the issue (e.g. router DNS), reload this page and try again.'))
				]));
			}
			if (urlBox.dataset.failed)
				return Promise.reject('login job failed');
		});
	},

	/* ---- 步骤 2: tunnel create ---- */
	step2: function (body) {
		body.appendChild(E('p', {},
			_('This step creates an intranet-exposure tunnel. Give it a name and click \"Create Tunnel\".')));

		var self = this;
		var warn = E('div', { 'class': 'alert-message warning', 'style': 'display:none' });
		body.appendChild(warn);

		/* CF 侧状态预检: tunnel 被删/凭据失效时提示自动恢复 */
		fs.exec(HT, ['check']).then(function (res) {
			var st = ((res.stdout || '') + (res.stderr || '')).match(/cf-tunnel:\s+(\S+)/);
			var state = st ? st[1] : '';
			if (state === 'missing' || state === 'auth-failed') {
				warn.style.display = '';
				warn.appendChild(E('div', {}, state === 'missing'
					? _('The tunnel was deleted on Cloudflare. Clicking Create below will recreate it automatically (new tunnel ID; DNS routes are republished later in the wizard).')
					: _('Cloudflare rejected the saved certificate. Re-run step ① first.')));
			}
		});

		var name = uci.get('hometunnel', 'global', 'tunnel_name') || 'hometunnel';
		var nameInput = E('input', {
			'type': 'text', 'class': 'cbi-input-text',
			'style': 'width:220px', 'value': name,
			'placeholder': 'hometunnel'
		});
		var nameRow = E('div', { 'style': 'margin:8px 0;display:flex;align-items:center;gap:8px' }, [
			E('label', { 'style': 'flex:0 0 auto' }, _('Tunnel name')), nameInput
		]);
		body.appendChild(nameRow);

		var btn = E('button', { 'class': 'btn cbi-button cbi-button-apply important' }, _('Create Tunnel'));
		btn.disabled = !nameInput.value.trim();
		nameInput.addEventListener('input', function () {
			btn.disabled = !nameInput.value.trim();
		});
		var out = E('pre', { 'style': 'max-height:150px;overflow:auto;font-size:12px' }, '');
		btn.addEventListener('click', function (ev) {
			ev.preventDefault();
			btn.disabled = true;
			out.textContent = 'running…';
			uci.set('hometunnel', 'global', 'tunnel_name', nameInput.value.trim());
			uci.save()
				.then(function () { return fs.exec(HT, ['create']); })
				.then(function (res) {
					out.textContent = (res.stdout || '') + (res.stderr || '');
					if (res.code === 0) {
						out.appendChild(E('div', { 'class': 'alert-message success' }, _('Created! Loading next step…')));
						window.setTimeout(function () { location.reload(); }, 1200);
					} else {
						btn.disabled = false;
					}
				})
				.catch(function () { btn.disabled = false; });
		});
		body.appendChild(E('div', { 'style': 'margin:10px 0' }, [btn]));
		body.appendChild(out);
	},

	/* ---- 步骤 3: 选择域名（cert.pem token 反查账户 zone 列表）---- */
	step3: function (body) {
		var self = this;
		body.appendChild(E('p', {},
			_('Pick the domain for the intranet-exposure tunnel (fetched automatically from your Cloudflare account; make sure the domain is already set up on Cloudflare), then click "Fetch Domains" to continue.')));

		var sel = E('select', { 'class': 'cbi-input-select' });
		var loadBtn = E('button', { 'class': 'btn cbi-button cbi-button-apply important' }, _('Fetch Domains'));
		var applyBtn = E('button', { 'class': 'btn cbi-button cbi-button-save important', 'style': 'display:none' }, _('Use Domain'));
		var out = E('pre', { 'style': 'max-height:120px;overflow:auto;font-size:12px' }, '');

		loadBtn.addEventListener('click', function (ev) {
			ev.preventDefault();
			loadBtn.disabled = true;
			sel.innerHTML = '';
			sel.appendChild(E('option', { 'value': '' }, _('loading…')));
			fs.exec(HT, ['zones']).then(function (res) {
				var text = (res.stdout || '') + (res.stderr || '');
				sel.innerHTML = '';
				if (res.code === 0) {
					var lines = text.trim().split('\n').filter(Boolean);
					lines.forEach(function (l) {
						var parts = l.trim().split(/\s+/);
						sel.appendChild(E('option', { 'value': parts[0], 'disabled': (parts[1] !== 'active') ? '' : null },
							parts[0] + (parts[1] === 'active' ? ' (' + _('active') + ')'
							: (parts[1] === 'pending' ? ' (' + _('pending') + ')'
							: (parts[1] ? ' (' + parts[1] + ')' : '')))));
					});
					if (lines.length > 0) {
						sel.style.display = '';
						applyBtn.style.display = '';
						loadBtn.textContent = _('Refetch');
					}
				} else {
					sel.style.display = 'none';
					out.textContent = text;
				}
				loadBtn.disabled = false;
			});
		});

		applyBtn.addEventListener('click', function (ev) {
			ev.preventDefault();
			var d = sel.value;
			var opt = sel.options[sel.selectedIndex];
			if (!d || (opt && opt.disabled)) return;
			applyBtn.disabled = true;
			fs.exec(HT, ['set', 'domain', d]).then(function (res) {
				if (res.code === 0) {
					out.appendChild(E('div', { 'class': 'alert-message success' }, _('Saved! Loading next step…')));
					window.setTimeout(function () { location.reload(); }, 1000);
				} else {
					applyBtn.disabled = false;
					out.textContent = (res.stdout || '') + (res.stderr || '');
				}
			});
		});

		body.appendChild(E('div', { 'style': 'margin:10px 0' }, [loadBtn]));
		body.appendChild(E('div', { 'style': 'margin:6px 0' }, [sel, ' ', applyBtn]));
		sel.style.display = 'none';
		body.appendChild(E('div', { 'class': 'cbi-section-descr', 'style': 'line-height:1.7;margin-top:4px' }, [
			E('div', { 'style': 'margin-bottom:4px' }, E('strong', {}, _('Domain status legend:'))),
			E('div', {}, [
				E('strong', {}, _('usable')), ' ', _('The domain is fully served by Cloudflare (nameservers switched to Cloudflare, DNS resolution active).')
			]),
			E('div', {}, [
				E('strong', {}, _('not fully active')), ' ', _('The domain was just added to Cloudflare, but its nameservers have not been switched over yet; Cloudflare has not taken it over.')
			]),
			E('div', { 'style': 'margin-top:4px' }, _('Only domains marked as usable can be selected.'))
		]));
		body.appendChild(out);
	},

	/* ---- 步骤 4: 授权开关服务（OAuth 设备流，一次扫码）---- */
	step4: function (body) {
		body.appendChild(E('p', {}, [
			_('Authorize the switch service deployment (a Cloudflare Worker).'), ' ',
			_('Scan the QR code with your phone, or open the link, then tap Allow — that is the only manual step.')
		]));
		this.appendOauthFlow(body);
	},

	/* ---- OAuth 授权卡（向导④与锁定态失效自愈共用）---- */
	appendOauthFlow: function (body) {
		var self = this;
		var btn = E('button', { 'class': 'btn cbi-button cbi-button-apply important' }, _('Start Authorization'));
		var box = E('div', { 'class': 'cbi-value', 'style': 'margin-top:8px' }, '');
		btn.addEventListener('click', function (ev) {
			ev.preventDefault();
			btn.disabled = true;
			box.innerHTML = '';
			fs.exec(HT, ['oauth-start']).then(function (res) {
				var text = ((res.stdout || '') + (res.stderr || '')).trim();
				if (res.code !== 0) {
					box.appendChild(E('div', { 'class': 'alert-message error' }, _('Failed: %s').format(text)));
					btn.disabled = false;
					return;
				}
				var m = text.match(/\{[^}]*"user_code"[^}]*\}/);
				var info = null;
				try { info = JSON.parse(m ? m[0] : text); } catch (e) {}
				if (info && info.already_authorized) {
					box.appendChild(E('div', { 'class': 'alert-message success' }, _('Already authorized! Loading next step…')));
					window.setTimeout(function () { location.reload(); }, 1000);
					return;
				}
				if (!info || !info.verification_url) {
					box.appendChild(E('div', { 'class': 'alert-message error' }, _('Unexpected response: %s').format(text)));
					btn.disabled = false;
					return;
				}
				/* 授权卡片: 二维码（有则显示）+ 链接 + 等待状态 */
				var card = E('div', { 'style': 'display:flex;gap:1rem;align-items:flex-start;flex-wrap:wrap' });
				fs.read_direct(RUNDIR + '/oauth-qr.svg').then(function (svg) {
					if (svg && svg.length > 100) {
						var holder = E('div', {
							'style': 'background:#fff;padding:6px;border-radius:8px;width:172px;height:172px;flex:none'
						});
						holder.innerHTML = svg;
						card.appendChild(holder);
					}
				}).catch(function () {});
				var right = E('div', { 'style': 'flex:1;min-width:220px' });
				right.appendChild(E('div', { 'style': 'word-break:break-all;margin-bottom:6px' }, [
					E('a', { 'href': info.verification_url, 'target': '_blank' }, info.verification_url)
				]));
				/* 授权码醒目展示（设备流核对用） */
				right.appendChild(E('div', { 'style': 'margin:2px 0 10px 0' }, [
					_('Authorization code:'),
					' ',
					E('span', { 'style': 'font-family:monospace;font-size:16px;font-weight:bold;letter-spacing:1px' }, info.user_code || '')
				]));
				/* 操作指引: 告诉用户在 Cloudflare 页面上要做什么 */
				right.appendChild(E('div', { 'class': 'cbi-section-descr', 'style': 'margin-bottom:4px' }, _('How to authorize:')));
				right.appendChild(E('ol', { 'style': 'margin:0 0 10px 0;padding-left:18px' }, [
					E('li', {}, _('Open the link above, or scan the QR code with a phone.')),
					E('li', {}, _('Log in to your Cloudflare account on that page.')),
					E('li', {}, _('Confirm the page shows the same code as above, then click "Authorize".')),
					E('li', {}, _('Come back to this page — it continues automatically.'))
				]));
				right.appendChild(E('div', { 'class': 'cbi-section-descr' },
					_('The page is served by Cloudflare and may show "Wrangler" — that is Cloudflare\'s official CLI identity and is expected.')));
				var status = E('div', { 'style': 'margin-top:8px' }, _('Waiting for authorization…'));
				right.appendChild(status);
				card.appendChild(right);
				box.appendChild(card);
				/* 轮询授权状态 */
				poll.add(L.bind(self.watchOauth, self, status));
			});
		});
		body.appendChild(E('div', { 'style': 'margin:10px 0' }, [btn]));
		body.appendChild(box);
	},

	watchOauth: function (statusEl) {
		return fs.exec(HT, ['oauth-status']).then(function (res) {
			var text = (res.stdout || '').trim();
			var st = null;
			try { st = JSON.parse(text); } catch (e) {}
			if (!st) return;
			if (st.state === 'authorized') {
				statusEl.innerHTML = '';
				statusEl.appendChild(E('div', { 'class': 'alert-message success' }, _('Authorized! Loading next step…')));
				window.setTimeout(function () { location.reload(); }, 1000);
				return;
			}
			if (st.state === 'expired') {
				statusEl.innerHTML = '';
				statusEl.appendChild(E('div', { 'class': 'alert-message error' }, _('The code expired (5 minutes). Click Start Authorization again.')));
				return;
			}
			if (st.state === 'failed') {
				statusEl.innerHTML = '';
				statusEl.appendChild(E('div', { 'class': 'alert-message error' }, _('Failed: %s').format(st.error || 'unknown')));
				return;
			}
			/* pending — 继续轮询 */
		});
	},

	/* ---- 步骤 5: 自动部署开关服务（OAuth token + 路由器内 curl）---- */
	/* 子域名可编辑 + 完整域名实时预览；冲突时提示（可改子域名或强制接管） */
	step5: function (body) {
		var self = this;
		var domain = uci.get('hometunnel', 'global', 'domain');
		var savedHost = uci.get('hometunnel', 'global', 'ctl_hostname') || 'ctl';
		var ctlHost = savedHost + '.' + domain;
		body.appendChild(E('p', {}, [
			_('The switch service controls starting and stopping the intranet-exposure tunnel. It will create a subdomain under the current domain: enter the subdomain the switch service should use, then click "Deploy Now".')
		]));

		/* 子域名输入 + 完整域名实时预览（msgid 不带尾空格——LuCI 翻译查找会修剪，
		   尾空格导致哈希不匹配；整句 %s 翻译同时避免 .format(element) 陷阱） */
		var preview = E('div', { 'style': 'margin:4px 0 10px 0' },
			_('Full name: %s').format(ctlHost));
		var input = E('input', { 'type': 'text', 'value': savedHost,
			'class': 'cbi-input-text', 'style': 'width:140px' });
		input.addEventListener('input', function () {
			var v = input.value.trim().toLowerCase().replace(/[^a-z0-9-]/g, '');
			preview.textContent = _('Full name: %s').format((v || 'ctl') + '.' + domain);
		});
		body.appendChild(E('div', { 'style': 'margin:6px 0' }, [
			E('label', { 'style': 'margin-right:6px' }, _('Switch service subdomain')), input
		]));
		body.appendChild(preview);

		var btn = E('button', { 'class': 'btn cbi-button cbi-button-apply important' }, _('Deploy Now'));
		var out = E('pre', { 'style': 'max-height:220px;overflow:auto;font-size:12px' }, '');
		var warn = E('div', { 'class': 'alert-message warning', 'style': 'display:none' });

		/* 保存子域名后部署（值未变时 set 幂等成功） */
		var saveAndDeploy = function (args) {
			var host = input.value.trim().toLowerCase().replace(/[^a-z0-9-]/g, '');
			if (!host) host = 'ctl';
			fs.exec(HT, ['set', 'ctl_hostname', host]).then(function () {
				startDeploy(args);
			}).catch(function () {
				startDeploy(args);
			});
		};

		var startDeploy = function (args) {
			btn.disabled = true;
			warn.style.display = 'none';
			out.textContent = 'deploying…';
			fs.exec(HT, ['job', 'oauth-deploy', HT, 'oauth-deploy'].concat(args || [])).then(function () {
				poll.add(L.bind(self.watchDeploy, self, out, btn), 2);
			});
		};

		/* 冲突（挂在其他 Worker）: 可改子域名重试，或确认强制接管 */
		var showConflict = function (st) {
			out.textContent = '';
			warn.innerHTML = '';
			warn.style.display = '';
			warn.appendChild(E('div', {}, [
				_('The switch domain %s is already taken by another service (Worker “%s”).').format(preview.textContent, st.by)
			]));
			warn.appendChild(E('div', { 'style': 'margin-top:6px' },
				_('You can type a different subdomain above and retry, or take over the domain (this removes it from that service).')));
			var yes = E('button', { 'class': 'btn cbi-button cbi-button-apply important', 'style': 'margin-top:8px' },
				_('Take Over and Deploy'));
			var no = E('button', { 'class': 'btn cbi-button', 'style': 'margin-top:8px;margin-left:8px' },
				_('Cancel'));
			yes.addEventListener('click', function (ev2) {
				ev2.preventDefault();
				saveAndDeploy(['takeover']);
			});
			no.addEventListener('click', function (ev2) {
				ev2.preventDefault();
				warn.style.display = 'none';
				btn.disabled = false;
			});
			warn.appendChild(E('div', {}, [yes, no]));
		};

		/* 冲突（已有普通 DNS 记录）: 改子域名，或去 dashboard 删记录 */
		var showDnsConflict = function (st) {
			out.textContent = '';
			warn.innerHTML = '';
			warn.style.display = '';
			warn.appendChild(E('div', {}, [
				_('The switch domain %s already has a %s DNS record.').format(preview.textContent, st.by)
			]));
			warn.appendChild(E('div', { 'style': 'margin-top:6px' },
				_('Pick a different subdomain above and retry, or delete that record in the Cloudflare dashboard (DNS app) first.')));
			var no = E('button', { 'class': 'btn cbi-button', 'style': 'margin-top:8px' },
				_('Cancel'));
			no.addEventListener('click', function (ev2) {
				ev2.preventDefault();
				warn.style.display = 'none';
				btn.disabled = false;
			});
			warn.appendChild(no);
		};

		btn.addEventListener('click', function (ev) {
			ev.preventDefault();
			btn.disabled = true;
			out.textContent = 'checking…';
			/* 预检: 冲突 → 提示（可改子域名或强制接管）；干净 → 保存后直接部署 */
			fs.exec(HT, ['deploy-check']).then(function (res) {
				var st = null;
				try { st = JSON.parse((res.stdout || '').trim()); } catch (e) {}
				if (st && st.state === 'conflict' && st.kind === 'worker') {
					showConflict(st);
					return;
				}
				if (st && st.state === 'conflict' && st.kind === 'dns') {
					showDnsConflict(st);
					return;
				}
				/* clean / 预检失败（后端会给出权威错误）→ 保存子域名后部署 */
				saveAndDeploy([]);
			}).catch(function () {
				saveAndDeploy([]);
			});
		});
		body.appendChild(E('div', { 'style': 'margin:10px 0' }, [btn]));
		body.appendChild(warn);
		body.appendChild(out);

			},
	watchDeploy: function (outEl, btn) {
		return jobPoll('oauth-deploy').then(function (st) {
			return jobOut('oauth-deploy').then(function (text) {
				outEl.textContent = text || '';
				if (st.state === 'done') {
					if (st.rc === 0) {
						fs.exec(HT, ['mark', 'worker-deployed']);
						/* 首次部署顺带发布已有规则的 DNS CNAME（原向导⑥职责并入，
						   后台执行不阻塞推进；规则页保存也会增量发布） */
						fs.exec(HT, ['job', 'route-regen', HT, 'route-and-regen']);
						fs.exec(HT, ['mark', 'dns-routed']);
						outEl.appendChild(E('div', { 'class': 'alert-message success' }, _('Deployed! Publishing DNS records…')));
						window.setTimeout(function () { location.reload(); }, 1500);
					} else {
						outEl.appendChild(E('div', { 'class': 'alert-message error' }, _('Deploy failed — check output above')));
						btn.disabled = false;
					}
					return Promise.reject('done');
				}
			});
		});
	},

	/* ---- 步骤 6: verify + finish ---- */
	step6: function (body) {
		var mode = uci.get('hometunnel', 'global', 'mode') || 'ondemand';
		/* 已验证过（重访向导）: 显示完成态，不再重复 Verify */
		if (this.verifiedOk) {
			var modeName = mode === 'ondemand' ? _('on-demand (remote switch)') : _('always-on');
			body.appendChild(E('p', {},
				_('Setup is complete. The switch daemon is running in %s mode.').format(modeName)));
			body.appendChild(E('a', {
				'class': 'btn cbi-button cbi-button-apply important', 'style': 'margin-top:6px',
				'href': L.url('admin', 'services', 'hometunnel', 'status')
			}, _('Open Status Page')));
			return;
		}
		body.appendChild(E('p', {},
				_('This step verifies all settings and starts the intranet-exposure tunnel. Click "Verify" to continue.')));

		var btn = E('button', { 'class': 'btn cbi-button cbi-button-apply important' }, _('Verify'));
		var out = E('pre', { 'style': 'max-height:150px;overflow:auto;font-size:12px' }, '');
		btn.addEventListener('click', function (ev) {
			ev.preventDefault();
			btn.disabled = true;
			out.textContent = 'verifying…';
			fs.exec(HT, ['verify']).then(function (res) {
				out.textContent = (res.stdout || '') + (res.stderr || '');
				if (res.code === 0) {
					fs.exec(HT, ['mark', 'worker-verified']).then(function () {
						return fs.exec(HT, ['apply-mode']);
					}).then(function () {
						out.appendChild(E('div', { 'class': 'alert-message success' },
							_('All checks passed. Daemon enabled. Opening status page…')));
						window.setTimeout(function () {
							location.href = L.url('admin', 'services', 'hometunnel', 'status');
						}, 1500);
					});
				} else {
					btn.disabled = false;
				}
			});
		});
		body.appendChild(E('div', { 'style': 'margin:10px 0' }, [btn]));
		body.appendChild(out);

		body.appendChild(E('p', { 'class': 'cbi-section-descr' }, [
			_('The tunnel will run in on-demand mode: it stays off until you switch it on remotely. If you want the tunnel always on, change it later in Settings.')
		]));

		var warnBox = E('div', { 'class': 'alert-message warning' });
		warnBox.appendChild(E('div', { 'style': 'font-weight:bold;margin-bottom:4px' }, _('Security notice:')));
		warnBox.appendChild(E('div', { 'style': 'line-height:1.7' }, [
			_('Intranet services such as the router admin UI or printer maintenance pages have very weak security protection; exposing them to the public internet is high risk and not recommended.'), E('br'),
			_('For NAS, download services and the like, set a strong password, enable brute-force protection and check logs regularly to keep your data safe.'), E('br'),
			_('Unless you have solid network-security experience, keeping the tunnel always on is not recommended.')
		]));
		body.appendChild(warnBox);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
