# D2c2 startup provisioning barrier / local safety checkpoint

Baseline `7838db93bafda278d388593936ff1d9b5b4a6273`; implementation commit `9f4f18a` followed by listener assertion/checkpoint commit. Exclusive feature/homepublish-product, local non-root WSL loopback only; no production/install/firewall/UPnP/public probes/push/merge/PR.

## Independent finding and test-first RED

Independent review injected EMFILE at guardian watchdog pidfd acquisition **after confirming a synthetic secret write**: start_rc=-1, runtime key present, size21. This models a specific syscall error; it is NOT observed natural descriptor/resource exhaustion. Old watchdog allowed the callback immediately after provider isolation and before guardian acquired its watchdog pidfd. Guardian startup failure killed/reaped without owned cleanup; outer startup error also lacked cleanup.

New official `HP_START_RED=1 HP_START_EVIDENCE=/home/eric/homestun-sdk-check/d2c2-red.json python3 homepublish/tests/test-startup-owned.py` failed exit1 on unchanged baseline: `case=wfd start_rc=-1 written=1 runtime_present=1 children=0`, assertion !residual. Metadata included key.pem size21, no secret bytes. Only this regression has independently observed pre-fix RED; supplemental cases are not represented as separate TDD RED proofs.

## Fix and responsibility

Guardian acquires watchdog pidfd before granting watchdog startup. Watchdog acquires provider pidfd before granting provider isolation. Isolated provider reports READY but blocks on a separate server-owned provisioning message. Guardian independently anchors provider pidfd, reports provider identity to parent; parent must anchor provider pidfd and ACK before guardian can grant callback execution. Required role FD sanitization, worker boundary and reciprocal cleanup ownership precede provisioning. No client flag or CLI fault selector exists. Weak native fault hook exists only in HP_GUARD_TEST builds.

Startup/runtime guardian and watchdog failures use kill owned group/leader -> retained pidfd bounded exit observation -> native inode cleanup -> kill reciprocal peer -> bounded reap. Required provider pidfds remain open through cleanup, avoiding an EMFILE reopen after secrets exist. Cleanup-before-peer-kill race fix is preserved. Before parent ACK, no secret can be written: parent can remove empty pinned anchors on startup failure. After ACK, parent observes its retained provider pidfd before cleanup and does not numerically signal indirect descendant identities that another supervisor could have reaped. Native peers own termination/reaping; parent only kills its direct unreaped guardian on bounded timeout. Cleanup remains identity-bound and ENOENT-idempotent; foreign replacement/hardlink/symlink/readonly and unknown temp residuals remain preserved.

## Reproducible verification

WSL cwd `/mnt/d/DevPortal/homelede/homepublish-product`, `TMPDIR=/home/eric/homestun-sdk-check`:

```
HP_START_EVIDENCE=$TMPDIR/d2c2-startup-1.json HP_D2B2_EVIDENCE=$TMPDIR/d2c2-committed-1 make -C homepublish/tests owned-runtime guardian direct product startup-owned guardian-nginx
HP_START_EVIDENCE=$TMPDIR/d2c2-startup-2.json HP_D2B2_EVIDENCE=$TMPDIR/d2c2-committed-2 make -C homepublish/tests startup-owned guardian-nginx
HP_START_EVIDENCE=$TMPDIR/d2c2-startup-3.json HP_D2B2_EVIDENCE=$TMPDIR/d2c2-committed-3 make -C homepublish/tests startup-owned guardian-nginx
```

Committed-source first pass all three exit0: each 12 real Nginx records, eight cleanup snapshots, eight native runtime absences, zero runtime-present snapshots, remaining_owned=[], channel_EPERM0/internal_errors0. 24 new startup cases each round: all six required pidfd acquisition failures (EMFILE), short READY packet, isolation/READY missing/error, deterministic after-write failure with a real loopback listener, and single guardian/watchdog/provider startup STOP/KILL before and after provisioning grant. After-write synchronizes on completed write/listen rather than guessing a sleep; STOP/KILL stage hooks are exact points, post-grant callback scheduling remains nondeterministic and is recorded honestly. Final completion report gives exact final hash and final committed-source rerun statuses. Logs `d2c2-committed-{1,2,3}.log`, JSON/snapshots under matching evidence dirs. Startup metadata is recorded before TemporaryDirectory fallback deletion; real Nginx snapshots precede harness fallback. Foreign inode/source TLS unchanged, stream EOF/listener refusal/owned PIDs absent in Nginx lifecycle faults. Native ownership 14 cases +100 Stop stress unchanged; guardian 19 tree +10 startup +18 lifecycle cases retained.

Initial full run exposed stop1 elapsed2490ms against unchanged2200ms bound; parent peer wait reduced to existing HP_WATCHDOG_MS, no assertion relaxation. Additional provider pidfds changed exact supervisor FD counts to4/3; foreign inode checks remain unchanged, provider count2. Recipe cached Lua upstream tmpnam linker warning persists; product C builds -Werror succeed.

## Remaining gates / no activation

Start/Apply unsupported, activation_ready=false and production helper exit78 remain. Fixed production executable/loader/library authority, source snapshot authority, SAN/chain/key/expiry validation, scope/approval generation health controller, typed durable residual ERROR protocol, crash manifest/recovery and target SDK/aarch64/BusyBox/procd/fw4 acceptance are not implemented. This local startup regression is not product completion. hp_owned_prepare partial creation failure still needs explicit controller residual accounting. Not every syscall/allocation/FD-clean failure has a dedicated new injected test. New startup listener is a native synthetic provider, not a Nginx-startup provisioning interruption test; real Nginx matrix exercises established lifecycle faults. Simultaneous stopped enforcement processes, privileged/sameUID adversarial mutation and D-state are excluded. Independent review required before further integration.
