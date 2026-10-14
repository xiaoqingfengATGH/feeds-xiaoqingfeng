# Device-provider interrupted checkpoint — simplification requested

## Outcome / authorization change

User directed stop on complex device adapter and move to Lua controller + standard procd dedicated Nginx + conventional PID lifecycle + least privilege. No further broker/dual-guardian/seccomp/memfd work, deployment, security matrices or wholesale deletion. Features 1–2 are NOT complete: actual target Start fails readiness; Apply/TLS marker never passed. Feature 3 not started.

## Source

Worktree D:/DevPortal/homelede/homepublish-product, branch feature/homepublish-product.
Local candidate commit `6768ad3dcbd4f3f22d9ee8717c84ddf68779d9bf` (not pushed/merged). Preserved prior dirty candidate, fixed actual `-Wall -Wextra -Werror` misleading-indentation failure, committed eight files: Makefile r2, init controller registration, renewable-guard device hooks, new device-provider.c, product-daemon.lua, product-device-cli.lua, product-device-provider.lua and test-device-provider.py. Only pre-existing untracked tests/__pycache__ remains. Temporary local diagnostics were removed using targeted edits; no reset.

## Verified

- Host gcc compiles device-provider.c and HP_DEVICE_PROVIDER renewable-guard.c with -Wall -Wextra -Werror.
- Fixed-device contract PASS; `make -C homepublish/tests product rpc` exit0, `/home/eric/homestun-sdk-check/device-product-rpc.log`. Linker Lua tmpnam warning exists.
- Cached official SDK 24.10.5 x86_64 built actual r2 TARGET_CC package after explicit CONFIG_PACKAGE_homepublish=m; first make exit0 produced no package because selection was unset. Shared build.lock used and actual Linux processes checked. SDK source ext4 archive of commit, not DrvFS hashing.
- First committed package SHA256 f8067b61d94480e51276dc43d04332cd051938c0e2e72bd69e7903d518220027; unpacked Lua/init/config exact archive bytes and native ELF verified. Upgraded actual device r1→r2 with IPKG_NO_SCRIPT=1; boot enable stayed disabled. Real procd controller registered/running PID94822; actual native Lua module loaded.
- Fixture backend initially HTTP403 due restrictive fixture directory; chmod fixture webroot/index fixed to actual marker A. Dedicated rendered nginx -t succeeds using fixture certificate paths; does NOT prove guarded provider works.
- Multiple actual Start attempts returned blocked/provider readiness failed/cleanup confirmed; no verified active_revision, no TLS marker or Apply. Root cause NOT established. 150ms broker timeout and provider initialization are remaining hypotheses, not findings.
- Diagnostic r2 rebuild attempted conventional stderr pipe; first build timed out120s with Linux make subsequently absent; next separate compile succeeded. Diagnostic package SHA256 `8abf8d2d1b522e927a7fbcc409acfc0d8683d672ac5687ffae7ddd56e54d8a95` was reinstalled (same version0.1.0-r2). Its native module SHA256 `8294247856efcbc7bca2bb00578ca7212ad61a9d02225137922823302e1ab5e1`. Start still readiness failed, no useful nginx diagnostic. Installed diagnostic bytes differ from committed candidate; DO NOT claim installed source binding. Local diagnostics removed; do not deploy again.

## Final actual device state / cleanup

Target root@127.0.0.1:222 key D:/DevPortal/CloudHosts/HomePri.key, ProxyCommand/ProxyJump=none, IdentitiesOnly=yes/BatchMode=yes.
- Installed homepublish0.1.0-r2 diagnostic build, luci-app-homepublish0.1.0-r1. Controller stopped, procd service list {}, init disabled/noS95.
- RPC Stop persisted disabled/manual_stop_latch=true, saved_revision1, intent_revision10, attempted/candidate_revision1, no verified active. Init stop uses unavailable system provider and leaves journal phaseblocked/cleanupunknown, despite independently verified absence of owned runtime/listener. Preserve this discrepancy, do not fake journal success.
- Both owned uhttpd fixture PIDs killed. /tmp/homepublish-device/runtime and /tmp/homepublish-device absent. Fixture cert/key and /etc/homepublish/device-test removed. No business certificate/key read. Acceptance evidence retained `/tmp/homepublish-device-acceptance/` including stopped-state, JSON, logs and backups; dir0755 was needed for fixture uhttpd, files root-private except marker index files.
- Full TCP listener listings before/after cmp identical. IPv4/IPv6 route snapshots cmp identical. Firewall SHA256 unchanged `52a2755e9a380e1e6d526204ec443dcdd85639f07d2903f64839d073edd55795`; default via192.168.1.1 br-lan. uhttpd4308/dropbear63780+34089/xray16371 remain; management HTTP200; independent SSH successful.
- r1 files backup `/tmp/homepublish-device-acceptance/r1-backup.tar.gz`; original uploaded r1 package remains prior deployment directory. No rollback performed; leave installed candidate disabled pending parent's new scope.
- No firewall/UPnP/public exposure/proxy/management configuration changes, no push/merge/PR.

## Simplified dependencies / removable mechanisms

Keep business modules canonical.lua/product-provider.lua/product-controller.lua/product-wire/json and durable store initially, direct-renderer/direct-backend/address, scoped RPC/UI. Reuse installed Lua/libuci-lua, ubus/rpcd/procd, nginx-ssl, curl/CA; ACME/DDNS real adapter deferred to feature3. Use private configuration/cert permissions, fixed app-owned paths, dedicated Nginx instance/user, standard procd/PID start-stop and real TLS readiness. Save stays pending; explicit Start/Apply approval, durable Stop latch, temporary original deadline, honest status and bounded recovery remain requirements.

Candidates to remove from the new active device path (NOT deleted this round): root Unix-socket broker/device C Lua module, device guard hooks, reciprocal guardians/capability heartbeat, custom seccomp/socketpair profile, memfd sealed loader/dependency snapshots, their device activation gates. Keep old experimental tests/code as historical until scoped cleanup is approved. No need to require natmap/STUN for normal manual direct Nginx publication; review dependency separately rather than uninstall authorized installed dependency.

Logs `/home/eric/homestun-sdk-check/device-sdk-r2-final.log`, device-sdk-diag.log (timeout), device-sdk-diag-final.log; ext4 archived source `/home/eric/homestun-sdk-check/device-r2-source` currently includes diagnostic source and is NOT exact commit anymore. Recreate archive for any future build; installed diagnostic package differs from restored local source. Next owner should first read this checkpoint and set simplified scope, not resume complex candidate debugging.
