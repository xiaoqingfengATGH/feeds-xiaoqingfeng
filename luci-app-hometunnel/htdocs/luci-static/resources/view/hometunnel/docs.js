/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright (C) 2026 xiaoqingfeng <xiaoqingfeng@yeah.net> */
/* hometunnel docs — 方案说明 + 使用指引（纯静态内容页） */

'use strict';
'require view';
'require view.hometunnel.ui as htui';

return view.extend({
	render: function () {
		var h = function (title) {
			return E('h3', { 'style': 'margin:18px 0 10px 0;font-size:15px;font-weight:600;color:#348cd4' }, title);
		};
		var p = function (nodes) {
			return E('p', { 'style': 'margin:0 0 10px 0;line-height:1.75' }, nodes);
		};
		var li = function (nodes) {
			return E('li', { 'style': 'margin:0 0 6px 0;line-height:1.7' }, nodes);
		};
		var cell = function (w, nodes) {
			return E('td', { 'class': 'td left', 'style': w ? ('width:' + w) : '' }, nodes);
		};
		var row = function (aspect, mine, theirs) {
			return E('tr', { 'class': 'tr' }, [
				cell('18%', E('strong', {}, aspect)),
				cell('34%', mine),
				cell('48%', theirs)
			]);
		};

		var content = E('div', {}, [
			p([_('HomeTunnel is the Homelede intranet-exposure solution built on Cloudflare Tunnel. It works with or without a public IP, and is secure and free.')]),

			h(_('Why HomeTunnel')),
			E('ul', { 'style': 'padding-left:20px;margin:0 0 12px 0' }, [
				li([E('strong', {}, _('No public IP required')), ' ', _('— the router establishes an outbound connection to Cloudflare; home broadband behind NAT (or with only an IPv6 prefix) works out of the box.')]),
				li([E('strong', {}, _('No DDNS required')), ' ', _('— every service opened to the public internet gets its own fixed hostname; Cloudflare detects the IP address automatically, so home IP changes are nothing to worry about.')]),
				li([E('strong', {}, _('Automatic encryption')), ' ', _('— all inbound public traffic is automatically encrypted with HTTPS; Cloudflare issues and renews the certificates, no intervention needed.')]),
				li([E('strong', {}, _('On-demand access')), ' ', _('— keeping intranet services exposed to the public internet for long is risky. The tunnel stays closed by default and opens only when needed, with a convenient on/off switch reachable from any network. Even if you forget to close it, the tunnel stops by itself after the agreed time.')]),
				li([E('strong', {}, _('Free of charge')), ' ', _('— uses only Cloudflare free-tier features (Tunnel, Workers, DNS).')])
			]),

			h(_('Compared with frp / IPv6 tunneling')),
			E('div', { 'style': 'overflow-x:auto;margin-bottom:12px' },
				E('table', { 'class': 'table' }, [
					E('tr', { 'class': 'tr' }, [
						cell('18%', E('strong', {}, _('Aspect'))),
						cell('34%', E('strong', {}, _('HomeTunnel'))),
						cell('48%', E('strong', {}, _('frp / IPv6')))
					]),
					row(_('Public IP'), _('Not needed'), _('frp needs a server with a public IP; IPv6 needs a public IPv6 on every network path')),
					row(_('Extra server'), _('None — Cloudflare edge is the entry point'), _('frp needs a rented VPS running frps (paid, and you manage it)')),
					row(_('HTTPS certificate'), _('Edge-terminated, auto-issued and renewed'), _('frps usually plain HTTP or self-signed; IPv6 needs its own certificate per service')),
					row(_('Address stability'), _('Stable hostnames on your own domain'), _('frp: fixed only if you pay for the server IP; IPv6 prefix changes require DDNS anyway')),
					row(_('Firewall / ISP'), _('Outbound-only connection; no inbound port opening'), _('frp server must open ports; IPv6 often firewalled or unavailable on mobile networks')),
					row(_('Cost'), _('Free'), _('frp: VPS rental; IPv6: free but constrained'))
				])
			),

			h(_('What you need')),
			E('ol', { 'style': 'padding-left:20px;margin:0 0 12px 0' }, [
				li([_('A Cloudflare account (free registration works).')]),
				li([_('A domain hosted on Cloudflare — the DNS of your domain is managed by Cloudflare (registrar anywhere).')]),
				li([_('A router running the Homelede firmware with the HomeTunnel app installed.')])
			]),

			h(_('How to use')),
			E('ol', { 'style': 'padding-left:20px;margin:0 0 12px 0' }, [
				li([_('Open the'), ' ', E('a', { 'href': L.url('admin', 'services', 'hometunnel', 'wizard') }, _('Access')), ' ', _('page and follow the wizard: authorize with OAuth in the Cloudflare web page (only the necessary permissions are requested — the app never gets full control of your account), pick your domain, and deploy the switch service.')]),
				li([_('Go to'), ' ', E('a', { 'href': L.url('admin', 'services', 'hometunnel', 'ingress') }, _('Ingress Rules')), ' ', _('and add what you want to expose — e.g. subdomain nas pointing at http://192.168.1.10:5000. DNS records are published automatically.')]),
				li([_('Save the ON / OFF bookmarks from the'), ' ', E('a', { 'href': L.url('admin', 'services', 'hometunnel', 'status') }, _('Status')), ' ', _('page to your phone. Open the ON link from any network to start the tunnel (default 45 minutes, auto-renewed while traffic flows), and the OFF link to close it immediately.')]),
				li([_('Visit https://nas.example.com from outside — your NAS is there.')])
			]),

			E('div', {
				'style': 'border:1px solid rgba(52,140,212,.25);border-radius:.5rem;padding:12px 16px;margin-top:6px'
			}, [
				E('div', { 'style': 'font-weight:600;margin-bottom:8px;color:#348cd4' }, _('Security model')),
				p([_('The tunnel is closed by default. It opens only on an ON link (time-limited) and closes automatically when idle or when the hard cap is reached.')]),
				p([_('The switch key never appears in the router config file — it lives only in /etc/hometunnel/ with 600 permissions.')]),
				p([_('Even while open, only the ingress rules you defined are reachable; everything else on the LAN stays invisible.')])
			])
		]);

		var body = E('div', { 'style': 'display:flex;flex-direction:column;min-height:calc(100vh - 200px)' }, [
			E('h2', {}, _('HomeTunnel')),
			E('div', { 'class': 'cbi-section', 'style': 'border-radius:.5rem;flex:1' }, [content])
		]);

		return htui.apply(body);
	}
});
