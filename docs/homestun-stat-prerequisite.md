# Target stat prerequisite resolved; guarded provisioning now verified

## Current evidence (supersedes the historical gap below)

Read-only init now registers native `--provision`; no init-created secret runtime exists before ubus submission. Controller/guardian precedes monitored provisioning. Final WSL source suite **30 passed, no expected failures**; genuine target no-stat assertion, native expiry/TERM/KILL/STOP, preparation KILL/STOP during rendering and isolated real procd STOP→TERM→KILL all passed, PID102659. Originals/foreign preserved; owned runtime already absent before fixture deletion. Cleanup readback 11:28:06 CST confirms no fixture/service/process and retained22/80/443, absent test ports. See [guarded final evidence](homestun-guarded-provisioning.md) for full stdout, exact hashes and fixture limits. SDK/target-musl ABI/seccomp and actual enabled HomeSTUN integration remain separate gates.

## Historical stat-only slice (not final source/expected-failure state)

## Changes and TDD
- `homestun-lease --identity PATH` emits device:inode; `--metadata PATH` emits uid:octal-mode:nlink. Root-only lstat accepts regular files/directories, rejects final symlinks/missing/special files with no stdout. Existing native binary supplies this API; Makefile dependencies unchanged.
- init and lease-run no longer invoke stat. Directory permission check ignores directory link count, preserving prior semantics.
- RED: removing stat from the WSL chroot failed expiry and init registration (`stat: not found`). Actual router RED used its BusyBox and libraries, no stat: adapter exit=2, line27 stat missing. Native metadata test RED returned2. GREEN evidence below.
- Additional RED: procd_close_instance fixture failure left generated TLS files. Init now checks the synchronous open/set/close builder chain and removes generated files on failure. This is NOT acknowledgement of subsequent rc.common/procd ubus submission.

## Final verification
- [Local final output](homestun-stat-free-local-final.txt): 18 tests, 17 successful + 1 explicit expected failure. The expected failure proves before-setsid-watcher failure still retains source copies; it is not cleanup success.
- [Other regression output](homestun-stat-free-other.txt): isolated socket boundary4, lifecycle1, recipe1, package1, Worker6 successful. Initial boundary attempt lacked `ip link set lo up`; rerun correctly configured isolated namespace passed. No host-network socket tests.
- [Target output](homestun-stat-free-router.txt): expiry, TERM, adapter KILL, adapter STOP, isolated real procd STOP→TERM→KILL successful; originals and foreign runtime preserved. Final rerun added mandatory no-stat check and native metadata check, both passed; real procd PID85670, run exit0. Earlier saved target transcript is PID85225 and also exit0.
- Router chroot contains copied target `/bin/busybox`, `/lib/libc.so`, `/lib/libgcc_s.so.1`, musl loader symlink, BusyBox applet links (sh/mkdir/rm/rmdir/cp/mktemp/setsid/sleep), regular `/dev/null` sink due to `/tmp` nodev. Native helper and non-networking engine fixtures are WSL gcc-static test binaries; NOT SDK/target-libc acceptance. No GNU stat or GNU utility/library injected. Fixture engines mark ready and sleep; they do not open sockets or perform NAT discovery.
- [Final target cleanup readback](homestun-stat-free-cleanup-final.txt): service absent, fixture runtime absent, no matching process output, `/tmp/homestun-test` removed, existing22/80/443 retained, test18443/18444/18081/18082 absent. SSH command returned0, 2026-10-12 10:57:42 CST.

## Remaining startup blocker and recommended separate slice
Init creates the private runtime and copies TLS before registering the adapter. Death during cp/render, later procd ubus submission failure, or adapter death/failure before detached watcher ownership can retain generated copies. Synchronous JSON-builder error cleanup is only a narrow repair, not crash-safe provisioning. The expected-failure regression deterministically substitutes failing setsid and asserts the desired no-retention property; it fails as expected. Do not present 18/18 cleanup PASS or claim all startup failures clean.

Recommended native lifecycle redesign (separate reviewed TDD task):
1. Init performs read-only plan/trust validation and registers a provisioning command, never copies secrets or creates secret runtime directories.
2. Start an independent native guardian before any mkdir/copy/render. Publish ownership under an inode-scoped exclusion before monitored preparation can create files, analogous to existing snapshot preparation.
3. Put runtime creation, descriptor-relative validated copying and Lua render into the monitored phase. Keep handles/identity and explicitly transfer ownership to native lease without a second unmonitored source-owner window.
4. Guardian must observe provisioner death/STOP with a bounded deadline and remove only owned entries; preserve originals/replacements/foreign instances. Avoid shell EXIT traps or blanket stale-directory sweeps as SIGKILL repair.
5. RED matrix: init killed before/after plan; rejected procd submission means zero generated secrets; command exec/setsid failure; preparation mkdir/copy/render KILL/STOP; death before ownership handoff; concurrent foreign runtime; final real BusyBox/procd runs without injected stat. Repeat existing socket/security tests after native changes.

SDK/.ipk, actual enabled HomeSTUN init/procd integration, target compiled ABI/seccomp and public reachability remain independent gates. No install, public NAT, firewall/Cloudflare changes, commit/merge/push/PR.
