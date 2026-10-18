# Controller bounded recovery / boot local checkpoint

Baseline `9952df7f17fa20d55ed611701dd4f9eddb0b0f0c`, exclusive feature/homepublish-product.

## Functional ledger

- Internal controller retains approved active_config/revision on provider loss; never consumes a newer saved pending snapshot. Fixed fixture scope is planned again, real per-service TLS/backend readiness is required before running/active_verified. All replacements use new intent/generation.
- Native stop performs bounded reap and requires runtime absence before retry. Cleanup unknown blocks without next_retry; no unknown metadata is silently consumed. The new host's native stop conservatively refuses extant runtime it cannot clean; durable production ownership recovery remains out of scope.
- Three recovery attempts per round, exponential 1/2/4 second wall-clock backoff, cap 4, stable running 30 seconds resets count. Persist attempt_count/next_retry/reason, budget exhaustion blocked. Plan rejection consumes the same finite budget. Start/Apply user operations reset the round. Stop persists disabled/latch first, removes retry and stale events cannot resurrect it.
- Boot restoration is an internal explicit restore() hook, invoked by the non-installed test host only. Default active policy boot_restore=false leaves stopped after old resource cleanup; true requires enabled/no-stop, approved active snapshot, fixed-scope revalidation and readiness before a new generation. No procd production wiring or automatic production boot startup is added.
- Optional functional clock dependency returns now/boot_id/trusted. Default clock is explicitly untrusted, not a production trust provider. Temporary recovery requires trusted readings, matching boot identity and non-regressing time relative to launch; uncertainty/changed boot/expiry stops, never recomputes duration. Test-only clock commands inject readings. Existing temporary Start still uses bounded native monotonic lifetime. Cross-boot temporary restoration is conservatively denied, not inferred from wall time.

## Evidence

- Formal initial real provider PID KILL regression failed with `bounded recovery missing`, runtime blocked/provider unavailable, before implementation: controller-recovery-red.log. The shell wrapper originally masked status, so use the captured AssertionError as RED evidence, not wrapper exit.
- Additional formal plan rejection RED timed out in retry_wait with attempt_count=0; then corrected to consume bounded attempts. Other recovery/boot/clock scenarios are appended regression coverage, not independently proven RED.
- Nonroot Ubuntu-24.04 eric, TMPDIR=/home/eric/homestun-sdk-check, PYTHONDONTWRITEBYTECODE=1: `timeout 200 make -C homepublish/tests controller controller-recovery rpc product` actual subprocess exit0, controller-recovery-final.log and .exit. Existing controller once exercised real 60s natural expiry with established stream and listener closure at original deadline; new recovery target also tests original expiry using explicitly injected fixture clock (not another natural 60s claim).
- New target covers actual owned Nginx PID KILL, short absent listener/runtime interval, new-generation TLS marker; Save pending active marker; Stop queued retry and stale event; start/plan budgets; cleanup unknown; cross-controller restart continuous boot off/on/latch; temporary original deadline and uncertain clock/boot identity.
- Postcommit controller-recovery target is mandatory; evidence controller-recovery-committed.log/.exit, final hash reported by handoff. Previous Lua upstream tmpnam linker warning unchanged.

## Remaining / unchanged release boundary

Production fixed adapter, TLS/DNS/ACME authority and maintenance, INPUT/UPnP, procd/BusyBox/SDK target acceptance, four-page wizard and deployment/public verification remain unfinished. ENOTSUP/helper78, production Start/Apply unsupported and activation_ready=false remain. No new security hardening/manifest scope; consolidated release-risk ledger unchanged. Local nonroot loopback only, no production install, SSH retry, firewall, mapping, external exposure, push/merge/PR.
