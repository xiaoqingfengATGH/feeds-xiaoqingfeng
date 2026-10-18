# HomeSTUN implementation evidence

## Stage 0 — scope and environment

REQ-001 registered before implementation. Branch `feature/homestun`, base `89534896304df50ba6eaf8fe98944d04d6b32539`; original repository untouched.
Inspected HomeTunnel Makefile, UCI defaults, procd service and LuCI settings/menu layout. Reuse independent feed/procd/UCI patterns, not cloudflared controls/metrics.

Remote read-only inspection: HomeLede v2026.10.01 / OpenWrt 24.10.5, kernel 6.18.55, x86_64 VMware, nginx 1.21.3 TLS support, Lua/ucode/openssl installed. NATMap absent. Router is 192.168.1.2, default gateway 192.168.1.1; management nginx listens 80/443. `/tmp` free ~891MiB. No package install, firewall change, CF write, or public service exposure authorized/performed.

First slice uses Lua (available on target) for strict config validation/nginx generation, JS module Worker with Node built-in tests. Production runtime remains disabled until independent TCP proof and lifecycle gates pass.

## Stage 1 — core and Worker RED/GREEN

Lua target tests: initial missing core failed, minimal acceptance passed; strict validator failed on management port before implementation, then 14 checks passed. Renderer missing-function failure preceded implementation; 15 checks now pass on the actual router Lua runtime. Generator emits a standalone config with dedicated PID/temp paths, default-deny host, explicit loopback/private listener, TLS and multi-host upstreams. Private HTTP upstreams only in this first slice (HTTPS upstream verification not implemented). Ports below 1024 are rejected; arbitrary management high ports still require operator review.

Node Worker tests: missing module RED → secret-missing fail-closed GREEN; authenticated publication RED → GREEN; expiration/validation/error tests RED (302 instead of 410, 204 instead of 400, uncaught malformed JSON) → GREEN. 5 tests pass. Durable Object class uses one lease, fixed two-host allowlist, separate router/viewer bearer roles, 120s maximum, no-store responses, bounded 512-byte parsing, revocation and unavailable-storage fail closed. Test storage is an in-memory adapter; this proves handler logic, NOT Cloudflare deployed persistence.

## Security iteration — SEC001

Added a leading-dot hostname regression before changing production code. Actual router RED: `lua /tmp/homestun-test/test-core.lua /tmp/homestun-test` failed `must reject leading-dot wildcard hostname`. GREEN after rejecting the first empty label: all 16 assertions passed (test numbering corrected below). Real nginx unknown-subdomain/Host checks remain to be run with the hardened runner.

## Recovered security continuation — in progress, release still blocked

Authenticated execution recovered. Router Lua: 16 assertions passed. Real nginx smoke: multi-host proxy, unknown/subdomain Host denial, expiry passed. Expanded SEC002 suite: runtime symlink, cert/key group-write/world-read/attacker ownership rejected; actual original nginx.conf/cert.pem/key.pem overwritten after snapshot, copied TLS bytes/modes checked, fresh TLS handshake returned 502 with backend stopped, lock removed.

Real SEC003 RED: guardian SIGKILL left TLS listener beyond TTL. Fixed controller monitoring, shared phase group, child parent-death protection, group kill/cleanup on guardian abnormal exit. GREEN: stopped controller past TTL, nginx exit, established TLS connection closure, guardian death, TERM and controller SIGKILL all passed on router. Snapshot fsync fault injection RED stranded runner.lock; moved snapshot work to monitored guardian and registered error cleanup. GREEN: fsync failure removes lock; delayed preparation bounded by startup deadline. Full final-version rerun and further crash-window/reaping review still outstanding. No commit/push/merge/PR, firewall/package/Cloudflare/management changes.

## Final security continuation — isolated regression complete, release blocked

Reproduced preparation-crash RED, then fixed monitored preparation and the separately reproduced mkdir/publication crash window. Final current-version builds (static gcc -Wall -Wextra -Werror) passed; Worker 6/6, router Lua 16 checks, all 9 router scripts with 33 explicit PASS lines passed twice. SHA256 readback matched 15 transferred files and 2 binary aliases. Final authenticated cleanup verified no test processes/listeners and removed the complete isolated fixture including TLS private key/certificate; existing SSH22/uhttpd80/dropbear443 remained unchanged. Exact output, hashes and cleanup are in homestun-final-regression.txt, homestun-final-hashes.json, homestun-final-inspection.txt and homestun-final-cleanup.txt; detailed fixes/limits/reproduction are in homestun-security-checkpoint.md. Earlier results above are historical, not the final acceptance record. STUN/TCP NAT, CF deployment and packaging/procd/LuCI remain unverified; no production-complete claim.

## Package/UCI/procd slice — REQ-001 checkpoint

- Package RED: `test-package.py` failed missing OpenWrt Makefile. GREEN: target-compiler recipe and disabled/approval-off defaults pass. Real compile/install macro-harness test passed, installed ELF helper and executable init script, no tests/host `.bin` files installed; this is NOT an SDK/ipk build.
- Adapter RED on real router: `test-config.lua` failed missing adapter. GREEN: disabled/approval gate, TTL 1..120, separate non-management ports, loopback target, discovery arguments, dedicated TLS paths and hostname/upstream validation pass. Real isolated UCI directory smoke passes disabled/no-procd, unapproved rejection, approved host rendering and honest status (`mapped=unknown`, `reachable=unverified`). No `/etc/config` writes occurred.
- Native lifecycle RED: chroot fixture returned 2 for coordinated arguments. GREEN: actual native helper starts foreground TCP NATMap + nginx in one monitored phase group; both processes are collected at TTL and snapshot lock removed. Either engine exit fails the lease; no daemon/respawn/auto-renewal. Fixture executables do not open sockets or query DNS. The original nginx-only interface remains supported.
- NATMap 20260214 upstream cloned recursively outside repository at `/home/eric/homestun-natmap-20260214`, revision `f8d7996710677c9885c148dda80a42d626f0a17b`, task submodule `8d83bbbf79557138726c8ee5a5fae99cbb978d61`. Static native build passed with upstream glibc `getaddrinfo` static-link warning; binary was NOT installed or executed on router. TCP forwarding uses `-4 -b <bind> -s <stun> -h <http> -t 127.0.0.1 -p <TLS-port>`; callback contract documented separately. No public TCP success claim.
- Final modified helper rebuilt with `-static -Wall -Wextra -Werror`; Worker 6/6, router Lua 16 checks and all 9 original security router scripts passed again. No firewall, Cloudflare, package installation, management configuration or public listener changes.
- Environment boundary: Windows/WSL source tree has no usable OpenWrt `.config`, `include/package.mk` or populated `staging_dir` (Python filesystem read, not shell status). True SDK/ipk dependency resolution/target ABI/install remain unverified. Initial standalone fault-fixture compile failed missing `main`; corrected by linking fault injection with helper, final full regression passed.
- Remaining: actual procd enabled-instance integration, additional coordinated-engine fault matrix, true SDK build, LuCI, authenticated mapping callback/publication, temporary production source TLS cleanup policy, and independent external TCP feasibility. Existing temp source TLS copies are root-private but retained after a production lease; do not approve production activation before retention/cleanup review.

## Next gates

1. Strict RED/GREEN validation, nginx generation and Worker lease handling.
2. Isolated `/tmp` deployment, nginx syntax and loopback multi-host test, cleanup.
3. NATMap availability/build and external probe require parent scope approval; no STUN-only success claim.
4. Lease-driven procd integration, credential storage, LuCI settings/status, SDK packaging validation, independent review.
