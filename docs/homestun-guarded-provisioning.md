# Guarded provisioning: final scoped regression evidence

Branch `feature/homestun`; isolated validation, not release/installation approval.

## Outcome

The old init-copy → ubus submission → detached-watcher ownership gap is superseded by read-only init registration of `/usr/libexec/homestun-lease --provision`. Native controller/guardian precedes monitored mkdir/copy/render; inode-scoped cleanup owns generated entries. This proves the cases below, not general crash recovery or secure erasure.

- [Final root WSL regression](homestun-guarded-local-final.txt): **30 passed**, 104.378s, no expected failures. Includes init death/submission rejection, native registration, concurrent provisioning, renderer exec failure, controller/guardian/preparation KILL/STOP during render and replacement/foreign preservation. This subtask independently reran final source cleanup; parent separately reported socket4/lifecycle1/recipe1/package1/Worker6 passing. Old 26-test guarded-local and 18-test stat-era expected failure are historical.
- [Final genuine router run](homestun-guarded-router-final.txt): 2026-10-12 11:26:34–11:27:14 CST, Homelede x86_64 kernel6.18.55; run/readback exit0. No-stat assertion and seven lifecycle cases passed: native provision expiry/TERM/KILL/STOP, preparation KILL/STOP during render, real unique-service procd STOP→TERM→KILL, PID **102659**, service-list readback absent.
- Original fixture cert/key bytes and SHA-256 identical before/after; foreign runtime key retained. Owned source/snapshot directories absent **before** explicit fixture removal.
- [Final cleanup readback](homestun-guarded-cleanup-final.txt), 11:28:06 CST: ubus service absent, `/tmp/homestun-test` absent, no fixture process root/exe/cwd; parsed listeners22/80/443 retained,18443/18444/18081/18082 absent. Full ps/listeners saved; SSH succeeded.
- [Exact hashes](homestun-guarded-final-hashes.json): production C/init/adapter and final script/suite, transferred native/engine/renderer fixtures. Router-side hashes match local payloads; final source hashes checked unchanged after target and WSL runs.

## Scope and harness corrections

Only `/tmp/homestun-test/guarded` and service `homestun-guarded-fixture` created and removed. Chroot shell/utilities copied from this router's BusyBox/libc/libgcc, no GNU stat/utilities/libraries. Regular `/dev/null` sink respects `/tmp` nodev. Native helper and engine fixtures are **WSL gcc-static x86_64**, not SDK/target-musl builds. Lua render is a BusyBox-shell stub; nginx/NATMap stubs mark ready and sleep, never open sockets/discover NAT/contact example.com. Real procd/ubus lifecycle is tested, **not installed enabled HomeSTUN init integration**.

[Attempt1](homestun-guarded-router-attempt1.txt) and [attempt3](homestun-guarded-router-attempt3.txt) failed on unavailable `/proc/PID/task/PID/children`; script now uses standard status PPid. [Attempt2](homestun-guarded-router-attempt2.txt) exposed BusyBox rejecting fractional sleep; bounded date polling avoids the two-second preparation timing race. These nonzero harness attempts are not acceptance evidence. Early readbacks preceded lease expiry; independent final readback verifies no survivors. No production C/init/adapter changes by this validation subtask.

## Independent gates

SDK/.ipk, target-toolchain ABI/seccomp, actual enabled HomeSTUN init/procd with real Lua/nginx/NATMap, mapping publication and external inbound TCP remain unverified. Conservative replacement preservation, blocked filesystem/D-state, power loss and secure erasure are outside this proof. No install, management changes, NAT/firewall/Cloudflare writes, public listeners, commit/merge/push/PR.
