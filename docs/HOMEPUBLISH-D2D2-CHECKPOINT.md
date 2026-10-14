# D2d2 fixed OpenSSL/provider authority subset (local, not activated)

Baseline: `cdfa83503216bc0840932a29afcca86261d9e95d` plus the local D2d2 changes below. Only WSL non-root loopback tests and local commit; no installation, production helper, firewall, UPnP, public probe, push, merge, or PR.

## Closed in this slice

- `trusted-nginx.c` now creates a server-owned fixed empty `openssl.cnf` (slot 11), and passes only fixed `PATH`, `LANG`, `OPENSSL_CONF=<owned runtime>/openssl.cnf`, `OPENSSL_MODULES=<owned runtime>`, and `OPENSSL_ENGINES=<owned runtime>` to the verified loader. The hostile `LD_PRELOAD`, `LD_LIBRARY_PATH`, `OPENSSL_CONF`, and client-manifest values injected before startup cannot reach this exec payload. The owned module/engine root has no loadable module; the config is not `/etc/ssl/openssl.cnf`.
- The same native ledger now reserves `openssl.cnf` and non-secret `provider-init.trace` (13 fixed file slots total; five existing temp-directory slots). Cleanup, FD allowlists, preparation, and fixture ownership all follow the ledger; no recursive deletion was added.
- The real cached Nginx TLS fixture passed IPv4/IPv6 TLS, renewal/worker respawn, temporary cutoff, controller/guardian/watchdog STOP/KILL, stream closure, listener refusal, native runtime absence before fallback, foreign inode/source TLS preservation, and 0 internal channel errors.
- Test-first evidence: the new D2d2 assertions initially failed because `OPENSSL_CONF` and `openssl.cnf` authority were absent; after implementation `test-guardian-nginx.py`, `test-trusted-provider.py`, and `test-owned-runtime.py` passed. The integration trace is a product-side fixed-exec payload record, not a claim that ptrace itself is a same-UID contract boundary.
- Formal actual-Nginx regression: `make -C homepublish/tests openssl-engine` builds a matching cached SDK gcc constructor-only shared module. Both cases execute the actual trusted Nginx provider with native preparation/seccomp. RED mutates only a copied fixture to its pre-fix exec environment; ptrace observes its ambient config access and redirects that owned tracee to scratch malicious config. The unmanifested module is actually opened, mapped, and executes its marker constructor. GREEN uses unchanged current provider source: fixed owned empty config is opened, ambient configs/module/marker are never accessed. No host ENGINE registration/ABI or `openssl engine` CLI is used; host `openssl req` only generates fixture TLS. Evidence is unique per-run `attack-summary.json`, red/green `actual-open.json`, `observation.json` (kernel-observed pre-exec environment and inode metadata), and `raw.maps` under `HP_OPENSSL_ENGINE_EVIDENCE` (default `/home/eric/homestun-sdk-check/openssl-engine-regression`). No scratch script or git worktree dependency. `HP_TEST_SDK` can select the matching cached x86_64 SDK; non-root x86_64 Linux, ptrace, host cc/libcrypto/openssl and that SDK are explicit prerequisites.
- Historical assertion (superseded): the old prefix-filtered map check claimed exact-set coverage, but silently omitted foreign/SDK paths. Independent review reproduced acceptance after appending `/foreign/unmanifested.so r-xp` to actual GREEN raw maps. That assertion was insufficient, not proof of closed dependency authority. The complete inventory correction below replaces it.

## Exact local verification

WSL non-root:

```text
python3 test-guardian-nginx.py                         exit 0
python3 test-trusted-provider.py                       exit 0
python3 test-owned-runtime.py                          exit 0
python3 test-openssl-engine.py                         exit 0
```

The guardian integration produced eight lifecycle cases plus renewal/respawn records and `provider-init.trace` evidence under `/home/eric/homestun-sdk-check/d2b2-nginx-evidence` during the run. The final run’s output included `PASS guarded Nginx integration including internal channels`.

## Resumed formal regression verification

Recovered from shutdown at `7c9e8d2907b90ad013dae2750eb484e983e6e50e`. The abandoned host OpenSSL engine CLI attempt failed with dynamic-engine ABI version incompatibility (`eng_dyn.c:481`); it is replaced, not counted as PASS. Constructor-only module loading proves the authority violation before ENGINE registration is needed. First recovered formal run and final full run both observed RED marker/maps true, GREEN false, bind intercepted true (117/115 observed file accesses respectively).

```sh
# Ubuntu-24.04, uid1000; cwd /mnt/d/DevPortal/homelede/homepublish-product
export TMPDIR=/home/eric/homestun-sdk-check
timeout 560 make -C homepublish/tests owned-runtime guardian direct product startup-owned guardian-nginx trusted-provider openssl-engine
# exit 0; full output: /home/eric/homestun-sdk-check/resume-openssl-final-full.log
```

Formal full-run probe evidence: `/home/eric/homestun-sdk-check/openssl-engine-regression/run-7rbelw4a`. Observer kills at bind syscall entry before any listener: raw status 9 is designed observer completion, not failed product startup. This standalone probe has no guardians; inode metadata is saved before observer fallback cleanup and source TLS is removed in finally. Native guardian cleanup is proved only by the separate complete guardian-nginx matrix, not by observer rmtree. No system `/etc` was changed. Existing cached Lua recipe `tmpnam` linker warning remains unrelated and is not a clean-warning claim. Post-commit verification runs `openssl-engine guardian-nginx` against the same committed source; its exact commit/result is returned in the handoff. Independent parent review remains required.


## Independent audit P1/P2 corrections (baseline 9af952f)

- P1 formal RED: actual old `elf_map_set` extracted from the real integration harness, given actual GREEN raw maps plus `/foreign/unmanifested.so r-xp`, hides the mapping; test exit 1 (`audit-p1-red.log`). GREEN uses shared `dependency_maps.py` in the integration and injection tests, enumerates every maps row before classification, rejects unknown executable files and readonly ELF (foreign, SDK, unknown memfd), missing expected objects and unapproved readonly data. Paths with spaces and `(deleted)` remain exact. Full master/all worker/respawn raw maps and parsed device/inode/offset/permissions/classification metadata are saved. Five library identities are stat/readback plus manifest SHA256; two sealed memfds use kernel maps identities and mapped ELF-header readback under the existing trusted provider contract, not a new same-UID/root sandbox or full mapped-image digest claim.
- Non-ELF allowances are finite: exact resolved `/etc/localtime` path, root-owned non-writable TZif readback; one-page `rw-s`, offset-zero, kernel shmem `/dev/zero (deleted)` of musl/Nginx with mapped non-ELF header. Arbitrary non-executable files are NOT allowed. First new live run exposed the previously hidden shared-zero row and failed closed; full inventory remains saved.
- P2 formal RED: real copied observer with host compiler `/bin/false` exits 1, leaves `owned` and lacks observation (`audit-p2-red.log`). Per-case lifecycle now includes owned mkdir/precompile/fork/trace inside try/finally; failures record secret-free runtime/fixture inode metadata, syscall/env/raw maps and failure before fallback, even with no PID. Reap is bounded, stuck tracee retains runtime. Only owned fixture is removed; evidence/foreign files are preserved. Compiler, injected trace exception and injected timeout regressions pass, verify PID absence and source TLS deletion, retain copied evidence in `audit-fault-evidence`.
- Scope remains single traced process stopped before bind, NOT a process-tree observer, host kill guarantee, or native guardian cleanup claim. Real provider constructor RED/GREEN remains unchanged (RED module marker/maps true, GREEN false; both bind intercepted).
- WSL uid1000 full `make -C homepublish/tests owned-runtime guardian direct product startup-owned guardian-nginx trusted-provider openssl-engine` retry exit 0; `/home/eric/homestun-sdk-check/audit-fixes-full-retry.log`, actual OpenSSL `run-d5npu89a`. First full attempt failed existing Stop-repeat 91 readiness read (`audit-fixes-full.log`); retained as intermittent unresolved timing evidence, not counted PASS and not modified in this scope.
- Final-source `make -C homepublish/tests audit-regressions guardian-nginx openssl-engine` exit 0; `/home/eric/homestun-sdk-check/audit-fixes-finalsource.log`, actual provider `run-w5qs1n9r`. Post-localcommit `guardian-nginx openssl-engine` is re-run separately, exact hash/log returned in handoff. Independent review of these new corrections remains pending.

Production ENOTSUP, helper78, Start/Apply unsupported and activation_ready=false stay unchanged. Target manifest/signature, immutable library paths/musl fallback, production controller/TLS/SAN/health, durable typed residual/partial prepare and matching SDK/BusyBox/procd target acceptance remain blocked. No install/download/public/firewall/UPnP/push/merge/PR.

## Observer evidence-write medium closure / Stop-repeat still open

Baseline `56947054536b514120cb2347b50b6e80ada23df8`. Old P1 complete maps correction stays closed; no maps/namespace/immutable-library expansion.

- Formal test-first RED: actual copied observer injected `PermissionError` at raw.maps (live bind-entry tracee), before-fallback.json and observation.json (already bind-truncated). All three exit 1 with `red/owned` remaining. Retained readback: `audit-fault-evidence/run-s2gvloff`, `run-kl_g6sd8`, `run-_zwmv5b2` / `write-result.json`. Initial RED reviewer PID scan used exe only and missed sealed memfd loader; the escaped live RED tracee subsequently spawned a worker/listener. Exact deleted fixture FD/cmdline ownership was read back and reviewer-only SIGKILL rescue performed (704/707/1165); this is RED residual, NOT probe cleanup. Harness now scans matching fixture cmdline/FDs before rescue and bounds connect readback to 300ms. Failed early GREEN attempts caused by that RED listener and unbounded connect were not counted PASS.
- GREEN separates best-effort evidence/metadata/JSON serialization from outermost kill + bounded reap + owned fixture cleanup finally. Evidence failures cannot prevent those steps. Original failure type, evidence_errors and cleanup_residual remain distinct; no exception messages/secret bytes in bounded stderr metadata fallback. All JSON/maps unavailable still exits nonzero with fallback; if stderr also unavailable reporting is explicitly unknown (not tested as a storage guarantee). Source key/cert unlink attempts are independent. Unreaped tracee retains runtime as residual/unknown. Scope remains single tracee stopped before bind, no native guardian or process-tree cleanup claim.
- Formal regression covers maps/metadata/observation/all-file-storage failures at both live and bind-truncated cuts: verifies no matching PID/FD, no listener, no owned runtime/source TLS, foreign bytes/inode preserved, incomplete evidence reported and fallback owner distinct from native guardians. Existing compiler/trace-error/trace-timeout and actual SDK Nginx constructor RED/GREEN remain passing.
- Stop-repeat is **unresolved**: historical Stop91 `audit-fixes-full.log` readiness abort retained. No native timing change, assert suppression or root-cause closure. On readiness read failure, native test probe emits bounded role topology/state (missing roles absent-or-unobserved), read count/errno, absolute/elapsed monotonic timing and unchanged 600ms window/200ms watchdog. Python harness saves failure/inode metadata before TemporaryDirectory fallback. Formal callback-readiness EOF injection first failed missing diagnostic (`readiness-diag-red.log`), then passed diagnostic assertion and separately verified native runtime absence. Diagnostic topology is observation, not PID signaling authority. Five existing 100-repeat rounds passed before the user requested scope reduction (`observer-stop-repeat-1..5.log`); no further pressure expansion. Non-reproduction does NOT close the incident.

WSL uid1000, cached tools only; export `TMPDIR=/home/eric/homestun-sdk-check`:

```sh
# Full suite before final diagnostic-role/TLS-tail polish, exit 0:
timeout 560 make -C homepublish/tests audit-regressions owned-runtime guardian direct product startup-owned guardian-nginx trusted-provider openssl-engine
# observer-finally-full.log; constructor run-hi6xskr7
# Final affected source, exit 0:
timeout 180 make -C homepublish/tests audit-regressions owned-runtime openssl-engine guardian-nginx
# observer-finally-affected.log; constructor run-4zpot_op
```

Final affected run: eight evidence-write scenarios plus existing maps/compiler/trace faults passed; readiness injection evidence `owned-readiness-evidence/hp-owned-23hw8xrg-0.json`; real constructor RED marker/maps true, GREEN false, both bind intercepted; native guardian-nginx complete lifecycle/TLS/channel matrix passed. Post-localcommit same affected targets re-run and exact hash/log returned in handoff. Parent independent re-run/review remains required; tests/__pycache__ is not source and excluded from commit.

### Next functional slice (not production activation)

Proceed with an internal controller plan/state API over canonical committed config + revision/approval/scope + desired disabled/enabled/manual_stop_latch + runtime generation/active_revision + journal adapter. First TDD vertical slice: Save only persists pending config, never starts/applies; Stop persists disabled/manual-stop intent and revokes internal capability idempotently; status distinguishes saved/active/pending/cleanup unknown. Provider adapter may return structured unsupported; Start/Apply stay unsupported and test-only guardian/provider entry points do not become production activation. Existing `hp_guard_start`/`hp_guard_send` are serialized internal inherited-channel APIs; do not expose arbitrary PID/command/config authority via controller.

Manifest/signature, immutable-library/musl fallback, target SDK/BusyBox/procd, production TLS/SAN/health/scope and typed durable recovery stay publication/activation gates, not a reason to keep extending this safety slice. Do not bypass a real safety blocker: production ENOTSUP/helper78/activation_ready=false remain until separately accepted. No install/download/production/public/firewall/UPnP/push/merge/PR.

## Remaining gates / safe claim

This is a real vertical subset, not complete dependency authority. The target installation manifest/signature, target kernel-supported immutable path or mount gate, target OpenSSL provider/engine/module layout across supported OpenSSL versions, target aarch64/musl SDK, BusyBox/procd, and production controller/TLS/SAN/health/scope/journal integration remain unverified. Nginx config semantic provenance still belongs to the trusted renderer; this test does not turn arbitrary Nginx text into a trusted parser or claim generic `load_module`/`include` policy closure. Do not infer a hostile-filesystem or same-UID/root boundary from ptrace/maps.

Because the target dependency and immutable-path gates remain open, production `hp_trusted_nginx_*` remains `ENOTSUP`, `activation_ready=false`, Start/Apply unsupported, and helper exit 78. No activation claim is made.
