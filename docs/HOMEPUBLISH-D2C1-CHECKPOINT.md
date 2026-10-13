# D2c1 native-owned flat runtime checkpoint (partial; activation disabled)

Baseline `17513f47f06b9017d402540648eb7c82b515781e`, exclusive `feature/homepublish-product`, local non-root WSL/loopback only. No production, network install, firewall/UPnP, push/merge/PR.

## Intermediate verified slice

Test-first real `test-guardian-nginx.py` exit1 on baseline behavior: `D2c1 RED: native-owned TLS/config/pid remain before harness cleanup`. RED summary retained in profile scratch `d2c1-red/summary.json`; original attempt through bash quoting failed to preserve shell variables and is NOT test evidence. Direct `wsl.exe --cd ... env ... python3 ...` reproduced actual RED.

Native `owned-runtime.h/.inc` implements a fixed-name, directory-FD anchored shared inode ledger. Trusted internal parent FD must be own-UID 0700 directory. Empty runtime and five empty fixed temp directories are prepared without secrets; both independent supervisors inherit pinned directory FDs before provider provisioning. Four file slots only (cert/key/config/pid), O_TMPFILE inode registration before link publication, O_NOFOLLOW metadata validation, 0700 directories / 0600 single-link files. No client path/exec/PID or wire ownership fields. Generic guard unchanged unless an HP_GUARD_TEST-only internal binding exists. Production main remains exit78.

Both supervisors first kill the owned data-plane group, bounded-reap, then clean registered files and empty registered temp directories. Missing entries are idempotent; replaced/symlink/hardlinked/unknown/nonempty entries are retained and return residual=1 (supervisor exit124), never recursively swept. Sequential replacement tests do not claim an atomic conditional-unlink primitive: concurrent same-UID/root interference is explicitly outside the trusted-provider contract. Simultaneously stopped supervisors and kernel D-state remain outside deadline guarantees. Typed durable residual reporting/controller integration is NOT complete.

Real cached Nginx 2-worker IPv4/IPv6 CA/SAN TLS, worker replacement and same-master multi-window renewal, temporary cutoff and controller/guardian/watchdog each single STOP/KILL: `test-guardian-nginx.py` exit0; 12 records, eight native runtime directories absent BEFORE fallback/harness cleanup, owned PIDs/listeners absent, stream closed, foreign sentinel inode and original source TLS hashes preserved; zero channel EPERM/internal errors. Sources intentionally remain fixture-owned and are separately harness-removed; they are NOT claimed as native-owned copies. Evidence `scratch/d2c1-green/summary.json`.

`make -C homepublish/tests owned-runtime` exit0: 13 native regression cases (idempotence, readonly permission cleanup failure/retry, hardlink, symlink, file replacement, directory replacement, unknown file in temp, startup fault after 0/1/2/3 writes, Stop, invalid generation with no secret). These are supplemental regression tests; only the real Nginx cleanup behavior has independently observed test-first RED. Initial probe compiler misleading-indentation warning fixed, then clean -Werror pass.

## Remaining gates / NOT production-ready

This is the requested **minimal snapshot/cleanup intermediate checkpoint**, not completion of D2c1 or provider authority. Fixed exec remains a cached host fixture: compiled paths are NOT immutable authority. Pinned loader/nginx/library verified snapshots, target trust manifest, prevention of executable/library replacement/symlink TOCTOU and new production-only fixed-provider startup API are NOT implemented. No generic production exec entry has been added. Test-only private profile remains test-only.

Snapshot source authority, server-owned generation/approval binding, scope validation before any secret write, production SAN/chain/key/expiry validator, controlled configuration authority and scope/DNS/health controller remain blocked. Arbitrary provider-created temp files are NOT owned by name or location: unknown temp content yields explicit residual. Safe recursive registration before tempfile publication, crash recovery across controller restart/durable manifest, provisioning-specific STOP/KILL at every syscall and source-copy lifecycle still need implementation/testing. Empty-root prepare failure can leave a non-secret directory and must be accounted for by the future controller, not advertised as successful cleanup.

`Start`/`Apply` unsupported, `activation_ready=false`, production helper exit78 retained. SDK/aarch64/BusyBox/procd/fw4/public reachability unverified. Independent review required before further integration.
