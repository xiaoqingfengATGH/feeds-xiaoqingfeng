# luci-app-homevpn

Turnkey **strongSwan IKEv2 VPN server** for HomeLede: flash → set server
address → add users → clients connect. Based on
[luci-app-ikev2-manager](https://github.com/naughtyGitCat/luci-app-ikev2-manager)
(C) naughtyGitCat, MIT — extended with full server provisioning.

## What it does out of the box

- **First-boot provisioning** (`/etc/init.d/homevpn`):
  - self-signed CA (RSA 3072, 10y) + server certificate (RSA 2048, 825d,
    SAN = server address, EKU serverAuth)
  - swanctl connection `homevpn-eap`: IKEv2 + EAP-MSCHAPv2, MOBIKE,
    fragmentation, split tunnel (`local_ts` = LAN subnet, re-rendered on
    network change via procd reload trigger)
  - **DHCP pool addressing**: VPN clients get real LAN leases from dnsmasq
    (dhcp plugin), and the farp plugin answers ARP for them — LAN peers can
    initiate toward VPN clients (Samba/mDNS/peer-to-peer both ways)
  - INPUT-path firewall rules for UDP 500/4500 (NAT-T) + ESP
- **EAP user management** — add/list/delete users; secrets regenerated and
  applied via `swanctl --load-all` (errors surfaced, not silenced)
- **Client profiles** — per-user iOS/macOS `.mobileconfig` (CA embedded),
  Android strongSwan-app `.sswan` (CA embedded), and a plain CA download for
  Android 11+ native / manual clients
- **Three certificate modes**:
  - `selfsigned` (default) — zero external dependencies
  - `import` — place your own `homevpn-server.crt/.key` + CA under
    `/etc/swanctl/{x509,x509ca,private}/`
  - `acme` — sync a certificate issued by the luci-app-acme Let's Encrypt app
    (DNS-01; needs a controlled domain). SAN must equal the server address.
    Selection uses domain + `homevpn.config.acme_key_type` (`rsa` by default,
    or `ecc` in LuCI). RSA searches `/etc/acme/<dom>/`, then `<dom>_rsa/`;
    ECC searches `/etc/acme/<dom>_ecc/`. The acme-common stable links under
    `/etc/ssl/acme/` are fallback only. Every candidate must have the requested
    actual key algorithm and a matching certificate/private-key pair; mtime
    never changes the resolver's choice, and a missing requested type is refused.
    LuCI queries the entered domain through read-only `discover_acme`: no usable
    pair shows “not found”, one available type is displayed and selected without
    a dropdown, and two types allow selection (retain a valid choice, else RSA).
    Debounced queries ignore stale replies; errors are distinct from not-found.
    Both settings-save entrances require a current successful discovery result
    in ACME mode; the backend rechecks the pair and exact server SAN before writing.
    Regression tests: `node tests/acme-discovery-ui-test.cjs htdocs/luci-static/resources/view/homevpn/overview.js`;
    on OpenWrt, `sh tests/acme-discovery-test.sh /` and
    `sh tests/acme-discovery-ubus-test.sh` (temporary read-only test object,
    isolated `/tmp` certificates; reloads rpcd, never charon).
    Renewals replace the complete leaf even when they reuse the same key.
    Issuance/renewal hotplug (`/etc/hotplug.d/acme/`) re-syncs and hot-reloads
    charon credentials — zero-touch renewal, connected clients survive.

## Requirements

OpenWrt 24.10+ with modern LuCI. Package dependencies (auto-installed):
strongswan-swanctl, mod-eap-mschapv2, mod-gcm, mod-openssl, mod-curve25519,
mod-pkcs8, mod-dhcp, mod-farp, openssl-util. **No** `pools {}` masquerade
needed — DHCP pool clients are LAN members.

## Usage

1. **VPN → HomeVPN → Server settings** — set **Server address** (DDNS name or
   public IP; SAN is issued for it), pick certificate mode, save.
2. **Add user** (username + password, or *Random*).
3. iOS/macOS: download **iOS/macOS profile**, AirDrop/open → install → connect.
   Android: download **Android .sswan** and import in the strongSwan app, or
   download the **CA certificate** and set up the native Android 11+ client
   (IKEv2, MSCHAPv2 = username/password).
4. Watch **Server status** readiness row: SAN match + connection loaded.

## Upstream NAT

The server must be reachable on UDP 500/4500 (+ESP) from the internet —
forward those from the upstream router, or put it directly on the WAN.

## Security notes

- EAP-MSCHAPv2 passwords are plaintext in UCI + the swanctl secrets file
  (root, mode 600) — inherent to EAP-MSCHAPv2. `.mobileconfig`/`.sswan`
  embed passwords; treat as secrets. One account per device = revocation.
- The repo contains no keys, certs, domains or passwords.

## License

MIT — see [LICENSE](LICENSE). Includes code from luci-app-ikev2-manager
(C) naughtyGitCat, MIT.
