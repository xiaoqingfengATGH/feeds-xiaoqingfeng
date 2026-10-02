# luci-app-ikev2-manager

A LuCI app to manage a **strongSwan IKEv2 / IPsec** road-warrior VPN — add/list/delete
**EAP username-password accounts**, see connected clients, and download ready-to-install
**iOS/macOS `.mobileconfig`** profiles (CA + VPN settings in one tap).

Adds a page under **LuCI → VPN → IKEv2 Users**. It's a management layer on top of a
strongSwan `swanctl` IKEv2 EAP-MSCHAPv2 setup (it manages *users* and *client profiles*,
not the IPsec connection itself — see *Server prerequisites*).

> No secrets are bundled. The server address, CA certificate and account passwords are read
> at runtime from UCI and the swanctl PKI. You set your DDNS / public address after install.

## Features
- **Status** — charon running / listening on 500-4500 / CA present / live connected clients.
- **EAP accounts** — add (one-click random password), list, delete. Regenerates
  `/etc/swanctl/conf.d/eap-users.conf` and applies via `swanctl --load-all`.
- **iOS/macOS profile** — per-user `.mobileconfig` with the CA embedded (auto-trusted) and
  IKEv2 pre-filled. AirDrop to iPhone / double-click on Mac → one-tap install.

## Requirements
- OpenWrt 24.10+ with modern (JS) LuCI.
- A working strongSwan IKEv2 EAP-MSCHAPv2 server (see below).
- `strongswan-swanctl`, `strongswan-mod-eap-mschapv2`, `openssl-util`.

## Server prerequisites (one-time, outside this app)
Needs an IKEv2 connection already defined in swanctl:
1. strongSwan + swanctl + EAP-MSCHAPv2 + OpenSSL plugins.
2. CA + server cert (SAN = your DDNS, EKU serverAuth) under `/etc/swanctl/x509ca`, `x509`, `private`.
3. A connection in `/etc/swanctl/conf.d/` with `remote { auth = eap-mschapv2 }`, a virtual-IP
   `pool` and pushed DNS — see [docs/example-swanctl.conf](docs/example-swanctl.conf).
4. Firewall: allow UDP 500 + 4500 and ESP on wan; forward + masquerade the client pool.

## Install
### Option A — manual (no build)
```sh
scp -O -r root/*   root@ROUTER:/
scp -O -r htdocs/* root@ROUTER:/www/luci-static/
ssh root@ROUTER 'chmod +x /usr/libexec/rpcd/ikev2mgr /etc/uci-defaults/40_luci-app-ikev2-manager; \
                 sh /etc/uci-defaults/40_luci-app-ikev2-manager; \
                 /etc/init.d/rpcd restart; rm -f /tmp/luci-indexcache'
```
Hard-refresh LuCI. The page appears under **VPN → IKEv2 Users**.

### Option B — build an `.ipk`
Drop into an OpenWrt LuCI feed (`feeds/luci/applications/luci-app-ikev2-manager`) and
`make package/luci-app-ikev2-manager/compile V=s`.

## Usage
1. **VPN → IKEv2 Users** → **Client profile settings** → set **Server address** to your DDNS/IP.
2. **Add user** (username + password, or *Random*).
3. **Download .mobileconfig** → AirDrop/open on Apple device → install → connect. Non-Apple:
   use IKEv2/EAP with the same username/password and trust the CA.
4. Lost a device? **Delete** the user.

## Security notes
- EAP-MSCHAPv2 passwords are plaintext in UCI + the swanctl secrets file (root, mode 600) —
  inherent to EAP-MSCHAPv2. `.mobileconfig` files embed the password; treat as secrets.
- One account per device = individual revocation.
- The repo contains **no** keys, certs, DDNS names, passwords or site data.

## License
MIT — see [LICENSE](LICENSE).
