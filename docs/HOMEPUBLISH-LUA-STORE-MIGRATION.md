# HomePublish Lua store migration — preparation checkpoint

## Scope

Implementation authorized; no commit/push/merge or IPK installation. Live journal and retained svc_1 must survive. Production store has NOT been switched: provider still loads homepublish_store.so.

## Target baseline

Authorized target root@192.168.1.2:22, OpenWrt/HomeLede 24.10.5 x86_64. Server-private backup `/root/homepublish-lua-store/baseline.lBkPbJ` contains state, native store and matching deployed provider. Backup hashes read back. No business private key exported.

State SHA256 before/after probes: `6995a844e18ac2c9182b3e4f8035138ebe561aee168530d43c550d5ee14be7d1`. saved_revision=3, active_revision=3, intent_revision=10, disabled/manual_stop_latch=true/stopped/cleanup=confirmed/active_verified=false. Idle controller running; publication runtime absent. migration-v1 absent.

## Real-device primitives

`homepublish/tests/device-lua-store-capabilities.lua` uploaded to `/root/homepublish-lua-store/` and executed with private root `/root/homepublish-lua-store/capabilities-formal`. Exit 0:

- CHILD_BUSY_GREEN: second real Lua process denied while parent owns tlock (errno 11).
- CHILD_EXIT_LOCK_HELD / EXIT_RELEASE_GREEN: process exit releases lock.
- RENAME_PERMISSIONS_GREEN: same-directory rename replaces complete bytes; file 0600.
- LUA_STORE_CAPABILITIES_GREEN.

Discovered API detail: nixio mkdir/open permissions take octal strings (`700`, `600`), not decimal numeric permission bits. Initial exploratory probe failed on numeric mkdir mode; corrected formal probe passed. Concurrent-reader rename stress, complete failure-shape coverage and store contract RED remain pending; this is not Task2/whole-migration completion.

## Build environment

Existing VM build tree `/home/homelede/sources/xiaoqingfeng/Homelede5` on 192.168.1.250 is usable. Root and all 11 git feeds fetched; all were clean and only ff-only updates were applied to their existing tracking branches. Main k5 now e80ee9392; xiaoqingfeng feed master now 972035c. Feature branch in Windows remains separate, never merged into feed master.

Main/feed updates do not modify target runtime. `.config` hash before build: f11f8a58adacd73e99da6266780912a4795b391eefe1e864c33d3563be40c3e6.

Narrow build `make -j1 package/feeds/luci/luci-lib-nixio/compile V=s` under an exclusive lock exited 0, using GCC13.3.0/musl. IPK generated at `bin/packages/x86_64/luci/luci-lib-nixio_26.084.15210~49ef9da_x86_64.ipk`. Not installed. Build warns configuration is out of sync after source updates; no defconfig or full firmware build was run. This system nixio component build is not a HomePublish Lua replacement package acceptance.

## Isolated implementation checkpoint (production NOT switched)

Created `product-store-core.lua`, fixed-root `product-store.lua`, `device-lua-store.lua`, and configurable SSH-only `run-device-lua-store.py`. Native module and live journal were not changed. All execution used real target Lua/nixio under `/root/homepublish-lua-store/test-*`; no local Lua simulation.

Parent independent verification: `parent-final-isolated-v2` and `parent-recheck` ran contract, two-process contention, injected faults, cleanup, resources, migration, unsafe paths and validation together; both exit 0. Two earlier combined runs exposed fixture cross-case contamination (backup directory and state left by preceding cases), now fixed in test cleanup; those failed logs remain recorded. Local provider now loads the fixed Lua wrapper and local Makefile no longer compiles/installs the native store. These changes have NOT been deployed to production; C source is retained until integration acceptance. Live journal was re-read unchanged, saved/active=3, intent=10, disabled/manual stop; publication runtime absent.

Integration review found an error-contract blocker: Lua assertion errors included source locations and did not match CLI's exact native-store vocabulary. The core now returns frozen public errors. Parent independently executed `parent-classification` and `parent-integrated-final` on the real target: corrupted journal reaches the actual CLI and returns STATE_UNKNOWN/state/retryable=true; combined contract/fault/resource/migration/safety/validation exits 0. Live production remains native. Existing P5 production tracer scopes only package.cpath, which no longer isolates the changed provider; it must be migrated before execution, otherwise it could write live state.

Matrix fixture migration is now staged locally: fixed test-only Lua dependency scope, no RPC-selected root, explicit refusal of an installed native provider. Shared Python helper uses repository-relative paths and direct SSH 192.168.1.2:22 (environment overrides for host/port/key). Matrix runner checks the fixture before entering lifecycle try/finally. Real target negative preflight was executed and correctly refused the still-native live provider before creating authentication fixtures or dispatching lifecycle operations. Live SHA remained unchanged; no runtime or matrix-auth directory exists. This refusal is safety verification, NOT a passing seven-case traffic matrix.

Evidence: `docs/evidence/lua-store/*.log` and corresponding `.json` record exact remote commands, exit codes and uploaded source SHA256. RED/GREEN pairs: 01/04 contract (missing implementation RED), 05/06 validation, 07/08 unsafe paths, 09/10 migration, 11/12 candidate/resource safety, 13/14 failed-backup candidate cleanup. Initial implementation attempts 02/03 failed because target nixio has no geteuid; root-owned application files are now explicitly required. Final source regressions: 15-final-resources-safety-validation, 17-final-migration, 18-final-cleanup, all exit 0. 16-final-migration-cleanup is a failed combined-case attempt: cleanup deliberately leaves a backup directory, so migration must run separately; it is retained, not counted as passing.

Verified: false response preserved; absent/old bytes; read-only mtime; invalid type/empty/262145 rejection and 262144 acceptance; callback errors preserve old state; state/lock/candidate symlink rejection; nonregular/empty/oversized old state rejection; original-byte migration backup, exact reuse and conflicting-backup rejection; backup permissions; failed-backup candidate cleanup; two-process lock contention; repeated callback errors without fd growth.

Re-run from repository (choose a fresh label to retain earlier logs; test root UUID is automatic):

```sh
python homepublish/tests/run-device-lua-store.py --host 192.168.1.2 --port 22 --key D:/DevPortal/CloudHosts/HomePri.key --case resources-safety-validation --label rerun-main --evidence docs/evidence/lua-store
python homepublish/tests/run-device-lua-store.py --host 192.168.1.2 --port 22 --key D:/DevPortal/CloudHosts/HomePri.key --case migration --label rerun-migration --evidence docs/evidence/lua-store
python homepublish/tests/run-device-lua-store.py --host 192.168.1.2 --port 22 --key D:/DevPortal/CloudHosts/HomePri.key --case cleanup --label rerun-cleanup --evidence docs/evidence/lua-store
```

Parent staged-provider integration also passed on real target Lua (`parent-provider-integration.log`): Save increments revision without enabling publication, stale revision rejects without changing bytes, controller_transaction preserves saved configuration, and native store was not loaded. This is an isolated dependency-scoped integration check, not a live lifecycle acceptance.

Remaining before production switch: fault-injected write/sync/close/rename and read failures; concurrent-reader atomicity; broader ancestor-path review; provider integration and lifecycle tests. Current implementation is an isolated checkpoint, NOT complete migration acceptance. No strong power-loss durability claim. Existing factory follows lstat/open basic checks in a root-private directory, not native openat/inode identity parity.

