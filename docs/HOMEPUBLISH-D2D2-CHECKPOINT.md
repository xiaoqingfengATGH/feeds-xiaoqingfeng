# D2d2 fixed OpenSSL/provider authority subset (local, not activated)

Baseline: `cdfa83503216bc0840932a29afcca86261d9e95d` plus the local D2d2 changes below. Only WSL non-root loopback tests and local commit; no installation, production helper, firewall, UPnP, public probe, push, merge, or PR.

## Closed in this slice

- `trusted-nginx.c` now creates a server-owned fixed empty `openssl.cnf` (slot 11), and passes only fixed `PATH`, `LANG`, `OPENSSL_CONF=<owned runtime>/openssl.cnf`, `OPENSSL_MODULES=<owned runtime>`, and `OPENSSL_ENGINES=<owned runtime>` to the verified loader. The hostile `LD_PRELOAD`, `LD_LIBRARY_PATH`, `OPENSSL_CONF`, and client-manifest values injected before startup cannot reach this exec payload. The owned module/engine root has no loadable module; the config is not `/etc/ssl/openssl.cnf`.
- The same native ledger now reserves `openssl.cnf` and non-secret `provider-init.trace` (13 fixed file slots total; five existing temp-directory slots). Cleanup, FD allowlists, preparation, and fixture ownership all follow the ledger; no recursive deletion was added.
- The real cached Nginx TLS fixture passed IPv4/IPv6 TLS, renewal/worker respawn, temporary cutoff, controller/guardian/watchdog STOP/KILL, stream closure, listener refusal, native runtime absence before fallback, foreign inode/source TLS preservation, and 0 internal channel errors.
- Test-first evidence: the new D2d2 assertions initially failed because `OPENSSL_CONF` and `openssl.cnf` authority were absent; after implementation `test-guardian-nginx.py`, `test-trusted-provider.py`, and `test-owned-runtime.py` passed. The integration trace is a product-side fixed-exec payload record, not a claim that ptrace itself is a same-UID contract boundary.
- ELF map checks are exact-set checks for every live master and worker and for respawned workers: the five owned runtime libraries plus sealed loader/Nginx memfds, with no cached SDK path or unknown candidate. FD-role maps and worker NoNewPrivs/seccomp metadata are retained in the D2d2 evidence JSON. This is stronger than a grep-only SDK exclusion.

## Exact local verification

WSL non-root:

```text
python3 test-guardian-nginx.py                         exit 0
python3 test-trusted-provider.py                       exit 0
python3 test-owned-runtime.py                          exit 0
```

The guardian integration produced eight lifecycle cases plus renewal/respawn records and `provider-init.trace` evidence under `/home/eric/homestun-sdk-check/d2b2-nginx-evidence` during the run. The final run’s output included `PASS guarded Nginx integration including internal channels`.

## Remaining gates / safe claim

This is a real vertical subset, not complete dependency authority. The target installation manifest/signature, target kernel-supported immutable path or mount gate, target OpenSSL provider/engine/module layout across supported OpenSSL versions, target aarch64/musl SDK, BusyBox/procd, and production controller/TLS/SAN/health/scope/journal integration remain unverified. Nginx config semantic provenance still belongs to the trusted renderer; this test does not turn arbitrary Nginx text into a trusted parser or claim generic `load_module`/`include` policy closure. Do not infer a hostile-filesystem or same-UID/root boundary from ptrace/maps.

Because the target dependency and immutable-path gates remain open, production `hp_trusted_nginx_*` remains `ENOTSUP`, `activation_ready=false`, Start/Apply unsupported, and helper exit 78. No activation claim is made.
