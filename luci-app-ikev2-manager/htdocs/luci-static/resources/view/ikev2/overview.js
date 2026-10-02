'use strict';
'require view';
'require rpc';
'require ui';

var callStatus      = rpc.declare({ object: 'ikev2mgr', method: 'status' });
var callListUsers   = rpc.declare({ object: 'ikev2mgr', method: 'list_users' });
var callGetSettings = rpc.declare({ object: 'ikev2mgr', method: 'get_settings' });
var callSetSettings = rpc.declare({ object: 'ikev2mgr', method: 'set_settings', params: [ 'remote', 'vpn_name' ] });
var callAddUser     = rpc.declare({ object: 'ikev2mgr', method: 'add_user', params: [ 'name', 'password' ] });
var callDelUser     = rpc.declare({ object: 'ikev2mgr', method: 'del_user', params: [ 'name' ] });
var callMobileCfg   = rpc.declare({ object: 'ikev2mgr', method: 'mobileconfig', params: [ 'name' ] });

function reload() { return location.reload(); }
function fail(res, action) {
	if (res && res.ok) return true;
	ui.addNotification(null, E('p', _('%s failed: %s').format(action, (res && res.error) || _('unknown error'))), 'danger');
	return false;
}
function randpw() {
	var c = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789', s = '';
	var a = new Uint8Array(16); (window.crypto || crypto).getRandomValues(a);
	for (var i = 0; i < 16; i++) s += c[a[i] % c.length];
	return s;
}

return view.extend({
	load: function() { return Promise.all([ callStatus(), callListUsers(), callGetSettings() ]); },
	render: function(data) {
		var st = data[0] || {}, ul = data[1] || {}, set = data[2] || {};
		var users = (ul && ul.users) || [];
		var clients = (st && st.clients) || [];
		var nodes = E('div', {}, [
			E('h2', {}, _('IKEv2 VPN Users')),
			E('p', { 'class': 'cbi-section-descr' },
				_('Manage EAP username/password accounts for the strongSwan IKEv2 server, and download ready-to-install iOS/macOS profiles. Requires the strongSwan IKEv2 server to be configured.'))
		]);
		var badge = function(okv, t, f) { return E('span', { 'style': 'color:' + (okv ? '#2e7d32' : '#c62828') }, okv ? ('✓ ' + t) : ('✗ ' + f)); };
		var sBox = E('div', { 'class': 'cbi-section' }, [ E('h3', {}, _('Server status')),
			E('table', { 'class': 'table' }, [
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '33%' }, _('strongSwan (charon)')), E('td', { 'class': 'td left' }, badge(st.running, _('running'), _('stopped'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Listening (500/4500)')), E('td', { 'class': 'td left' }, badge(st.listening, _('yes'), _('no'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Server certificate / CA')), E('td', { 'class': 'td left' }, badge(st.pki_ready, _('present'), _('missing'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Connected clients')), E('td', { 'class': 'td left' }, String(clients.length)) ])
			]) ]);
		if (clients.length) {
			var crows = [ E('tr', { 'class': 'tr table-titles' }, [ E('th', { 'class': 'th' }, _('User')), E('th', { 'class': 'th' }, _('VPN IP')), E('th', { 'class': 'th' }, _('Remote IP')) ]) ];
			clients.forEach(function(c) { crows.push(E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td' }, c.user), E('td', { 'class': 'td' }, c.vip), E('td', { 'class': 'td' }, c.remote_ip) ])); });
			sBox.appendChild(E('div', { 'class': 'table cbi-section-table', 'style': 'margin-top:.5em' }, crows));
		}
		nodes.appendChild(sBox);
		var sRemote = E('input', { 'type': 'text', 'value': set.remote || '', 'placeholder': 'vpn.example.com', 'style': 'width:16em' });
		var sName = E('input', { 'type': 'text', 'value': set.vpn_name || 'Home IKEv2', 'style': 'width:16em' });
		nodes.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Client profile settings')),
			E('p', { 'class': 'cbi-section-descr' }, _('Used when generating .mobileconfig profiles. Remote is your DDNS / public IP — never stored in the app source.')),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Server address (DDNS/IP)')), E('div', { 'class': 'cbi-value-field' }, sRemote) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('VPN display name')), E('div', { 'class': 'cbi-value-field' }, sName) ]),
			E('div', { 'class': 'cbi-value' }, [ E('div', { 'class': 'cbi-value-field' }, E('button', {
				'class': 'btn cbi-button cbi-button-save',
				'click': ui.createHandlerFn(this, function() { return callSetSettings(sRemote.value, sName.value).then(function(r) { if (fail(r, _('Save settings'))) ui.addNotification(null, E('p', _('Saved.')), 'info'); }); })
			}, _('Save settings'))) ])
		]));
		var rows = [ E('tr', { 'class': 'tr table-titles' }, [ E('th', { 'class': 'th' }, _('Username')), E('th', { 'class': 'th cbi-section-actions' }, _('Actions')) ]) ];
		if (!users.length) rows.push(E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td', 'colspan': 2 }, E('em', {}, _('No users yet.'))) ]));
		users.forEach(function(u) {
			rows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, u.name),
				E('td', { 'class': 'td cbi-section-actions' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, function() {
						return callMobileCfg(u.name).then(function(r) {
							if (!fail(r, _('Generate profile'))) return;
							var blob = new Blob([ r.mobileconfig ], { type: 'application/x-apple-aspen-config' });
							var a = E('a', { 'href': URL.createObjectURL(blob), 'download': u.name + '.mobileconfig' });
							document.body.appendChild(a); a.click(); document.body.removeChild(a);
						});
					}) }, _('Download .mobileconfig')),
					' ',
					E('button', { 'class': 'btn cbi-button cbi-button-remove', 'click': ui.createHandlerFn(this, function() {
						if (!confirm(_('Delete user "%s"? They will no longer be able to connect.').format(u.name))) return;
						return callDelUser(u.name).then(function(r) { if (fail(r, _('Delete'))) reload(); });
					}) }, _('Delete'))
				])
			]));
		});
		var nName = E('input', { 'type': 'text', 'placeholder': _('e.g. alice, iphone'), 'style': 'width:12em' });
		var nPw = E('input', { 'type': 'text', 'value': '', 'placeholder': _('password'), 'style': 'width:14em' });
		nodes.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('EAP accounts')),
			E('div', { 'class': 'table cbi-section-table' }, rows),
			E('div', { 'class': 'cbi-value', 'style': 'margin-top:1em' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Add user')),
				E('div', { 'class': 'cbi-value-field' }, [ nName, ' ', nPw, ' ',
					E('button', { 'class': 'btn cbi-button', 'click': function() { nPw.value = randpw(); } }, _('Random')), ' ',
					E('button', { 'class': 'btn cbi-button cbi-button-add', 'click': ui.createHandlerFn(this, function() {
						var n = (nName.value || '').trim(), p = (nPw.value || '').trim();
						if (!n || !p) { ui.addNotification(null, E('p', _('Enter a username and password.')), 'warning'); return; }
						return callAddUser(n, p).then(function(r) { if (fail(r, _('Add user'))) { ui.addNotification(null, E('p', _('Added "%s".').format(n)), 'info'); reload(); } });
					}) }, _('Add'))
				]) ])
		]));
		return nodes;
	},
	handleSaveApply: null, handleSave: null, handleReset: null
});
