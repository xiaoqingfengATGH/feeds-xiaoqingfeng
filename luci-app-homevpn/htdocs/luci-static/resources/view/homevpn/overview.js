'use strict';
'require view';
'require rpc';
'require ui';

var callStatus      = rpc.declare({ object: 'homevpn', method: 'status' });
var callListUsers   = rpc.declare({ object: 'homevpn', method: 'list_users' });
var callGetSettings = rpc.declare({ object: 'homevpn', method: 'get_settings' });
var callSetSettings = rpc.declare({ object: 'homevpn', method: 'set_settings', params: [ 'remote', 'vpn_name', 'cert_mode', 'acme_domain', 'ip_mode', 'pool_start', 'pool_end', 'pool_subnet', 'masq' ] });
var callAddUser     = rpc.declare({ object: 'homevpn', method: 'add_user', params: [ 'name', 'password' ] });
var callDelUser     = rpc.declare({ object: 'homevpn', method: 'del_user', params: [ 'name' ] });
var callSetUserIp   = rpc.declare({ object: 'homevpn', method: 'set_user_ip', params: [ 'name', 'ip' ] });
var callProvision   = rpc.declare({ object: 'homevpn', method: 'provision' });
var callDownload    = rpc.declare({ object: 'homevpn', method: 'download', params: [ 'name', 'what' ] });

function reload() { return location.reload(); }
function ok(res, action) {
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
		var modeLabels = { lansubnet: _('LAN subnet pool + ARP proxy'), dhcp: _('DHCP (local dnsmasq)'), subnet: _('Independent subnet') };

		var nodes = E('div', {}, [
			E('h2', {}, _('HomeVPN — IKEv2 Server')),
			E('p', { 'class': 'cbi-section-descr' },
				_('Turnkey strongSwan IKEv2 VPN server: clients dial in with username/password (EAP-MSCHAPv2) and become full LAN members via DHCP pool + ARP proxy.'))
		]);

		/* ---- server status + readiness ---- */
		var modeLabel = { selfsigned: _('Self-signed'), import: _('Imported'), acme: _('ACME (Let\u0027s Encrypt)') };
		var appliedCell = (modeLabels[st.applied_mode] || st.applied_mode || '—') + (st.applied_pool ? ' — ' + st.applied_pool : '');
		var appliedModeRow;
		if (st.ip_mode && st.ip_mode !== st.applied_mode) {
			appliedModeRow = E('tr', { 'class': 'tr', 'style': 'background:rgba(217,83,79,.12)' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, _('IP allocation mode (applied)')),
				E('td', { 'class': 'td left' }, [
					E('strong', { 'style': 'color:#d9534f' }, appliedCell),
					E('br'),
					E('small', { 'style': 'color:#d9534f' }, _('Selected %s is NOT applied — the precheck refused it (reason below). The highlighted mode is what clients get right now.').format(modeLabels[st.ip_mode] || st.ip_mode))
				])
			]);
		}
		else {
			appliedModeRow = E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '33%' }, _('IP allocation mode (applied)')), E('td', { 'class': 'td left' }, appliedCell) ]);
		}
		var sBox = E('div', { 'class': 'cbi-section' }, [ E('h3', {}, _('Server status')),
			E('table', { 'class': 'table' }, [
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '33%' }, _('strongSwan (charon)')), E('td', { 'class': 'td left' }, badge(st.running, _('running'), _('stopped'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Listening (500/4500)')), E('td', { 'class': 'td left' }, badge(st.listening, _('yes'), _('no'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Certificate mode')), E('td', { 'class': 'td left' }, modeLabel[st.mode] || st.mode) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Server certificate / CA')), E('td', { 'class': 'td left' }, badge(st.pki_ready, _('present'), _('missing'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Certificate SAN matches server address')), E('td', { 'class': 'td left' }, badge(st.san_ok, _('match'), _('MISMATCH — clients cannot connect'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Firewall INPUT rules (500/4500/ESP)')), E('td', { 'class': 'td left' }, badge(st.input_rules, _('present'), _('missing'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Connection loaded in charon')), E('td', { 'class': 'td left' }, badge(st.conn_loaded, _('loaded'), _('not loaded'))) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '33%' }, _('Server address (clients dial)')), E('td', { 'class': 'td left' }, st.remote || _('(not set — WAN IP will be used)')) ]),
				appliedModeRow,
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Connected clients')), E('td', { 'class': 'td left' }, String(clients.length)) ])
			]) ]);
		if (clients.length) {
			var crows = [ E('tr', { 'class': 'tr table-titles' }, [ E('th', { 'class': 'th' }, _('User')), E('th', { 'class': 'th' }, _('VPN IP')), E('th', { 'class': 'th' }, _('Remote IP')) ]) ];
			clients.forEach(function(c) { crows.push(E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td' }, c.user), E('td', { 'class': 'td' }, c.vip), E('td', { 'class': 'td' }, c.remote_ip) ])); });
			sBox.appendChild(E('div', { 'class': 'table cbi-section-table', 'style': 'margin-top:.5em' }, crows));
		}
		nodes.appendChild(sBox);

		if (st.precheck === 'refused') {
			nodes.appendChild(E('div', { 'class': 'alert-message warning', 'style': 'margin:0 0 .5em' }, [
				E('strong', {}, _('Configuration check refused: ')),
				document.createTextNode(st.precheck_reason || _('unknown reason')),
				E('br'), E('small', {}, _('The last working configuration stays active. Fix the issue above, then apply again.'))
			]));
		}
		if (st.suggest && st.applied_mode === 'subnet' && st.applied_masq !== '1') {
			nodes.appendChild(E('div', { 'class': 'alert-message info', 'style': 'margin:0 0 .5em' }, [
				E('strong', {}, _('Static route needed on the main router: ')),
				document.createTextNode(st.suggest),
				E('br'), E('small', {}, _('Add this route so LAN hosts can reach VPN clients. If the main router cannot configure static routes, enable the masquerade fallback in Client IP allocation instead.'))
			]));
		}

		/* ---- IP allocation mode ---- */
		var sIpMode = E('select', { 'style': 'width:22em' }, [
			E('option', { 'value': 'lansubnet', 'selected': (set.ip_mode === 'dhcp' || set.ip_mode === 'subnet') ? null : 'selected' }, modeLabels.lansubnet),
			E('option', { 'value': 'dhcp', 'selected': (set.ip_mode === 'dhcp') ? 'selected' : null }, modeLabels.dhcp),
			E('option', { 'value': 'subnet', 'selected': (set.ip_mode === 'subnet') ? 'selected' : null }, modeLabels.subnet)
		]);
		var sPs = E('input', { 'type': 'text', 'value': set.pool_start || '', 'placeholder': '(auto) ' + (st.lan_net || '192.168.x.x').replace(/\.\d+$/, '.50'), 'style': 'width:10em' });
		var sPe = E('input', { 'type': 'text', 'value': set.pool_end || '', 'placeholder': '(auto) .99', 'style': 'width:10em' });
		var sPc = E('input', { 'type': 'text', 'value': set.pool_subnet || '', 'placeholder': '10.100.1.0/24', 'style': 'width:10em' });
		var sMasq = E('select', { 'style': 'width:10em' }, [
			E('option', { 'value': '0', 'selected': (set.masq === '1') ? null : 'selected' }, _('Off (static route preferred)')),
			E('option', { 'value': '1', 'selected': (set.masq === '1') ? 'selected' : null }, _('On (fallback: main router cannot route)'))
		]);
		var modeHint = E('p', { 'class': 'cbi-section-descr' });
		function updModeHint() {
			var m = sIpMode.value;
			var hints = {
				lansubnet: _('Pool carved from the LAN subnet (default .50-.99) — no configuration on any other router needed, and VPN clients are reachable from the LAN. Recommended for side routers.'),
				dhcp: _('Clients get real LAN leases from THIS router\u0027s dnsmasq (DHCP must run here). Supports mDNS/AirPlay. Per-user fixed IPs need identity_lease + dhcp-host bindings. Not available while firewall flow-offloading is on.'),
				subnet: _('Clients live in an independent subnet — cleanest isolation, recommended as main router. On a SIDE router the main router needs a static route for the pool subnet (suggested command shown below after saving); masquerade is the last-resort fallback when it cannot.')
			};
			modeHint.textContent = hints[m] || '';
			[ sPs, sPe ].forEach(function(el) {
				var row = el.closest ? el.closest('.cbi-value') : null;
				if (row) row.style.display = (m === 'lansubnet') ? '' : 'none';
			});
			var pcRow = sPc.closest ? sPc.closest('.cbi-value') : null;
			if (pcRow) pcRow.style.display = (m === 'subnet') ? '' : 'none';
			var masqRow = sMasq.closest ? sMasq.closest('.cbi-value') : null;
			if (masqRow) masqRow.style.display = (m === 'subnet') ? '' : 'none';
		}
		sIpMode.addEventListener('change', updModeHint);
		nodes.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Client IP allocation')),
			E('p', { 'class': 'cbi-section-descr' }, _('How VPN clients get their virtual IP. Every mode is prechecked before applying (pool occupancy on the LAN, DHCP availability, subnet conflicts) — a failed check refuses the change and keeps the last working configuration, with the reason shown in the status banner above.')),
			modeHint,
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Mode')), E('div', { 'class': 'cbi-value-field' }, sIpMode) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Pool start')), E('div', { 'class': 'cbi-value-field' }, sPs) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Pool end')), E('div', { 'class': 'cbi-value-field' }, sPe) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Pool subnet (CIDR)')), E('div', { 'class': 'cbi-value-field' }, sPc) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Masquerade fallback')), E('div', { 'cbi-value-field': null, 'class': 'cbi-value-field' }, sMasq) ]),
			E('div', { 'class': 'cbi-value' }, [ E('div', { 'class': 'cbi-value-field' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'click': ui.createHandlerFn(this, function() {
						var ps = (sPs.value || '').trim(), pe = (sPe.value || '').trim(), pc = (sPc.value || '').trim();
						if (sIpMode.value === 'lansubnet' && ps && !/^\d+\.\d+\.\d+\.\d+$/.test(ps)) { ui.addNotification(null, E('p', _('Pool start is not a valid IP address.')), 'warning'); return; }
						if (sIpMode.value === 'lansubnet' && pe && !/^\d+\.\d+\.\d+\.\d+$/.test(pe)) { ui.addNotification(null, E('p', _('Pool end is not a valid IP address.')), 'warning'); return; }
						if (sIpMode.value === 'subnet' && !/^(\d+\.){3}\d+\/\d+$/.test(pc)) { ui.addNotification(null, E('p', _('Pool subnet must be a CIDR like 10.100.1.0/24.')), 'warning'); return; }
						return callSetSettings(sRemote.value, sName.value, sMode.value, sAcme.value, sIpMode.value, ps, pe, pc, sMasq.value).then(function(r) {
							if (r && r.ok) {
								if (r.precheck_ok) {
									ui.addNotification(null, E('p', _('Applied. Mode: %s, pool: %s').format(sIpMode.value, pc || (ps || 'auto') + '-' + (pe || 'auto'))), 'info');
								} else {
									ui.addNotification(null, E('p', _('Refused: %s — the last working configuration stays active.').format(r.precheck_reason || _('precheck failed'))), 'error');
								}
								reload();
							} else {
								ok(r, _('Apply'));
							}
						});
					})
				}, _('Apply IP settings')), ' ',
				E('span', { 'style': 'color:#666;font-size:90%' }, _('Applying re-runs the prechecks and (re)loads the swanctl config; existing VPN connections survive whenever possible.'))
			]) ])
		]));
		updModeHint();

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
						return callSetSettings(sRemote.value, sName.value, sMode.value, sAcme.value, sIpMode.value, (sPs.value || '').trim(), (sPe.value || '').trim(), (sPc.value || '').trim(), sMasq.value).then(function(r) {
							if (r && r.ok && !r.precheck_ok)
								ui.addNotification(null, E('p', _('Refused: %s — the last working configuration stays active.').format(r.precheck_reason || _('precheck failed'))), 'error');
							if (ok(r, _('Save settings'))) ui.addNotification(null, E('p', _('Saved. Server re-provisioned.')), 'info');
						});
					})
				}, _('Save settings')), ' ',
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, function() {
						return callProvision().then(function(r) {
							if (ok(r, _('Provision'))) { ui.addNotification(null, E('p', _('Provisioning output: %s').format((r && r.output) || '')), 'info'); reload(); }
						});
					})
				}, _('Re-provision now'))
			]) ])
		]));

		/* ---- EAP users ---- */
		var isDhcp = (st.applied_mode === 'dhcp');
		var rows = [ E('tr', { 'class': 'tr table-titles' }, [ E('th', { 'class': 'th' }, _('Username')), E('th', { 'class': 'th' }, _('Fixed IP (DHCP mode)')), E('th', { 'class': 'th cbi-section-actions' }, _('Client config + actions')) ]) ];
		if (!users.length) rows.push(E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td', 'colspan': 3 }, E('em', {}, _('No users yet.'))) ]));
		users.forEach(function(u) {
			var fipCell;
			if (isDhcp) {
				var ipInput = E('input', { 'type': 'text', 'value': u.fixed_ip || '', 'placeholder': _('dynamic'), 'style': 'width:9em' });
				fipCell = E('td', { 'class': 'td' }, [
					ipInput, ' ',
					E('button', { 'class': 'btn cbi-button cbi-button-save', 'click': ui.createHandlerFn(this, function() {
						var v = (ipInput.value || '').trim();
						return callSetUserIp(u.name, v).then(function(r) {
							if (ok(r, _('Set fixed IP')))
								ui.addNotification(null, E('p', v ? _('Fixed IP for "%s": %s — applies on the next dial-in.').format(u.name, v) : _('Fixed IP for "%s" cleared — dynamic allocation again.').format(u.name)), 'info');
						});
					}) }, _('Set')),
					(u.fixed_ip ? E('button', { 'class': 'btn cbi-button cbi-button-remove', 'click': ui.createHandlerFn(this, function() {
						return callSetUserIp(u.name, '').then(function(r) {
							if (ok(r, _('Clear fixed IP'))) { ui.addNotification(null, E('p', _('Fixed IP for "%s" cleared — dynamic allocation again.').format(u.name)), 'info'); ipInput.value = ''; }
						});
					}) }, _('Clear')) : '')
				]);
			}
			else {
				fipCell = E('td', { 'class': 'td' }, E('em', {}, u.fixed_ip ? _('%s (not applied — IP mode is not DHCP)').format(u.fixed_ip) : '—'));
			}
			rows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, u.name),
				fipCell,
				E('td', { 'class': 'td cbi-section-actions' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, function() {
						return callDownload(u.name, 'mobileconfig').then(function(r) {
							if (ok(r, _('Generate profile'))) saveBlob(r.mobileconfig, u.name + '.mobileconfig', 'application/x-apple-aspen-config');
						});
					}) }, _('iOS/macOS profile')),
					' ',
					E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, function() {
						return callDownload(u.name, 'sswan').then(function(r) {
							if (ok(r, _('Generate profile'))) saveBlob(r.sswan, u.name + '.sswan', 'application/json');
						});
					}) }, _('Android .sswan')),
					' ',
					E('button', { 'class': 'btn cbi-button cbi-button-remove', 'click': ui.createHandlerFn(this, function() {
						if (!confirm(_('Delete user "%s"? They will no longer be able to connect.').format(u.name))) return;
						return callDelUser(u.name).then(function(r) { if (ok(r, _('Delete'))) reload(); });
					}) }, _('Delete'))
				])
			]));
		});
		var nName = E('input', { 'type': 'text', 'placeholder': _('e.g. alice, iphone'), 'style': 'width:12em' });
		var nPw = E('input', { 'type': 'text', 'value': '', 'placeholder': _('password'), 'style': 'width:14em' });
		nodes.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('EAP accounts')),
			E('p', { 'class': 'cbi-section-descr' },
				_('Fixed IP pins a user\'s virtual IP in DHCP mode: the username travels as the DHCP client-id and dnsmasq hands out the pinned address. Leave empty for dynamic allocation; applies on the next dial-in.')),
			E('div', { 'class': 'table cbi-section-table' }, rows),
			E('div', { 'class': 'cbi-value', 'style': 'margin-top:1em' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Add user')),
				E('div', { 'class': 'cbi-value-field' }, [ nName, ' ', nPw, ' ',
					E('button', { 'class': 'btn cbi-button', 'click': function() { nPw.value = randpw(); } }, _('Random')), ' ',
					E('button', { 'class': 'btn cbi-button cbi-button-add', 'click': ui.createHandlerFn(this, function() {
						var n = (nName.value || '').trim(), p = (nPw.value || '').trim();
						if (!n || !p) { ui.addNotification(null, E('p', _('Enter a username and password.')), 'warning'); return; }
						return callAddUser(n, p).then(function(r) { if (ok(r, _('Add user'))) { ui.addNotification(null, E('p', _('Added "%s".').format(n)), 'info'); reload(); } });
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
							if (ok(r, _('Download CA'))) saveBlob(r.ca, 'homevpn-ca.crt', 'application/x-x509-ca-cert');
						});
					}) }, _('Download CA certificate'))
				])
			])
		]));

		return nodes;
	},
	handleSaveApply: null, handleSave: null, handleReset: null
});
