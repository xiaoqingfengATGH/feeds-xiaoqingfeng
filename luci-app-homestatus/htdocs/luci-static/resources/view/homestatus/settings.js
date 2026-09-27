'use strict';
'require form';
'require uci';
'require ui';
'require view';
'require rpc';
'require view.homestatus.shared as hs';

/*
 * Settings page for luci-app-homestatus.
 *
 * Saving goes through the standard client-side `uci` class so the page gets
 * Save & Apply, Revert and the unsaved-changes indicator for free.  The
 * backend re-reads UCI on every call, so no service restart is needed for a
 * change to take effect - the overview blocks pick it up on their next poll
 * (they set disableCache).
 *
 * luci.homestatus.set_config() exists as the programmatic equivalent for
 * scripting; this page does not need it.
 */

/* Section names are what the backend reports as each app's `id`, and they are
 * also used to build /etc/init.d/<name> paths indirectly, so keep them
 * conservative. */
var ID_RE = /^[A-Za-z0-9][A-Za-z0-9_.-]*$/;

/* Accepts 00:11:22:33:44:55, 00-11-22-33-44-55 (Windows) and 001122334455. */
var MAC_RE = /^[0-9a-fA-F]{2}([-:]?[0-9a-fA-F]{2}){5}$/;

var callWolTargets = rpc.declare({
	object: 'luci.homestatus',
	method: 'wol_targets',
	expect: {}
});

var callWake = rpc.declare({
	object: 'luci.homestatus',
	method: 'wake',
	params: [ 'payload' ],
	expect: {}
});

/* Probe a target and report whether its MAC is currently in the neighbour
 * table, so the admin can tell a dead config from a sleeping machine. */
function testWake(section_id, btn) {
	var mac = uci.get('luci-wol', section_id, 'mac');

	if (mac == null || !MAC_RE.test(mac)) {
		ui.addNotification(null, E('p', {}, [ _('请先填写有效的 MAC 地址') ]), 'warning');
		return;
	}

	var old = btn.textContent;
	btn.disabled = true;
	btn.textContent = _('测试中…');

	L.resolveDefault(callWake({ mac: mac }), null).then(function(r) {
		btn.disabled = false;
		btn.textContent = old;

		if (r != null && r.ok === true)
			ui.addNotification(null, E('p', {}, [
				_('已向 %s 发送唤醒包（接口 %s）').format(r.mac, r.iface || '—')
			]), 'info');
		else
			ui.addNotification(null, E('p', {}, [
				_('发送失败：%s').format((r && (r.message || r.error)) || _('未知错误'))
			]), 'error');
	});
}

function importServices(map) {
	hs.services().then(function(r) {
		var list = (r && r.services) || [];

		if (!list.length) {
			ui.addNotification(null, E('p', {}, [ _('没有找到可添加的服务') ]), 'warning');
			return;
		}

		var boxes = list.map(function(s, i) {
			var cb = E('input', {
				'type': 'checkbox',
				'id': 'hs-imp-%d'.format(i),
				'disabled': s.monitored ? true : null
			});

			return E('div', { 'style': 'padding:.15rem 0' }, [
				E('label', { 'style': 'display:flex;gap:.5rem;align-items:baseline' }, [
					cb,
					E('span', { 'style': 'min-width:14rem' }, [ s.name ]),
					E('span', { 'class': 'hs-muted', 'style': 'font-size:.85em' }, [
						s.monitored ? _('已监视')
							: (s.running ? _('运行中 %s').format(s.pid != null ? 'pid ' + s.pid : '')
							             : _('未运行'))
					])
				])
			]);
		});

		ui.showModal(_('从已安装服务添加'), [
			E('p', { 'class': 'hs-muted' }, [
				_('这些服务都有 init 脚本。勾选后会用推测的探测方式加入监视列表，保存后可在表格里再调整。')
			]),
			E('div', { 'style': 'max-height:50vh;overflow:auto;margin:.5rem 0' }, boxes),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, [ _('取消') ]),
				' ',
				E('button', {
					'class': 'btn cbi-button cbi-button-action important',
					'click': function() {
						var added = 0;

						list.forEach(function(s, i) {
							var cb = document.getElementById('hs-imp-%d'.format(i));
							if (cb == null || !cb.checked || s.monitored)
								return;
							if (!ID_RE.test(s.name))
								return;
							/* uci.add() accepts the section name as its third
							 * argument; without it the section stays anonymous
							 * (cfg0a1b2c) and the resulting config is
							 * unreadable to `uci show`. The name may already
							 * be taken by an unrelated section, so fall back
							 * to a generated one. */
							var sec;
							if (uci.get('homestatus', s.name) == null)
								sec = uci.add('homestatus', 'app', s.name);
							else
								sec = uci.add('homestatus', 'app');

							uci.set('homestatus', sec, 'id', s.name);
							uci.set('homestatus', sec, 'label', s.name);
							uci.set('homestatus', sec, 'probe', s.probe_guess || 'exe');
							uci.set('homestatus', sec, 'init', s.name);
							/* present in every existing entry - keep rows uniform */
							uci.set('homestatus', sec, 'enabled', '1');

							if (s.probe_guess === 'cmd')
								uci.set('homestatus', sec, 'match', s.name);

							added++;
						});

						ui.hideModal();

						if (added) {
							/* Same in-place refresh the grid's own Add button
							 * uses (renderSectionAdd -> map.save(null, true));
							 * the user still has to press Save & Apply. */
							ui.addNotification(null, E('p', {},
								[ _('已添加 %d 项，请按「保存并应用」提交。').format(added) ]), 'info');
							map.save(null, true);
						}
					}
				}, [ _('添加') ])
			])
		]);
	});
}

return view.extend({
	load: function() {
		/* luci-wol holds the wake targets, shared with the stock
		 * luci-app-wol page so both stay in sync */
		return Promise.all([
			uci.load('homestatus'),
			uci.load('luci-wol')
		]);
	},

	render: function() {
		var m, s, o;

		m = new form.Map('homestatus', _('磁盘容量与应用监视'),
			_('为「概览」页面增加磁盘容量、关键应用状态与网络唤醒三个区块。前两者是纯展示，只有「重启」按钮会执行写操作；唤醒会向目标主机发送魔术包。'));

		/* ------------------------------------------------------------ 磁盘 --- */

		s = m.section(form.NamedSection, 'global', 'global', _('显示与监测'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('启用应用状态监视'),
			_('关闭后，「关键应用状态」区块显示为已关闭，磁盘区块仍正常显示。'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'warn', _('黄色告警门限'),
			_('使用率超过此百分比时，进度条与百分比转为黄色。'));
		o.datatype = 'range(1,100)';
		o.default = '80';
		o.rmempty = false;

		o = s.option(form.Value, 'crit', _('红色危险门限'),
			_('使用率超过此百分比时转为红色。应大于黄色门限。只读固件镜像不参与染色。'));
		o.datatype = 'range(1,100)';
		o.default = '90';
		o.rmempty = false;

		/* ------------------------------------------- 概览页面区块显隐 --- */
		/* These only hide the block on the overview page. The settings
		 * page always shows them so a hidden block can be brought back. */

		o = s.option(form.Flag, 'show_apps', _('在概览页显示「关键应用」'),
			_('关闭后「概览」页面不再显示关键应用区块，监视配置本身保留。'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Flag, 'show_wol', _('在概览页显示「网络唤醒」'),
			_('关闭后「概览」页面不再显示网络唤醒区块，唤醒目标列表本身保留，仍可在「服务 → 网络唤醒」中管理。'));
		o.default = '1';
		o.rmempty = false;

		/* ------------------------------------------------------ 应用监视 --- */

		s = m.section(form.GridSection, 'app', _('关键应用状态监视'));
		s.addremove = true;
		s.sortable = true;
		s.rowcolors = true;
		s.modaltitle = _('编辑监视项');
		s.nodescriptions = true;

		o = s.option(form.Value, 'id', _('标识'));
		o.rmempty = false;
		o.modalonly = true;
		o.validate = function(section_id, value) {
			if (!ID_RE.test(value))
				return _('只能包含字母、数字、下划线、点与连字符');
			return true;
		};

		o = s.option(form.Value, 'label', _('显示名'));
		o.rmempty = false;

		o = s.option(form.Flag, 'enabled', _('启用'));
		o.default = '1';
		o.editable = true;

		o = s.option(form.ListValue, 'probe', _('探测方式'));
		o.value('exe', _('进程名（最可靠）'));
		o.value('cmd', _('命令行子串'));
		o.value('port', _('本地监听端口'));
		o.value('path', _('运行时文件存在'));
		o.default = 'exe';
		o.rmempty = false;
		/* The collapsed grid prints the raw config value ("port"), not the
		 * ListValue label - override textvalue so the table shows the same
		 * Chinese wording the dropdown does. (Stock CBI.FlagValue does the
		 * same for its Yes/No.) */
		o.textvalue = function(section_id) {
			var val = this.cfgvalue(section_id) ?? this.default;
			var idx = (this.keylist || []).indexOf(val);

			return idx >= 0 ? this.vallist[idx] : val;
		};

		o = s.option(form.Value, 'init', _('init 脚本名'),
			_('用于「重启」按钮，对应 /etc/init.d/<名称>。留空则用标识。'));
		o.rmempty = true;

		o = s.option(form.Value, 'match', _('匹配串'),
			_('进程名探测：与 /proc/<pid>/cmdline 的 argv[0] 基名精确比较；命令行探测：整条命令行的子串。留空则用标识。'));
		o.depends('probe', 'exe');
		o.depends('probe', 'cmd');
		o.rmempty = true;

		o = s.option(form.Value, 'port', _('监听端口'),
			_('探测 /proc/net/tcp 上是否存在该端口的 LISTEN。'));
		o.depends('probe', 'port');
		o.datatype = 'port';
		o.rmempty = true;

		o = s.option(form.Value, 'path', _('运行时文件'),
			_('该文件存在即视为运行中，适合进程名不固定的服务。'));
		o.depends('probe', 'path');
		o.datatype = 'string';
		o.rmempty = true;

		o = s.option(form.Value, 'uci', _('开关对应的 UCI 选项'),
			_('可选。填应用自己的总开关，例如 passwall2.@global[0].enabled，关闭时会显示为「已禁用」而不是「已停止」。'));
		o.rmempty = true;

		o = s.option(form.Value, 'note', _('备注'),
			_('显示在名称下方的灰色小字。'));
		o.rmempty = true;

		o = s.option(form.Value, 'order', _('排序'));
		o.datatype = 'integer';
		o.rmempty = true;
		o.modalonly = true;

		/* ------------------------------------------------------ 从服务导入 --- */
		/* Appended to the rendered map instead of being a form section:
		 * Map.section() rejects anything that is not a strict subclass of
		 * CBIAbstractSection (passing the exported AbstractSection itself
		 * raises "Class must be a descendant of CBIAbstractSection"), and a
		 * plain div is all this needs. */

		/* The wake targets live in /etc/config/luci-wol as `config target`
		 * sections - exactly what the stock luci-app-wol page reads and
		 * writes, so both pages edit the same list.
		 *
		 * They get their OWN map rather than being a section on the
		 * homestatus map with `uciconfig` set. form.js resolves row-modal
		 * lookups (handleAdd / renderMoreOptionsModal) against
		 * `this.map.config` and ignores `uciconfig` there, so a section
		 * pointing at another config throws
		 * "Cannot read properties of null (reading '.name')" when Edit or
		 * Add is pressed. A dedicated map keeps map.config == 'luci-wol',
		 * which is also how the stock page avoids this. */

		var wolMap = new form.Map('luci-wol', _('网络唤醒目标'),
			_('配置可被远程唤醒的主机。与「服务 → 网络唤醒」是同一份配置，两边都可以编辑。'));

		s = wolMap.section(form.GridSection, 'target', _('唤醒目标列表'),
			_('名称与 MAC 为必填，MAC 支持冒号、连字符或纯十六进制写法。点击行内的「唤醒」直接发送魔术包；「概览」页面的唤醒卡片读取同一份配置。'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;
		s.nodescriptions = true;
		s.modaltitle = _('编辑唤醒目标');

		o = s.option(form.Value, 'name', _('名称'));
		o.rmempty = false;
		o.validate = function(section_id, value) {
			if (value == null || value.trim() == '')
				return _('名称不能为空');
			return true;
		};

		o = s.option(form.Value, 'mac', _('MAC 地址'));
		o.rmempty = false;
		o.placeholder = '00:11:22:33:44:55';
		o.validate = function(section_id, value) {
			if (value == null || !MAC_RE.test(value.trim()))
				return _('MAC 地址格式无效，例如 00:11:22:33:44:55');
			return true;
		};

		o = s.option(form.Value, 'iface', _('接口'),
			_('可选。留空时自动选择：优先目标主机最近出现的接口，其次 br-lan。多网卡设备建议显式指定。'));
		o.rmempty = true;
		o.datatype = 'string';

		o = s.option(form.Flag, 'broadcast', _('使用广播地址'),
			_('etherwake 的 -b。某些网卡在单播魔术包下无响应时启用。'));
		o.default = o.disabled;
		o.rmempty = true;

		o = s.option(form.Value, 'password', _('SecureOn 密码'),
			_('可选。网卡启用了 SecureOn 时才需要，填写 MAC 形式的密码（如 00:22:44:66:88:aa）。'));
		o.rmempty = true;

		/* Row actions: keep the stock Edit/Delete, add Wake. The row actions
		 * live in a child div, so the button must be inserted there - the
		 * stock wrapper's own children are the container, not the buttons. */
		var grid = s;

		s.renderRowActions = L.bind(function(section_id) {
			var btns = form.GridSection.prototype.renderRowActions.call(grid, section_id, _('编辑'));
			var box = btns.querySelector('div') || btns;

			var wake = E('button', {
				'class': 'cbi-button cbi-button-action',
				'title': _('向该主机发送唤醒包'),
				'click': ui.createHandlerFn(this, function() {
					return testWake(section_id, this);
				})
			}, [ _('唤醒') ]);

			box.insertBefore(wake, box.firstChild);

			return btns;
		}, this);

		return Promise.resolve(m.render()).then(function(node) {
			return wolMap.render().then(function(wolNode) {
				node.appendChild(wolNode);

				node.appendChild(E('div', { 'class': 'cbi-section' }, [
					E('h3', {}, [ _('从已安装服务添加') ]),
					E('div', { 'class': 'cbi-section-descr' }, [
						_('列出所有带 init 脚本的服务，勾选即可加入上面的监视列表。')
					]),
					E('div', { 'style': 'margin-top:.5rem' }, [
						E('button', {
							'class': 'btn cbi-button cbi-button-add',
							'click': ui.createHandlerFn(this, function() {
								importServices(m, this);
							})
						}, [ _('选择服务…') ])
					])
				]));

				return node;
			});
		});
	}
});
