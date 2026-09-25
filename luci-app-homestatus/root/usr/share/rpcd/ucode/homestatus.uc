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
function read_config() {
	const cfg = { enabled: true, warn: 80, crit: 90 };

	try {
		const ctx = cursor();
		ctx.load(UCI_PKG);

		ctx.foreach(UCI_PKG, 'global', (s) => {
			if (s.enabled != null)
				cfg.enabled = (s.enabled == '1' || s.enabled == 'true');
			if (s.warn != null && !isnan(int(s.warn)))
				cfg.warn = int(s.warn);
			if (s.crit != null && !isnan(int(s.crit)))
				cfg.crit = int(s.crit);
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
			if (s.enabled == '0' || s.enabled == 'false')
				return;

			push(entries, {
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
				order: int(s.order ?? 999)
			});
		});
	}
	catch (e) {
		return [ { error: `${e}` } ];
	}

	// stable order: explicit order first, then id
	entries = sort(entries, (a, b) => (a.order - b.order) || (a.id < b.id ? -1 : 1));

	// warm the process table once so per-app lookups are pure array filters
	scan_procs();

	for (let a in entries) {
		const name = a.init ?? a.id;
		const pr = probe_app(a, null);
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
		if (pr.running === true)
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
			restartable: access(`/etc/init.d/${name}`) === true
		});
	}

	return out;
}

// ------------------------------------------------------------------ status ----
function status() {
	let disks = [];
	let apps = [];

	try {
		disks = build_disks();
	}
	catch (e) {
		disks = [ { error: `${e}` } ];
	}

	try {
		apps = build_apps(read_config());
	}
	catch (e) {
		apps = [ { error: `${e}` } ];
	}

	return {
		ts: now(),
		backend: 'homestatus',
		version: VERSION,
		config: read_config(),
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
	}
};

if (DEBUG)
	warn(sprintf('%s\n', 'homestatus: debug build'));

return { 'luci.homestatus': methods };
