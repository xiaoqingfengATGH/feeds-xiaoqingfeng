# Controller multi-service local functional checkpoint

Baseline: `56bc5fac2a604b67e0003afccf2bf8f9be03a59d`, exclusive feature/homepublish-product worktree.

## Runnable acceptance

- Added `make controller-multi`; `controller` now runs existing single-service acceptance plus multi-service acceptance.
- Actual canonical → journal → internal controller → full renderer plan → one fixed cached SDK Nginx provider. Independent service.home/second.home SAN certificates and keys copied into native-owned TLS slots under **HP_CONTROLLER_MULTI_TEST only**; production file set/activation remain unchanged.
- Canonical private IPv6 fd00::2 ingress/fd00::3 backend map only in the non-installed fixed host adapter to ::1. No production validator changes. Actual loopback v4→v4, v6→v4, v4→v6, v6→v6 TLS backend markers pass.
- Runtime service_id map records hostname/ready/generation. Multi-service readiness requires individual results; active snapshot switches only after every service is ready. Failed second readiness closes all traffic; historical active_revision is not claimed running (active_verified=false); attempted/candidate remain explicit.
- Save changes first service only and retains both old streams/markers until Apply. Apply stop/reap then starts the entire generation: **brief downtime, not zero-downtime atomic reload**. Deletion pending still serves old hostname, after Apply old SNI is rejected. Unknown SNI stays rejected.
- Stop closes established streams for both hostnames, both family listeners, and native runtime before fixture deletion. Source certificates and test directory removed by bounded harness scope.
- Multi-service temporary Save/Apply preserves first deadline without another 60s wait. Existing single-service real 60s natural expiry/live-stream acceptance ran once in full regression.

## TDD / execution evidence

Initial fixture corrections: explicit addressFamily required for IPv6; canonical correctly rejects ::1 backend/range, so fixed private scope mapping is used (validator unchanged). Genuine RED after valid canonical Save: test-controller-multi.py exit1, `multi-service controller missing`, response `fixture scope denied` (old single-service adapter).

GREEN nonroot Ubuntu-24.04 user eric, cwd /mnt/d/DevPortal/homelede/homepublish-product, TMPDIR=/home/eric/homestun-sdk-check, PYTHONDONTWRITEBYTECODE=1:

- `make -C homepublish/tests controller-multi` exit0.
- `make -C homepublish/tests controller rpc product direct guardian-nginx` exit0; `/home/eric/homestun-sdk-check/controller-multi-full.log` (includes real 60s expiry).
- Final refinement `make -C homepublish/tests controller-multi rpc product direct guardian-nginx` exit0; `/home/eric/homestun-sdk-check/controller-multi-final.log`.
- Postcommit `controller-multi` to be read back in handoff; log `/home/eric/homestun-sdk-check/controller-multi-committed.log`.

Existing Lua recipe upstream tmpnam linker warning is unchanged. Tests are local acceptance, not matching production SDK/IPK or public reachability.

## Next interface, explicitly not implemented

Bounded recovery: consume persisted desired/manual-stop latch, approved service set/scope, attempted generation and original temporary expiry; enforce finite attempt budget/backoff before revalidate→new-generation replace. Stop/expired/stale generation may never restart. Trusted clock/boot: supply boot identity and trustworthy remaining deadline; uncertain temporary remaining time must stay stopped, boot_restore remains default false. This round adds neither recovery nor clock provider and does not claim production Start readiness.

Production provider remains ENOTSUP, CLI/RPC Start/Apply unsupported and renderer activation_ready=false. Production TLS authority, INPUT/UPnP, procd/BusyBox/matching SDK, DNS/ACME maintenance, Passwall2 and external reachability remain unimplemented/unverified. Security deepening deferred to consolidated assessment. No production install, firewall, mapping, external exposure, push/merge/PR or retry of refused test SSH.
