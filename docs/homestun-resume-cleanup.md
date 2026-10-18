# HomeSTUN cleanup resume — recovered isolated regression

2026-10-12: worktree `feature/homestun`; no commit/merge/push/PR. Production adapter/init/native/package unchanged in this resumed cleanup task.

## Exact final execution

At 10:43:46 CST, `timeout 45 /bin/sh /tmp/homestun-test/source-cleanup-fixture/router-source-cleanup.sh` returned **0**:
- PASS BusyBox expiry, TERM, KILL and STOP: owned source runtime removed; original certificate/key and foreign runtime bytes preserved.
- PASS isolated real procd: registered PID 82350 running, `term_timeout=1`; stopped adapter then deleted unique service; cleanup completed and service readback absent.
- Static native helper built from current source with `gcc -static -Wall -Wextra -Werror`. Dummy nginx/NATMap only write readiness then sleep; they create no sockets or real mappings. Target BusyBox supplies shell/setsid/copy/cleanup utilities. All remote writes stayed inside the fixture or the unique ubus service namespace.
- Full final stdout: [regression](homestun-resume-cleanup-regression.txt); pre-deletion inventory [readback](homestun-resume-cleanup-readback.txt); [final cleanup](homestun-resume-cleanup-final.txt).

## Reproduced harness failure and minimal fix

Original script failed after successfully removing the procd runtime because it compared pretty-printed empty ubus JSON to literal `{}`. First whitespace-class fix also failed: this target's reduced BusyBox `tr` does not implement `[:space:]`. Literal `tr -d ' \\t\\r\\n'` fixes the existing regression; two subsequent complete router runs returned zero. Only `homestun/tests/router-source-cleanup.sh` code changed.

## Important target prerequisite — NOT resolved

The actual router has **no `stat` command**, and its BusyBox lacks the stat applet. Existing adapter/init use `stat`; therefore this does **not** prove unmodified package activation works on this firmware. The isolated chroot used WSL GNU `/usr/bin/stat` plus its glibc dependencies, copied only inside fixture. Package dependency/target utility acceptance is a remaining blocker for parent review; do not hide it under a generic BusyBox PASS or enable the installed service.

Fixture reconstruction also required target musl `libgcc_s.so.1`. `/tmp` is mounted `nodev`, so a real chroot `/dev/null` device failed permission checks; the no-network fixture used a writable regular-file sink instead. Neither installed system libraries nor mounts were changed. This is BusyBox-shell and real procd isolated lifecycle evidence, not a complete OpenWrt userspace/package test.

## Safe leftover inspection and final readback

Initial 10:37:55 inspection plus `ls -la`: `/tmp/homestun-test` empty, unique ubus service absent; no unknown paths deleted. Reconstructed only the known `source-cleanup-fixture` child.

At 10:44:18 CST, verified owned runtime absent, ubus empty JSON, no matching live fixture cmdlines (excluding the inspection shell), recorded procd PID 82350 absent. Removed only the inspected fixture tree, then used `rmdir` on empty parent. `/tmp/homestun-test` now absent. Existing SSH 22 and web 80/443 remain listening; test ports 18443/18444/18081/18082 absent. No real NATMap, package installation, firewall, Cloudflare or business-service changes.

## Continuation gates

Parent-provided latest local regression counts: boundary4/lifecycle1/recipe1/package1/source-cleanup15/Worker6 passed; not rerun or newly claimed here. SDK/ipk, missing target stat prerequisite, actual enabled HomeSTUN init/procd lifecycle, authenticated mapping publication and independent external reachability remain unverified. Detached watcher kill/power loss/blocked filesystem or malicious concurrent root path mutation still have no general crash-recovery/secure-erasure guarantee. Parent independent read-only review remains required.
