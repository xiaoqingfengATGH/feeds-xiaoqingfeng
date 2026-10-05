# luci-app-homeacme

HomeLede-maintained fork of LuCI's ACME application, with a read-only certificate
inventory supporting multiple certificate instances for the same domain.
Upstream copyright is retained; license: GPL-3.0-or-later.

## Package identity and compatibility

- Main package: `luci-app-homeacme`, maintained by xiaoqingfeng.
- Translations: `luci-i18n-homeacme-<language>`; their dependency is the new app.
- Main package conflicts with `luci-app-acme`; each translation conflicts with
  its stock `luci-i18n-acme-<language>` counterpart. This is an explicit mutually
  exclusive replacement, not a co-installable second ACME UI. Remove the stock
  UI and its translations before installing this fork; retain the `acme` service
  and its configuration/certificate data. Do not use force-overwrite.
- Existing runtime names are intentionally retained: UCI `acme`, the service
  `acme`, view `acme/acme`, menu/ACL `luci-app-acme.json`, RPC object `luci.acme`,
  `/usr/share/ucode/luci/acme-inventory.uc`, and the `acme` translation domain.
  For Simplified Chinese, the payload is still
  `/usr/lib/lua/luci/i18n/acme.zh-cn.lmo`, compiled from `po/zh_Hans/acme.po`.
- Dependencies: `acme`, `rpcd-mod-ucode`, `ucode-mod-fs`, `ucode-mod-uci`,
  `openssl-util`, and `coreutils-timeout` (plus buildroot's automatic `libc`).

This build tree's `luci.mk` does not consume `LUCI_CONFLICTS`, and a top-level
`CONFLICTS` is reset by `Package/Default`. The Makefile locally extends that
macro for both the app and generated translations, without editing shared
build infrastructure. Translation versions track the app release so an
uncommitted new package does not receive an unusable git-derived version.

## Offline index refresh and package-only build

From the Homelede5 build root:

```sh
./scripts/feeds update -i xiaoqingfeng
./scripts/feeds install -p xiaoqingfeng luci-app-homeacme
make package/feeds/xiaoqingfeng/luci-app-homeacme/compile \
  CONFIG_PACKAGE_luci-app-homeacme=m \
  CONFIG_PACKAGE_luci-i18n-homeacme-zh-cn=m -j1 V=s
```

The command-line selections do not change `.config` or firmware defaults.
The compile target updates normal build/staging outputs; it does not deploy
anything to a router. IPKs are in `bin/packages/<arch>/xiaoqingfeng/`.
Check each IPK's `control.tar.gz` for `Conflicts` and `Depends`, and its
`data.tar.gz` for the preserved runtime paths before distributing it.

## Tests

```sh
node tests/test_view.js htdocs/luci-static/resources/view/acme/acme.js
```

`tests/test_inventory.py` is an opt-in on-device integration test, not a
package build step. It connects to a router and creates isolated fixtures;
do not run it for a package-only build or without explicit router access
approval. Neither tests nor this README are included in the runtime IPK.
