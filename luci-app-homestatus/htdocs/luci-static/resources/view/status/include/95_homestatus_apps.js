'use strict';
'require baseclass';
'require ui';
'require poll';
'require view.homestatus.shared as hs';

/*
 * Overview block: key application status, with a restart action.
 *
 * Everything comes from one luci.homestatus.status() call; the shared module
 * memoises it so the disk block in the same poll tick does not issue a second
 * request.  Restarts go through luci.homestatus.restart_app, which shells out
 * to the init script - `ubus call rc init` deadlocks when issued from inside
 * rpcd, so the backend cannot use it.
 */

function confirmRestart(app, onDone) {
	ui.showModal(_('确认重启服务'), [
		E('p', {}, [
			_('即将重启 %s，已建立的连接会中断。').format(app.label),
			' ',
			E('span', { 'class': 'hs-muted' }, [
				E('code', {}, [ app.init || app.id ])
			])
		]),
		E('div', { 'class': 'right' }, [
			E('button', {
				'class': 'btn',
				'click': ui.hideModal
			}, [ _('取消') ]),
			' ',
			E('button', {
				'class': 'btn cbi-button cbi-button-negative important',
				'click': function() {
					ui.hideModal();
					onDone();
				}
			}, [ _('确认重启') ])
		])
	]);
}

function stateCell(app) {
	var b = hs.badge(app);

	return E('span', { 'class': 'badge %s'.format(b.cls) }, [ b.text ]);
}

function actionCell(app, row) {
	if (!app.restartable)
		return E('td', { 'class': 'hs-act hs-muted' }, [ _('—') ]);

	return E('td', { 'class': 'hs-act' }, [
		E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'click': function(ev) {
				var btn = ev.currentTarget;

				confirmRestart(app, function() {
					btn.disabled = true;
					btn.textContent = _('重启中…');

					hs.restart(app.id).then(function(r) {
						btn.disabled = false;
						btn.textContent = _('重启');

						if (r == null || r.ok !== true) {
							ui.addNotification(null, E('p', {},
								[ _('重启 %s 失败：%s').format(app.label,
									(r && (r.message || r.error)) || _('未知错误')) ]),
								'error');
							return;
						}

						ui.addNotification(null, E('p', {},
							[ _('已重启 %s').format(app.label) ]), 'info');

						/* The status endpoint has to be re-read past the memo
						 * window, and the daemon needs a moment to come back. */
						hs.invalidate();
						window.setTimeout(hs.invalidate, 2000);
						window.setTimeout(hs.invalidate, 8000);
					});
				});
			}
		}, [ _('重启') ])
	]);
}

return baseclass.extend({
	title: _('关键应用状态'),

	disableCache: true,

	load: function() {
		return hs.status();
	},

	render: function(data) {
		if (data == null)
			return E('div', { 'class': 'hs-empty' }, [ _('无法读取应用状态') ]);

		var cfg = data.config || {};

		if (cfg.enabled === false)
			return E('div', { 'class': 'hs-empty hs-muted' }, [ _('监视功能已关闭') ]);

		var apps = data.apps || [];
		var rows = [];

		for (var i = 0; i < apps.length; i++) {
			var app = apps[i];
			var nameCell = [ E('span', { 'class': 'hs-app' }, [ app.label ]) ];

			if (app.note != null)
				nameCell.push(E('div', { 'class': 'hs-alias' }, [ app.note ]));

			rows.push(E('tr', { 'class': 'hs-row' }, [
				E('td', {}, nameCell),
				E('td', {}, [ stateCell(app) ]),
				E('td', {}, [
					app.autostart
						? E('span', { 'class': 'badge badge-soft-info' }, [ _('开机启动') ])
						: E('span', { 'class': 'hs-muted' }, [ _('否') ])
				]),
				E('td', { 'class': 'hs-detail hs-muted' }, [
					app.detail != null ? app.detail : '—'
				]),
				actionCell(app)
			]));
		}

		var table = E('table', { 'class': 'table hs-table hs-apps' }, [
			E('thead', {}, E('tr', { 'class': 'tr' }, [
				E('th', { 'class': 'th' }, [ _('名称') ]),
				E('th', { 'class': 'th' }, [ _('状态') ]),
				E('th', { 'class': 'th' }, [ _('自启') ]),
				E('th', { 'class': 'th' }, [ _('详情') ]),
				E('th', { 'class': 'th hs-act' }, [ _('操作') ])
			])),
			E('tbody', {}, rows)
		]);

		return E('div', { 'class': 'hs-apps-wrap' }, [
			table,
			E('div', { 'class': 'hs-foot hs-muted' }, [
				_('共 %d 项').format(apps.length)
			])
		]);
	}
});
