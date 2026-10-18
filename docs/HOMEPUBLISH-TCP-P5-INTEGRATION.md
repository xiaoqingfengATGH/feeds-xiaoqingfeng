# P5 production integration checkpoint

## Current continuation discovery (private engines / four-protocol slice)

Verified branch feature/homepublish-product HEAD 7ac1fe8 with pre-existing dirty P4/P5 work retained. Target has no private engine directory and production adapter explicitly rejects non-HTTPS. Built WSL artifacts are x86-64 musl ELF; NEEDED nginx: pcre2/ssl3/crypto3/z/gcc/libc; sslh: pcre2/cap/gcc/libc. Business RSA SAN contains only home.iwonderful.top. Live journal remains revision1/intent7 disabled/latch/stopped. No target writes yet in this continuation. Next: back up fixed destinations and journal, deploy verified artifacts, target capability test, RED four-protocol production plan, server-owned internal port allocation and private-journal lifecycle. TLS passthrough transport readiness must not assume arbitrary passed-through application is HTTP or shares ingress certificate identity.

## Resume batch: private engines deployed

Actual target readback verified original journal SHA unchanged and publication group absent. Backed up live bytes and installed adapter/runtime to `/root/homepublish-p5/resume-backup`. Deployed only fixed `/usr/libexec/homepublish/{nginx,sslh-select}` with exact documented SHA256. Target execution confirms Nginx1.30.6 with HTTP SSL/realip + stream SSL/preread; sslh2.3.1 commit with proxyprotocol/cap/config. All NEEDED libraries present; runtime OpenSSL3.6.4. Evidence `resume-engine-deploy.log`. No system engine replacement. Four-protocol RED/implementation next; no lifecycle GREEN yet.

Four-protocol production plan RED captured (`four-production-red.log`: explicit unsupported capability); after server-owned ephemeral loopback port allocation, installed real production plan GREEN (`four-production-plan-green.log`). First allocation attempt exposed nixio getsockname tuple (not table), corrected and rerun. Runtime lifecycle and TLS passthrough protocol-correct readiness still pending; current installed runtime retains HTTP-based passthrough check and must not be claimed GREEN. Next bounded batch must add opaque-TLS readiness RED before replacing that check, then real four-protocol Start/traffic/held-session Stop EOF. No live journal mutation or publication Start has occurred in this resume batch.

## Final resumed target tracer result

Final exact deployed bytes ran through private native journal + unchanged installed production adapter/procd. Four services all ready in one generation; HTTPS system-CA+hostname marker `P5_PRODUCTION_A`, raw echo and SSH banner held sockets followed by Stop EOF passed. `run-device-tcp-p5-four.py` exit0; evidence `four-run.log`, `four-production-lifecycle-attempt.json`, `four-final-source-sha256.json`, `four-final-readback.log`. No fixture marker/profile or fixed internal ports. Initial actual Start failed because renderer emitted fastcgi/uwsgi/scgi temp directives absent from minimized engine; removed unused directives. Next actual RED had HTTPS/SSH/TCP ready but opaque TLS not ready (HTTP/CA assumption). Changed only opaque passthrough readiness to bounded openssl SNI TLS handshake; HTTPS verification unchanged. Target now requires openssl CLI for this readiness (package dependency still needs adding before packaging).

Final Stop confirmed, publication/backend procd objects and runtime absent; all 50881/50882/50885–50888 listeners absent. Live journal remains exact SHA64fdd7f00450e683e460215f2fda4054f27152d1d1d2bbe24ed1945e06178dba. Retained private four-service saved configuration; no global firewall/routes/DNS/auth/UPnP/IPK/commit changes.

**Not complete overall:** held HTTPS/TLS EOF not yet tested, TLS payload transparency/negative-SNI tests not yet added, full native SSH authentication not proven (banner backend only), four-family matrix/no-HTTPS combinations and ordinary RPC/browser success chain pending. New TLS probe parses OpenSSL output; adversarial parser failure coverage and explicit openssl-util package dependency remain follow-up gates. Do not call this full four-protocol product acceptance. No frontend changes by this worker.

## Frozen backend API / ownership (batch 1)

- Provider is fixed installed `product-system-provider`, not RPC-selected. Reuse `product-v2-runtime` and `product-procd-group`; no new guardian.
- Engine owner handoff: reserve `/usr/libexec/homepublish/nginx` and `/usr/libexec/homepublish/sslh-select`. Backend will prefer this installed Nginx; HTTPS-only may use the existing `/usr/sbin/nginx` when its actual compile capabilities suffice. No `/tmp` engine, marker, fixture trust or fixed 495xx selection is production authority. Missing stream/sslh is an explicit capability refusal, not enabled evidence.
- Canonical listener network/address is resolved by actual inventory before rendering and during renew. No address narrowing. Backend endpoints/ranges derive from validated services. Certificates resolve server-side through device-integrations, snapshots private, normal system CA readiness.
- Production service name `homepublish-runtime`; owned runtime `/tmp/homepublish-runtime`. Mixed-only internal ports are allocated server-side, not user supplied.
- Keep original live journal (currently SHA256 `64fdd7f00450e683e460215f2fda4054f27152d1d1d2bbe24ed1945e06178dba`) untouched for private-journal tests. No firewall/routes/DNS/auth/UPnP/public changes.

## Discovery

B1 reproduced in source: production plan unavailable; CLI marker-gated; daemon fixed device provider. Target standard procd/controller service currently absent. System Nginx 1.21.3 has HTTP SSL but no stream/realip; private product engine directory absent. Private journal native store already exists under P3. Actual session RPC supports create/grant/access/destroy, permitting short-lived scoped test sessions without changing auth files. No credentials requested or logged.

## Batch 2 actual target evidence

- RED: installed production plan failed `production provider unavailable` (`docs/evidence/tcp-p5/production-red.log`). GREEN: unchanged installed production adapter starts with system Nginx through standard `product-procd-group`, no test marker/profile or fixture trust.
- Private native journal retained/backed up at `/root/homepublish-p5/private-state.before`, test saved configuration retained in existing scoped store. Actual `192.168.1.2:50881` HTTPS→`127.0.0.1:50882` A marker, Save pending retains A, Apply→50883 B, Stop confirmed. Second actual eligible ULA `fd89:878e:a47f::1:50884`→IPv4 B also passed. Business certificate system CA + hostname verified; no custom CA flag.
- Publication group/runtime absent after Stop; owned backend procd stopped. Source backups `/root/homepublish-p5/*.before`; nonsecret backend config/test CLI retained. No frontend or package Makefile edits.
- Ordinary daemon/CLI now fixed production provider with marker gating removed. Standard `/etc/init.d/homepublish start` registered a real idle procd controller; an already stopped journal is not rewritten at startup. Live journal hash still exactly original above.
- Real HTTP `/ubus` short-lived session test reached rpcd: readonly status allowed and readonly/anonymous start returned JSON-RPC `-32002 Access denied`. Initial assertion incorrectly expected `result:[6]`; target uses an error object, corrected full matrix pending. Sessions from both attempts destroyed; no auth/ACL files changed.
- Production capability currently **HTTPS-only**. Other enabled protocols explicitly return `production stream/multiplex capability unavailable`; four-protocol B1 is not closed. Product engine owner must coordinate next slice before enabling stream/multiplex.

## Final bounded result / rerun

`python D:/DevPortal/homelede/homepublish-product/homepublish/tests/run-device-tcp-p5-production.py` exited **0** on the final driver, printing `P5_HTTPS_PRODUCTION_AND_REAL_RPCD_SCOPED_GREEN`. Evidence: `docs/evidence/tcp-p5/production-and-rpcd-final.log` and `production-final-source-sha256.json` (three newly deployed Lua source files only, not a whole-tree freeze). `git diff --check` exited 0. Existing dirty P4 shared runtime/controller were reused, not rewritten.

Real HTTP `/ubus` matrix completed: anonymous and read-only denied each save/stop/start/apply (`-32002`); readonly allowed status/network_inventory/validate/certificates; scoped write Start/Apply reaches controller and rejects approved=false, stale revision rejected. Sessions were created/granted/destroyed using existing rpcd APIs with exact homepublish methods derived from installed ACL, no wildcard grants, no auth file changes. This verifies actual session method enforcement, **not** username-to-LuCI-role login mapping. No SSH-to-JSON-RPC bridge or Playwright interception.

Source business certificate/key hashes and ownership/mode were compared server-only before/after; no private material exported. All test listeners 50881–50884 absent, publication procd group and private TLS runtime absent after Stop. Idle standard homepublish controller remains running, intentionally no publication; existing saved revision1/intent7/manual latch/stopped journal and management/network configuration hashes unchanged. Test config and nonsecret backend files retained. Initial pre-fix plan failure and initial incorrect error-shape assertion preserved as described; corrected final test passed.

### Explicit remaining boundaries / next small batch

1. **B1 partially repaired, not closed for four protocols.** HTTPS production plan/Start/Save/Apply/Stop with two real eligible LAN bindings is working via unchanged installed provider + scoped native journal. Stream/TLS passthrough/SSH/raw TCP deliberately remain capability-unavailable. Coordinate engine owner on installed private paths and compile modules, then allocate mixed internal ports server-side and implement the next runtime slice; do not promote fixture binaries or fixed ports.
2. Ordinary installed rpcd→CLI→standard daemon→production provider was exercised through read/status and safe rejected write requests. Full successful ordinary-route Save/Start/Apply/Stop was **not** run because original revision1 intent7 journal was explicitly preserved. Parent must coordinate a backed-up merged retained test configuration if choosing to exercise those mutations; do not overwrite original with private state.
3. No full P3/P4 regression, browser controls, held-session EOF, fresh non-loopback remote LAN client, multi-host certificates, package build/install or public reachability acceptance in this bounded batch. Dedicated tests use local clients addressing actual LAN v4/ULA sockets, not external ingress.
4. H2 safety/provenance gate remains: existing system Nginx 1.21.3 is a functional fallback, **not** a security-approved release dependency. Production adapter prefers `/usr/libexec/homepublish/nginx` if installed; coordinate reload/owned cleanup before changing engine path while a generation runs. No broad ACL/auth/firewall/routes/DNS/UPnP changes and no commit/push/merge.

