# D2 runnable internal controller slice (local only)

## Controlled Apply / original temporary deadline slice

Source `926311e`, local WSL uid1000 only. Controlled replacement checks saved revision, explicit internal approval and exact fixed fixture scope before stopping old generation. Candidate/attempted snapshots are durable; only actual loopback TLS + HTTP readiness commits active/running. Historical active is not reported verified after stop/failure. Separate-process status exports attempted/candidate, pending, stage/error/cleanup and active_verified. Production client remains unsupported; fixture CA/hostname checking is NOT production SAN/source authority.

Executable acceptance covers two actual backend markers/counters, Save leaves old marker, Apply changes marker/newgen, stale revision/unapproved rejection; provider-start and readiness failure, failed Apply after old stop, cleanup-unknown blocking restart, Stop/stale-event latch; real minimum 60s policy with Save and Apply preserving first expires_at and actual streaming cutoff/new listener absent, backend alive after cutoff and runtime absent. Continuous guard renewal had a newly exposed ~9s heartbeat queue overflow: reciprocal beat producer outpaced one-read-per-loop consumer; bounded drain fixes it. The 60s test failed twice before that native fix, then passed. Apply RED before implementation was missing error/action; later failure cases are supplemental regression, not independently proven RED.

Committed-source command: `TMPDIR=/home/eric/homestun-sdk-check timeout 380 make -C homepublish/tests controller product direct guardian-nginx`, exit **0**, log `/home/eric/homestun-sdk-check/controller-apply-committed.log`, persisted `.exit` = 0. 64 PASS lines (not 64 independent tests), guardian-nginx 12 integration records. Original deadline 1791948111; last tick 1791948110.9846134, 284 streamed chunks. Wrapper later attempted Linux git against Windows worktree metadata and failed; make exit was already durably recorded and separately read back. Earlier expanded existing-target run reached all PASS/Leaving but tool output timed out; do not assign a verified exit to that run. One bounded CLI retry handles only store-busy rejection before writes.

Next functional direction: scoped RPC/UI contracts for genuine saved/active/pending/attempted state and Save/Stop, then explicitly authorized internal controlled actions; multi-service/dual-stack controller, DNS/cert maintenance and bounded recovery remain. Clock rollback/trust and boot recovery remain unresolved. No additional security stress/review phase scheduled; final unified reassessment checklist below remains open. No production install/network/firewall/UPnP/push/merge/PR.

## Implemented (previous slice history)

- `product-controller.lua`: canonical journal/revision read via existing private native store; detached plan and saved/active snapshots, desired state, generation and approval. Save remains the fixed HP1 cross-process product CLI and never starts or applies.
- `controller-host.lua` + `controller-adapter.c` are **non-installed test-only** fixed host scope. Exact fixture service/domain/cert/backend/private ingress tuple is checked; only that tuple maps to loopback. No production CLI/env/client callback/path activation switch. Adapter builds with HP_GUARD_TEST and the existing server-owned fixed SDK digest profile, owned-runtime, guard and trusted Nginx implementation.
- Actual TLS backend marker after Start and again after 1.4 seconds without browser activity proves controller finite renew across multiple 600ms windows. Same running active snapshot survives Save revision2/name pending; pending difference is visible. Stop writes durable latch before provider stop, waits bounded owned child reap plus native runtime disappearance, then marks cleanup confirmed. Explicit restart produces newer generation. Separate CLI Stop is observed and cleaned by the running controller. Old events and subsequent Save cannot resurrect it.
- Runtime supports phase/generation/error/cleanup unknown/confirmed and optional first temporary expiry. Cleanup failures block reentry; no generic framework or production activation.

## Evidence

RED before implementation: `python3 homepublish/tests/test-controller.py` exit1, `internal runnable controller missing`. Additional restart test RED: runtime busy; after controller change native EBUSY exposed premature adapter reap, fixed by bounded full child observation. Cross-process Save exposed store busy; tick skips unavailable journal reads (does not renew), native bounded guard remains fail closed.

Ubuntu-24.04 uid1000, cwd `/mnt/d/DevPortal/homelede/homepublish-product`:

```
TMPDIR=/home/eric/homestun-sdk-check timeout 560 make -C homepublish/tests controller product direct guardian-nginx
```

Source commit `2717852`, real exit0, `/home/eric/homestun-sdk-check/controller-full-verified.log`. Controller target actual lifecycle PASS; product/review/recipe/package, both direct TLS matrices and guardian-nginx's 12 records PASS. Existing upstream Lua tmpnam warning remains recipe-only; recipe is not matching SDK acceptance. First shell wrapper returned exit2 because Windows argument expansion removed shell rc variable; the full suite had printed PASS but that wrapper was NOT counted as exit0. Python subprocess wrapper reran exact suite and returned full_exit=0.

## Previous next-slice list (superseded by section above; historical limitations)

1. Controlled Apply candidate→stop/reap→newgen start→journal outcome; preserve original temporary expiry and explicit scope approval. **Apply is not implemented here.**
2. Controller health/TLS readiness before running, truthful crash/error reconciliation, provider unsupported/error and cleanup-unknown executable cases, bounded recovery; current host healthy hook is fixture-only and native READY proves supervision, not TLS readiness. Start sets active to attempted snapshot before provider succeeds; blocked failure reports that attempt, not a verified active publication. Refine before broader UI acceptance.
3. Temporary deadline actual controller integration test (minimum canonical60s); first expiry is persisted and passed as remaining finite guard budget, but this slice's executable test covers continuous only. Wall-clock trust/reboot behavior not implemented.
4. Dual-stack controller/multi-service, DNS/cert maintenance, fw4/UPnP, scoped RPC/LuCI, target packaging and authorized external verification remain.

## Deferred final security reassessment (do not deepen now)

Installation manifest/signature, immutable dependency paths and musl fallback; authoritative TLS source/SAN/chain/key/owner and health/scope; typed durable residual/crash recovery and partial preparation accounting; matching SDK/aarch64/BusyBox/procd/fw4/kernel budget. Historical Stop-repeat readiness remains open, not closed by nonreproduction; no stress expansion. Existing observer/maps fixes retained.

Production ENOTSUP/helper78, product CLI Start/Apply unsupported, renderer activation_ready=false remain unchanged. Only local WSL loopback/source/localcommit; no production install, public network, firewall, UPnP, push, merge or PR. Parent independent final-source verification required.
