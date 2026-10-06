#!/usr/bin/ucode
// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 xiaoqingfeng <xiaoqingfengatgm@gmail.com>
//
// HomeLede overview extensions - rpcd ucode plugin.
// Exposed as the ubus object `luci.homestatus`.
//
// rpcd ucode plugin conventions (verified against /usr/share/rpcd/ucode/luci,
// ddns.uc, luci.wol on 24.10.5):
//   - shebang + 'use strict'
//   - ucode stdlib via `import { x } from 'fs'` (NOT LuCI's 'require fs' -
//     that style silently fails to register the ubus object)
//   - LuCI helpers via `import { x } from 'luci.sys' / 'luci.core'`
//   - end with `return { '<ubus.object.name>': methods }`
//
// Methods:
//   status()             -> { disks, apps, config, ts }
//   services()           -> installed service candidates
//   set_config(payload)  -> persist monitor config
//   restart_app({id})    -> restart one monitored service
//   wol_targets()        -> wake-on-LAN targets + neighbour-table presence
//   wake({id|mac})       -> send one magic packet via etherwake
//   set_wol_targets(p)   -> replace the target list (stored in /etc/config/luci-wol)

'use strict';

import { readfile, realpath, dirname, basename, lsdir, access, popen } from 'fs';
import { cursor } from 'uci';
import { statvfs } from 'luci.core';
import { isnan } from 'math';
import { ulog, LOG_DEBUG } from 'log';

const UCI_PKG = 'homestatus';
const VERSION = '1.0.0';
const SYS_BLOCK = '/sys/class/block';

// Pseudo filesystems never carry capacity worth showing.
const SKIP_FSTYPES = [ 'proc', 'sysfs', 'devpts', 'debugfs', 'bpf', 'cgroup',
                       'cgroup2', 'securityfs', 'tracefs', 'pstore', 'mqueue',
                       'hugetlbfs', 'configfs', 'fusectl', 'autofs', 'binfmt_misc' ];

function now() {
	return int(time());
}

// ------------------------------------------------------------------ config ----
// `show_apps` / `show_wol` / `show_storage` control whether the overview page
// renders the corresponding block. They are read here rather than in the
// frontend alone so every consumer (ngOverview and the stock status page) sees
// one source of truth. Defaults are true: an absent config means "show
// everything".
//
// `show_apps` also gates the probe itself: with the card hidden nothing
// consumes the results, and build_apps() spawns one process per monitored app.
// `show_storage` only gates rendering - the disk data comes from the same
// status() call either way.
function read_config() {
	const cfg = { warn: 80, crit: 90, show_apps: true, show_wol: true, show_storage: true };

	try {
		const ctx = cursor();
		ctx.load(UCI_PKG);

		ctx.foreach(UCI_PKG, 'global', (s) => {
			if (s.show_apps != null)
				cfg.show_apps = (s.show_apps == '1' || s.show_apps == 'true');
			if (s.show_wol != null)
				cfg.show_wol = (s.show_wol == '1' || s.show_wol == 'true');
			if (s.show_storage != null)
				cfg.show_storage = (s.show_storage == '1' || s.show_storage == 'true');
			if (s.warn != null && !isnan(int(s.warn)))
				cfg.warn = int(s.warn);
			if (s.crit != null && !isnan(int(s.crit)))
				cfg.crit = int(s.crit);
			/* optional netprobe target overrides (must stay http(s) URLs) */
			if (s.probe_cn != null && match(`${s.probe_cn}`, /^https?:\/\//))
				cfg.probe_cn = `${s.probe_cn}`;
			if (s.probe_intl != null && match(`${s.probe_intl}`, /^https?:\/\//))
				cfg.probe_intl = `${s.probe_intl}`;
		});
	}
	catch (e) {
		// No config present is not an error - defaults apply.
	}

	return cfg;
}

// -------------------------------------------------------------- block devices --
// Enumerate /sys/class/block once. maj:min is the reliable key: it is read from
// sysfs rather than derived from the name (sda128 is 259:0, a dynamic major,
// and mountinfo reports /dev/root for sda2 whose maj:min really is 8:2).
// The disk<->partition relationship comes from realpath(), not name prefixing:
// on nvme0n1p1 / mmcblk0p1 a prefix match would pick the wrong parent.
function read_block_devices() {
	const by_majmin = {};
	const by_name = {};

	for (let name in lsdir(SYS_BLOCK)) {
		const dev = trim(readfile(`${SYS_BLOCK}/${name}/dev`) ?? '');
		if (!dev)
			continue;

		const size_raw = trim(readfile(`${SYS_BLOCK}/${name}/size`) ?? '');
		const part_raw = trim(readfile(`${SYS_BLOCK}/${name}/partition`) ?? '');

		let disk = null;
		const rp = realpath(`${SYS_BLOCK}/${name}`);
		if (rp) {
			const parent = basename(dirname(rp));
			if (parent && parent != 'block' && parent != 'virtual')
				disk = parent;
		}

		let backing = null;
		const bk = trim(readfile(`${SYS_BLOCK}/${name}/loop/backing_file`) ?? '');
		if (bk)
			backing = basename(bk);

		let model = null;
		const mdl = trim(readfile(`${SYS_BLOCK}/${name}/device/model`) ?? '');
		if (mdl)
			model = mdl;

		const rec = {
			name: name,
			dev: dev,
			bytes: (size_raw != '' && !isnan(int(size_raw))) ? int(size_raw) * 512 : 0,
			partition: (part_raw != '') ? int(part_raw) : null,
			disk: disk,
			is_loop: (substr(name, 0, 4) == 'loop'),
			backing: backing,
			model: model
		};

		by_majmin[dev] = rec;
		by_name[name] = rec;
	}

	return { by_majmin, by_name };
}

// ------------------------------------------------------------------- mounts ----
// /proc/self/mountinfo, fields before the ' - ' separator:
//   1 id  2 parent_id  3 major:minor  4 root  5 mount_point  6.. options
// after it: fstype source superopts
function read_mounts() {
	const raw = readfile('/proc/self/mountinfo');
	if (type(raw) != 'string')
		return [];

	const out = [];

	for (let line in split(raw, '\n')) {
		if (!length(trim(line)))
			continue;

		const sep = split(line, ' - ');
		if (length(sep) != 2)
			continue;

		const left = split(trim(sep[0]), ' ');
		const right = split(trim(sep[1]), ' ');
		if (length(left) < 6 || length(right) < 2)
			continue;

		push(out, {
			id: int(left[0]),
			parent_id: int(left[1]),
			majmin: left[2],
			mount_point: left[4],
			options: left[5],
			fstype: right[0],
			source: right[1],
			superopts: right[2] ?? ''
		});
	}

	return out;
}

// fstype is not in mountinfo's field 5 (that is the option list), so pull it
// from /proc/mounts by mount point.
function fstype_map() {
	const map = {};
	const raw = readfile('/proc/mounts');
	if (type(raw) != 'string')
		return map;

	for (let line in split(raw, '\n')) {
		const f = split(trim(line), ' ');
		if (length(f) >= 3)
			map[f[1]] = { fstype: f[2], source: f[0], ro: (substr(f[3] ?? '', 0, 2) == 'ro') };
	}

	return map;
}

function statvfs_of(mp) {
	let st = null;

	try {
		st = statvfs(mp);
	}
	catch (e) {
		return null;
	}

	if (!st || !st.blocks)
		return null;

	const bs = st.bsize || st.frsize || 4096;
	const total = st.blocks * bs;
	const free = st.bfree * bs;
	const used = total - free;

	return {
		bytes_total: total,
		bytes_used: used,
		bytes_avail: st.bavail * bs,
		use_pct: (total > 0) ? int(used * 100 / total) : 0
	};
}

// ------------------------------------------------------------------- disks -----
// Shape: disk -> partitions -> volumes(loop) -> mount points.
// Mounts sharing one maj:min form a group. A virtual group (overlayfs, 0:21) is
// attributed to the block device of a child mount that has a real one.
function build_disks() {
	const blk = read_block_devices();
	const mounts = read_mounts();
	const fmap = fstype_map();

	// group mounts by maj:min
	const groups = {};
	for (let m in mounts) {
		if (!groups[m.majmin])
			groups[m.majmin] = [];
		push(groups[m.majmin], m);
	}

	// resolve each mount group to a physical block device (null = virtual/pseudo)
	const attached = {};
	for (let majmin, members in groups) {
		if (blk.by_majmin[majmin]) {
			attached[majmin] = blk.by_majmin[majmin];
			continue;
		}

		// Virtual fs (overlayfs, 0:21). Do NOT guess from parent/child mount
		// order: /rom is also a child of the overlay root, so the first child
		// with a real device would wrongly win. The overlay's own upperdir
		// names the writable volume, so follow that path instead.
		let found = null;
		for (let m in members) {
			// ucode's regex engine has no non-capturing groups - use a plain
			// group and take the last capture.
			const up = match(', ' + (m.superopts ?? ''), /[, ]upperdir=([^,]+)/);
			if (!up)
				continue;

			let probe = up[1];
			while (length(probe) > 1) {
				for (let other in mounts) {
					if (other.mount_point != probe)
						continue;
					const od = blk.by_majmin[other.majmin];
					if (od) {
						found = od;
						break;
					}
				}
				if (found)
					break;
				probe = dirname(probe);
			}
			if (found)
				break;
		}

		// Fallback for virtual filesystems without upperdir (e.g. tmpfs-backed
		// overlays): take the first child with a real block device.
		if (!found) {
			for (let m in members) {
				for (let c in mounts) {
					if (c.parent_id != m.id)
						continue;
					if (blk.by_majmin[c.majmin]) {
						found = blk.by_majmin[c.majmin];
						break;
					}
				}
				if (found)
					break;
			}
		}

		attached[majmin] = found;
	}

	// physical devices -> their mount points (dedup repeated target paths)
	const mounts_for = {};
	for (let majmin, members in groups) {
		const dev = attached[majmin];
		if (!dev || dev.is_loop)
			continue;

		const info = fmap[members[0].mount_point] ?? {};
		const fstype = info.fstype ?? null;
		if (fstype && index(SKIP_FSTYPES, fstype) >= 0)
			continue;

		for (let m in members) {
			if (!mounts_for[dev.name])
				mounts_for[dev.name] = [];

			const list = mounts_for[dev.name];
			if (index(map(list, e => e.target), m.mount_point) >= 0)
				continue;

			push(list, {
				target: m.mount_point,
				fstype: fstype,
				readonly: (info.ro === true)
			});
		}
	}

	// loop volumes -> their mount points
	const loop_targets = {};
	for (let majmin, members in groups) {
		const dev = attached[majmin];
		if (!dev || !dev.is_loop)
			continue;

		if (!loop_targets[dev.name])
			loop_targets[dev.name] = [];

		for (let m in members)
			if (index(loop_targets[dev.name], m.mount_point) < 0)
				push(loop_targets[dev.name], m.mount_point);
	}

	// Assemble the tree.
	const disks = [];

	for (let dname, disk in blk.by_name) {
		if (disk.partition != null || disk.is_loop)
			continue;   // whole disks only at the top level

		const dnode = {
			name: disk.name,
			model: disk.model,
			bytes: disk.bytes,
			mounts: [],
			partitions: []
		};

		for (let m in (mounts_for[disk.name] ?? []))
			push(dnode.mounts, m);

		for (let pname, part in blk.by_name) {
			if (part.partition == null || part.disk != disk.name)
				continue;

			const pnode = {
				name: part.name,
				bytes: part.bytes,
				fstype: null,
				readonly: false,
				unmounted: false,
				mounts: [],
				volumes: []
			};

			const pm = mounts_for[part.name] ?? [];
			if (length(pm)) {
				pnode.fstype = pm[0].fstype;
				pnode.readonly = (pm[0].readonly === true);
				for (let m in pm)
					push(pnode.mounts, m);
			}
			else {
				pnode.unmounted = true;
			}

			// loop volumes backed by this partition
			for (let lname, ldev in blk.by_name) {
				if (!ldev.is_loop || ldev.backing != part.name)
					continue;

				const targets = loop_targets[ldev.name] ?? [];
				if (!length(targets))
					continue;

				let primary = targets[0];
				for (let t in targets)
					if (substr(t, 0, 9) == '/overlay')
						primary = t;

				const vnode = {
					name: ldev.name,
					bytes: ldev.bytes,
					fstype: (fmap[primary] ?? {}).fstype ?? null,
					mounts: []
				};

				for (let t in targets) {
					const mp = { target: t };
					if (t != primary)
						mp.alias = `与 ${primary} 同源`;
					push(vnode.mounts, mp);
				}

				const vst = statvfs_of(primary);
				if (vst) {
					vnode.bytes_total = vst.bytes_total;
					vnode.bytes_used = vst.bytes_used;
					vnode.bytes_avail = vst.bytes_avail;
					vnode.use_pct = vst.use_pct;
				}

				push(pnode.volumes, vnode);
			}

			push(dnode.partitions, pnode);
		}

		// attach capacity to every emitted mount point
		const enrich = (list) => {
			for (let m in list) {
				const st = statvfs_of(m.target);
				if (st) {
					m.bytes_total = st.bytes_total;
					m.bytes_used = st.bytes_used;
					m.bytes_avail = st.bytes_avail;
					m.use_pct = st.use_pct;
				}
			}
		};

		enrich(dnode.mounts);
		for (let p in dnode.partitions) {
			enrich(p.mounts);
			for (let v in p.volumes)
				enrich(v.mounts);
		}

		push(disks, dnode);
	}

	return disks;
}

// ------------------------------------------------------------------ apps -----
// IMPORTANT (verified on 24.10.5, rpcd 2024-12-02-cc9a471c): a method running
// inside rpcd MUST NOT call another ubus object. `ubus.call('rc', 'list')`,
// `('service', 'list')`, `('system', 'board')` and `('ubus', 'list')` all
// deadlock and hang the request until rpcd's timeout; only self-contained
// objects such as `system.info` and `network.device.status` survive. Since rc
// and service are exactly what we need, every probe below reads kernel
// interfaces directly instead - no subprocesses, no nested ubus.
//
// Probe kinds, in decreasing reliability:
//   exe   - /proc/<pid>/cmdline argv[0] basename == match  (most reliable)
//   cmd   - 'match' appears in that process' full command line (substring)
//   port  - /proc/net/tcp{,6} has a LISTEN socket on 127.0.0.1:<port>
//   path  - a runtime artefact that only exists after the service started
//
// socket.connect() is likewise unusable: ucode's socket API is asynchronous
// and returns immediately, so no connection can be awaited inside a call.
// NOTE: rpcd keeps the plugin's module-level state alive between calls, so a
// naive cache would freeze the first observation forever (verified: a stopped
// daemon kept reporting its original pid). Every lookup below therefore
// recomputes from the kernel on each call - it costs a few ms and the page is
// only polled every few seconds.

// Every live process as { pid, argv, exe, cmd }.
function scan_procs() {
	const procs = [];

	let names = [];
	try {
		names = lsdir('/proc') ?? [];
	}
	catch (e) {
		names = [];
	}

	for (let n in names) {
		if (type(n) != 'string' || !match(n, /^[0-9]+$/))
			continue;

		let raw = null;
		try {
			raw = readfile(`/proc/${n}/cmdline`);
		}
		catch (e) {
			continue;	// process vanished mid-scan
		}

		if (type(raw) != 'string' || !length(raw))
			continue;	// kernel thread

		const argv = filter(split(raw, '\0'), (x) => length(x));
		if (!length(argv))
			continue;

		push(procs, {
			pid: int(n),
			argv: argv,
			exe: basename(argv[0]),
			cmd: join(' ', argv)
		});
	}

	return procs;
}

function find_procs(mode, pattern) {
	const procs = scan_procs();

	if (mode == 'exe')
		return filter(procs, (p) => p.exe == pattern);

	return filter(procs, (p) => index(p.cmd, pattern) >= 0);
}

// Set of ports with a LISTEN socket.
function listening_ports() {
	const set = {};

	for (let f in [ '/proc/net/tcp', '/proc/net/tcp6' ]) {
		const raw = readfile(f);
		if (type(raw) != 'string')
			continue;

		for (let line in split(raw, '\n')) {
			const t = trim(line);
			if (!length(t) || substr(t, 0, 2) == 'sl')
				continue;

			const fld = split(t, ' ');
			if (length(fld) < 4)
				continue;

			// state 0A = TCP_LISTEN
			if (fld[3] != '0A')
				continue;

			const la = fld[1];
			const colon = rindex(la, ':');
			if (colon < 0)
				continue;

			const hexport = substr(la, colon + 1);
			if (length(hexport) != 4)
				continue;

			set[hexport] = true;
		}
	}

	return set;
}

function port_open(port) {
	const key = sprintf('%04X', int(port));
	return (listening_ports()[key] === true);
}

function dbg(msg) {
	if (DEBUG)
		ulog(LOG_DEBUG, sprintf('homestatus: %s\n', msg));
}

// Restart a monitored service.
//
// `ubus call rc init {name, action:'restart'}` is NOT usable from inside rpcd:
// it deadlocks exactly like `rc list` / `service list` (verified - the restart
// does happen, but the caller gets a 30s timeout, so the UI would report a
// failure for a successful action). Invoking the init script through popen
// works synchronously and returns the real exit code.
const SVC_NAME_RE = /^[A-Za-z0-9][A-Za-z0-9_.-]*$/;

function restart_service(name) {
	if (name == null || !match(`${name}`, SVC_NAME_RE))
		return { ok: false, error: 'bad-name', message: '服务名不合法' };

	const path = `/etc/init.d/${name}`;

	if (access(path) !== true)
		return { ok: false, error: 'no-init', message: `无 init 脚本 ${path}` };

	let rc = null;
	let out = '';

	try {
		// The name is validated above, so it cannot inject shell syntax. No
		// user-supplied string ever reaches this command.
		const fd = popen(`${path} restart 2>&1`);
		out = trim(fd.read('all') ?? '');
		rc = fd.close();
	}
	catch (e) {
		return { ok: false, error: 'exec-failed', message: `${e}` };
	}

	if (rc != 0)
		return {
			ok: false,
			error: 'exit-code',
			code: rc,
			message: out || `init 脚本返回 ${rc}`
		};

	return { ok: true, service: name, output: out };
}

function probe_app(app, ctx) {
	const kind = app.probe ?? 'exe';

	try {
		switch (kind) {
		case 'exe':
		case 'pid': {
			const pat = app.match ?? app.init ?? app.id;
			const hits = find_procs('exe', pat);
			return {
				running: length(hits) > 0,
				detail: length(hits) ? `pid ${hits[0].pid}` : null
			};
		}

		case 'cmd':
		case 'pgrep': {
			const pat = app.match ?? app.init ?? app.id;
			const hits = find_procs('cmd', pat);
			return {
				running: length(hits) > 0,
				detail: length(hits) ? `pid ${hits[0].pid}` : null
			};
		}

		case 'port': {
			const p = int(app.port ?? 0);
			if (!p)
				return { state: 'unknown', detail: '未配置端口' };
			const up = port_open(p);
			return {
				running: up,
				detail: up ? `监听 :${p}` : null
			};
		}

		case 'path': {
			// access() returns true or null - never false - so "not configured"
			// must be decided from the option itself, not from the return value.
			const want = app.path;
			if (want == null || !length(`${want}`))
				return { state: 'unknown', detail: '未配置路径' };

			const exists = (access(want) === true);
			return {
				running: exists,
				detail: exists ? `存在 ${want}` : null
			};
		}

		default:
			return { state: 'unknown', detail: `未知探针 ${kind}` };
		}
	}
	catch (e) {
		// One bad entry must never take down the whole status() call.
		return { state: 'unknown', detail: `${e}` };
	}
}

// "starts at boot" - true when /etc/rc.d/S<NN><name> exists. This replaces the
// rc.enabled field from `rc list`, which is unreachable from inside rpcd.
function autostart(name) {
	let rcd = [];

	try {
		rcd = lsdir('/etc/rc.d') ?? [];
	}
	catch (e) {
		rcd = [];
	}

	for (let f in rcd) {
		if (match(f, /^S[0-9][0-9]/) && substr(f, 3) == name)
			return true;
	}

	return false;
}

function build_apps(cfg) {
	const out = [];

	// rpcd ucode plugins have no uci object passed in, so load one here. A
	// failure must not break app probing - the entries just lose their
	// switch state.
	let ucix = null;
	try {
		ucix = cursor();
	}
	catch (e) {
		ucix = null;
	}

	let entries = [];

	try {
		const c = cursor();
		c.load(UCI_PKG);
		c.foreach(UCI_PKG, 'app', (s) => {
			push(entries, {
				enabled: !(s.enabled == '0' || s.enabled == 'false'),
				// Prefer an explicit `id` option. The section name is only a
				// fallback: a GridSection with addremove generates names like
				// cfg0a1b2c, which would leak into the UI and into the
				// restart target.
				id: s.id ?? s['.name'],
				label: s.label,
				probe: s.probe ?? 'exe',
				init: s.init,
				match: s.match,
				port: s.port,
				path: s.path,
				note: s.note,
				uci: s.uci,
				order: int(s.order ?? 999),
				critical: !(s.critical == '0' || s.critical == 'false')
			});
		});
	}
	catch (e) {
		return [ { error: `${e}` } ];
	}

	// UCI foreach preserves file order, including disabled entries.

	// warm the process table once so per-app lookups are pure array filters
	scan_procs();

	for (let a in entries) {
		const name = a.init ?? a.id;
		const pr = a.enabled ? probe_app(a, null) : { running: false };
		const auto = autostart(name);

		// 'switch' answers a different question than 'running': "starts at boot"
		// (from /etc/rc.d) is not the same as the app's own master switch - e.g.
		// passwall2 keeps enabled=0 while still being an autostart service. Both
		// are surfaced so the frontend can show "已禁用" instead of "已停止".
		//
		// The spec is '<package>.<section>.<option>' and is parsed from the
		// outside in, because the section may itself contain dots
		// (e.g. 'passwall2.@global[0].enabled').
		let sw = null;
		if (a.uci != null && ucix != null) {
			const first = index(a.uci, '.');
			const last = rindex(a.uci, '.');

			if (first > 0 && last > first) {
				const pkg = substr(a.uci, 0, first);
				const section = substr(a.uci, first + 1, last - first - 1);
				const opt = substr(a.uci, last + 1);

				try {
					ucix.load(pkg);
					const v = ucix.get(pkg, section, opt);
					if (v != null)
						sw = (v === true || v == '1' || v == 'true' || v == 'yes');
				}
				catch (e) {
					sw = null;
				}
			}
		}

		let state = 'unknown';
		if (!a.enabled)
			state = 'disabled';
		else if (pr.running === true)
			state = 'running';
		else if (pr.running === false)
			state = (sw === false) ? 'disabled' : 'stopped';

		push(out, {
			id: a.id,
			label: a.label ?? a.id,
			state: state,
			autostart: auto,
			switch: sw,
			probe: a.probe,
			detail: pr.detail ?? null,
			note: a.note ?? null,
			critical: a.critical,
			restartable: access(`/etc/init.d/${name}`) === true
		});
	}

	return out;
}

// ------------------------------------------------------------------ status ----
function status() {
	let disks = [];
	let apps = [];
	const cfg = read_config();

	try {
		disks = build_disks();
	}
	catch (e) {
		disks = [ { error: `${e}` } ];
	}

	// Nothing renders the app list while the card is switched off, and
	// build_apps() costs one process spawn per monitored entry - skip it.
	if (cfg.show_apps) {
		try {
			apps = build_apps(cfg);
		}
		catch (e) {
			apps = [ { error: `${e}` } ];
		}
	}

	return {
		ts: now(),
		backend: 'homestatus',
		version: VERSION,
		config: cfg,
		disks: disks,
		apps: apps
	};
}

// Candidates for the "key application" list: everything that has an init
// script, annotated with whether it is already monitored and what probe would
// fit. The frontend turns this into a picker.
//
// This deliberately does NOT use `rc list` (deadlocks inside rpcd). Autostart
// comes from /etc/rc.d instead.
// Init scripts that are boot-phase plumbing rather than manageable services.
const NOT_A_SERVICE = [
	'boot', 'done', 'cgroupfs-mount', 'sysfixtime', 'sysctl', 'mountd',
	'umount', 'leds', 'gpio_switch', 'urandom_seed'
];

// Candidate list size: find_procs rescans /proc per call, so scan once here.
function services() {
	const out = [];
	const monitored = {};
	const all = scan_procs();

	try {
		const c = cursor();
		c.load(UCI_PKG);
		c.foreach(UCI_PKG, 'app', (s) => {
			// the section name, the explicit id and the init script name can
			// all differ, and any of them identifies the entry for matching
			monitored[s['.name']] = true;
			if (s.id != null)
				monitored[s.id] = true;
			if (s.init != null)
				monitored[s.init] = true;
		});
	}
	catch (e) {
		// an unreadable config just means "nothing monitored yet"
	}

	let names = [];
	try {
		names = lsdir('/etc/init.d') ?? [];
	}
	catch (e) {
		return [ { error: `${e}` } ];
	}

	names = sort(names);

	for (let n in names) {
		const name = basename(n);

		if (!match(name, SVC_NAME_RE))
			continue;

		if (index(NOT_A_SERVICE, name) >= 0)
			continue;

		// Prefer an exact process-name match; fall back to a substring match on
		// the command line because several daemons rename themselves
		// (e.g. init script 'cron' runs as 'crond').
		let hits = filter(all, (p) => p.exe == name);
		let guess = 'exe';

		if (!length(hits)) {
			hits = filter(all, (p) => index(p.cmd, name) >= 0);
			guess = 'cmd';
		}

		push(out, {
			name: name,
			monitored: monitored[name] === true,
			autostart: autostart(name),
			running: length(hits) > 0,
			pid: length(hits) ? hits[0].pid : null,
			probe_guess: guess
		});
	}

	return out;
}

// -------------------------------------------------------------------- wol -----
// Wake-on-LAN targets.
//
// Storage: the targets live in the stock `luci-wol` UCI package as `wol`
// sections (/etc/config/luci-wol), i.e. the same data the official
// luci-app-wol page edits. One source of truth: a target added on the overview
// shows up under Services -> Wake on LAN and vice versa.
//
// Execution: while luci-app-wol ships a `luci.wol.exec` ubus method, this
// plugin MUST NOT call it - like `rc list`, calling another ubus object from
// inside rpcd deadlocks until the 30s timeout (see restart_service above).
// /usr/bin/etherwake is invoked directly through popen instead.
//
// The binary is fixed to etherwake on purpose: luci.wol's own whitelist only
// accepts etherwake and wakeonlan, and this build ships etherwake only
// (CONFIG_PACKAGE_wakeonlan is off - it is a perl script pulling in perl).
// etherwake additionally supports -i/-b, which wakeonlan does not.
const WOL_PKG = 'luci-wol';
const ETHERWAKE = '/usr/bin/etherwake';
const ARP_FILE = '/proc/net/arp';

// MAC as printed by `ip link` / uci: six hex octets, any case.
const MAC_RE = /^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$/;

// Interface names are kernel-validated; this is a shell-safety whitelist
// because the value reaches a popen command line.
const IFACE_RE = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,14}$/;

function norm_mac(mac) {
	if (mac == null)
		return null;

	/* Accept the separators people actually paste: `:` (unix/ip link),
	 * `-` (Windows ipconfig / Get-NetAdapter) and `.` (Cisco). Normalise to
	 * lower-case colon form, which is what etherwake and uci expect. */
	const s = lc(trim(`${mac}`));

	if (!match(s, /^[0-9a-f]{2}([-:.]?[0-9a-f]{2}){5}$/))
		return null;

	const bare = replace(replace(s, /[-:.]/g, ''), /^/, '');

	if (length(bare) != 12)
		return null;

	const out = [];

	for (let i = 0; i < 12; i += 2)
		push(out, substr(bare, i, 2));

	return join(':', out);
}

// /proc/net/arp: <ip> <hwtype> <flags> <mac> <mask> <device>
// flags are bit 0x2 = ATF_COM (entry complete). Incomplete/stale probes are
// listed with an all-zero MAC, which must not count as "present".
function read_arp() {
	const out = {};

	let txt = null;

	try {
		txt = readfile(ARP_FILE);
	}
	catch (e) {
		return out;
	}

	if (txt == null)
		return out;

	for (let line in split(trim(`${txt}`), '\n')) {
		const f = split(trim(line), /[ \t]+/);

		if (length(f) < 6)
			continue;

		const mac = norm_mac(f[3]);

		if (mac == null || mac == '00:00:00:00:00:00')
			continue;

		// Several IPs may map to one MAC (multi-homed host) - keep the first.
		if (out[mac] == null)
			out[mac] = { ip: f[0], device: f[5], flags: f[2] };
	}

	return out;
}

// Read errors are surfaced rather than swallowed - a silent empty list is
// indistinguishable from "no targets configured" in the UI.
let WOL_CFG_ERR = null;

function wol_targets_cfg() {
	const list = [];

	WOL_CFG_ERR = null;

	try {
		const c = cursor();
		c.load(WOL_PKG);

		/* The stock luci-app-wol page stores each target as `config target`,
		 * while an older local draft of this app used `config wol`. Read
		 * both so existing configs keep working and the official page stays
		 * interoperable; writes always go out as `target`. */
		for (let stype in [ 'target', 'wol' ]) {
			c.foreach(WOL_PKG, stype, (s) => {
				if (s.name == null && s.mac == null)
					return;

				const mac = norm_mac(s.mac);

				/* ucode arrays have no methods - push(a, v) is the global form */
				push(list, {
					id: s['.name'],
					name: s.name ?? mac ?? s['.name'],
					mac: mac,
					/* an unparseable mac is surfaced, not silently dropped -
					 * it is the one thing that makes waking fail */
					invalid_mac: mac == null ? (s.mac ?? null) : null,
					iface: s.iface ?? null,
					broadcast: s.broadcast == '1',
					password: s.password ?? null
				});
			});
		}
	}
	catch (e) {
		WOL_CFG_ERR = `${e}`;
	}

	return list;
}

function build_wol_targets() {
	const arp = read_arp();
	const list = wol_targets_cfg();
	const out = [];

	for (let t in list) {
		const seen = t.mac != null ? arp[t.mac] : null;

		push(out, {
			id: t.id,
			name: t.name,
			mac: t.mac,
			invalid_mac: t.invalid_mac,
			iface: t.iface,
			broadcast: t.broadcast,
			/* present in the neighbour table == the NIC is reachable, so a
			 * magic packet can actually land */
			online: t.mac != null && seen != null,
			ip: seen?.ip ?? null,
			via: seen?.device ?? null
		});
	}

	return out;
}

// Pick the interface to inject the magic packet on.
//
// Order: explicit per-target override -> the device the target was last seen
// on -> br-lan -> lan -> first non-loopback device in /proc/net/dev.
function pick_iface(target, ctx) {
	if (target?.iface != null && match(target.iface, IFACE_RE))
		return target.iface;

	if (target?.via != null && match(target.via, IFACE_RE))
		return target.via;

	const cand = [ 'br-lan', 'lan' ];

	for (let c in cand)
		if (ctx?.devs?.[c] === true)
			return c;

	return ctx?.firstDev ?? null;
}

function iface_present() {
	const out = { devs: {}, firstDev: null };

	let txt = null;

	try {
		txt = readfile('/proc/net/dev');
	}
	catch (e) {
		return out;
	}

	if (txt == null)
		return out;

	for (let line in split(`${txt}`, '\n')) {
		const m = match(line, /^\s*([^\s:]+):/);

		if (m == null)
			continue;

		const dev = m[1];

		if (dev == 'lo')
			continue;

		/* sit0/gre0/... sit at the tail; only real elements are useful as a
		 * fallback, so anything with a non-ethernet prefix is skipped */
		if (match(dev, /^(sit|gre|gretap|erspan|dummy|tun|tap)/))
			continue;

		out.devs[dev] = true;

		if (out.firstDev == null)
			out.firstDev = dev;
	}

	return out;
}

function wake_target(payload) {
	const id = payload?.id ?? null;
	const macIn = payload?.mac ?? null;

	let target = null;

	if (id != null) {
		for (let t in build_wol_targets())
			if (t.id == id) {
				target = t;
				break;
			}

		if (target == null)
			return { ok: false, error: 'not-found', message: `${id} 不在唤醒列表中` };
	}
	else if (norm_mac(macIn) != null) {
		target = { name: macIn, mac: norm_mac(macIn) };
	}
	else {
		return { ok: false, error: 'no-target' };
	}

	if (target.mac == null)
		return { ok: false, error: 'bad-mac', message: `MAC 地址无效：${target.invalid_mac ?? ''}` };

	if (access(ETHERWAKE, 'x') !== true)
		return { ok: false, error: 'no-etherwake', message: `${ETHERWAKE} 不存在` };

	const iface = pick_iface(target, iface_present());

	/* etherwake is a broadcast tool: without -i it picks the interface itself
	 * and on a multi-nic x86 box it can pick the WAN side. Always state it. */
	const args = [];

	if (iface != null)
		push(args, '-i', iface);

	if (target.broadcast === true)
		push(args, '-b');

	/* etherwake wants the colon form here: `-p 00:22:44:66:88:aa` is
	 * accepted and logged ("The Magic packet password is ..."), while a
	 * bare hex string is rejected with "Unable to read the Wake-On-LAN
	 * password". Pass it through unchanged after whitelisting, because the
	 * value reaches the shell. */
	if (target.password != null && match(`${target.password}`, /^[0-9a-fA-F:]{6,23}$/))
		push(args, '-p', lc(`${target.password}`));

	push(args, target.mac);

	let out = '';
	let rc = null;

	try {
		/* iface passed the IFACE_RE whitelist and the mac the MAC_RE one, so
		 * no unvalidated string reaches the shell */
		const fd = popen(`${ETHERWAKE} ${join(' ', args)} 2>&1`);
		out = trim(fd.read('all') ?? '');
		rc = fd.close();
	}
	catch (e) {
		return { ok: false, error: 'exec-failed', message: `${e}` };
	}

	if (rc != 0)
		return { ok: false, error: 'exit-code', code: rc, message: out || `etherwake 返回 ${rc}` };

	return { ok: true, id: target.id ?? null, name: target.name, mac: target.mac, iface: iface, output: out };
}

// Replace the whole target list (so removals take effect), mirroring the way
// set_config handles the app list.
function set_wol_targets(payload) {
	const listIn = payload?.targets ?? null;

	if (listIn == null || type(listIn) != 'array')
		return { ok: false, error: 'no-targets' };

	const clean = [];
	const rejected = [];

	for (let t in listIn) {
		if (t == null)
			continue;

		const mac = norm_mac(t.mac);
		const name = trim(`${t.name ?? ''}`);

		/* Report what was dropped instead of silently discarding it - the UI
		 * echoes this back so a typo'd MAC never vanishes without a reason. */
		if (mac == null) {
			push(rejected, { name: name, mac: `${t.mac ?? ''}`, reason: 'bad-mac' });
			continue;
		}

		if (name == '') {
			push(rejected, { name: '', mac: mac, reason: 'no-name' });
			continue;
		}

		push(clean, {
			name: name,
			mac: mac,
			iface: t.iface ?? null,
			broadcast: t.broadcast === true,
			password: t.password ?? null
		});
	}

	try {
		const c = cursor();
		c.load(WOL_PKG);

		c.foreach(WOL_PKG, 'target', (s) => {
			/* never touch the stock `defaults` section - it holds the
			 * executable preference the official page writes */
			if (s['.name'] != 'defaults')
				c.delete(WOL_PKG, s['.name']);
		});

		c.foreach(WOL_PKG, 'wol', (s) => {
			/* migrate any section written by an earlier revision of this
			 * app to the stock `target` type */
			if (s['.name'] != 'defaults')
				c.delete(WOL_PKG, s['.name']);
		});

		for (let t in clean) {
			/* `target` is what the stock luci-app-wol page reads, so keep
			 * both pages looking at the same sections */
			const sec = c.add(WOL_PKG, 'target');

			c.set(WOL_PKG, sec, 'name', t.name);
			/* store lower-case, like the official luci-app-wol page does */
			c.set(WOL_PKG, sec, 'mac', t.mac);

			if (t.iface != null && match(t.iface, IFACE_RE))
				c.set(WOL_PKG, sec, 'iface', t.iface);

			if (t.broadcast)
				c.set(WOL_PKG, sec, 'broadcast', '1');

			/* SecureOn password: colon form, which is what etherwake
			 * accepts. Whitelisted because it reaches the shell. */
			if (t.password != null && match(`${t.password}`, /^[0-9a-fA-F:]{6,23}$/))
				c.set(WOL_PKG, sec, 'password', lc(`${t.password}`));
		}

		c.commit(WOL_PKG);
	}
	catch (e) {
		return { ok: false, error: `${e}` };
	}

	return { ok: true, targets: build_wol_targets(), rejected: rejected };
}

// --------------------------------------------------------------- netprobe ----
// Router-LOCAL dual-path reachability probe for the overview "互联网" KPI.
//
// Why popen+curl and not the browser: the KPI must reflect what traffic
// leaving THE ROUTER experiences - the router's own resolver, its routing
// table and (with passwall2 localhost_proxy enabled) its proxy chain. A
// browser-side fetch tests the ADMIN PC's path instead, which is a
// different question entirely.
//
// Two targets with distinct meaning:
//   cn   - https://www.baidu.com   domestic direct egress
//   intl - https://www.google.com  overseas; with passwall2 running and
//          localhost_proxy=1 the router's own OUTPUT traffic is proxied,
//          so this exercises the same chain LAN clients use. With the
//          proxy off it fails exactly like un-proxied traffic would -
//          that is the truth we want to show.
//
// One curl --parallel invocation probes both concurrently; each URL
// writes one %{json} line on stdout. Timing fields name the failure
// phase (time_namelookup / time_connect / time_appconnect), exitcode +
// errormsg carry the reason. read_config() allows overriding the two
// targets (probe_cn / probe_intl) without touching this file.
const CURL = '/usr/bin/curl';

const CURL_EXIT_REASONS = {
	'4': 'HTTP 协议错误',
	'5': '无法解析代理地址',
	'6': '域名解析失败（DNS）',
	'7': '连接被拒绝',
	'21': 'FTP 命令错误',
	'22': 'HTTP 状态异常',
	'26': '读取文件失败',
	'28': '连接超时',
	'30': 'FTP 端口错误',
	'35': 'TLS 握手失败',
	'47': '重定向次数过多',
	'51': '证书校验失败',
	'55': '发送数据失败',
	'56': '接收数据失败',
	'60': '证书已过期或无效',
	'61': '内容编码错误',
	'66': '未知传输协议',
	'77': 'CA 证书读取失败',
	'88': 'FTP 登录失败',
	'90': 'FTP 访问被拒',
	'92': 'HTTP/2 流错误',
	'94': '认证方式不受支持',
	'95': 'HTTP/3 错误',
};

// Probe one batch { cn: url, intl: url } through a single parallel curl.
// Returns { cn: result, intl: result } where result is:
//   { ok: true, ms, ip, code }                    on success
//   { ok: false, reason, exitcode, stage, ms }    on failure
function netprobe_run(targets) {
	const urls = [ targets.cn, targets.intl ];
	// lightweight per-URL write-out: one line per URL (curl emits the
	// -w block once per URL in --parallel mode), fields separated so we
	// can split them without a JSON parser tripwire (the full %{json}
	// blob embeds the whole peer certificate - huge and fragile).
	const WF = 'URL=%{url_effective} IP=%{remote_ip} CODE=%{http_code} NL=%{time_namelookup} CT=%{time_connect} AC=%{time_appconnect} TT=%{time_total} ERR=%{errormsg} EC=%{exitcode}\\n';
	/* one -o per URL: in --parallel mode -o applies to the NEXT url only,
	 * a single /dev/null would let the second body leak to stdout */
	const cmd = `${CURL} -s -o /dev/null -o /dev/null -w '${WF}' --parallel --parallel-max 2 --connect-timeout 4 -m 8 ${join(' ', urls)}`;

	let out = '';
	let rc = null;

	try {
		const fd = popen(`${cmd} 2>&1`);
		out = fd.read('all') ?? '';
		rc = fd.close();
	}
	catch (e) {
		return { cn: { ok: false, reason: `探测执行失败：${e}` }, intl: { ok: false, reason: `探测执行失败：${e}` } };
	}

	// parse one "KEY=VALUE ..." record per line. ERR (curl errormsg) may
	// contain spaces, so the line is split from the right at the known
	// " ERR=" key marker instead of naive whitespace tokenisation.
	const parsed = [];

	for (let l in split(out, '\n')) {
		const t = trim(l);

		if (length(t) == 0 || index(t, 'URL=') != 0)
			continue;

		const rec = {};
		let head = t;

		// tail: " ERR=<free text> EC=<int>"
		const ecpos = rindex(t, ' EC=');

		if (ecpos > 0) {
			rec.EC = substr(t, ecpos + 4);
			head = substr(t, 0, ecpos);

			const errpos = rindex(head, ' ERR=');

			if (errpos > 0) {
				rec.ERR = substr(head, errpos + 5);
				head = substr(head, 0, errpos);
			}
		}

		for (let kv in split(head, ' ')) {
			const eq = index(kv, '=');

			if (eq <= 0)
				continue;

			rec[substr(kv, 0, eq)] = substr(kv, eq + 1);
		}

		push(parsed, rec);
	}

	// match records back to the requested urls: exact first, then
	// scheme+host prefix, so a http->https redirect still lands
	const mkResult = (url, want) => {
		let j = null;

		for (let p in parsed)
			if (p.URL == url || `${p.URL}/` == url || url == `${p.URL}/`)
				j = p;

		if (j == null)
			for (let p in parsed)
				if (index(p.URL ?? '', want.host) >= 0)
					j = p;

		if (j == null)
			return { ok: false, reason: '无探测结果', exitcode: rc };

		const ec = int(j.EC ?? -1);
		const code = int(j.CODE ?? 0);
		const tt = +j.TT ?? 0;

		if (ec == 0 && code >= 200 && code < 400)
			return { ok: true, ms: int(tt * 1000), ip: j.IP, code: code };

		// failure: name the phase from the timing ladder
		const nl = +j.NL ?? 0;
		const ct = +j.CT ?? 0;
		const ac = +j.AC ?? 0;
		let stage = null;

		if (nl <= 0.0001)
			stage = 'dns';
		else if (ct <= 0.0001)
			stage = 'connect';
		else if (ac <= 0.0001)
			stage = 'tls';

		const base = CURL_EXIT_REASONS[`${ec}`] ?? ((ec == 0) ? `HTTP 状态 ${code}` : `curl 退出码 ${ec}`);

		return {
			ok: false,
			reason: j.ERR ? (`${base}：${j.ERR}`) : base,
			exitcode: ec,
			stage: stage,
			ms: int(tt * 1000),
			ip: (j.IP ?? '') || null
		};
	};

	function hostOf(url) {
		const m = match(`${url}`, /^https?:\/\/([^\/]+)/);

		return m ? m[1] : `${url}`;
	}

	return {
		cn: mkResult(targets.cn, { host: hostOf(targets.cn) }),
		intl: mkResult(targets.intl, { host: hostOf(targets.intl) })
	};
}

function netprobe() {
	const cfg = read_config();

	const targets = {
		cn: cfg.probe_cn ?? 'https://www.baidu.com',
		intl: cfg.probe_intl ?? 'https://www.google.com'
	};

	if (access(CURL, 'x') !== true)
		return { ok: false, error: 'no-curl', message: `未安装 ${CURL}（opkg install curl）` };

	return { ok: true, ts: now(), targets: targets, result: netprobe_run(targets) };
}

// ------------------------------------------------------------------ methods ---
// NOTE: rpcd's ucode loader rejects the whole plugin if a method is added to
// this object *after* its literal is defined (e.g. `methods.foo = fn;` on a
// later line) - the ubus object then silently fails to register while
// `ucode -c` still reports success. Every method must live inside this
// literal. Verified on rpcd 2024-12-02-cc9a471c (24.10.5).
//
// Every method that takes a message must declare a Table-typed arg, otherwise
// ubus rejects the call with `Invalid argument` before the plugin is ever
// entered. `args: {}` is NOT enough - the signature stays empty and ubus
// refuses to accept a message at all. The call then reads the payload from
// req.args.<name> (verified on 24.10.5; luci.wol's exec does the same).
let DEBUG = false;

const methods = {
	status: {
		call: function() {
			return status();
		}
	},

	// Monitorable candidates (anything with an init script) for the settings
	// page picker.
	services: {
		call: function() {
			try {
				return { ok: true, services: services() };
			}
			catch (e) {
				return { ok: false, error: `${e}` };
			}
		}
	},

	// Persist global thresholds and/or the monitored app list. Accepts:
	//   { config: { enabled, warn, crit }, apps: [ {id, label, probe, ...} ] }
	// Both keys are optional; whatever is present is applied.
	//
	// cursor().commit() is the only method that reaches /etc/config - save()
	// merely stages into /tmp/.uci (verified on 24.10.5).
	set_config: {
		args: { payload: {} },
		call: function(req) {
			const req_ = req?.args?.payload ?? null;

			if (req_ == null)
				return { ok: false, error: 'no-payload' };

			const cfgIn = req_.config;
			const appsIn = req_.apps;

			const done = { config: false, apps: false };

			try {
				const c = cursor();
				c.load(UCI_PKG);

				if (cfgIn != null) {
					c.set(UCI_PKG, 'global', 'global');

					for (let k, v in cfgIn) {
						if (v == null)
							continue;
						c.set(UCI_PKG, 'global', k,
						      type(v) == 'bool' ? (v ? '1' : '0') : `${v}`);
					}

					done.config = true;
				}

				if (appsIn != null && type(appsIn) == 'array') {
					// replace the whole list so removals take effect
					c.foreach(UCI_PKG, 'app', (s) => c.delete(UCI_PKG, s['.name']));

					for (let a in appsIn) {
						if (a == null || a.id == null)
							continue;
						if (!match(`${a.id}`, SVC_NAME_RE))
							continue;

						const sec = c.add(UCI_PKG, 'app');
						c.set(UCI_PKG, sec, 'id', a.id);
						c.set(UCI_PKG, sec, 'label', a.label ?? a.id);
						c.set(UCI_PKG, sec, 'probe', a.probe ?? 'exe');

						if (a.enabled != null) c.set(UCI_PKG, sec, 'enabled', a.enabled ? '1' : '0');
						if (a.init != null)   c.set(UCI_PKG, sec, 'init', a.init);
						if (a.match != null)  c.set(UCI_PKG, sec, 'match', a.match);
						if (a.port != null)   c.set(UCI_PKG, sec, 'port', `${a.port}`);
						if (a.path != null)   c.set(UCI_PKG, sec, 'path', a.path);
						if (a.note != null)   c.set(UCI_PKG, sec, 'note', a.note);
						if (a.uci != null)    c.set(UCI_PKG, sec, 'uci', a.uci);
						if (a.order != null)  c.set(UCI_PKG, sec, 'order', `${a.order}`);

						// rename the auto-generated section to the id so the config
						// stays readable; `id` is still written explicitly because a
						// section name colliding with a reserved word (e.g. "global")
						// makes uci fall back to a generated name
						c.rename(UCI_PKG, sec, a.id);
					}

					done.apps = true;
				}

				c.commit(UCI_PKG);
			}
			catch (e) {
				return { ok: false, error: `${e}`, applied: done };
			}

			return { ok: true, applied: done, config: read_config() };
		}
	},

	// Restart one monitored application.
	restart_app: {
		args: { payload: {} },
		call: function(req) {
			const id = req?.args?.payload?.id ?? null;

			if (id == null)
				return { ok: false, error: 'no-id' };

			// The id must be a monitored app - never an arbitrary init script.
			// Match against the `id` option first (what the UI shows and sends),
			// falling back to the section name for configs written by hand.
			let entry = null;
			let c = null;

			try {
				c = cursor();
				c.load(UCI_PKG);
				c.foreach(UCI_PKG, 'app', (s) => {
					if ((s.id ?? s['.name']) == id)
						entry = s;
				});
			}
			catch (e) {
				return { ok: false, error: 'config-unreadable', message: `${e}` };
			}

			if (entry == null)
				return { ok: false, error: 'not-monitored', message: `${id} 不在监视列表中` };

			const name = entry.init ?? entry.id ?? entry['.name'] ?? id;
			const rv = restart_service(name);
			rv.id = id;
			return rv;
		}
	},

	// Router-local dual-path reachability probe (see netprobe section above).
	// Read-only; one curl --parallel run, bounded by -m 8.
	netprobe: {
		call: function() {
			try {
				return netprobe();
			}
			catch (e) {
				return { ok: false, error: `${e}` };
			}
		}
	},

	// Wake-on-LAN targets, merged with neighbour-table presence.
	// Read-only; sleep/wake state comes from /proc/net/arp, not from a ping, so
	// this stays cheap enough for the overview poll.
	wol_targets: {
		call: function() {
			try {
				const targets = build_wol_targets();

				return {
					ok: true,
					targets: targets,
					etherwake: access(ETHERWAKE, 'x') === true,
					/* read_error is null on success; when set, `targets` is
					 * empty because the config could not be read, NOT because
					 * none are configured - the UI must say so. */
					read_error: WOL_CFG_ERR
				};
			}
			catch (e) {
				return { ok: false, error: `${e}` };
			}
		}
	},

	// Send one magic packet. Accepts { id } for a configured target or { mac }
	// for an ad-hoc wake.
	wake: {
		args: { payload: {} },
		call: function(req) {
			const p = req?.args?.payload ?? null;

			if (p == null)
				return { ok: false, error: 'no-payload' };

			try {
				return wake_target(p);
			}
			catch (e) {
				return { ok: false, error: `${e}` };
			}
		}
	},

	// Replace the whole target list: { targets: [ { name, mac, iface?, broadcast? } ] }
	set_wol_targets: {
		args: { payload: {} },
		call: function(req) {
			const p = req?.args?.payload ?? null;

			if (p == null)
				return { ok: false, error: 'no-payload' };

			try {
				return set_wol_targets(p);
			}
			catch (e) {
				return { ok: false, error: `${e}` };
			}
		}
	}
};

if (DEBUG)
	warn(sprintf('%s\n', 'homestatus: debug build'));

return { 'luci.homestatus': methods };
