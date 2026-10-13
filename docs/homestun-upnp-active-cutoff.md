# UPnP continuously active HTTPS cutoff — final acceptance

**PASS — actual target Nginx 1.21.3, independent public TLS client, continuously active application stream, native 120-second cutoff, and bounded cleanup.** This closes the previously unproven active-connection gate; it does not validate STUN hole punching or a permanent UPnP adapter.

## Executed scope

- One generation: `homestun-upnp-20261012T122756Z`. Exactly **one AddPortMapping**, requesting **300 seconds**, `18444/TCP → 192.168.1.2:18444`, empty RemoteHost. Initial and immediately-before-Add exact-key queries returned **714**. Readback matched internal address/port, enabled flag and generation, with **299 seconds remaining**. No renewal, permanent fallback or DeletePortMapping.
- Public client connected directly to `60.20.170.34:18444` from the independent Beijing network, not through SSH. Hostname `homestun-test.homelede.com`, explicit fixture CA and unique marker all verified. Initial HTTPS returned HTTP 200 and the exact marker; held connection independently used Python certificate and hostname verification.
- Router's actual `/usr/sbin/nginx` was copied unchanged into the isolated chroot: **1.21.3**, SHA256 `d24cceeb3b33fb61545b7c50b49be6299167959ffcdebf6d765dc4a67bb3d0f1`. This is not the prior WSL SDK Nginx 1.26.1 test.
- Original IPK native lease payload retained: SHA256 `540b98eb8be0ed039d9f8bb19b52d287f1b5c7d594321b397e3d8783e50072a4`. Local 300-second invocation was rejected with exit 2; real local TTL remained **120 seconds**, including setup after native launch. Previously verified seccomp boundary and socket-only SO_MARK=255 forwarder were unchanged; Passwall2 stayed enabled. No package installation, production code/configuration, firewall, routes, DNS or Cloudflare changes; no commit/merge/push. Management 22/80/443 and the pre-existing 60022 path were not modified or retested.

## Streaming prerequisite and cutoff evidence

The old `limit_rate 1` static return body was removed. A test-only static C backend binds **loopback 18081**, emits immediately flushed HTTP chunked numbered heartbeat lines every **2 seconds**, and includes the unique marker and source monotonic timestamp. Nginx uses HTTP/1.1 proxying, `proxy_buffering off`, no `limit_rate`, and read/send timeouts **240 seconds**.

The backend stream lasts **182 seconds per connection**, not 120; it has a separate **210-second process-group alarm** and child 190-second fail-safe. It was also explicitly stopped after cutoff evidence. Before any public Add, actual target verified TLS delivered **6 ticks over 10.000969 seconds** in an 11.377667-second bounded observation. Local TDD first failed for missing streaming backend, then static `gcc -Wall -Wextra -Werror` build and real six-tick 10-second test passed.

Public held TLS result:

| Measurement | Observed |
|---|---:|
| HTTP response | 200, Nginx 1.21.3, chunked |
| Received bytes, including HTTP/chunk framing | 4619 |
| Consecutive numbered application ticks | **53**, no gaps/reordering |
| First received tick since native launch estimate | 15.278363 s |
| Last received tick since native launch estimate | **119.291786 s** |
| Inter-tick receive-gap range | **1.938741–2.063616 s** |
| EOF since native launch estimate | **120.128582 s** |
| Last tick to EOF | **0.836796 s** |
| Native supervisor exit | 0 |

The target wrote `/proc/uptime` immediately before native launch. A bounded SSH uptime correlation estimates the native start in the client's monotonic clock, with **±0.159489-second measurement uncertainty**, plus the uninstrumented small shell-to-exec scheduling interval. The Windows launcher-to-supervisor-exit interval was separately **120.583169 seconds**; do not confuse it with the correlated EOF measurement or claim exact nanosecond deadline proof. This is an observed bounded cutoff near the configured native deadline, not a guarantee against kernel stalls or total guardian failure.

Crucially, after public EOF the independent backend **still delivered two fresh marker-bearing ticks** through its loopback endpoint. Thus source TTL/EOF did not terminate the public held connection. The final real application tick was less than one second before EOF; 240-second Nginx idle timeouts cannot explain this continuously active 120-second cutoff. A new public attempt then failed with **curl exit 7 / Connection refused**, while the gateway entry was still owned and live.

## Gateway expiry and cleanup

Read-only exact-key observations showed the gateway entry still present after local cutoff and later at Add +296.911 seconds with **3 seconds remaining**. First absent observation was **714 at +312.275 seconds** (reported outer completion +312.277 seconds); final exact query again returned 714. The sampling interval brackets natural expiry; it does not assert expiry occurred exactly at the observation timestamp. No Delete was needed.

The native snapshot/lock was absent before fixture removal. Final run readback and a separate SSH readback verified:

- `/tmp/homestun-test/upnp-active` absent, parent directory empty, including fixture private key removal.
- No 18444/18443/18081 listeners; no owned `/proc/*/{root,exe,cwd}` references or mounts.
- Dedicated backend and native/Nginx/forwarder processes gone; `ubus` HomeSTUN service query returned `{}`.
- Management 22/80/443 retained. Persistent firewall/network/passwall2/HomeSTUN configuration hashes, nft table/chain/rule structure (counters normalized; dynamic set elements excluded), and policy routes unchanged.

Independent cleanup query initially hit Windows/bash JSON quoting; the read-only `ubus` query was corrected by stdin script and returned `{}`. This did not create or alter a service. Retained local PEM is only the public test certificate, not a private key.

## Reproducible evidence

- [Machine-readable timeline and cleanup](homestun-upnp-active-cutoff.json)
- [Independent cleanup readback](homestun-upnp-active-cutoff-cleanup.txt)
- [Executed one-shot harness](homestun-upnp-active-cutoff-run.py) — **do not rerun without fresh authorization**; would create another public mapping. SHA256 `7eaabf7746b3c6462c27b5e0c8320db912295ffc84841daab8814aca090cbf8c`.
- [Test-only backend source](homestun-upnp-active-backend.c), SHA256 `9394edbf7eb951e8f3725259a7d671741e2862abf53f6ee4b97af2b7bc66919f`; binary/transfer SHA256 `8be9fbd5893bdb21e47d097722fa7d91e163de5f790f5db07751b0455f9fd2b7`. Static WSL-built test helper, not an installed SDK package.
- Private bounded SOAP/SSH/native/backend logs: `artifacts/upnp-lease-private/active-cutoff/`. Prior zero-byte result remains historical in [previous final report](homestun-upnp-lease-final.md).

Remaining independent gates: permanent UPnP lifecycle implementation, full enabled production/procd integration, Cloudflare deployment and STUN ingress. None are implied by this synthetic explicit-UPnP acceptance.
