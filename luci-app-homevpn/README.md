# luci-app-homevpn

Turnkey **strongSwan IKEv2 VPN server** for HomeLede: flash → set server
address → add users → clients connect. Based on
[luci-app-ikev2-manager](https://github.com/naughtyGitCat/luci-app-ikev2-manager)
(C) naughtyGitCat, MIT — extended with full server provisioning.

## Master switch (exclusive strongSwan service)

The independent service button calls `homevpn.set_enabled` with a strict JSON
boolean; it does not submit the settings draft or validate its CIDR/ACME fields.
`homevpn.config.enabled` defaults to enabled when absent (upgrade compatibility).
Disabling persists `0`, disables swanctl boot, and stops the swanctl procd instance
including respawn and charon/SAs. HomeVPN boot, reload, provisioning, ACME and
settings regeneration remain no-ops while off. The swanctl init start/reload and
interface-trigger entries are guarded on takeover; replacing that vendor init
script during a strongSwan package upgrade requires reinstalling the guard.
Enabling restores HomeVPN/swanctl boot links and verifies the HomeVPN connection,
not just a process PID. Failed startup rolls back to disabled.

HomeVPN requires exclusive strongSwan ownership. Foreign conf.d files, root
includes, UCI remotes or live connections cause a refusal before service changes.
The guard is installed atomically only for the recognized vendor init layout.
The service lock rejects concurrent actions as busy. Disabled saves preserve
settings for the next enable and cannot start charon. Disabling removes generated
HomeVPN firewall rules and subnet route, but retains DHCP reservations to avoid
restarting dnsmasq and interrupting LAN users. Certificates and EAP accounts are
not deleted. Explicit CLI `stop` stops the owned service; use `set-enabled 0` for
the persistent master-switch operation.

Configuration writes, firewall/nft application, DHCP reloads and route changes
must all succeed before an apply records `result=ok`. Boot, provisioning and
reload propagate failures; enabling uses the existing disabled-state rollback.
These checks do not make a running-service reload an atomic transaction.

The service lock fails closed after an untrappable termination such as SIGKILL.
Manual stale-lock recovery requires confirming that **both the recorded owner
and every remaining transaction child process have exited**. An exited owner
alone is not sufficient: children may still be applying configuration. Do not
remove the lock or retry writes until the entire transaction is quiescent.

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
   Android: download **Android .sswan** and import it in the strongSwan App.
   The file embeds the selected CA for trust; enter the EAP password when the
   App imports or connects. Android system VPN settings cannot import `.sswan`;
   use the App's file picker if the download does not open it automatically.
   Alternatively download the **CA certificate** and configure the native
   Android 11+ client (IKEv2, MSCHAPv2 = username/password).
4. Watch **Server status** readiness row: SAN match + connection loaded.

## Upstream NAT

The server must be reachable on UDP 500/4500 (+ESP) from the internet —
forward those from the upstream router, or put it directly on the WAN.

## Security notes

- EAP-MSCHAPv2 passwords are plaintext in UCI + the swanctl secrets file
  (root, mode 600) — inherent to EAP-MSCHAPv2. The `.mobileconfig` still embeds
  its AuthPassword; the `.sswan` profile does **not** contain the password.
  Treat downloaded profiles as sensitive: they include the account/domain and
  the CA used to establish server trust. Base64 is encoding, not encryption.
  One account per device = revocation.
- The repo contains no keys, certs, domains or passwords.

### `.sswan` lifecycle and trust

The self-signed CA is embedded in the strongSwan App profile; Android does not
need the CA installed as a system user CA. Obtain the file only over a trusted
channel and accept the VPN permission in the App, then verify access to the
expected internal network. Changing the server name, EAP identity, or CA
requires a new export. Each download has a fresh UUID, so repeated imports can
create multiple entries; delete the old entry when replacing it. A normal
server-certificate renewal under the same CA does not require re-importing the
profile, provided the identity and validity remain correct. This does not alter
the `.mobileconfig` format or its separate plaintext-password warning.

## License

MIT — see [LICENSE](LICENSE). Includes code from luci-app-ikev2-manager
(C) naughtyGitCat, MIT.
