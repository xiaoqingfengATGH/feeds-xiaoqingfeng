'use strict';
'require baseclass';
'require rpc';

/*
 * Shared plumbing for the luci-app-homestatus overview blocks.
 *
 * Note this returns a baseclass subclass, not a plain object: LuCI's module
 * loader rejects any factory whose result is not a Class instance
 * ("factory yields invalid constructor"), so a bare object literal would make
 * every dependent module fail to load.
 *
 * The overview page polls every include separately, so raw per-block calls to
 * luci.homestatus.status() would double the ubus traffic.  Both blocks go
 * through status() here, which memoises the reply for a short window: the two
 * blocks render within the same poll tick, so the second one hits the cache.
 *
 * That cache lives in the *browser*, not in rpcd - a module-level cache inside
 * the rpcd plugin would survive across requests and freeze the first
 * observation forever (verified: a stopped daemon kept reporting its original
 * pid).
 */

var callStatus = rpc.declare({
	object: 'luci.homestatus',
	method: 'status',
	expect: {}
});

var callRestart = rpc.declare({
	object: 'luci.homestatus',
	method: 'restart_app',
	params: [ 'payload' ],
	expect: {}
});

var callServices = rpc.declare({
	object: 'luci.homestatus',
	method: 'services',
	expect: {}
});

var _cache = null;
var _at = 0;

var WARN_COLOR = '#e0a800';
var CRIT_COLOR = '#dc3545';

/* Both overview blocks require this module, so loading the stylesheet here
 * guarantees it is present exactly once and before either block renders. */
if (typeof(document) != 'undefined' && document.querySelector('head') != null
    && document.querySelector('link[href*="homestatus.css"]') == null) {
	document.querySelector('head').appendChild(E('link', {
		'rel': 'stylesheet',
		'type': 'text/css',
		'href': L.resource('view/homestatus/homestatus.css')
	}));
}

return baseclass.extend({
	/* maxAge=0 forces a refetch past the memo window. */
	status: function(maxAge) {
		var ttl = (maxAge == null) ? 1500 : maxAge;
		var now = Date.now();

		if (_cache != null && (now - _at) < ttl)
			return Promise.resolve(_cache);

		return L.resolveDefault(callStatus(), null).then(function(r) {
			if (r != null) {
				_cache = r;
				_at = Date.now();
			}

			return r;
		});
	},

	invalidate: function() {
		_cache = null;
		_at = 0;
	},

	restart: function(id) {
		return callRestart({ id: id });
	},

	services: function() {
		return L.resolveDefault(callServices(), null);
	},

	fmtBytes: function(b) {
		if (b == null || isNaN(b))
			return '—';

		return String.format('%1024.2mB', b);
	},

	barColor: function(pct, cfg) {
		var warn = (cfg && cfg.warn) || 80;
		var crit = (cfg && cfg.crit) || 90;

		if (pct >= crit)
			return CRIT_COLOR;

		if (pct >= warn)
			return WARN_COLOR;

		return null;
	},

	/* state -> badge. 'disabled' means the app's own master switch is off,
	 * which is a different thing from "enabled but not currently running". */
	badge: function(app) {
		switch (app.state) {
		case 'running':
			return { cls: 'badge-soft-success', text: _('运行中') };
		case 'stopped':
			return { cls: 'badge-soft-danger', text: _('已停止') };
		case 'disabled':
			return { cls: 'badge-soft-secondary', text: _('已禁用') };
		default:
			return { cls: 'badge-soft-warning', text: _('未知') };
		}
	}
});
