# D2d1 fixed-provider authority subset (local, NOT production trust closed)

Baseline e3a73ff2e2888c4c09893ab2d7e7ecdaf254c2ba; early runnable commit ae8ad67.
Only WSL loopback/source/local commits. No installation/network download/firewall/UPnP/public probe/push/merge/PR.

## Actual launch chain and authority

Cached x86 SDK Nginx uses musl loader. `loader --library-path ... --list nginx` reports pcre2, ssl3, crypto3, z1, gcc_s1 and libc (loader). Source loader and pcre/z sonames are symlinks; trusted host profile explicitly names the underlying regular files, never accepts symlinks during execution. No arbitrary client exec/loader/library/path/environment or manifest parameter in the new API. Production build of trusted-nginx.c returns ENOTSUP: no target installation manifest authority is claimed. HP_GUARD_TEST owner derives a compiled manifest ONLY from the known cached SDK installation, before mutations; attack sources never get new authorized digests. Compilation path itself is not authority. Client manifest environment is ignored.

`hp_trusted_nginx_verify` and `hp_trusted_nginx_exec` open every path component with O_NOFOLLOW; require regular single-link bounded files, hash exact FD-read bytes against the server-owned profile and check FD inode/size/mtime stability. Provisioning re-verifies and copies those same buffers only after the established supervision grant. Loader and Nginx execute from sealed memfds; musl actually opens Nginx through /proc/self/fd. Real /proc/master/maps verifies both memfds and all five actual libraries from the owned runtime, no cached SDK mappings. Thus fexecve-loader-alone is not mistaken for dependency locking.

Libraries are verified private read-only runtime snapshots (0400) with pinned ownership entries, NOT kernel-immutable against same-UID/root mutation. They still resolve through the private runtime pathname. This is a runnable fixed-exec/dependency subset under the preexisting trusted-provider contract, NOT a hostile-filesystem sandbox or full immutable production chain. Client cannot select this prefix; trusted admin modification of install root is outside contract. Sealed loader/Nginx survive path replacement; input exec/loader/libs tampering and symlinks reject. No claim of adversarial snapshot-parent rename or same-UID chmod/write protection. Next gate must close that remaining path authority with target-supported restricted mount namespace or equivalent, not claim WSL userns support proves router support.

Native runtime has eleven fixed registered file slots plus five existing empty temp directories; no recursive deletion of foreign content. Guardian/watchdog FD allowlists size follows the file ledger; all anchors are CLOEXEC. Process group, private STREAM seccomp, pidfds, provisioning barrier and cleanup-before-peer-kill preserved. ETXTBSY when executing disk inode held O_RDWR by cleaners was a real implementation failure; sealed memfd execution fixed it without dropping cleanup anchors. LD_PRELOAD/LD_LIBRARY_PATH/OPENSSL_CONF injected after fixture startup, then execve receives only fixed PATH/LANG. Nginx rewrites argv/environ; forbidden markers and actual mapped dependency closure are checked, not a false requirement to retain PATH visibility.

## TDD and verification

Before implementation, formal exec replacement case returned exit0 / `guard rc=0`: assertion `untrusted executable accepted` genuinely RED. New API made it GREEN (exit2, rc=-1); fourteen official negative cases now cover exec replacement, loader/five-lib byte tamper and seven symlink replacements. Supplemental cases are regression coverage, not individually observed RED. Native prepared runtime absent before fixture cleanup in every rejection. No provider is launched in these preflight rejections (guardian=0); zero listening follows no provider entry, not a broad host socket inventory claim.

Final full command (WSL Ubuntu-24.04, non-root):

```
TMPDIR=/home/eric/homestun-sdk-check HP_D2B2_EVIDENCE=/home/eric/homestun-sdk-check/d2d1-final/nginx HP_START_EVIDENCE=/home/eric/homestun-sdk-check/d2d1-final/startup.json make -C homepublish/tests owned-runtime guardian direct product startup-owned guardian-nginx trusted-provider
```

Exit0, log `/home/eric/homestun-sdk-check/d2d1-final/full.log`. Startup 79 runs + 2 ownership contracts; owned runtime/stress, guardian tree/lifecycle/startup/foreign descriptors, direct dual-stack TLS/no-replay, product/recipe/package all passed. Cached Lua tmpnam warning remains preexisting. Real fixed-provider Nginx: 12 integration records, eight lifecycle cases, dual-stack CA/SAN-checked TLS, two workers, killed-worker respawn, same master across renewed windows, temporary cutoff, controller/guardian/watchdog individual STOP/KILL. Eight cases prove stream closed/listener refused/owned PIDs and all runtime files absent BEFORE harness fallback; foreign inode/source TLS preserved; internal errors/channel EPERM zero. Actual dependency maps checked for all eight cases with malicious env/client-manifest marker present at fixture entry. Final committed-source provider/Nginx rerun required; completion report supplies exact hash/result.

## Remaining / unsupported target mechanisms

No target installation signature/package-digest integration; host-test SHA256 uses cached host libcrypto, not a new production dependency. No target memfd sealing, proc FD loader semantics, pidfd/close_range/seccomp, mount/user namespace, aarch64, BusyBox/procd/fw4 or matching SDK acceptance. Namespace restrictions already inherited by worker mean any future mount setup belongs in a trusted supervised provisioning phase BEFORE provider seccomp, not an arbitrary callback escape. No unsupported-kernel fallback to plain paths.

Source TLS/SAN/chain/key/expiry authority, full scope/approval/health controller, durable typed residual/crash recovery and partial prepare accounting remain. Source TLS test copies are preserved, not claimed native source lifecycle. Simultaneous enforcement suspension, D-state and privileged/sameUID interference remain excluded. Start/Apply unsupported, activation_ready=false and production helper exit78 unchanged. Independent review and parent final-source verification pending.
