'use strict';
'require baseclass';
'require view.homestatus.shared as hs';

/*
 * Overview block: disk capacity, disk/mount-point combined view.
 *
 * The backend already groups everything into disk -> partition -> volume ->
 * mount, with loop devices attributed to the partition that backs them.  This
 * block renders that tree flat, one row per mount point, with the device chain
 * inline in the second column - which is the variant chosen for this firmware.
 */

function bar(mount, cfg, ro) {
	var pct = mount.use_pct;

	/* A read-only firmware image is 100% full by construction; colouring it
	 * with the "critical" threshold would cry wolf on every page load.  Draw
	 * it neutral and explain it in the row instead. */
	if (ro) {
		var flat = E('div', { 'style': 'width:100%;background-color:#5a6673' });

		return E('div', {
			'class': 'cbi-progressbar',
			'title': '%s · %s'.format(_('只读固件镜像'), _('恒 100%，不代表已用尽'))
		}, flat);
	}

	var color = hs.barColor(pct, cfg);

	var inner = E('div', { 'style': 'width:%d%%'.format(pct) });

	if (color != null)
		inner.style.backgroundColor = color;

	return E('div', {
		'class': 'cbi-progressbar',
		'title': '%s / %s (%d%%)'.format(
			hs.fmtBytes(mount.bytes_used), hs.fmtBytes(mount.bytes_total), pct)
	}, inner);
}

function deviceChain(dev, part, vol) {
	var chain = [];

	if (vol != null && part != null)
		chain.push('%s → %s'.format(vol.name, part.name));
	else if (part != null)
		chain.push(part.name);
	else
		chain.push(dev.name);

	var fs = (vol != null ? vol.fstype : part != null ? part.fstype : null) || dev.fstype;

	if (fs != null)
		chain.push(fs);

	return chain.join(' · ');
}

function mountRow(dev, part, vol, mount) {
	var alias = mount.alias;
	var cell = [ E('span', { 'class': 'hs-mount' }, [ mount.target ]) ];

	if (alias != null)
		cell.push(E('div', { 'class': 'hs-alias' }, [ alias ]));

	/* A mount is read-only when the mount itself is, or when it sits directly
	 * on a read-only partition.  A writable volume backed by a read-only
	 * partition (loop0 on the squashfs sda2 -> the f2fs overlay) is NOT
	 * read-only, so the parent's flag must not be inherited through `vol`. */
	var ro = (mount.readonly === true)
		|| (vol == null && part != null && part.readonly === true);

	var pctCell;

	if (ro) {
		pctCell = E('td', { 'class': 'hs-pct hs-muted' }, [ '—' ]);
	}
	else {
		var pct = mount.use_pct;
		var level = hs.barColor(pct, _cfg);
		var cls = 'hs-pct';

		if (level === '#dc3545') cls += ' hs-crit';
		else if (level === '#e0a800') cls += ' hs-warn';

		pctCell = E('td', { 'class': cls }, [ '%d%%'.format(pct) ]);
	}

	var avail;

	if (ro)
		avail = E('td', { 'class': 'hs-avail hs-muted' }, [ '—' ]);
	else
		avail = E('td', { 'class': 'hs-avail' }, [
			'%s'.format(_('可用')), ' ', hs.fmtBytes(mount.bytes_avail)
		]);

	return E('tr', { 'class': 'hs-row' }, [
		E('td', { 'class': 'hs-tcell' }, cell),
		E('td', { 'class': 'hs-dev' }, [ deviceChain(dev, part, vol) ]),
		E('td', { 'class': 'hs-bar' }, [ bar(mount, _cfg, ro) ]),
		pctCell,
		avail
	]);
}

var _cfg = null;

return baseclass.extend({
	title: _('磁盘容量'),

	/* The overview caches rendered HTML in sessionStorage for 30s, which would
	 * hide a threshold just changed on the settings page. */
	disableCache: true,

	load: function() {
		return hs.status().then(function(r) {
			var cfg = (r && r.config) || null;
			_cfg = cfg;
			return r;
		});
	},

	render: function(data) {
		if (data == null)
			return E('div', { 'class': 'hs-empty' }, [ _('无法读取磁盘信息') ]);

		var cfg = data.config || {};
		var disks = data.disks || [];
		var rows = [];
		var nMounts = 0, nParts = 0, nVols = 0, nUnmounted = 0, nReadonly = 0;

		for (var i = 0; i < disks.length; i++) {
			var dev = disks[i];

			/* disk-level mounts (none on this firmware, but keep it honest) */
			for (var dm = 0; dm < (dev.mounts || []).length; dm++) {
				rows.push(mountRow(dev, null, null, dev.mounts[dm]));
				nMounts++;
			}

			for (var p = 0; p < (dev.partitions || []).length; p++) {
				var part = dev.partitions[p];
				nParts++;

				if (part.readonly) nReadonly++;

				if (part.unmounted && (part.mounts || []).length == 0
				    && (part.volumes || []).length == 0) {
					nUnmounted++;
					rows.push(E('tr', { 'class': 'hs-row hs-dim' }, [
						E('td', { 'class': 'hs-tcell hs-muted' }, [ '—' ]),
						E('td', { 'class': 'hs-dev' }, [
							'%s · '.format(part.name),
							part.fstype != null ? part.fstype : _('无文件系统')
						]),
						E('td', { 'class': 'hs-span', 'colspan': 3 }, [
							'%s · %s'.format(hs.fmtBytes(part.bytes), _('未挂载'))
						])
					]));
					continue;
				}

				if ((part.mounts || []).length == 0 && (part.volumes || []).length == 0
				    && !part.readonly) {
					rows.push(E('tr', { 'class': 'hs-row hs-dim' }, [
						E('td', { 'class': 'hs-tcell hs-muted' }, [ '—' ]),
						E('td', { 'class': 'hs-dev' }, [ part.name, ' · ',
							part.fstype != null ? part.fstype : _('无文件系统') ]),
						E('td', { 'class': 'hs-span', 'colspan': 3 }, [
							'%s · %s'.format(hs.fmtBytes(part.bytes), _('未挂载'))
						])
					]));
					continue;
				}

				for (var pm = 0; pm < (part.mounts || []).length; pm++) {
					rows.push(mountRow(dev, part, null, part.mounts[pm]));
					nMounts++;
				}

				for (var v = 0; v < (part.volumes || []).length; v++) {
					var vol = part.volumes[v];
					nVols++;

					for (var vm = 0; vm < (vol.mounts || []).length; vm++) {
						rows.push(mountRow(dev, part, vol, vol.mounts[vm]));
						nMounts++;
					}
				}
			}
		}

		var head = E('div', { 'class': 'hs-disk-head' }, [
			E('span', { 'class': 'hs-disk-name' }, [
				disks.length ? (disks[0].model || disks[0].name) : _('无磁盘'),
				' ',
				E('span', { 'class': 'hs-mono hs-muted' }, [
					'(' + (disks.length ? disks[0].name : '-') + ')'
				])
			]),
			E('span', { 'class': 'hs-disk-sum hs-muted' }, [
				disks.length ? hs.fmtBytes(disks[0].bytes) : ''
			])
		]);

		var table = E('table', { 'class': 'table hs-table' }, [
			E('thead', {}, E('tr', { 'class': 'tr' }, [
				E('th', { 'class': 'th' }, [ _('挂载点') ]),
				E('th', { 'class': 'th' }, [ _('设备 / 类型') ]),
				E('th', { 'class': 'th' }, [ _('容量与已用') ]),
				E('th', { 'class': 'th hs-pct' }, [ _('使用率') ]),
				E('th', { 'class': 'th hs-avail' }, [ _('剩余') ])
			])),
			E('tbody', {}, rows)
		]);

		var foot = E('div', { 'class': 'hs-foot hs-muted' }, [
			_('%d 块磁盘 · %d 个挂载点 · %d 个数据卷')
				.format(disks.length, nMounts, nVols),
			nUnmounted ? _(' · %d 个未挂载分区').format(nUnmounted) : '',
			nReadonly ? _(' · %d 个只读镜像').format(nReadonly) : ''
		]);

		return E('div', { 'class': 'hs-disk' }, [ head, table, foot ]);
	}
});
