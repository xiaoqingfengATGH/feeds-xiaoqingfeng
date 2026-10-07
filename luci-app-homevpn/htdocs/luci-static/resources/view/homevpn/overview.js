'use strict';
'require view';
'require rpc';
'require ui';

var callSetEnabled  = rpc.declare({ object: 'homevpn', method: 'set_enabled', params: [ 'enabled' ] });
var callStatus      = rpc.declare({ object: 'homevpn', method: 'status' });
var callListUsers   = rpc.declare({ object: 'homevpn', method: 'list_users' });
var callDiscoverAcme = rpc.declare({ object: 'homevpn', method: 'discover_acme', params: [ 'domain' ] });
var callGetSettings = rpc.declare({ object: 'homevpn', method: 'get_settings' });
var callSetSettings = rpc.declare({ object: 'homevpn', method: 'set_settings', params: [ 'remote', 'vpn_name', 'cert_mode', 'acme_domain', 'acme_key_type', 'ip_mode', 'pool_start', 'pool_end', 'pool_subnet', 'masq', 'traffic_scope' ] });
var callAddUser     = rpc.declare({ object: 'homevpn', method: 'add_user', params: [ 'name', 'password' ] });
var callDelUser     = rpc.declare({ object: 'homevpn', method: 'del_user', params: [ 'name' ] });
var callSetUserIp   = rpc.declare({ object: 'homevpn', method: 'set_user_ip', params: [ 'name', 'ip' ] });
var callEnsureCA = rpc.declare({ object: 'homevpn', method: 'ensure_selfsigned_ca', params: [ 'replace', 'fingerprint' ] });
var callProvision   = rpc.declare({ object: 'homevpn', method: 'provision' });
var callUploadCerts = rpc.declare({ object: 'homevpn', method: 'upload_certs', params: [ 'server', 'key', 'ca' ] });
var callDownload    = rpc.declare({ object: 'homevpn', method: 'download', params: [ 'name', 'what' ] });

/* Translate known backend diagnostics only at the presentation boundary.
 * Keep service/RPC strings and unknown tool diagnostics intact. */
function backendMessage(value) {
	var text = String(value || '');
	var pkiMessages = {
		"remote_required": _('Save a server address first.'),
		"invalid_remote": _('Invalid server address. Use a domain or IPv4 address without URL, port or path.'),
		"remote_clear_blocked": _('Cannot clear the address while strongSwan is running. Disable HomeVPN first; the saved configuration was not changed.'),
		"ca_replace_confirmation_required": _('Existing CA assets are invalid. Confirm replacement to migrate client trust.'),
		"ca_key_invalid": _('Root CA certificate or private key is missing, invalid or mismatched.'),
		"ca_constraints_invalid": _('Root certificate is not a CA.'),
		"ca_usage_invalid": _('Root CA does not permit certificate signing.'),
		"ca_not_selfsigned": _('Root CA is not self-signed.'),
		"ca_signature_or_validity_invalid": _('Root CA signature or validity check failed.'),
		"ca_lifetime_insufficient": _('Root CA has less than 31 days remaining. Confirm CA replacement before signing.'),
		"ca_creation_failed": _('Root CA creation failed; existing assets were kept.'),
		"pki_publish_failed": _('Certificate installation failed; previous assets were restored.'),
		"leaf_key_invalid": _('Server certificate or private key is missing, invalid or mismatched.'),
		"leaf_san_mismatch": _('Server certificate SAN does not match the saved address.'),
		"leaf_renewal_required": _('Server certificate is expired or enters its 30-day renewal window.'),
		"leaf_constraints_invalid": _('Server certificate has invalid basic constraints.'),
		"leaf_usage_invalid": _('Server certificate does not permit server authentication or digital signatures.'),
		"leaf_chain_invalid": _('Server certificate is not valid under the current root CA.'),
		"leaf_signing_failed": _('Server certificate signing failed; previous assets were kept.'),
		"selfsigned_mode_required": _('Save self-signed mode before preparing the root CA.'),
		"ca_changed_retry": _('Root CA changed. Refresh and confirm again.'),
		"ca_rotation_requires_stopped_service": _('Stop HomeVPN before replacing the root CA.')
	};
	if (pkiMessages[text]) return pkiMessages[text];
	if (text.indexOf('\n') >= 0) return text.split('\n').map(backendMessage).join('\n');
	if (text === 'dhcp (real LAN leases via local dnsmasq)') return _('DHCP (real LAN leases via local dnsmasq)');
	if (text === 'Pool subnet is required in independent subnet mode. Enter a CIDR such as 10.100.1.0/24.') return _('Pool subnet is required in independent subnet mode. Enter a CIDR such as 10.100.1.0/24.');
	if (text === 'Enter a valid IPv4 CIDR with a prefix from /8 to /30, such as 10.100.1.0/24.') return _('Enter a valid IPv4 CIDR with a prefix from /8 to /30, such as 10.100.1.0/24.');
	var suffix = '; keeping previous settings';
	if (text.slice(-suffix.length) === suffix)
		return _('%s; keeping previous settings').format(backendMessage(text.slice(0, -suffix.length)));
	var prefix = 'homevpn: refusing to render: ';
	if (text.indexOf(prefix) === 0)
		return _('HomeVPN configuration refused: %s').format(backendMessage(text.slice(prefix.length)));
	var messages = [
		[ /^invalid\ name\ \(A\-Z\ a\-z\ 0\-9\ \.\ _\ \-\ max\ 32\)$/ , _('invalid name (A-Z a-z 0-9 . _ - max 32)') ],
		[ /^password\ required$/ , _('password required') ],
		[ /^user\ '(.+?)'\ already\ exists$/ , _('user \'%s\' already exists') ],
		[ /^user\ '(.+?)'\ not\ found$/ , _('user \'%s\' not found') ],
		[ /^regen\ failed$/ , _('regen failed') ],
		[ /^invalid\ IP\ '(.+?)'$/ , _('invalid IP \'%s\'') ],
		[ /^x\.x\.x\.1\-9\ reserved\ for\ the\ router$/ , _('x.x.x.1-9 reserved for the router') ],
		[ /^network\.lan\.ipaddr\ not\ set$/ , _('network.lan.ipaddr not set') ],
		[ /^network\.lan\.ipaddr\ is\ not\ set$/ , _('network.lan.ipaddr is not set') ],
		[ /^IP\ must\ be\ in\ the\ LAN\ subnet\ \((.+?)\ expected\)$/ , _('IP must be in the LAN subnet (%s expected)') ],
		[ /^IP\ equals\ the\ router\ LAN\ address$/ , _('IP equals the router LAN address') ],
		[ /^IP\ (.+?)\ already\ pinned\ to\ user\ '(.+?)'$/ , _('IP %s already pinned to user \'%s\'') ],
		[ /^(.+?)\ answers\ ping\ —\ already\ occupied\ by\ a\ LAN\ host$/ , _('%s answers ping — already occupied by a LAN host') ],
		[ /^(.+?)\ is\ in\ an\ active\ DHCP\ lease$/ , _('%s is in an active DHCP lease') ],
		[ /^certificate\ query\ unavailable:\ openssl\ missing$/ , _('certificate query unavailable: openssl missing') ],
		[ /^certificate\ query\ unavailable:\ resolver\ missing$/ , _('certificate query unavailable: resolver missing') ],
		[ /^invalid\ domain$/ , _('invalid domain') ],
		[ /^invalid\ ACME\ key\ type\ \(use\ rsa\ or\ ecc\)$/ , _('invalid ACME key type (use rsa or ecc)') ],
		[ /^invalid\ key\ type\ \(use\ rsa\ or\ ecc\)$/ , _('invalid key type (use rsa or ecc)') ],
		[ /^ACME\ domain\ is\ empty\ —\ set\ it\ to\ the\ domain\ issued\ in\ Services\ →\ Let's\ Encrypt$/ , _('ACME domain is empty — set it to the domain issued in Services → Let\'s Encrypt') ],
		[ /^no\ valid\ matching\ (.+?)\ certificate\/key\ for\ (.+?)\ in\ (.+?)\ or\ (.+?)$/ , _('no valid matching %s certificate/key for %s in %s or %s') ],
		[ /^server\ address\ '(.+?)'\ is\ not\ an\ exact\ SAN\ of\ the\ ACME\ certificate\ for\ '(.+?)'\ \(SANs:\ (.+?)\)\ —\ strongSwan\ never\ matches\ wildcard\ SANs;\ staying\ in\ '(.+?)'\ mode$/ , _('server address \'%s\' is not an exact SAN of the ACME certificate for \'%s\' (SANs: %s) — strongSwan never matches wildcard SANs; staying in \'%s\' mode') ],
		[ /^nothing\ to\ upload\ —\ pick\ at\ least\ one\ file$/ , _('nothing to upload — pick at least one file') ],
		[ /^mktemp\ failed$/ , _('mktemp failed') ],
		[ /^incomplete\ set:\ server\ certificate\ \+\ private\ key\ required\ \(upload\ both,\ or\ deploy\ the\ missing\ part\ first\)$/ , _('incomplete set: server certificate + private key required (upload both, or deploy the missing part first)') ],
		[ /^server\ certificate:\ not\ a\ valid\ PEM\ certificate\ —\ (.+?)$/ , _('server certificate: not a valid PEM certificate — %s') ],
		[ /^private\ key:\ not\ a\ valid\ unencrypted\ PEM\ key\ —\ (.+?)\ \(export\ WITHOUT\ a\ passphrase\)$/ , _('private key: not a valid unencrypted PEM key — %s (export WITHOUT a passphrase)') ],
		[ /^server\ certificate\ expired\ on\ (.+?)$/ , _('server certificate expired on %s') ],
		[ /^server\ certificate\ has\ no\ Subject\ Alternative\ Name\ —\ clients\ cannot\ match\ it\ \(reissue\ with\ SAN\)$/ , _('server certificate has no Subject Alternative Name — clients cannot match it (reissue with SAN)') ],
		[ /^server\ address\ '(.+?)'\ is\ not\ an\ exact\ SAN\ of\ the\ uploaded\ certificate\ \(SANs:\ (.+?)\)\ —\ strongSwan\ never\ matches\ wildcard\ SANs:\ set\ the\ server\ address\ to\ an\ exact\ SAN\ of\ the\ certificate,\ or\ reissue\ it\ with\ the\ server\ address\ as\ SAN$/ , _('server address \'%s\' is not an exact SAN of the uploaded certificate (SANs: %s) — strongSwan never matches wildcard SANs: set the server address to an exact SAN of the certificate, or reissue it with the server address as SAN') ],
		[ /^private\ key\ does\ not\ match\ the\ server\ certificate\ \(public\ keys\ differ\)$/ , _('private key does not match the server certificate (public keys differ)') ],
		[ /^CA\ certificate:\ not\ a\ valid\ PEM\ certificate\ —\ (.+?)$/ , _('CA certificate: not a valid PEM certificate — %s') ],
		[ /^CA\ certificate\ does\ not\ sign\ the\ server\ certificate\ —\ import\ the\ issuer\ CA,\ or\ leave\ the\ CA\ field\ empty\ to\ keep\ the\ current\ one$/ , _('CA certificate does not sign the server certificate — import the issuer CA, or leave the CA field empty to keep the current one') ],
		[ /^deployed\ CA\ does\ not\ sign\ the\ uploaded\ server\ certificate\ —\ clients\ that\ trust\ this\ CA\ will\ reject\ it$/ , _('deployed CA does not sign the uploaded server certificate — clients that trust this CA will reject it') ],
		[ /^no\ CA\ deployed\ —\ client\ profiles\ embed\ the\ CA,\ so\ upload\ one\ or\ the\ generated\ profiles\ cannot\ verify\ the\ server$/ , _('no CA deployed — client profiles embed the CA, so upload one or the generated profiles cannot verify the server') ],
		[ /^CA\ not\ found\ —\ run\ provisioning\ first$/ , _('CA not found — run provisioning first') ],
		[ /^server\ address\ not\ set\ —\ set\ it\ in\ Settings\ first$/ , _('server address not set — set it in Settings first') ],
		[ /^unknown\ download\ type:\ (.+?)$/ , _('unknown download type: %s') ],
		[ /^unknown\ method:\ (.+?)$/ , _('unknown method: %s') ],
		[ /^pool_start\ '(.+?)'\ is\ not\ a\ valid\ IPv4\ address$/ , _('pool_start \'%s\' is not a valid IPv4 address') ],
		[ /^pool_end\ '(.+?)'\ is\ not\ a\ valid\ IPv4\ address$/ , _('pool_end \'%s\' is not a valid IPv4 address') ],
		[ /^pool_start\ \((.+?)\)\ is\ greater\ than\ pool_end\ \((.+?)\)$/ , _('pool_start (%s) is greater than pool_end (%s)') ],
		[ /^pool\ must\ fit\ inside\ a\ single\ \/24\ —\ start\ and\ end\ are\ in\ different\ subnets$/ , _('pool must fit inside a single /24 — start and end are in different subnets') ],
		[ /^pool\ range\ too\ large\ \((.+?)\ addresses,\ max\ 200\)$/ , _('pool range too large (%s addresses, max 200)') ],
		[ /^pool\ must\ not\ include\ the\ network\ address\ (.+?)$/ , _('pool must not include the network address %s') ],
		[ /^pool\ must\ not\ include\ the\ broadcast\ address\ (.+?)$/ , _('pool must not include the broadcast address %s') ],
		[ /^(.+?)\ is\ outside\ the\ LAN\ subnet\ \((.+?)\ on\ (.+?)\)\ —\ the\ pool\ must\ be\ carved\ from\ the\ LAN\ subnet$/ , _('%s is outside the LAN subnet (%s on %s) — the pool must be carved from the LAN subnet') ],
		[ /^pool\ range\ includes\ this\ router's\ own\ address\ (.+?)$/ , _('pool range includes this router\'s own address %s') ],
		[ /^pool\ addresses\ already\ in\ use\ on\ the\ LAN\ \(ARP\ probe\ answered\):\ (.+?)\ —\ pick\ a\ free\ range$/ , _('pool addresses already in use on the LAN (ARP probe answered): %s — pick a free range') ],
		[ /^dhcp\ mode\ needs\ the\ strongswan\-mod\-dhcp\ plugin\ \(not\ installed\)$/ , _('dhcp mode needs the strongswan-mod-dhcp plugin (not installed)') ],
		[ /^dhcp\ mode\ requires\ THIS\ router's\ dnsmasq\ to\ serve\ DHCP\ on\ (.+?)\ \(no\ dhcp\-range\ found\)\ —\ enable\ LAN\ DHCP\ here,\ or\ use\ lansubnet\ mode$/ , _('dhcp mode requires THIS router\'s dnsmasq to serve DHCP on %s (no dhcp-range found) — enable LAN DHCP here, or use lansubnet mode') ],
		[ /^dhcp\ mode\ together\ with\ firewall\ flow\-offloading:\ offloaded\ flows\ bypass\ the\ IPsec\ policies\ \(traffic\ blackholes\ after\ the\ first\ packets\)\ —\ disable\ flow\ offloading\ or\ use\ lansubnet\ mode$/ , _('dhcp mode together with firewall flow-offloading: offloaded flows bypass the IPsec policies (traffic blackholes after the first packets) — disable flow offloading or use lansubnet mode') ],
		[ /^subnet\ mode\ requires\ pool_subnet\ \(e\.g\.\ 10\.100\.1\.0\/24\)$/ , _('subnet mode requires pool_subnet (e.g. 10.100.1.0/24)') ],
		[ /^pool_subnet\ must\ be\ in\ CIDR\ form\ a\.b\.c\.d\/N\ \(got\ '(.+?)'\)$/ , _('pool_subnet must be in CIDR form a.b.c.d/N (got \'%s\')') ],
		[ /^pool_subnet\ '(.+?)'\ is\ not\ a\ valid\ subnet$/ , _('pool_subnet \'%s\' is not a valid subnet') ],
		[ /^pool_subnet\ prefix\ '(.+?)'\ is\ not\ a\ number$/ , _('pool_subnet prefix \'%s\' is not a number') ],
		[ /^pool_subnet\ prefix\ must\ be\ between\ \/8\ and\ \/30\ \(got\ \/(.+?)\)$/ , _('pool_subnet prefix must be between /8 and /30 (got /%s)') ],
		[ /^cannot\ probe\ routing\ for\ (.+?)\ —\ no\ route\?$/ , _('cannot probe routing for %s — no route?') ],
		[ /^pool_subnet\ (.+?)\ overlaps\ an\ existing\ local\ network:\ (.+?)\ —\ pick\ an\ unused\ subnet$/ , _('pool_subnet %s overlaps an existing local network: %s — pick an unused subnet') ],
		[ /^unknown\ ip_mode\ '(.+?)'\ \(expected\ lansubnet,\ dhcp\ or\ subnet\)$/ , _('unknown ip_mode \'%s\' (expected lansubnet, dhcp or subnet)') ],
		[ /^homevpn:\ ACME\ sync\ FAILED\ —\ the\ previously\ deployed\ certificate\ \(if\ any\)\ keeps\ serving;\ issue\ the\ certificate\ in\ Services\ →\ Let's\ Encrypt\ first$/ , _('homevpn: ACME sync FAILED — the previously deployed certificate (if any) keeps serving; issue the certificate in Services → Let\'s Encrypt first') ]
	];
	for (var i = 0; i < messages.length; i++) {
		var match = text.match(messages[i][0]);
		if (match) return messages[i][1].format.apply(messages[i][1], match.slice(1));
	}
	return text;
}

function reload() { return location.reload(); }
function ok(res, action) {
	if (res && res.ok) return true;
	ui.addNotification(null, E('p', _('%s failed: %s').format(action, backendMessage(res && res.error) || _('unknown error'))), 'danger');
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
function flash(msg, cls) {
	/* notification that survives the reload() after an import: stash it in
	   the URL hash and replay it when the page renders again */
	location.hash = 'hvmsg=' + encodeURIComponent(JSON.stringify({ m: msg, c: cls || 'info' }));
}
/* Unified severity palette, dark-theme tuned + WCAG-verified (AA ≥4.5:1 on the
   measured theme bg rgb(48,56,65)): layered design per Material dark-theme
   practice — saturated border anchors the severity, PASTEL text carries the
   message (a saturated 500-level color on a same-hue tint is unreadable:
   ~3:1), background stays a ≤10% faint tint of the same hue. */
var CLR = {
	error: { txt: '#f9dedc', box: 'border-left:3px solid #ef5350;background:rgba(239,83,80,.10);color:#f9dedc' },
	ok:    { txt: '#c8ecca', box: 'border-left:3px solid #66bb6a;background:rgba(102,187,106,.10);color:#c8ecca' },
	warn:  { txt: '#ffe0b2', box: 'border-left:3px solid #ffb74d;background:rgba(255,183,77,.10);color:#ffe0b2' }
};
function hintColors(kind) { return CLR[kind] ? CLR[kind].box : ''; }
function replayFlash() {
	var m = (location.hash || '').match(/^#hvmsg=(.*)$/);
	if (!m) return;
	history.replaceState(null, '', location.pathname + location.search);
	try {
		var d = JSON.parse(decodeURIComponent(m[1]));
		ui.addNotification(null, E('p', d.m), d.c);
	} catch (e) { }
}

return view.extend({
	load: function() { return Promise.all([ callStatus(), callListUsers(), callGetSettings() ]); },
	render: function(data) {
		var st = data[0] || {}, ul = data[1] || {}, set = data[2] || {};
		var users = (ul && ul.users) || [];
		var clients = (st && st.clients) || [];
		replayFlash();
		var badge = function(okv, t, f) { return E('span', { 'style': 'color:' + (okv ? CLR.ok.txt : CLR.error.txt) }, okv ? ('✓ ' + t) : ('✗ ' + f)); };
		var modeLabels = { lansubnet: _('LAN subnet pool + ARP proxy'), dhcp: _('DHCP (local dnsmasq)'), subnet: _('Independent subnet') };

		var nodes = E('div', {}, [
			E('h2', {}, _('HomeVPN')),
			E('div', { 'class': 'cbi-map-descr' },
				_('Homelede customized IKEv2 + EAP-MSCHAPv2 VPN server, supporting the default clients on iOS, Android, Windows and MacOS for convenient device access to your home network.'))
		]);

		/* Independent action: never submits or validates the settings draft. */
		var switchBusy = false, switchState = st, stateKnown = true;
		var switchStatus = E('div', { 'id': 'homevpn-toggle-status', 'role': 'status', 'aria-live': 'polite' });
		var switchButton = E('button', { 'id': 'homevpn-toggle', 'type': 'button', 'class': 'btn cbi-button cbi-button-action', 'click': function() {
			if (switchBusy || settingsSaving || caBusy || !stateKnown) return Promise.resolve();
			switchBusy = true; switchButton.disabled = true; paintPkiDraft();
			switchStatus.textContent = _('Applying service state…');
			var failure = '';
			return callSetEnabled(switchState.enabled === false).then(function(res) {
				if (!res || !res.ok) failure = backendMessage(res && res.error) || _('unknown error');
			}, function(err) { failure = String(err.message || err); }).then(function() {
				return callStatus().then(function(actual) {
					if (!actual || actual.enabled == null) throw new Error(_('Service state unavailable. Refresh before trying again.'));
					refreshState(actual);
					if (failure) switchStatus.textContent += ' — ' + failure;
				}, function(err) { throw err; });
			}).catch(function(err) {
				stateKnown = false;
				[ statusPanel, routeCard, certTable ].forEach(function(panel) {
					while (panel.firstChild) panel.removeChild(panel.firstChild);
					panel.appendChild(E('p', { 'role': 'alert', 'style': hintColors('error') + ';padding:.5em .75em' }, _('Service state unavailable. Refresh before trying again.')));
				});
				switchStatus.textContent = (failure ? failure + ' — ' : '') + String(err.message || err) + ' — ' + _('Service state unavailable. Refresh before trying again.');
			}).then(function() { switchBusy = false; switchButton.disabled = !stateKnown; paintPkiDraft(); });
		} });
		function paintSwitch() {
			switchButton.textContent = switchState.enabled === false ? _('Enable HomeVPN') : _('Disable HomeVPN');
			switchStatus.textContent = switchState.enabled === false
				? (switchState.running ? _('Disabled, but strongSwan is still running — retry or check the conflict.') : _('Disabled — strongSwan stopped'))
				: (switchState.running && switchState.conn_loaded && switchState.remote && switchState.pki_ready !== false ? _('Enabled — HomeVPN connection loaded') : _('Enabled, but HomeVPN is not ready'));
		}
		paintSwitch();
		nodes.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('HomeVPN service')), switchButton, switchStatus,
			E('p', {}, _('Disabling disconnects VPN clients and stops strongSwan. HomeVPN requires exclusive use of strongSwan.'))
		]));

		/* Refresh read-only snapshots only; never rebuild draft controls. */
		var statusPanel = E('div', { 'id': 'homevpn-status-panel' });
		var routeCard = E('div', { 'id': 'homevpn-route-status' });
		nodes.appendChild(statusPanel);
		function paintStatus() {
			while (statusPanel.firstChild) statusPanel.removeChild(statusPanel.firstChild);
			while (routeCard.firstChild) routeCard.removeChild(routeCard.firstChild);
			/* ---- server status + readiness ---- */
			var modeLabel = { selfsigned: _('Self-signed'), import: _('Import mode'), acme: _('ACME (Let\u0027s Encrypt)') };
			var appliedCell = st.applied_mode === 'dhcp'
				? _('Obtain an address via local DHCP')
				: (modeLabels[st.applied_mode] || st.applied_mode || '—') + (st.applied_pool ? ' — ' + backendMessage(st.applied_pool) : '');
			var appliedModeRow;
			if (st.ip_mode && st.ip_mode !== st.applied_mode) {
				appliedModeRow = E('tr', { 'class': 'tr', 'style': hintColors('error') }, [
					E('td', { 'class': 'td left', 'width': '33%' }, _('IP allocation mode (applied)')),
					E('td', { 'class': 'td left' }, [
						E('strong', { 'style': 'color:' + CLR.error.txt }, appliedCell),
						E('br'),
						E('small', { 'style': 'color:' + CLR.error.txt }, _('Selected %s is NOT applied — the precheck refused it (reason below). The highlighted mode is what clients get right now.').format(modeLabels[st.ip_mode] || st.ip_mode))
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
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Certificate SAN matches server address')), E('td', { 'class': 'td left' }, E('span', { 'style': 'color:' + (!st.remote || !st.cert ? CLR.warn.txt : st.san_ok ? CLR.ok.txt : CLR.error.txt) }, !st.remote ? _('Not configured') : !st.cert ? _('Certificate missing') : st.san_ok ? _('exact match') : _('MISMATCH — server address must be an exact SAN (wildcards never match)'))) ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Firewall INPUT rules (500/4500/ESP)')), E('td', { 'class': 'td left' }, badge(st.input_rules, _('present'), _('missing'))) ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Connection loaded in charon')), E('td', { 'class': 'td left' }, badge(st.conn_loaded, _('loaded'), _('not loaded'))) ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '33%' }, _('Server address (clients dial)')), E('td', { 'class': 'td left' }, st.remote || _('Not configured')) ]),
					appliedModeRow,
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Connected clients')), E('td', { 'class': 'td left' }, String(clients.length)) ])
				]) ]);
			if (clients.length) {
				var crows = [ E('tr', { 'class': 'tr table-titles' }, [ E('th', { 'class': 'th' }, _('User')), E('th', { 'class': 'th' }, _('VPN IP')), E('th', { 'class': 'th' }, _('Remote IP')) ]) ];
				clients.forEach(function(c) { crows.push(E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td' }, c.user), E('td', { 'class': 'td' }, c.vip), E('td', { 'class': 'td' }, c.remote_ip) ])); });
				sBox.appendChild(E('div', { 'class': 'table cbi-section-table', 'style': 'margin-top:.5em' }, crows));
			}
			statusPanel.appendChild(sBox);

			if (st.precheck === 'refused') {
				statusPanel.appendChild(E('div', { 'class': 'alert-message warning', 'style': 'margin:0 0 .5em' }, [
					E('strong', {}, _('Configuration check refused:') + ' '),
					document.createTextNode(backendMessage(st.precheck_reason) || _('unknown reason')),
					E('br'), E('small', {}, _('The last working configuration stays active. Fix the issue above, then apply again.'))
				]));
			}
			/* The route guidance is deliberately tied to the applied snapshot. It is
			 * read-only: draft UCI values never become a route suggestion. */
			var routeToggle, routeContent;
			if (st.applied_mode === 'subnet') {
				var routeOpen = false;
				var routeBody = E('div', { 'style': 'display:none;margin:.5em 0 0' });
				var routeButtonText = _('Get main-router static route command (side-router mode only)');
				routeToggle = E('button', {
					'class': 'btn cbi-button cbi-button-neutral',
					'click': function() {
						routeOpen = !routeOpen;
						routeBody.style.display = routeOpen ? '' : 'none';
						routeToggle.textContent = routeOpen ? _('Hide main-router static route') : routeButtonText;
					}
				}, routeButtonText);
				var routeText = String(st.suggest || '');
				var routeTarget = routeText.match(/destination\s+([^ ]+)/);
				var routeGateway = routeText.match(/gateway\s+([^ ]+)/);
				var routeCommand = routeText.match(/\((ip route add [^)]+)\)/);
				var routeRows = [
					E('p', {}, _('Run this command on the main router, not on this device. It is temporary and is lost after reboot; configure a permanent static route on the main router for persistence.')),
					E('div', {}, [ E('strong', {}, _('Currently applied destination:')), ' ', document.createTextNode(routeTarget ? routeTarget[1] : (st.applied_pool || _('unavailable'))) ]),
					E('div', {}, [ E('strong', {}, _('Currently applied next hop:')), ' ', document.createTextNode(routeGateway ? routeGateway[1] : _('unavailable')) ])
				];
				if (routeCommand) {
					var commandText = routeCommand[1];
					var commandInput = E('input', { 'type': 'text', 'readonly': 'readonly', 'value': commandText, 'style': 'width:28em;max-width:100%' });
					var copyButton = E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function() {
						if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(commandText).then(function() { ui.addNotification(null, E('p', _('Copied.')), 'info'); }, function() { commandInput.focus(); commandInput.select(); ui.addNotification(null, E('p', _('Clipboard API is unavailable; the command is selected for manual copying.')), 'warning'); });
						else { commandInput.focus(); commandInput.select(); ui.addNotification(null, E('p', _('Clipboard API is unavailable; the command is selected for manual copying.')), 'warning'); }
					} }, _('Copy command'));
					routeRows.push(E('div', {}, [ commandInput, ' ', copyButton ]));
				} else routeRows.push(E('p', {}, _('No route command is available from the applied snapshot.')));
				routeBody.appendChild(E('div', { 'class': 'alert-message info' }, routeRows));
				routeContent = E('div', { 'class': 'cbi-value' }, [ E('div', { 'class': 'cbi-value-field' }, [ routeToggle, routeBody ]) ]);
			} else {
				routeToggle = E('button', {
					'class': 'btn cbi-button cbi-button-neutral',
					'click': function() { ui.addNotification(null, E('p', _('Apply the IP allocation settings first.')), 'info'); }
				}, _('Get main-router static route command (side-router mode only)'));
				routeContent = E('div', { 'class': 'cbi-value' }, [ E('div', { 'class': 'cbi-value-field' }, [ routeToggle ]) ]);
			}

			routeCard.appendChild(routeContent);
		}
		function refreshState(actual) {
			st = actual;
			clients = st.clients || [];
			switchState = st;
			paintStatus();
			paintCertificate();
			paintPki();
			paintSwitch();
			if (sIpMode) updModeHint();
		}
		paintStatus();

		/* ---- IP allocation mode ---- */
		var sIpMode = E('select', { 'style': 'width:22em' }, [
			E('option', { 'value': 'lansubnet', 'selected': (set.ip_mode === 'dhcp' || set.ip_mode === 'subnet') ? null : 'selected' }, modeLabels.lansubnet),
			E('option', { 'value': 'dhcp', 'selected': (set.ip_mode === 'dhcp') ? 'selected' : null }, modeLabels.dhcp),
			E('option', { 'value': 'subnet', 'selected': (set.ip_mode === 'subnet') ? 'selected' : null }, modeLabels.subnet)
		]);
		var sTrafficScope = E('select', { 'id': 'homevpn-traffic-scope', 'style': 'width:22em' }, [
			E('option', { 'value': 'lan', 'selected': set.traffic_scope === 'full' ? null : 'selected' }, _('Home LAN only (split tunnel)')),
			E('option', { 'value': 'full', 'selected': set.traffic_scope === 'full' ? 'selected' : null }, _('All IPv4 traffic (full tunnel)'))
		]);
		// Use only a validated /24 LAN network for examples; never change saved pool values.
		var poolLan = String(st.lan_net || '').match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\/24$/);
		var poolPrefix = poolLan && poolLan.slice(1).every(function(o) { return +o <= 255; }) ? poolLan.slice(1, 4).join('.') : '192.168.1';
		var sPs = E('input', { 'type': 'text', 'value': set.pool_start || '', 'placeholder': _('Example: %s').format(poolPrefix + '.50'), 'style': 'width:16em' });
		var sPe = E('input', { 'type': 'text', 'value': set.pool_end || '', 'placeholder': _('Example: %s').format(poolPrefix + '.99'), 'style': 'width:16em' });
		var sPc = E('input', { 'type': 'text', 'value': set.pool_subnet || '', 'placeholder': '10.100.1.0/24', 'style': 'width:16em' });
		var cidrError = E('div', { 'id': 'homevpn-cidr-error', 'role': 'alert', 'style': hintColors('error') + ';margin-top:.5em;padding:.5em .75em;display:none' });
		sPc.setAttribute('aria-describedby', 'homevpn-cidr-error');
		function validateCidr(pc) {
			var match = pc.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\/(\d{1,2})$/);
			var message = sIpMode.value !== 'subnet' ? '' : !pc
				? _('Pool subnet is required in independent subnet mode. Enter a CIDR such as 10.100.1.0/24.')
				: !match || !match.slice(1, 5).every(function(o) { return +o <= 255; }) || +match[5] < 8 || +match[5] > 30
					? _('Enter a valid IPv4 CIDR with a prefix from /8 to /30, such as 10.100.1.0/24.') : '';
			cidrError.textContent = message;
			cidrError.style.display = message ? '' : 'none';
			sPc.setAttribute('aria-invalid', message ? 'true' : 'false');
			if (message) {
				sPc.focus();
				cidrError.scrollIntoView({ block: 'center', behavior: 'instant' });
			}
			return !message;
		}
		var sMasq = E('select', { 'style': 'width:16em' }, [
			E('option', { 'value': '0', 'selected': (set.masq === '1') ? null : 'selected' }, _('Off (VPN subnet return route required)')),
			E('option', { 'value': '1', 'selected': (set.masq === '1') ? 'selected' : null }, _('On (when the main router cannot add a static route)'))
		]);
		var modeHint = E('p', { 'class': 'cbi-section-descr' });
		function updModeHint() {
			var m = sIpMode.value;
			if (typeof routeCard !== 'undefined' && routeCard) routeCard.style.display = (m === 'subnet' || st.applied_mode === 'subnet') ? '' : 'none';
			var hints = {
				lansubnet: _('Pool carved from the LAN subnet (default .50-.99) — suitable for side routers where the main router provides DHCP; keep the main router DHCP allocation range clear of the addresses reserved on this device for VPN clients'),
				dhcp: _('Obtain addresses via local DHCP so VPN clients share the same subnet as local devices. This mode requires local dnsmasq and is only available when this device provides DHCP service for the LAN. Supports mDNS/AirPlay. To assign fixed IPs to VPN users, use the "Fixed IP (DHCP mode)" column in the "EAP accounts" section. This mode is unavailable when firewall flow offloading is enabled.'),
				subnet: _('Clients use a subnet separate from the home LAN. When this device is the main router, VPN clients and home LAN devices can naturally access each other in both directions; when this device is a side router, add a static route for the VPN subnet via this device on the main router to enable access in both directions. If the main router cannot add a static route, enable "NAT masquerade" so VPN clients can initiate access to home LAN devices; in that case, LAN devices cannot initiate access to VPN clients.')
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
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('IP allocation mode')), E('div', { 'class': 'cbi-value-field' }, [ sIpMode, modeHint ]) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Client traffic scope')), E('div', { 'class': 'cbi-value-field' }, [ sTrafficScope, E('p', { 'class': 'cbi-section-descr' }, _('Home LAN only keeps other traffic on the client network. All IPv4 traffic requests a default route through this VPN; internet access also requires working forwarding and NAT on the server router. Existing client profiles may need to be reconnected or updated. IPv6 is not tunneled.')) ]) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Pool start')), E('div', { 'class': 'cbi-value-field' }, sPs) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Pool end')), E('div', { 'class': 'cbi-value-field' }, sPe) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Pool subnet (CIDR)')), E('div', { 'class': 'cbi-value-field' }, [ sPc, cidrError ]) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('NAT masquerade (side-router compatibility)')), E('div', { 'class': 'cbi-value-field' }, [ sMasq, E('p', { 'class': 'cbi-section-descr' }, _('Only effective in independent subnet mode. Translates the source address of VPN clients accessing the home LAN to this device’s address, so the main router does not need a static route for the VPN subnet. LAN devices cannot see the clients’ real IP addresses or initiate access to VPN clients through this feature alone.')) ]) ]),
			routeCard,
			/* This label-free action row must not inherit the theme's half-width field column. */
			E('div', { 'class': 'cbi-value' }, [ E('div', { 'id': 'homevpn-ip-actions', 'class': 'cbi-value-field', 'style': 'width:100%;max-width:100%' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-neutral',
					'click': ui.createHandlerFn(this, function() {
						var ps = (sPs.value || '').trim(), pe = (sPe.value || '').trim(), pc = (sPc.value || '').trim();
						if (sIpMode.value === 'lansubnet' && ps && !/^\d+\.\d+\.\d+\.\d+$/.test(ps)) { ui.addNotification(null, E('p', _('Pool start is not a valid IP address.')), 'warning'); return; }
						if (sIpMode.value === 'lansubnet' && pe && !/^\d+\.\d+\.\d+\.\d+$/.test(pe)) { ui.addNotification(null, E('p', _('Pool end is not a valid IP address.')), 'warning'); return; }
						/* CIDR validation is shared by both save entrances below. */
						return saveSettings(ps, pe, pc, function(r) {
							if (r && r.ok) {
								if (r.precheck_ok) {
									ui.addNotification(null, E('p', _('Applied. Mode: %s, pool: %s').format(modeLabels[sIpMode.value] || sIpMode.value, pc || (ps || _('automatic')) + '-' + (pe || _('automatic')))), 'info');
								} else {
									ui.addNotification(null, E('p', _('Refused: %s — the last working configuration stays active.').format(backendMessage(r.precheck_reason) || _('precheck failed'))), 'error');
								}
								reload();
							} else {
								ok(r, _('Apply'));
							}
						});
					})
				}, _('Apply IP settings')), ' ',
				E('span', { 'style': 'font-size:90%;color:inherit' }, _('Applying re-runs the prechecks and (re)loads the swanctl config; existing VPN connections survive whenever possible.'))
			]) ])
		]));
		updModeHint();

		/* ---- settings ---- */
		var sRemote = E('input', { 'id': 'homevpn-remote', 'type': 'text', 'value': set.remote || '', 'placeholder': _('vpn.example.com or public IP'), 'style': 'width:16em' });
		var sName = E('input', { 'type': 'text', 'value': set.vpn_name || 'Home VPN', 'style': 'width:16em' });
		var sMode = E('select', { 'id': 'homevpn-cert-mode', 'style': 'width:16em' }, [
			E('option', { 'value': 'selfsigned', 'selected': (set.cert_mode === 'selfsigned' ? 'selected' : null) }, _('Self-signed (auto-generated)')),
			E('option', { 'value': 'import', 'selected': (set.cert_mode === 'import' ? 'selected' : null) }, _('Import own certificate')),
			E('option', { 'value': 'acme', 'selected': (set.cert_mode === 'acme' ? 'selected' : null) }, _('ACME / Let\u0027s Encrypt'))
		]);
		var sAcme = E('input', { 'id': 'homevpn-acme-domain', 'type': 'text', 'value': set.acme_domain || '', 'placeholder': _('domain from Services → Let\u0027s Encrypt'), 'style': 'width:16em' });
		var typeLabels = { rsa: _('RSA (recommended for iPhone)'), ecc: _('ECC (ECDSA)') };
		var sAcmeType = E('select', { 'id': 'homevpn-acme-type', 'style': 'width:16em' });
		var acmeSingle = E('span', { 'id': 'homevpn-acme-single' });
		var acmeHint = E('div', { 'id': 'homevpn-acme-hint', 'class': 'cbi-section-descr', 'role': 'status', 'aria-live': 'polite' });
		var acme = { generation: 0, domain: '', state: 'empty', types: [], selected: set.acme_key_type || 'rsa' };
		var acmeTimer;
		function paintAcme() {
			var ready = acme.state === 'ready', dual = ready && acme.types.length === 2;
			sAcmeType.style.display = dual ? '' : 'none';
			sAcmeType.disabled = !dual;
			acmeSingle.style.display = ready && acme.types.length === 1 ? '' : 'none';
			acmeSingle.textContent = ready && acme.types.length === 1 ? typeLabels[acme.selected] : '';
			var text = _('Enter the domain to look for local certificates.'), kind = '';
			if (acme.state === 'loading') text = _('Checking local certificates…');
			else if (acme.state === 'error') { text = _('Certificate query failed. Edit the domain or retry; this does not mean no certificate was found.'); kind = 'error'; }
			else if (ready && !acme.types.length) { text = _('No usable local certificate found for this domain. Issue a certificate in Services → Let\u0027s Encrypt first.'); kind = 'warn'; }
			else if (ready) { text = _('Local certificate found. The server address will be checked against its SAN when saving.'); kind = 'ok'; }
			acmeHint.textContent = text;
			acmeHint.setAttribute('style', 'margin:.25em 0 0' + (kind ? ';' + hintColors(kind) : ''));
			paintPkiDraft();
		}
		function queryAcme(delay) {
			clearTimeout(acmeTimer);
			var generation = ++acme.generation, domain = (sAcme.value || '').trim();
			acme.domain = domain; acme.types = []; acme.state = domain ? 'loading' : 'empty';
			paintAcme();
			if (!domain) return;
			acmeTimer = setTimeout(function() {
				Promise.resolve().then(function() { return callDiscoverAcme(domain); }).then(function(r) {
					if (generation !== acme.generation || domain !== (sAcme.value || '').trim()) return;
					if (!r || r.ok !== true || r.domain !== domain || !Array.isArray(r.types) ||
						r.types.some(function(t) { return t !== 'rsa' && t !== 'ecc'; }) ||
						r.types.length !== r.types.filter(function(t, i, a) { return a.indexOf(t) === i; }).length)
						throw new Error('Invalid certificate discovery response');
					acme.types = r.types; acme.state = 'ready';
					if (acme.types.indexOf(acme.selected) < 0) acme.selected = acme.types.indexOf('rsa') >= 0 ? 'rsa' : (acme.types[0] || '');
					while (sAcmeType.firstChild) sAcmeType.removeChild(sAcmeType.firstChild);
					acme.types.forEach(function(t) { sAcmeType.appendChild(E('option', { 'value': t }, typeLabels[t])); });
					sAcmeType.value = acme.selected;
					paintAcme();
				}).catch(function() {
					if (generation !== acme.generation || domain !== (sAcme.value || '').trim()) return;
					acme.state = 'error'; acme.types = []; paintAcme();
				});
			}, delay);
		}
		sAcme.addEventListener('input', function() { queryAcme(300); });
		sAcmeType.addEventListener('change', function() { acme.selected = sAcmeType.value; });
		queryAcme(0);
		var acmeRow = E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('ACME domain')), E('div', { 'class': 'cbi-value-field' }, [
			sAcme,
			E('p', { 'id': 'homevpn-acme-candidate-hint' }, _('ACME candidates are not deployed certificates. Only a successful certificate installation changes deployment; current deployment is shown separately below.')),
			E('div', {}, [ sAcmeType, acmeSingle ]),
			E('div', { 'class': 'cbi-section-descr' }, _('A single available key type is selected automatically. If both exist, choose RSA or ECC. Source: /etc/acme, then /etc/ssl/acme.')),
			acmeHint,
			E('button', { 'class': 'btn cbi-button', 'click': function() { queryAcme(0); } }, _('Check again'))
		]) ]);
		var settingsSaving = false;
		function settingsError(message, output) {
			ui.showModal(_('Save settings failed'), [
				E('p', {}, message),
				E('pre', { 'style': 'white-space:pre-wrap' }, output || ''),
				E('div', { 'class': 'right' }, E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Close')))
			]);
		}
		function confirmPki(title, message) {
			return new Promise(function(resolve) {
				ui.showModal(title, [ E('p', {}, message), E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': function() { ui.hideModal(); resolve(false); } }, _('Cancel')), ' ',
					E('button', { 'class': 'btn cbi-button-apply', 'click': function() { ui.hideModal(); resolve(true); } }, _('Confirm'))
				]) ]);
			});
		}
		function saveSettings(ps, pe, pc, done) {
			if (settingsSaving || caBusy || switchBusy) return Promise.resolve();
			if (!validateCidr(pc) || !validateRemote()) return Promise.resolve();
			var domain = (sAcme.value || '').trim();
			if (sMode.value === 'acme' && (acme.state !== 'ready' || domain !== acme.domain || !domain || acme.types.indexOf(acme.selected) < 0)) {
				ui.addNotification(null, E('p', _('Wait for a successful local certificate query and select an available type before saving.')), 'warning');
				return Promise.resolve();
			}
			var payload = [ sRemote.value.trim(), sName.value, sMode.value, domain, acme.selected || set.acme_key_type || 'rsa', sIpMode.value, ps, pe, pc, sMasq.value, sTrafficScope.value ];
			settingsSaving = true; paintPkiDraft();
			function submit(yes) {
				if (!yes) return;
				return callSetSettings.apply(null, payload).then(function(r) {
					if (r && (r.ok || r.saved)) set = Object.assign({}, set, {remote:payload[0],vpn_name:payload[1],cert_mode:payload[2],acme_domain:payload[3],acme_key_type:payload[4],ip_mode:payload[5],pool_start:payload[6],pool_end:payload[7],pool_subnet:payload[8],masq:payload[9],traffic_scope:payload[10]});
					if (!r || !r.ok) {
						settingsError(r && r.saved ? _('Settings saved, but application failed.') : (backendMessage(r && r.error) || _('unknown error')), backendMessage(r && (r.output || r.precheck_reason)));
						return;
					}

					return callStatus().then(function(actual) {
						if (!actual || actual.ok === false) throw new Error(_('Certificate query failed.'));
						refreshState(actual);
						ui.addNotification(null, E('p', r.reason === 'remote_required' ? _('Saved. Enter a server address before applying or exporting profiles.') : _('Saved and checked. Disabled service remains stopped.')), r.reason === 'remote_required' ? 'warning' : 'info');
						if (payload[2] === 'selfsigned' && !payload[0]) return ensureCA(false, true);
					});
				});
			}
			var task = !payload[0] && (st.remote || st.conn_loaded)
				? confirmPki(_('Clear server address?'), _('Clearing the address makes HomeVPN unconfigured and disables profile exports. Certificates and accounts are kept. Disable HomeVPN first if it is running; unsafe live unloading is refused.')).then(submit) : submit(true);
			return Promise.resolve(task).catch(function(e) { settingsError(_('Unable to save settings: %s').format(e && e.message || _('unknown error'))); })
				.finally(function() { settingsSaving = false; paintPkiDraft(); });
		}

		var profileButtons = [];
		var caBusy = false, caMessage = '', caError = false;
		var remoteError = E('div', { 'id': 'homevpn-remote-error', 'role': 'alert', 'style': hintColors('error') + ';padding:.5em .75em;display:none' });
		sRemote.setAttribute('aria-describedby', 'homevpn-remote-error');
		var pkiDraft = E('div', { 'id': 'homevpn-pki-draft', 'role': 'status', 'aria-live': 'polite' });
		var pkiDetails = E('div', { 'id': 'homevpn-pki-details', 'style': 'overflow-wrap:anywhere' });
		var pkiPanel = E('div', { 'id': 'homevpn-selfsigned' }, [ E('strong', {}, _('Self-signed certificates')), pkiDetails, pkiDraft ]);
		function validateRemote() {
			var r = sRemote.value.trim(), valid = !r || r.length <= 253 && /^[A-Za-z0-9.-]+$/.test(r) && r.split('.').every(function(label) { return label.length <= 63 && /^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/.test(label); });
			if (r && /^[0-9.]+$/.test(r)) valid = /^(\d{1,3}\.){3}\d{1,3}$/.test(r) && r.split('.').every(function(o) { return +o <= 255 && (o.length === 1 || o[0] !== '0'); });
			remoteError.textContent = valid ? '' : _('Enter a domain or IPv4 address, without URL, port, path or wildcard. IPv6 is not supported.');
			remoteError.style.display = valid ? 'none' : '';
			sRemote.setAttribute('aria-invalid', valid ? 'false' : 'true');
			if (!valid) { sRemote.focus(); remoteError.scrollIntoView({block:'center',behavior:'instant'}); }
			return valid;
		}
		// Match every field sent by the shared IP/server save path, including hidden drafts.
		function pkiDirty() {
			return sRemote.value.trim() !== (set.remote || '') || sName.value !== (set.vpn_name || 'Home VPN') ||
				sMode.value !== (set.cert_mode || 'selfsigned') || sAcme.value.trim() !== (set.acme_domain || '') ||
				(acme.selected || set.acme_key_type || 'rsa') !== (set.acme_key_type || 'rsa') ||
				sIpMode.value !== (set.ip_mode || 'lansubnet') || sPs.value.trim() !== (set.pool_start || '') ||
				sPe.value.trim() !== (set.pool_end || '') || sPc.value.trim() !== (set.pool_subnet || '') || sMasq.value !== (set.masq || '0') ||
				sTrafficScope.value !== (set.traffic_scope === 'full' ? 'full' : 'lan');
		}
		var maintenanceDraft = E('p', { 'id': 'homevpn-maintenance-draft', 'role': 'status', 'style': 'display:none' }, _('Unsaved changes. Save and apply first.'));
		function paintPkiDraft() {
			if (!pkiDraft) return;
			maintenanceDraft.style.display = pkiDirty() ? '' : 'none';
			pkiDraft.textContent = pkiDirty() ? _('Settings have unsaved changes. Save and apply first; deployed certificate details remain unchanged.') : '';
			pkiDraft.setAttribute('style', pkiDirty() ? 'margin:.5em 0;padding:.5em .75em;' + hintColors('warn') : 'display:none');
			if (profileButtons) profileButtons.forEach(function(b) { b.disabled = !st.pki_ready; });
			var caButtons = pkiDetails.querySelectorAll ? pkiDetails.querySelectorAll('button') : [];
			Array.prototype.forEach.call(caButtons, function(b) { b.disabled = caBusy || settingsSaving || switchBusy; });
			if (provisionButton) provisionButton.disabled = settingsSaving || caBusy || switchBusy || !stateKnown || pkiDirty();
		}
		function paintPki() {
			if (!pkiDetails) return;
			pkiPanel.style.display = sMode.value === 'selfsigned' ? '' : 'none';
			while (pkiDetails.firstChild) pkiDetails.removeChild(pkiDetails.firstChild);
			var pk = st.selfsigned || {}, preview = (set.cert_mode || 'selfsigned') !== 'selfsigned';
			pkiDetails.appendChild(E('p', { 'role': 'status', 'style': hintColors(caError ? 'error' : pk.ca_valid ? 'ok' : 'warn') + ';padding:.5em .75em' },
				preview ? _('Preview only. The local CA is prepared after saving self-signed mode.') : caBusy ? _('Checking or creating root CA…') : caMessage || (pk.ca_valid ? _('Root CA is valid.') : _('Root CA needs attention. Existing trust assets are never replaced automatically.'))));
			if (!preview) {
				pkiDetails.appendChild(E('p', {}, _('Valid until') + ': ' + (pk.notafter || '—')));
				pkiDetails.appendChild(E('p', {}, _('SHA-256 fingerprint') + ': ' + (pk.fingerprint || '—')));
				if (pk.ca_reason) pkiDetails.appendChild(E('p', { 'style': hintColors('error') }, backendMessage(pk.ca_reason)));
				if (pk.ca_expiring) pkiDetails.appendChild(E('p', { 'style': hintColors('warn') }, _('Root CA expires soon. Renewing a leaf does not change client trust; replacing the CA does.')));
				pkiDetails.appendChild(E('p', {}, !st.remote ? _('Server certificate: waiting for a saved address.') : pk.leaf_state === 'ready' ? _('Server certificate is ready and reusable.') : _('Server certificate needs issuance or re-signing: %s').format(backendMessage(pk.leaf_state))));
				pkiDetails.appendChild(E('p', {}, _('Saved server address') + ': ' + (st.remote || '—')));
				// Deployed leaf details are shown once in the shared certificate panel.

				pkiDetails.appendChild(E('p', {}, _('Address changes require updating client connection settings. Leaf renewal under the same CA normally does not require installing the CA again.')));
				pkiDetails.appendChild(E('p', {}, _('For manual client configuration, download and install the CA certificate below.')));
				pkiDetails.appendChild(E('button', { 'class':'btn cbi-button cbi-button-neutral', 'click': function() {
					if (caBusy || settingsSaving || switchBusy) return;
					return confirmPki(_('Replace root CA?'), _('Existing clients must install the new CA or re-import their profiles, otherwise they cannot verify the new server certificate. Certificates are replaced only after validation. Stop HomeVPN before replacing its CA.')).then(function(yes) { if (yes) return ensureCA(true); });
				} }, _('Replace root CA…')));
			}

			paintPkiDraft();
		}
		function ensureCA(replace, savedAction) {
			if (caBusy || switchBusy || (settingsSaving && !savedAction) || (set.cert_mode || 'selfsigned') !== 'selfsigned') return Promise.resolve();
			caBusy = true; caError = false; caMessage = ''; paintPki();
			return callEnsureCA(!!replace, (st.selfsigned || {}).fingerprint || '').then(function(r) {
				if (!r || !r.ok) { caError = true; caMessage = backendMessage(r && r.error) || _('Certificate query failed.'); }
				else if (r.replaced) caMessage = _('Root CA replaced. Update client trust now.');
				return callStatus().then(function(actual) { if (!actual || actual.ok === false) throw new Error(_('Certificate query failed.')); refreshState(actual); });
			}).catch(function(e) { caError = true; caMessage = String(e.message || e); })
				.finally(function() { caBusy = false; paintPki(); });
		}
		var provisionButton = E('button', { 'id':'homevpn-provision', 'class':'btn cbi-button cbi-button-neutral', 'click': function() {
			if (settingsSaving || caBusy || switchBusy || !stateKnown || pkiDirty()) return Promise.resolve();
			settingsSaving = true; paintPkiDraft();
			return callProvision().then(function(r) { if (!ok(r, _('Provision'))) return; return callStatus().then(refreshState); })
				.catch(function(e) { settingsError(String(e.message || e)); }).finally(function() { settingsSaving = false; paintPkiDraft(); });
		} }, _('Reapply saved settings'));
		[ sRemote, sName, sAcme, sPs, sPe, sPc ].forEach(function(field) { field.addEventListener('input', paintPkiDraft); });
		[ sIpMode, sMasq, sTrafficScope, sAcmeType ].forEach(function(field) { field.addEventListener('change', paintPkiDraft); });
		sMode.addEventListener('change', paintPki);
		paintPki();

		/* ---- import-mode: deployed-cert info panel + collapsible upload ---- */
		var certTable = E('div', { 'class': 'table', 'style': 'margin-top:.4em' });
		function paintCertificate() {
			var certRows = [];
			var ct = st.cert || null;
			var keyCell = _('(not deployed)');
			if (ct && ct.key_matches === true)
				keyCell = E('span', { 'style': 'color:' + CLR.ok.txt }, _('✓ matches the certificate'));
			else if (ct && ct.key_matches === false)
				keyCell = E('span', { 'style': 'color:' + CLR.error.txt }, _('✗ does NOT match the certificate'));
			if (ct && ct.subject) {
				var expColor = (ct.expiry === 'expired') ? CLR.error.txt : ((ct.expiry === 'soon') ? CLR.warn.txt : CLR.ok.txt);
				var expText = (ct.expiry === 'expired') ? _('EXPIRED') : ((ct.expiry === 'soon') ? _('expiring soon') : _('valid'));
				certRows = [
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Certificate source')), E('td', { 'class': 'td left' }, ({ selfsigned: _('HomeVPN self-signed'), import: _('User import'), acme: _('ACME') })[ct.source] || _('Unknown')) ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('SHA-256 fingerprint')), E('td', { 'class': 'td left', 'style': 'overflow-wrap:anywhere' }, ct.fingerprint || '—') ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '33%' }, _('Server certificate')), E('td', { 'class': 'td left' }, ct.subject || '?') ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Issuer')), E('td', { 'class': 'td left' }, ct.issuer || '?') ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('SAN')), E('td', { 'class': 'td left' }, ct.san || _('(none)')) ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Valid until')), E('td', { 'class': 'td left' },
						E('span', { 'style': 'color:' + expColor }, (ct.notafter || '?') + ' — ' + expText)) ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Private key')), E('td', { 'class': 'td left' }, keyCell) ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('CA (for client profiles)')), E('td', { 'class': 'td left' }, ct.ca_subject || _('(none deployed)')) ])
				];
			}
			while (certTable.firstChild) certTable.removeChild(certTable.firstChild);
			if (!ct || !ct.subject) certRows.push(E('p', { 'role': 'status' }, _('No certificate deployed yet.')));
			certRows.forEach(function(row) { certTable.appendChild(row); });
		}
		paintCertificate();
		var importSourceHint = E('p', { 'id': 'homevpn-import-source-hint', 'role': 'status' });
		var importReplace = E('div', { 'id': 'homevpn-import-replace', 'style': 'margin-top:.4em' }, [
			E('button', { 'class': 'btn cbi-button cbi-button-neutral', 'click': function() {
				if (sMode.value !== 'import') return;
				importBox.style.display = '';
				if (upServer.focus) upServer.focus();
			} }, _('Replace certificate…'))
		]);
		var certInfo = E('div', { 'id': 'homevpn-deployed-certificate', 'style': 'margin:.3em 0 .3em' }, [
			E('strong', {}, _('Currently deployed certificate')),
			importSourceHint,
			certTable,
			importReplace
		]);
		function readPem(file) {
			/* frontend sanity: reject non-text uploads early (DER/PKCS#12) —
			   full validation happens server-side */
			return new Promise(function(resolve) {
				var fr = new FileReader();
				fr.onload = function() {
					var t = String(fr.result || '');
					if (!/-----BEGIN [^-]+-----/.test(t)) { resolve(null); return; }
					resolve(t);
				};
				fr.onerror = function() { resolve(null); };
				fr.readAsText(file);
			});
		}
		var upServer = E('input', { 'type': 'file', 'accept': '.crt,.cer,.pem' });
		var upKey    = E('input', { 'type': 'file', 'accept': '.key,.pem' });
		var upCa     = E('input', { 'type': 'file', 'accept': '.crt,.cer,.pem' });
		[ upServer, upKey, upCa ].forEach(function(el) { el.style.width = '16em'; });
		var upHint = E('p', { 'class': 'cbi-section-descr' });
		var importBox = E('div', { 'id': 'homevpn-import-upload', 'style': 'border:1px dashed #888;padding:.6em .9em;margin:.3em 0 .3em' }, [
			E('strong', {}, _('Import own certificate (PEM)')),
			upHint,
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Server certificate')), E('div', { 'class': 'cbi-value-field' }, upServer) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Private key (unencrypted)')), E('div', { 'class': 'cbi-value-field' }, upKey) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('CA certificate (for clients)')), E('div', { 'class': 'cbi-value-field' }, upCa) ]),
			E('div', { 'class': 'cbi-value' }, [ E('div', { 'class': 'cbi-value-field' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'click': ui.createHandlerFn(this, function() {
						var picked = [ upServer.files[0], upKey.files[0], upCa.files[0] ];
						var names = [ _('server certificate'), _('private key'), _('CA certificate') ];
						var missing = [0, 1, 2].filter(function(i) { return picked[i] === null || picked[i] === undefined; });
						if (!(missing.length === 3) && (missing.indexOf(0) >= 0) !== (missing.indexOf(1) >= 0))
							{ ui.addNotification(null, E('p', _('Server certificate and private key must be uploaded together.')), 'warning'); return; }
						return Promise.all(picked.map(function(f) { return f ? readPem(f) : Promise.resolve(undefined); })).then(function(txts) {
							for (var i = 0; i < 3; i++)
								if (txts[i] === null)
									{ ui.addNotification(null, E('p', _('%s: not a PEM text file — export Base64 PEM (a .p12/.der needs converting first).').format(names[i])), 'warning'); return; }
							return callUploadCerts(txts[0] || '', txts[1] || '', txts[2] || '').then(function(r) {
								if (r && r.ok) {
									var msg = _('Certificate imported: %s — SAN %s, expires %s.').format(r.subject || '?', r.san || _('(none)'), r.expires || '?');
									if (r.ca_installed)
										msg += ' ' + _('CA installed — client profiles will embed it.');
									else
										msg += ' ' + _('No CA uploaded — the deployed CA (if any) keeps serving client profiles.');
									if (r.warning) msg += ' || ' + backendMessage(r.warning);
									flash(msg, r.warning ? 'warning' : 'info');
									reload();
								}
								else {
									ok(r, _('Import certificate'));
								}
							});
						});
					})
				}, _('Upload & apply')),
				' ',
				E('span', { 'style': 'font-size:90%;color:inherit' }, _('Validated before anything is written: PEM parse, expiry, SAN present, server address must be an EXACT SAN (wildcard SANs never match in strongSwan), key↔certificate pair, CA signs the certificate. On any error nothing is changed.'))
			]) ])
		]);
		function updImportBox() {
			var show = (sMode.value === 'import');
			acmeRow.style.display = (sMode.value === 'acme') ? '' : 'none';
			var hasCert = !!(st.cert && st.cert.subject), source = (st.cert || {}).source;
			importBox.style.display = (show && source !== 'import') ? '' : 'none';
			certInfo.style.display = '';
			importSourceHint.style.display = (show && hasCert) ? '' : 'none';
			importReplace.style.display = show && hasCert ? '' : 'none';
			importSourceHint.textContent = source === 'selfsigned'
				? _('The current server certificate was generated by HomeVPN. Selecting import mode does not replace it; upload the certificate and private key.')
				: source === 'acme' ? _('The current server certificate comes from ACME, not a user import. Selecting import mode does not replace it; upload the certificate and private key.')
				: source === 'import' ? _('The current server certificate was uploaded by the user. Upload a replacement only when needed.')
				: _('The current certificate source is unknown. Selecting import mode does not mean a certificate has been imported; upload the certificate and private key.');
			if (show && !hasCert) {
				upHint.textContent = _('No certificate deployed yet. Upload the server certificate, its private key, and the CA certificate clients should trust (e.g. your NAS/ACME issuer CA).');
			}
			else if (show && hasCert) {
				upHint.textContent = _('Upload the replacement set (server certificate + private key, CA optional) — the old files are replaced only after all checks pass.');
			}
		}
		sMode.addEventListener('change', updImportBox);
		updImportBox();
		nodes.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Server settings')),
			E('p', { 'class': 'cbi-section-descr' },
				_('The server address must exactly match a certificate SAN; wildcard certificates are not supported. Self-signed mode prepares a local root CA and issues the server certificate only after an address is saved. Import uses your uploaded files. ACME uses a locally issued certificate (RSA is recommended for iOS).')),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Server address (DDNS/IP)')), E('div', { 'class': 'cbi-value-field' }, [ sRemote, remoteError, E('p', {}, _('Enter the domain or IP clients connect to. Use DDNS for a dynamic public IP; HomeVPN never uses the WAN IP automatically.')) ]) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('VPN display name')), E('div', { 'class': 'cbi-value-field' }, sName) ]),
			E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title' }, _('Certificate mode')), E('div', { 'class': 'cbi-value-field' }, sMode) ]),
			pkiPanel,
			acmeRow,
			importBox,
			certInfo,
			E('div', { 'class': 'cbi-value' }, [ E('div', { 'class': 'cbi-value-field' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-save',
					'click': ui.createHandlerFn(this, function() {
						return saveSettings((sPs.value || '').trim(), (sPe.value || '').trim(), (sPc.value || '').trim(), function(r) {
							if (r && r.ok && !r.precheck_ok)
								ui.addNotification(null, E('p', _('Refused: %s — the last working configuration stays active.').format(backendMessage(r.precheck_reason) || _('precheck failed'))), 'error');
							if (ok(r, _('Save settings'))) { flash(_('Saved. Server re-provisioned.'), 'info'); reload(); }
							else { flash(_('Save refused: %s').format(backendMessage(r && r.error) || _('unknown error')), 'error'); reload(); }
						});
					})
				}, _('Save and apply'))
			]) ]),
			E('details', { 'id': 'homevpn-maintenance' }, [
				E('summary', {}, _('Maintenance operations')),
				E('p', {}, _('Does not save current input. Checks certificates and reapplies saved settings to retry after an application failure.')),
				provisionButton,
				maintenanceDraft
			])
		]));

		/* ---- EAP users ---- */
		var isDhcp = (st.applied_mode === 'dhcp');
		var rows = [ E('tr', { 'class': 'tr table-titles' }, [ E('th', { 'class': 'th' }, _('Username')), E('th', { 'class': 'th' }, _('Fixed IP (DHCP mode)')), E('th', { 'class': 'th cbi-section-actions' }, _('Client config + actions')) ]) ];
		if (!users.length) rows.push(E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td', 'colspan': 3 }, E('em', {}, _('No users yet.'))) ]));
		users.forEach(function(u) {
			var fipCell;
			if (isDhcp) {
				/* measured live: theme .cbi-button renders 36px tall
				   (padding 7.2px 14.4px + 13px font) — match it exactly so
				   the input, Set/Clear buttons and username align on a line */
				var ipInput = E('input', { 'type': 'text', 'value': u.fixed_ip || '', 'placeholder': _('dynamic'), 'style': 'width:11em;height:36px;padding:2px 10px;vertical-align:middle;box-sizing:border-box' });
				var btnStyle = 'vertical-align:middle';
				fipCell = E('td', { 'class': 'td', 'style': 'vertical-align:middle' }, [
					ipInput, ' ',
					E('button', { 'class': 'btn cbi-button cbi-button-save', 'style': btnStyle, 'click': ui.createHandlerFn(this, function() {
						var v = (ipInput.value || '').trim();
						return callSetUserIp(u.name, v).then(function(r) {
							if (ok(r, _('Set fixed IP')))
								ui.addNotification(null, E('p', v ? _('Fixed IP for "%s": %s — applies on the next dial-in.').format(u.name, v) : _('Fixed IP for "%s" cleared — dynamic allocation again.').format(u.name)), 'info');
						});
					}) }, _('Set')),
					(u.fixed_ip ? E('button', { 'class': 'btn cbi-button cbi-button-remove', 'style': btnStyle, 'click': ui.createHandlerFn(this, function() {
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
				E('td', { 'class': 'td', 'style': 'vertical-align:middle' }, u.name),
				fipCell,
				E('td', { 'class': 'td cbi-section-actions' }, [
					(function() { var button = E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, function() {
						return callDownload(u.name, 'mobileconfig').then(function(r) {
							if (ok(r, _('Generate profile'))) saveBlob(r.mobileconfig, u.name + '.mobileconfig', 'application/x-apple-aspen-config');
						});
					}) }, _('iOS/macOS profile')); profileButtons.push(button); button.disabled = !st.pki_ready; return button; })(),
					' ',
					(function() { var button = E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(this, function() {
						return callDownload(u.name, 'sswan').then(function(r) {
							if (ok(r, _('Generate profile'))) saveBlob(r.sswan, u.name + '.sswan', 'application/vnd.strongswan.profile');
						});
					}) }, _('Android .sswan')); profileButtons.push(button); button.disabled = !st.pki_ready; return button; })(),
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
			E('p', { 'class': 'cbi-section-descr' }, _('Fixed IP: only effective in DHCP mode. When set, dnsmasq assigns a fixed IP to the VPN user by username; leave empty for dynamic allocation. Changes apply on the next connection. The fixed IP must be within the LAN subnet and must not conflict with other devices.')),
			E('details', { 'id': 'homevpn-client-guide', 'style': 'margin:0 0 1em' }, [
				E('summary', { 'style': 'cursor:pointer;font-weight:600' }, _('Client connection guide')),
				E('p', {}, _('Connection steps depend on the "Certificate mode" in "Server settings":')),
				E('div', { 'style': 'margin:0.75em 0' }, [
					E('strong', {}, _('Certificate mode: ACME (recommended)')),
					E('p', {}, _('The CA for an ACME certificate is trusted by mainstream clients, so no CA certificate installation is needed on the client.')),
					E('p', {}, _('To connect, use the device built-in IKEv2 client (phone or operating system) and enter the server domain, remote identifier (the same as the server domain), EAP username and password.')),
					E('p', {}, _('You can also download and import a profile (one per VPN user): .mobileconfig for Apple devices and .sswan for Android. Android system client support varies by device; the strongSwan App is recommended.')),
					E('p', {}, _('Reminder: for iPhone/iPad compatibility, when requesting an ACME certificate, select an option starting with RSA in the "Key length" dropdown under certificate "Advanced settings" to generate an RSA certificate.'))
				]),
				E('div', { 'style': 'margin:0.75em 0' }, [
					E('strong', {}, _('Certificate mode: self-signed (automatically generated)')),
					E('p', {}, _('In this mode, HomeVPN generates a certificate and signs it with the generated CA certificate. Mainstream clients do not trust self-signed certificates, so import and trust the HomeVPN CA certificate on the client before connecting.')),
					E('p', {}, _('The profiles provided on this page are recommended (one per VPN user; download using the button after the username).')),
					E('p', {}, _('Apple devices (iPhone/iPad example): download the .mobileconfig file, transfer it to the device using WeChat or another method, and save it in "Files". Open it in "Files"; the system will prompt you to enable trust in "Settings".')),
					E('p', {}, _('Then go to Settings → General → About → Certificate Trust Settings and trust the self-signed CA certificate. This VPN connection will appear in the system VPN settings, where you can connect.')),
					E('p', {}, _('Android: download the .sswan file and import it with the strongSwan App. The CA is imported into the App with the profile; no separate installation in the system certificate store is needed. Enter the account password when importing or connecting; if the file cannot be opened directly, use the App file picker.')),
					E('p', {}, _('Other clients: download and install the CA certificate, trust it, then manually configure an IKEv2 connection.'))
				]),
				E('p', {}, _('ACME certificates are recommended: they are free, quick to obtain, and avoid extra trust steps.'))
			]),
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
				_('For manual IKEv2 setup, enter the server domain, matching remote identifier, EAP username and password. Install the CA first for self-signed certificates; usually this is unnecessary with ACME certificates. See the client connection guide in EAP accounts for device-specific instructions.')),
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

		if ((set.cert_mode || 'selfsigned') === 'selfsigned') Promise.resolve().then(function() { return ensureCA(false); });
		return nodes;
	},
	handleSaveApply: null, handleSave: null, handleReset: null
});
