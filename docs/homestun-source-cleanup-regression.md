# Targeted TLS-source cleanup regression

Scope: `homestun/files/usr/share/homestun/lease-run.sh`, init command registration, regression tests and documentation only. Native C, UCI configuration, package recipe and Worker unchanged. No commits, deployment, package installation, firewall changes, Cloudflare writes or public listeners.

## TDD evidence

1. Before adapter changes, root WSL `test-source-cleanup.py -v` failed `test_normal_expiry_removes_private_sources`: `generated TLS source directory retained after expiry`. The real native helper returned zero and removed its snapshot, but generated source copies remained.
2. After adapter cleanup, expiry passed. An executable init fixture then failed because its registered command was `/usr/libexec/homestun-lease`, not `/usr/share/homestun/lease-run.sh`. Init was changed to register the already-packaged adapter.
3. Test harness corrections: chroot initially lacked `/dev/null`, cp shared-library dependencies and a fixture readiness marker. These were harness errors, not claimed production regressions.

## Current evidence (supersedes historical 8-test run below)

Final native guarded provisioning supersedes init-created TLS and pre-watcher ownership gaps: init is read-only and registers `--provision`; guardian precedes monitored preparation. [Final evidence](homestun-guarded-provisioning.md): **30 WSL tests passed, no xfail**; genuine no-stat BusyBox target native expiry/TERM/KILL/STOP, preparation render KILL/STOP and real isolated procd STOP→TERM→KILL passed, PID102659. Originals/foreign preserved and owned runtimes absent before manual fixture removal; final service/process/listener readback clean. Native C/init changed in the follow-up implementation; this document’s original scope/counts describe historical adapter work. SDK, target-compiled ABI/seccomp and actual enabled service/public mapping remain unverified.

## Historical final execution

Executed on root WSL using isolated temporary chroots and static native/engine fixtures; no sockets or real NATMap networking:

- `python3 homestun/tests/test-source-cleanup.py -v`: **8 tests passed**, 21.682 seconds.
  - expiry removes private source directory;
  - startup nginx validation failure removes private sources;
  - TERM cancellation forwards to/reaps helper, then removes private sources;
  - competing adapter cannot remove active runtime/snapshot;
  - pre-existing competing snapshot remains untouched;
  - replacement runtime directory remains untouched;
  - replacement source inode and unknown files remain untouched;
  - actual sourced init registers cleanup adapter (procd calls and Lua rendering stubbed).
- `python3 homestun/tests/test-lifecycle.py -v`: **1 passed**, 3.576 seconds.
- `python3 homestun/tests/test-recipe.py -v`: **1 passed**, 0.706 seconds; real macro-harness compile/install, not SDK/ipk.
- Windows `python homestun/tests/test-package.py`: **1 passed**.
- `node --test homestun/tests/worker.test.mjs`: **6 passed**.
- Post-run root WSL readback: `/tmp/homestun-source-*` directories `[]`; processes referencing `homestun-service-Test123` `[]`.

All cleanup/preservation cases assert `/etc/homestun/cert.pem` and `key.pem` retain their original fixture bytes. Adapter cleanup is limited to the original runtime/owner/source device+inode identities; it never recursively removes a runtime and refuses to clean while `runner.lock` exists.

## Remaining limitations

TERM remains an isolated adapter cancellation test rather than the installed enabled HomeSTUN service. Post-watcher adapter SIGKILL/STOP cleanup and target BusyBox/no-stat plus real isolated procd timeout behavior are now verified (see current evidence above); the earlier blanket adapter-SIGKILL limitation is obsolete. For the native registered path, read-only init death/submission rejection creates no generated copies and monitored provisioning fault cases pass; the previous pre-watcher limitation applies only to the historical legacy adapter path. Power loss and blocked filesystem operations remain outside the cleanup guarantee. Root-controlled inode/path replacement is conservatively preserved; sequential shell identity checks are not an atomic defense against malicious concurrent root pathname mutation. No secure-erasure/general crash-recovery claim. Native hard lease deadline remains enforced by the helper, not shell traps. Only isolated target fixture changes were made and removed.
