# HomeSTUN authenticated mapping publication slice

## Outcome and boundaries
Local native callback → curl → loopback HTTP fixture → actual LeasePortal code → authenticated viewer fixed-host redirect verified. No remote credentials, deployments, public NAT, firewall, router writes, package installation, git commit/push/merge/PR. Mapped does NOT mean externally reachable: neither DNS-to-mapped-IP consistency nor WAN ingress is verified. SDK/ipk and real enabled HomeSTUN integration remain missing.

Historical initial slice (superseded by [final UCI checkpoint](homestun-publication-uci.md)): native integration was explicitly opt-in INTERNAL CLI: append `publish` to `homestun-lease --provision TTL BIND PORT STUN HTTP`. Current source now has default-off UCI/init opt-in and a fixed private-file reference, with isolated registration verified. Independent review and actual enabled integration remain required; do not manually enable against real services. Tests use test secrets only. Fixed origin https://stun-test.innonext.win and nas/files allowlisted redirect domains; mappedIP is validated metadata, not an arbitrary redirect target.

## Protocol / stale protection
Router-auth POST /session {generation,session,expiresAt} reserves a strictly increasing persisted generation and closes old links transactionally. POST /lease additionally requires sequence, mappedIP,port; exact current session/generation/expiry and increasing sequence enforced in storage transactions. Never extend expiry from callback. Old generations, duplicate begins, out-of-order/duplicate callbacks rejected 409; expired/legacy/corrupted leases yield 410 without Location. Legacy two-field POST and unconditional DELETE intentionally unsupported. Router/viewer secrets distinct; viewer cannot mutate. Wall-clock generation means clock rollback/repeated same-millisecond begin can fail closed until clock catches up; no automatic retries/renewal.

Native guardian starts before provisioning, snapshots root-private /etc/homestun/router.token into owned runtime only for opt-in, writes random session and hard monotonic deadline, owns five tracked files, cleans session/token with TLS on expiry. Begin must return HTTP204 before either engine starts. NATMap callbacks inherit only runtime path, not secret. Seccomp pidfd_getfd boundary preserved. Root-private single-link nofollow files and directory validated. Callback validates IPv4 and mapped port>=1024, TCP, matching bind port; ip4p not used. Local address must parse IPv4. Token 32..128 allowed opaque ASCII chars, no newline; root is trusted, never setuid.

Curl receives Authorization/body by anonymous stdin pipe, argv only --disable --config -, stderr suppressed and response body /dev/null. No ~/.curlrc/proxy/CA environment overrides; fixed HTTPS-only protocols, system CA/hostname verification defaults, no insecure/no redirect; connect timeout1s/max2s. Honest curl bounded; guardian TTL additionally bounds production descendants. Package explicitly installs target-built publisher and adds curl+ca-bundle dependencies. Production strict TLS config and real certificate rejection exercised in root WSL network/mount namespaces: system-untrusted chain curl60, fixture-CA-trusted wrong hostname curl60, trusted fixed-host success curl0/HTTP204. CA injection exists only in a compile-time CURL_PROGRAM test shim; production binary still uses system trust and rejects the fixture despite poisoned CA/proxy/HOME environment.

## Pinned upstream contract
Read /home/eric/homestun-natmap-20260214 at exact f8d7996710677c9885c148dda80a42d626f0a17b using per-command safe.directory only. src/hev-exec.c execl(path,path,oaddr,oport,ip4p,iport,mode,iaddr,NULL), ports ntohs decimal, mode tcp/udp. Native passes -e /usr/libexec/homestun-publish. No upstream mutation; no real discovery traffic.

## Actual RED/GREEN
1. Worker /session test RED404 vs401, then GREEN.
2. Delayed session/out-of-order callback RED204 vs409, transactional generation/sequence GREEN.
3. Native fixture RED missing publisher source, real HTTP callback GREEN.
4. Opt-in provisioning RED native exit2 for 8th argument, native callback lifecycle GREEN.
5. Install recipe RED publisher missing, target recipe GREEN.
6. Nonfinite monotonic deadline RED observed unwanted third request, finite check GREEN.
Additional cases: bad IPv4/ports/injection/UDP/wrong bind, wrong router secret, unsafe/symlink token, expired monotonic deadline; real HTTP stall fails within3s (curl max2s).

## Final verification evidence
- docs/homestun-publication-worker-final.txt: Worker8 passed exit0.
- docs/homestun-publication-linux-final.txt: publication3, socket4, lifecycle1, recipe1, package1, cleanup30 passed exit0 (final production source).
- docs/homestun-publication-extra-final.txt: final expanded publication3 and git diffcheck/cleanup readback.
WSL root unshare -n loopback only; Windows node executes actual Worker code via stdio bridge, not a deployed Durable Object. Durable Object storage transactions modeled by local serialized memory fixture, require platform acceptance later. Real HTTP exists in isolated Linux namespace; compile-time curl shim rewrites fixed HTTPS to that HTTP fixture only, cannot be configured in production binary.

## Issues / next review
Transient WSL /mnt/d Python import metadata hung; bounded retries, direct exec of harness source avoids import pycache stat. A throwaway copy command used unescaped shell $p and copied to /homestun; removed only that created fixture, readback required. Fixture random underscores rejected correctly by strict runtime naming; switched to hex names. No leftover daemons intended. Independent security review needed for native ownership changes, secret pipe/FD hygiene, Worker transactions, generation clock behavior, token size boundary, failclosed startup and TLS failure paths. Do not call production approved. Opt-in publication token/session cleanup now fault-injected after both credentials exist: controller, guardian and preparation each SIGKILL/SIGSTOP pass, original token SHA256 and foreign runtime preserved; no engines start while begin is stalled. See security follow-up below. Target BusyBox/procd publication fault injection and independent reviewer remain separate gates.

## Security follow-up: TLS and publication secret faults

Re-run command (root WSL, private network and mount namespaces):

```sh
wsl -u root -- unshare -nm --propagation private bash /mnt/d/DevPortal/homelede/feeds-xiaoqingfeng-homestun/homestun/tests/run-publication-security.sh
```

- `homestun/tests/test-publication-security.py`: three test methods; real cryptographic HTTPS fixture on namespace-local port443, callback credential matrix, six credential-snapshot lifecycle fault subcases.
- Real OpenSSL-generated CA and signed leaf certificates; Python SSL server serves HTTP204 only after TLS handshake. Correct fixed-host leaf without fixture trust fails with actual curl exit60 and zero HTTP requests. Wrong-host leaf with explicit fixture CA fails exit60 and zero HTTP requests. Correct fixed-host leaf with explicit fixture CA succeeds curl0/HTTP204. No HTTPS→HTTP rewrite in this security fixture.
- `CURL_PROGRAM` compile-time test shim alone adds `--cacert`. No production CA injection feature was added. Unmodified production transport separately rejects the private CA even with CURL_CA_BUNDLE, SSL_CERT_FILE, SSL_CERT_DIR, proxy variables, HOME and an insecure `.curlrc` injected. Test shim verifies curl receives only sanitized environment and disabled user config.
- Token sizes31/129/4096 reject before transport; sizes32/128 succeed. Newline, quote, backslash and embedded NUL reject. Token and session wrong owner, unsafe permissions, symlink and hardlink reject with no transport invocation.
- Reproduced RED: sizes129 and4096 were incorrectly accepted because publisher read only the first128 bytes. That intermediate fix was superseded: final publisher and provisioner loop through short reads, retry EINTR, and stop at EOF or the 129th-byte oversize sentinel before validating exact length/content and any side effect. The current token2 suite proves regular/short/EINTR cases on both paths; see [canonical UCI checkpoint](homestun-publication-uci.md). The original security-only step did not change those other components; subsequent supervisor token-loop and UCI changes are documented in the final checkpoint.
- Publication preparation pauses inside the begin adapter only after session and token snapshots exist. Controller/guardian/preparation each receives SIGKILL and SIGSTOP separately; owned runtime including both credentials disappears within the bounded fixture deadline, original token SHA256 and original TLS sources/foreign runtime remain intact, engines never start before begin acceptance.
- Final same-source regression: security3, publication3, socket-boundary4, lifecycle1, recipe1, package1, source-cleanup30, all exit0. Supplemental publication Worker tests2 passed. Intentional seccomp/bind-rejection diagnostics in socket tests are expected.
- Evidence: `docs/homestun-publication-security-red.txt`, `docs/homestun-publication-security-final.txt`, `docs/homestun-publication-security-hashes.txt`, `docs/homestun-publication-security-cleanup.txt`.
- Readback found no new TLS/security/hosts fixtures or fixture processes. Four older source-cleanup directories were preserved and explicitly listed in cleanup evidence; global /tmp cleanliness is not claimed. Empty hosts scratch from the first manual command was removed using rmdir only. Namespace-only hosts override is gone.

No CF deployment, public NAT, firewall, router changes, init/UCI publication enablement, commit, push or PR. Linux/chroot fixtures are not target BusyBox/procd acceptance or SDK/ipk verification. Independent reviewer remains required.

