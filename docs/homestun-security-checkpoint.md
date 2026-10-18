# HomeSTUN final security checkpoint — isolated regression GREEN, release blocked

Supersedes the obsolete terminal-outage checkpoint. Worktree `D:/DevPortal/homelede/feeds-xiaoqingfeng-homestun`, branch `feature/homestun`. No commit, push, merge or PR.

## Reproduced RED and focused fixes

- Rebuilt the incoming revision with WSL gcc and reproduced `FAIL SEC003: controller death during preparation strands lock beyond TTL` on the actual router.
- Split snapshot preparation into a child phase monitored by the guardian. Controller pipe HUP/cancellation and monotonic startup deadline are observed while snapshot mkdir/write/fsync is delayed. Preparation has its own process group and parent-death SIGKILL protection.
- Eliminated creation of runner.lock before guardian fork. Added prefork-delay fault injection: controller death before fork leaves no directory lock.
- Added a post-mkdir delay and reproduced a second RED: guardian death in the lock-creation/publication window left runner.lock. Moved mkdir into the monitored preparation child. Runtime-directory inode flock excludes concurrent helpers; a pre-existing lock is rejected before ownership is published; ownership is published before preparation can mkdir. Guardian/controller cleanup reopens the owned directory descriptor-relative. Final tests show both stale-lock preservation and live-helper exclusion without deleting another snapshot.
- Removed the blocking waitpid after SIGKILL. Both phase/controller collection use WNOHANG, bounded polling and a 250ms collection interval rather than a single orphan sweep. Existing controller TERM/INT polling remains nonblocking.

## Exact-final-version verification

WSL gcc 13.3.0, `-static -Wall -Wextra -Werror`; both production helper and separate fault binary built without warnings/errors. `file` identifies static x86-64 Linux ELF binaries.

```sh
gcc -static -Wall -Wextra -Werror homestun/src/lease-supervisor.c -o homestun/tests/lease-supervisor.bin
gcc -static -Wall -Wextra -Werror -Dfsync=test_fsync -Dfork=test_fork -Dmkdirat=test_mkdirat homestun/src/lease-supervisor.c homestun/tests/preparation-fault.c -o homestun/tests/preparation-fault.bin
node --test homestun/tests/worker.test.mjs
```

- Worker: **6 passed, 0 failed/cancelled/skipped**.
- Actual router Lua: **16 numbered checks passed**.
- All **9 router scripts** passed, with **33 explicit PASS lines**: smoke, trust, term, failure, faults, guardian-stop, preparation, preparation-crash, lock-window. The complete final suite passed twice without subsequent code/test changes.
- Smoke verifies both fixture upstreams, unknown/subdomain Host denial and real TLS expiry. Trust verifies directory/file ownership, permissions, symlinks, 0400 copied bytes, actual original config/cert/key replacement, and a new TLS response from the surviving snapshot.
- Lifecycle verifies stopped controller, stopped guardian, nginx exit, established TLS connection closure, guardian SIGKILL, controller SIGKILL, TERM, snapshot fsync error, delayed preparation startup bound, controller death during preparation, guardian death inside delayed mkdir, prefork controller death, stale/live lock exclusion, and preparation TERM/INT.
- SHA256 readback matched **15 transferred files plus 2 runtime binary aliases**. Manifest: `docs/homestun-final-hashes.json`. Production binary SHA256: `62bf9f14e1ecc5a76e69dce08092116cd8cabf92896ac25d38ac01186b1eef1a`; source SHA256: `5881738d8ec50fdcf827d6037f16f781e067635af03ce0440cb5d207e0a1ff9d`.
- Exact repeated final output: `docs/homestun-final-regression.txt`; hash/process/listener readback: `docs/homestun-final-inspection.txt`.

## Cleanup and management preservation

First authenticated inspection found no leftover test processes/listeners. Final authenticated process/listener inspection after the complete run also found no helper, fixture nginx or client test processes, no 18443/18081/18082 listeners, no runner.lock/client FIFO. The entire isolated `/tmp/homestun-test` directory (including test private key/certificate) was then removed after checking it was not a symlink and that no `-real` fixture remained. A separate authenticated readback verified the directory absent, no test processes/listeners, and existing management listeners 22/80/443 retained. See `docs/homestun-final-cleanup.txt`.

Correction to earlier progress wording: current port80 is uhttpd PID4308; current port443 is pre-existing dropbear PID127610; SSH22 is dropbear PID34089. These same listeners were present initially and finally. We did not alter management configuration or reinterpret 443 as a tested web/TLS service.

To independently rerun, recreate root-owned mode0700 `/tmp/homestun-test`, transfer the exact manifest files, copy the .bin binaries to their extensionless runtime names and chmod0700, run `lua /tmp/homestun-test/test-core.lua /tmp/homestun-test`, chmod0600 generated nginx.conf, then execute the scripts in the order listed above. Smoke generates fresh test-only TLS material and loopback fixtures. Remote test artifacts no longer exist; local binaries and evidence remain.

## Limits and remaining release gates

This is an isolated lifecycle/security regression result, **not production completion**. No packages, firewall, Cloudflare, UCI/procd or real-service exposure changes. Actual STUN/TCP NAT reachability, NATMap integration, SDK/package/procd/LuCI acceptance and deployed Cloudflare persistence remain unverified; parent independent review is still required.

Bounded user-space waits cannot guarantee recovery from uninterruptible kernel I/O, a stalled cleanup filesystem syscall, arbitrary scheduler starvation, simultaneous destruction of both supervisors, or malicious root. Source reads before fork create no directory lock but can still block on kernel I/O; delayed-fork injection demonstrates lock safety, not a complete pre-fork wall-clock termination guarantee. SIGKILL collection is attempted for 250ms; a permanently D-state child cannot be reaped until the kernel releases it. No such residual task was observed in either final run. Tests exercise fault injection and ordinary target kernel behavior, not a proof against these excluded conditions. Stale locks are deliberately preserved/fail-closed rather than automatically deleting unknown ownership.
