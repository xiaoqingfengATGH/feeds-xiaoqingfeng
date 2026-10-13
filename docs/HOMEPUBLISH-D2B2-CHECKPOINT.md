# D2b2 checkpoint — guarded Nginx integration is BLOCKED / genuine RED

Baseline: `408d963896a33aac076b48cbe4c31896586df05d`, branch `feature/homepublish-product`.
Test-first intermediate local commit: `ba57e816c16efd853de64f0b572e655717246216`.
Only local non-root WSL loopback/source/local commits; no production, package/network installation, firewall, UPnP, push, merge or PR. Old fixed-TTL experimental implementation unchanged.

## Outcome / exact completion boundary

**Compatibility has NOT been fixed.** Production `renewable-guard.c` is unchanged. Its seccomp policy is a syscall **denylist with default ALLOW**, not a syscall allowlist. Global `recvmsg`/`recvmmsg` import prohibition is retained. No exception, activation, arbitrary executable interface, namespace privilege grant or security closure is claimed.

New `homepublish/tests/guardian-nginx-fixture.c` and `test-guardian-nginx.py` plus `make guardian-nginx` put the independent review's uncovered behavior into the project as a real, non-xfail RED gate. Cached musl loader/Nginx/library paths and per-test config prefix are compiled into the host fixture; no executable/path argv interface. This is still **test-only fixed exec**, not a production-authority provider or a verified immutable executable/certificate provider.

Completed observations in eight actual guarded `daemon off; master_process on; worker_processes 2` cases:

- Renderer's literal frozen IPv4 backend with generated fixture CA/SAN certificates; actual TLS requests through IPv4 **and** IPv6 loopback ingress, inside the guard, not reuse of standalone direct-suite results.
- Worker SIGKILL yields a replacement worker; continuous renewal runs across multiple 600ms windows without changing the master PID. New post-rebuild live stream is observed during renewal.
- Temporary 1200ms cap closes the live stream near its original fixed deadline despite renewal; controller/guardian/watchdog each single KILL and STOP closes live stream and both-family listeners.
- Backend still emits ticks through a separate connection after guard closure, ruling out backend termination as the cause. Expected deliberately injected worker signal-9 alert is excluded from internal-error acceptance; real channel alerts are never excluded.
- All tracked owned PIDs and both-family listeners checked absent **before** fallback kill/removal. Actual files are listed before harness cleanup: TLS key/cert, nginx.pid/config/temp directories remain. **Native renewable guard does not yet own/clean these files.** Harness removes the isolated fixture afterward; do not call this guardian TLS-snapshot cleanup acceptance.
- Existing guardian regression continues to check foreign connected/listening/file/control descriptors across three roles by inode. New real external pathname UNIX sender queues `SCM_RIGHTS` carrying a real sentinel-file FD; guarded provider `recvmsg` returns `EPERM`, and foreign content is preserved. This is proof of the existing global prohibition, **not** proof of any hypothetical relaxed Nginx profile.

Acceptance remains RED: error logs contain actual `recvmsg() failed (1: Operation not permitted)`. Normal internal `NGX_CMD_OPEN_CHANNEL` FD receipt/notify was **not** successfully verified. HTTP/TLS and worker rebuilding can appear functional despite this failure; neither constitutes a compatible channel gate.

## Cached source analysis / why static FD numbers are unsafe

Read the existing SDK `dl/nginx-1.26.1.tar.gz`; extracted only three source files into profile scratch `d2b2-source-analysis`, without changing cached SDK/source:

- `src/os/unix/ngx_process.c`, `ngx_spawn_process`: creates nonblocking AF_UNIX socketpair dynamically **before each worker fork**, sets FIOASYNC/F_SETOWN/CLOEXEC, selects channel[1], then forks. This occurs after loader exec/config/listener initialization, not before guardian installs its inherited filter.
- `ngx_process_cycle.c`, `ngx_start_worker_processes` / `ngx_pass_open_channel`: sends `NGX_CMD_OPEN_CHANNEL` containing channel[0] to existing workers. `ngx_reap_children` closes dead channels and calls `ngx_spawn_process` plus `ngx_pass_open_channel` again on respawn. Worker init closes unused endpoints.
- `ngx_channel.c` lines 39–41/79: real `sendmsg` with `SOL_SOCKET/SCM_RIGHTS`. Lines 120–128/153–172: real `recvmsg`, ancillary validation and imported integer FD on OPEN_CHANNEL. The real cached binary's error log confirms the denied syscall. No syscall tracer is installed; source plus real kernel error / per-role `/proc` FD evidence are used, not fabricated trace output.

An inherited cBPF filter can inspect the numeric fd argument, not socket inode/cookie/peer nor pointee sockaddr/control memory. Pre-exec static fd lists cannot know newly created channels. A numerical allow-rule survives `close` and future FD reuse. Blocking all closes/dup replacements of reserved descriptors would break normal Nginx channel teardown/rebuild and does not establish the required successful channel lifecycle. Merely changing recvmsg to recv/read loses ancillary FD transfer. Trusting a callback flag or naming a path "nginx" is not a kernel object boundary. No such shortcuts were implemented.

## Feasibility probes and minimum next implementation

Current WSL is non-root uid1000, x86_64 kernel `6.18.54.1-microsoft-standard-WSL2`. Child-only probes (child exits without host mounts/config changes): `unshare(CLONE_NEWUSER)` and then `unshare(CLONE_NEWNS)` both return 0; Landlock ABI query syscall444 returns 7. Ancestor `pidfd_getfd` syscall438 on an owned child socket succeeds (returned fd6, errno0).

**Therefore this is an incomplete engineering/security implementation, NOT a demonstrated kernel/permission impossibility.** Do not report "WSL cannot safely support an exception". No root operation was needed or attempted. A supported building block is not a completed security boundary.

Preferred small architectural follow-up to investigate with a fresh RED→GREEN slice:

1. A separately fixed Nginx-only internal entry point, executable/inode/hash and configuration/certificate authority locked before launch, not caller-selected callback/argv. Retain original generic callback's global recvmsg deny.
2. Kernel seccomp user-notification broker for this profile: interpose internal AF_UNIX `socketpair` creation, create/pin both socket objects in broker, inject descriptors with `SECCOMP_IOCTL_NOTIF_ADDFD`, write checked pair result. Reject unapproved pair types. Pin kernel objects, not FD numbers, across respawn.
3. For recvmsg, duplicate the **current** target fd using pidfd_getfd and verify pinned socket identity/cookie; emulate receipt on that pinned object, validate every SCM_RIGHTS object is another owned internal channel, inject only those descriptors, copy bounded trusted Nginx channel data/control to target. Never `CONTINUE` an inspected mutable fd/pointer, and never import arbitrary foreign rights. Guard peer/root/capability checks and notification-ID validity, blocking flags/EAGAIN semantics, fault/FD reuse races, cancellation and bounded broker work need tests before adopting this route.
4. Broker is another liveness/failure boundary: KILL/STOP/startup failure must not freeze renewal or leave live ingress. Integration with 600/200 budget needs measured target tests. Socketpair/recvmsg mediation plus correct own-object import is substantive implementation, not a one-line exception.
5. Alternative private mount root + abstract-UNIX scope needs verified `/proc`/root/directory-FD/exec escape closure, read-only fixed binaries/libs, private certificate authority and peer isolation without disconnecting real ingress/backend. IPC namespace alone does **not** isolate UNIX sockets; abstract UNIX belongs to network namespace, while filesystem socket paths still matter. Userns success alone cannot prove this alternative safe.

## Reproduce / evidence

WSL cwd `/mnt/d/DevPortal/homelede/homepublish-product`:

```sh
export TMPDIR=/home/eric/homestun-sdk-check
make -C homepublish/tests guardian direct product
# exit 0: 19 tree + 10 startup + 18 lifecycle scenarios, direct/boundary and product/recipe/package regressions.
export HP_D2B2_EVIDENCE=/mnt/c/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch/d2b2-review-evidence
make -C homepublish/tests guardian-nginx
# Python exit 1 / make exit 2: genuine channel EPERM assertion, after all nine records.
```

Intermediate verified integration run: nine records = one foreign SCM_RIGHTS attack plus eight real Nginx scenarios; 10 channel EPERM alerts total, `remaining_owned=[]`; temporary stream closure 1202ms from startup. Single-fault closure observations: controller KILL2ms/STOP535ms, guardian KILL1ms/STOP183ms, watchdog KILL5ms/STOP247ms. These are observations, not a target latency contract; process exit includes the fixture's additional bounded reap wait. Exact final readback/hash values are recorded below after final-version execution.

Pre-final source hash `renewable-guard.c`: `e15ae36953b399dcd3fa4928cefcee23468c71f1f8825141e15cd24ffb81a52f`.
Cached Nginx binary hash: `39526014e291b8d70f49da6de5d5f3641d966d60da976a54e9c0153bd2bc6ef3`.
Regression log hash: `b134cd73b73077c92513992db5c4c9af8043140e749c60450f41f0e551b84d80` (intermediate checkpoint run).

## Final-version execution / readback

Final command `export TMPDIR=/home/eric/homestun-sdk-check HP_D2B2_EVIDENCE=/mnt/c/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch/d2b2-review-evidence; make -C homepublish/tests guardian direct product guardian-nginx` returned make exit2 **only at guardian-nginx's channel assertion**, after prior guardian/direct/product targets completed. Parsed final log: 19 tree, 10 startup, 18 lifecycle; nine integration records, nine real channel EPERM alerts total, all eight guarded Nginx scenarios completed. Temporary stream closed at 1203ms; controller KILL/STOP observed 1/524ms, guardian 1/201ms, watchdog 1/294ms after fault observation. These timings are not advertised target guarantees.

Final `/proc` readback: no tracked owned PIDs, all real master/workers UID/GID1000 with NoNewPrivs1/Seccomp2. Independent post-run connections to all eight ports on both loopback families fail. No `d2b2-nginx-*` runtime fixture directories remain. Per-role descriptor/inode symlink snapshots are in summary. File listings prove native TLS cleanup remains unimplemented before harness deletion.

Final artifact SHA256:
- `summary.json`: `5c2c98b75730cb59d70237499f3bd3cf43fd0d2f1988e1b41cf2a7b391a27b20`
- `final.log`: `589c3f43e96dae3a3827fa23f75d0324dff800e825fdb53c2a322f5eb77dac22`

`git diff --check` passed. Final source changes after the intermediate checkpoint add only FD/NNP evidence and checkpoint/status documentation; no production guard/CLI/provider code changed.

## Still blocked / preserved

Successful internal worker FD transfer/notify without channel/signal errors; implemented safe exception plus foreign-import attacks against it (all roles); native-owned TLS/file cleanup; production provider/controller scope-health/DNS/TLS/journal/fw; typed ERROR packets; recovery/boot/UPnP; matching SDK/aarch64/real procd and post-measured 600/200 budgets. Exec leader PDEATHSIG9 and fork-worker0 behavior unchanged, owned tree cleanup still required. Simultaneous STOP of both supervisors and kernel D-state/no scheduling not guaranteed. Start/Apply unsupported, activation_ready=false and production helper exit78 remain; no product activation.
