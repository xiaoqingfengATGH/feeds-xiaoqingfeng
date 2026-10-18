# HomePublish real SDK/IPK checkpoint

Source commits: ec46452 lifecycle and 6798609 rpcd executable fix (local only).
SDK: `/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64`.
Official source: https://downloads.openwrt.org/releases/24.10.5/targets/x86/64/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.zst (cached; no new SDK download).
Feeds: cached OpenWrt 24.10.5, packages 953b6d47b4e9f0ad3c39547c6d3f9a828f10e206, LuCI d88390be4ec9722cb427fee03368fc8c8582627d.
Build source is fixed Git archive in ext4 `/home/eric/homestun-sdk-check/package-product-source`, not Windows ignored node_modules.

## Artifacts

Absolute directory: `/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64/bin/packages/x86_64/homestunlocal/`

- `homepublish_0.1.0-r1_x86_64.ipk`: SHA256 `d24fe623b166be515d89a841d68fb873a2b9110ab8c6e2ec9bfc05cb8334c412`
- `luci-app-homepublish_0.1.0-r1_all.ipk`: SHA256 `f0176aee51a1df7d7ac19f9ed7c4ffbdfb68d10172ec8437ac6029669b5a6462`

Control: homepublish depends libc/libgcc1/liblua5.1.5/lua/libuci-lua/nginx-ssl/natmap/curl/ca-bundle; LuCI depends libc/homepublish/luci-base. Native compiled by SDK TARGET_CC, no host binary substitution. Legacy helper dependencies remain because legacy helpers still ship; init no longer invokes them.

## Real execution evidence

All logs under `/home/eric/homestun-sdk-check/`:
- `package-lifecycle-red.log`: missing lifecycle entry assertion before implementation (Python nonzero; outer Windows wrapper incorrectly returned zero, not used as success proof).
- `package-lifecycle-green.log`: ordinary uid1000 `make -C homepublish/tests product rpc` passes, including new real native-journal lifecycle status/start/Stop latch and existing RPC Save/Stop.
- `package-sdk-build.log`: feeds update/install discovery succeeds, but unset package selection produced no IPKs despite make exit0. Not counted as build acceptance.
- `package-sdk-selected.log`: explicit CONFIG_PACKAGE_homepublish=m CONFIG_PACKAGE_luci-app-homepublish=m real compile/package succeeds.
- `package-ipk-acceptance.log`: real IPK unpack RED: plugin mode 0644, not executable. Fixed git mode 100755, not fake recipe grep.
- `package-sdk-final.log`: final committed-source LuCI clean/compile succeeds.
- `package-ipk-final.log`: both real IPKs unpacked, all product Lua bytes match source, native ELF, modes/defaults/deps/menu/ACL/no test adapter PASS. Core 22 files; LuCI 7 files.
- `package-final-product-rpc.log`: final ordinary-user make product rpc succeeds.

Reproduce actual package acceptance:
`python3 homepublish/tests/test-ipk.py <absolute SDK> /home/eric/homestun-sdk-check/package-product-source`
SDK builds serialized with existing build.lock and bounded timeout. First distro name Ubuntu was absent; actual distro Ubuntu-24.04 used. No installation into host or router.

## Lifecycle functional ledger / exact limits

init uses fixed product-lifecycle CLI, not legacy NATMap/UCI plan. Disabled start is no-op, no procd instance or respawn. Stop invokes real controller, whose durable revocation precedes fixed production provider stop. The fixed system provider cannot activate; it only confirms cleanup when no active/attempted history exists, otherwise unknown/blocked. Status reads journal. This is a useful installed Save/Stop/status bridge, NOT a running production controller daemon. A production provider, daemon registration and target BusyBox/procd service behavior remain missing/unverified. Do not claim procd runtime acceptance from this change.

Existing UI/browser and internal Nginx multi-service Apply/recovery evidence remains valid at its local layer; it does not close production provider/fw4/UPnP/DNS/ACME/Passwall2 or public reachability. Matching SDK package gate now passed for x86_64 only. No target installation, package-manager dependency resolution, procd ubus registration or target runtime gate claimed. SSH 127.0.0.1:222 not retried; wait for restoration and separately authorized deployment. No firewall/mapping/public operations or new security-review matrix.
