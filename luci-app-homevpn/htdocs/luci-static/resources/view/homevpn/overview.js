'use strict';
'require view';
'require rpc';
'require ui';

var callStatus      = rpc.declare({ object: 'homevpn', method: 'status' });
var callListUsers   = rpc.declare({ object: 'homevpn', method: 'list_users' });
var callGetSettings = rpc.declare({ object: 'homevpn', method: 'get_settings' });
var callSetSettings = rpc.declare({ object: 'homevpn', method: 'set_settings', params: [ 'remote', 'vpn_name', 'cert_mode', 'acme_domain' ] });
var callAddUser     = rpc.declare({ object: 'homevpn', method: 'add_user', params: [ 'name', 'password' ] });
var callDelUser     = rpc.declare({ object: 'homevpn', method: 'del_user', params: [ 'name' ] });
var callProvision   = rpc.declare({ object: 'homevpn', method: 'provision' });
var callDownload    = rpc.declare({ object: 'homevpn', method: 'download', params: [ 'name', 'what' ] });

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
function saveBlob(text, filename, mime) {
	var blob = new Blob([ text ], { type: mime });
	var a = E('a', { 'href': URL.createObjectURL(blob), 'download': filename });
	document.body.appendChild(a); a.click(); document.body.removeChild(a);
}

return view.extend({
	load: function() { return Promise.all([ callStatus(), callListUsers(), callGetSettings() ]); },
	render: function(data) {
		var st = data[0] || {}, ul = data[1] || {}, set = data[2] || {};
		var users = (ul && ul.users) || [];
		var clients = (st && st.clients) || [];
		var badge = function(okv, t, f) { return E('span', { 'style': 'color:' + (okv ? '#2e7d32' : '#c62828') }, okv ? ('✓ ' + t) : ('✗ ' + f)); };

		var nodes = E('div', {}, [
			E('h2', {}, _('HomeVPN — IKEv2 Server')),
			E('p', { 'class': 'cbi-section-descr' },
				_('Turnkey strongSwan IKEv2 VPN server: clients dial in with username/password (EAP-MSCHAPv2) and become full LAN members via DHCP pool + ARP proxy.'))
		]);

		/* ---- server status + readiness ---- */
		var modeLabel = { selfsigned: _('Self-signed'), import: _('Imported'), acme: _('ACME (Let\u0027s Encrypt)') };
		var sBox = E('div', { 'class': 'cbi-section' }, [ E('h3', {}, _('Server status')),
			E('table', { 'class': 'table' }, [
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '33%' }, _('strongSwan (charon)')), E('td', { 'class': 'td left' }, badge(st.running, _('running'), _('stopped'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Listening (500/4500)')), E('td', { 'class': 'td left' }, badge(st.listening, _('yes'), _('no'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Certificate mode')), E('td', { 'class': 'td left' }, modeLabel[st.mode] || st.mode) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Server certificate / CA')), E('td', { 'class': 'td left' }, badge(st.pki_ready, _('present'), _('missing'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Certificate SAN matches server address')), E('td', { 'class': 'td left' }, badge(st.san_ok, _('match'), _('MISMATCH — clients cannot connect'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Firewall INPUT rules (500/4500/ESP)')), E('td', { 'class': 'td left' }, badge(st.input_rules, _('present'), _('missing'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Connection loaded in charon')), E('td', { 'class': 'td left' }, badge(st.conn_loaded, _('loaded'), _('not loaded'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Server address (clients dial)')), E('td', { 'class': 'td left' }, st.remote || _('(not set — WAN IP will be used)')) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Connected clients')), E('td', { 'class': 'td left' }, String(clients.length)) ])
			]) ]);
		if (clients.length) {
			var crows = [ E('tr', { 'class': 'tr table-titles' }, [ E('th', { 'class': 'th' }, _('User')), E('th', { 'class': 'th' }, _('VPN IP')), E('th', { 'class': 'th' }, _('Remote IP')) ]) ];
			clients.forEach(function(c) { crows.push(E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td' }, c.user), E('td', { 'class': 'td' }, c.vip), E('td', { 'class': 'td' }, c.remote_ip) ])); });
			sBox.appendChild(E('div', { 'class': 'table cbi-section-table', 'style': 'margin-top:.5em' }, crows));
		}
		nodes.appendChild(sBox);

		/* ---- settings ---- */
		var sRemote = E('input', { 'type': 'text', 'value': set.remote || '', 'placeholder': 'vpn.example.com or public IP', 'style': 'width:16em' });
		var sName = E('input', { 'type': 'text', 'value': set.vpn_name || 'Home VPN', 'style': 'width:16em' });
		var sMode = E('select', { 'style': 'width:16em' }, [
			E('option', { 'value': 'selfsigned', 'selected': (set.cert_mode === 'selfsigned' ? 'selected' : null) }, _('Self-signed (auto-generated)')),
			E('option', { 'value': 'import', 'selected': (set.cert_mode === 'import' ? 'selected' : null) }, _('Import own certificate')),
			E('option', { 'value': 'acme', 'selected': (set.cert_mode === 'acme' ? 'selected' : null) }, _('ACME / Let\u0027s Encrypt'))
		]);
		var sAcme = E('input', { 'type': 'text', 'value': set.acme_domain || '', 'placeholder': 'domain from Services → Let\u0027s Encrypt', 'style': 'width:16em' });
		nodes.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Server settings')),
			E('p', { 'class': 'cbi-section-descr' },
				_('Server address is what clients dial (DDNS name or public IP) — the certificate SAN must match it. Self-signed mode generates a CA + server certificate on first boot; import mode uses files you place under /etc/swanctl/; ACME mode syncs a certificate issued by the Let\u0027s Encrypt app.')),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Server address (DDNS/IP)')), E('div', { 'class': 'cbi-value-field' }, sRemote) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('VPN display name')), E('div', { 'class': 'cbi-value-field' }, sName) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Certificate mode')), E('div', { 'class': 'cbi-value-field' }, sMode) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('ACME domain')), E('div', { 'class': 'cbi-value-field' }, sAcme) ]),
			E('div', { 'class': 'cbi-value' }, [ E('div', { 'class': 'cbi-value-field' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-save',
					'click': ui.createHandlerFn(this, function() {
						return callSetSettings(sRemote.value, sName.value, sMode.value, sAcme.value).then(function(r) {
							if (fail(r, _('Save settings'))) ui.addNotification(null, E('p', _('Saved. Server re-provisioned.')), 'info');
						});
					})
				}, _('Save settings')), ' ',
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, function() {
						return callProvision().then(function(r) {
							if (fail(r, _('Provision'))) { ui.addNotification(null, E('p', _('Provisioning output: %s').format((r && r.output) || '')), 'info'); reload(); }
						});
					})
				}, _('Re-provision now'))
			]) ])
		]));

		/* ---- EAP users ---- */
		var rows = [ E('tr', { 'class': 'tr table-titles' }, [ E('th', { 'class': 'th' }, _('Username')), E('th', { 'class': 'th cbi-section-actions' }, _('Client config + actions')) ]) ];
		if (!users.length) rows.push(E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td', 'colspan': 2 }, E('em', {}, _('No users yet.'))) ]));
		users.forEach(function(u) {
			rows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, u.name),
				E('td', { 'class': 'td cbi-section-actions' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, function() {
						return callDownload(u.name, 'mobileconfig').then(function(r) {
							if (!fail(r, _('Generate profile'))) saveBlob(r.mobileconfig, u.name + '.mobileconfig', 'application/x-apple-aspen-config');
						});
					}) }, _('iOS/macOS profile')),
					' ',
					E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, function() {
						return callDownload(u.name, 'sswan').then(function(r) {
							if (!fail(r, _('Generate profile'))) saveBlob(r.sswan, u.name + '.sswan', 'application/json');
						});
					}) }, _('Android .sswan')),
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
				])
			])
		]));

		/* ---- manual client setup / CA download ---- */
		nodes.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Manual client setup (no profile)')),
			E('p', { 'class': 'cbi-section-descr' },
				_('For Android 11+ native VPN or other manual clients: download the CA certificate, install it on the device, then create an IKEv2 connection with EAP-MSCHAPv2 (username/password) pointing at the server address above.')),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('CA certificate (PEM)')),
				E('div', { 'class': 'cbi-value-field' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, function() {
						return callDownload('', 'ca').then(function(r) {
							if (!fail(r, _('Download CA'))) saveBlob(r.ca, 'homevpn-ca.crt', 'application/x-x509-ca-cert');
						});
					}) }, _('Download CA certificate'))
				])
			])
		]));

		return nodes;
	},
	handleSaveApply: null, handleSave: null, handleReset: null
});
