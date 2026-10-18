# D2a implementation checkpoint

Scope: local-only renderer/backend slice; Start/Apply remain unsupported. No guardian, firewall, router, mapping or production activation.

Discovery: baseline ab57f163de613cc8601d156b8f6af16afe678bbb clean. WSL has no system nginx; cached SDK nginx 1.26.1 runs using cached musl loader/library path. Lua5.1 available under local-tools. No installation/network needed.

Plan completed as a local internal slice: direct-address/backend/renderer + Lua fixture + real Python TLS test + tests/Makefile. Mid-slice commit 97fb603. Final `make -C homepublish/tests direct product` in WSL with TMPDIR=/home/eric/homestun-sdk-check exited 0: four family combinations plus controlled hostname, POST exactly-once on upstream failure, unknown Host/SNI rejection, process/listener/certificate cleanup, and existing product/review/recipe/package regressions. Full evidence and remaining blockers in HOMEPUBLISH-PROGRESS.md. Start/Apply unchanged unsupported; activation_ready=false. Authoritative production DNS/ownership/roles/TLS readiness, TTL refresh/replacement, guardian/controller remain unimplemented. Fixture loopback bypass of canonical ingress prohibition exists only in non-installed internal test caller; never a production permission.

Original plan: vertical TDD (1) static backend selection, (2) literal-listener direct renderer, (3) isolated real TLS four-family matrix + rejection and POST no replay. Trusted providers are injected only by internal Lua caller, never client wire; their fixture assertions do not prove DNS, ownership, role, certificate readiness. Keep product activation blocked. All runtime binds loopback and temporary certificates/processes cleaned and read back.

## D2a independent review closure (after 2ef5be5ab7488e65f85e02f85f2340748d4171be)

Local fix commit is the commit introducing this section (`git log -- docs/HOMEPUBLISH-D2A-CHECKPOINT.md`). Product remains incomplete; next stage is the independent finite-capability guardian/controller, not activation.

- Finding 1: `$host` prioritizes absolute-form request authority over the raw Host header. Review reproduced `SNI=service.home`, absolute authority `service.home`, `Host=unknown.home` reaching upstream. Policy now rejects **all absolute-form** (including same-domain), authority-form and asterisk-form requests: this is a reverse proxy, not a forward proxy. Only origin-form enters the service.
- Finding 2: case-sensitive SNI equality rejected valid `SERVICE.HOME`. SNI now matches a strictly anchored case-insensitive validated hostname pattern; dots render as `[.]`, not wildcard or fragile Nginx backslash escapes. Default unknown-SNI TLS handshake rejection and client CA/SAN verification remain intact.
- Raw Host is mandatory and case-insensitively exact. Optional port must be canonical decimal and equal the actual listening socket's `$server_port`; absent port is legal. Empty/nonnumeric/zero/out-of-range/leading-zero/different ports, trailing dots, suffix/prefix and wildcard-dot lookalikes are rejected. This deliberately does not yet allow a differing externally translated port; a future authoritative mapping/controller contract must explicitly implement that policy before activation, not loosen this internal slice.
- `test-direct-boundary.py` + `direct-boundary-fixture.lua` are project regressions registered in the `direct` Makefile target. Two distinct SAN certificates and two separately counted/marked backends exercise IPv4/IPv6 ingress against IPv4/IPv6 backends. Every rejected origin/absolute Host/authority combination asserts both GET counters unchanged; accepted service checks require exactly its own backend +1 and the other +0. Uppercase/mixed Host/SNI and Host:actual-port pass. HTTP/1.0 missing Host, unknown/lookalike SNI, malformed ports/names and three absolute URI scheme spellings also reject. Process/listener/temp certificate cleanup is read back.

### Actual vertical TDD evidence

All commands used WSL cwd `/mnt/d/DevPortal/homelede/homepublish-product` and `export TMPDIR=/home/eric/homestun-sdk-check`:

1. `python3 homepublish/tests/test-direct-boundary.py absolute`: RED exit 1, approved absolute URI reached backend (`[1,0]` versus required `[0,0]`); origin-form-only guard then GREEN exit 0 in all four family combinations.
2. `python3 homepublish/tests/test-direct-boundary.py case`: RED exit 1, uppercase SNI produced empty response and `[0,0]` versus `[1,0]`; anchored case-insensitive SNI guard then GREEN exit 0.
3. `python3 homepublish/tests/test-direct-boundary.py port`: RED exit 1, `service.home:0` reached backend; raw Host/socket-port map then `python3 homepublish/tests/test-direct-boundary.py all` GREEN exit 0.
4. Final expanded/registered tests: `make -C homepublish/tests direct product` exit 0. Original direct TLS/four-family/controlled-hostname/POST-no-replay regressions, new boundary matrix, product review, product (including unsupported Start/Apply), recipe and package all passed. Recipe/package each `Ran 1 test ... OK`. Existing upstream Lua `tmpnam` linker warning persists; recipe remains temporary macro-fixture smoke, not system installation or matching SDK/IPK acceptance.

No production/public-network/install/router/mapping/firewall/route/Cloudflare/push/merge/PR changes. `activation_ready=false` and Start/Apply unsupported are preserved; authoritative TLS readiness, DNS refresh/ownership roles and guardian remain blockers.
