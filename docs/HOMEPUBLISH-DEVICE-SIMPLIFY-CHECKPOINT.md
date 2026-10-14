# Simplified device controller/provider acceptance

## Current outcome
Lua controller + standard procd dedicated Nginx built and installed; real root-local scoped ubus Start → Save-pending → Apply → Stop passed on OpenWrt. This is the fixed device internal test profile (loopback 49284, fixture backends 49285/49286), NOT public production publication or finished LuCI Start/Apply buttons. No new safety foundation, firewall/UPnP, proxy, routing or business certificate changes.

## Source/package binding
Runtime source commit `5ee89fd` on feature/homepublish-product; later commits update tests/docs only. Cached official SDK24.10.5 x86_64, shared build.lock, fresh ext4 git archive; TARGET_CC native journal retained. Final homepublish0.1.0-r3 SHA256 `eadca6be45d11a34753accefdb4f96115d4b4223c4f9b78e65cd18794be7e281`; luci-app-homepublish0.1.0-r3 `ebba68d1123f7c6a8eb5bc8a9dbfc90b49f90851af82098226f898c728d81ae5`. Both uploaded hashes read back. Final IPK extracted; channel/provider/init match archive and installed hashes, init0755/store0644. No device C module/guard/lease/publisher in runtime package; historical sources/evidence retained. Dependencies now nixio instead of compulsory natmap.

## Real device evidence
- procd controller running PID101989; dedicated Nginx PID102121 then Apply PID102370. Root master reads private fixture TLS; worker nobody UID65534, no additional sandbox.
- Start rev1/gen13 phase running, active_verified=true; CA/hostname TLS response `HP_R3_MARKER_A`.
- Save rev2 leaves active1/gen13, pending=true; real TLS remains A.
- Apply rev2/gen14 phase running, active_verified=true; CA/hostname TLS response `HP_R3_MARKER_B`.
- Stop persisted disabled/manual_stop_latch=true, phase stopped/cleanup confirmed; procd Nginx empty, runtime gone and fresh listener probe curl7.
- Second Start/Stop: openssl verified actual HTTP200 markerB with keepalive; client alive before Stop and peer EOF after Stop. Initial CGI stream test produced no data (fixture CGI disabled), NOT counted as streaming acceptance; fixed backend CGI independently emitted ticks but no sustained proxied-stream acceptance claimed.
- Controller restore reconciled pre-existing r2 cleanupunknown to confirmed by conventional owned-instance stop/absence. Test journals backed up (`accepted-journal`, `stop-final-journal`), then initial journal restored by removing only test state after stopping; exact readback revision0/disabled/no latch/unsupported.
- All owned fixtures/certs/keys/runtime removed, both app init services disabled/stopped, procd objects empty. IPv4/IPv6 routes and TCP listener snapshots cmp identical; firewall SHA256 `52a2755e9a380e1e6d526204ec443dcdd85639f07d2903f64839d073edd55795` identical. uhttpd4308, dropbear63780/34089, xray16371 retained; management HTTP200 and SSH readback succeeds.

## Tests/diagnostics
New conventional package contract RED C adapter packaged → GREEN; actual target nixio mkdir decimal permissions and poll boolean errors reproduced, fixed in source and freshly SDK rebuilt (no diagnostic package reuse). Final local make product controller-recovery exit0; real bounded recovery, Stop/stale, original temporary deadline regressions pass with historical host fixture. Local SDK logs under /home/eric/homestun-sdk-check/device-sdk-r3-final.log and device-r3-regression.log. Target evidence /tmp/homepublish-r3-evidence, backup r2-backup.tar.gz; local IPKs D:/DevPortal/homelede/homepublish-r3-artifacts. No push/merge/PR.

## Architecture/risk contract superseding historical hardening requirements
Controller ordinary health tick, persisted intent/latch/deadline and bounded recovery own policy. Standard procd runs foreground controller/Nginx without respawn/config/network triggers. Normal TERM/timeout process lifecycle replaces reciprocal guardians, capability heartbeat, memfd/seccomp/device C broker in active path. Root master only where needed for private TLS, nobody workers. Stop closes actual connections/listener via normal lifecycle; NO millisecond hard-cutoff guarantee or independent controller-SIGSTOP fail-close claim. Controller crash/freeze/kernel blocking are availability/closure-delay risks to reassess, not reasons to introduce a new sandbox. Private fixed directories/permissions and canonical validation remain.

## Remaining feature3 / product limitations
ACME/DDNS real adapters, DNS/backend refresh and Passwall2 actual-version return-route/DNS/reload coexistence remain unimplemented/unverified. Public production scope, owned firewall/UPnP, dual-stack device matrix and browser Start/Apply integration remain separate; current UI buttons stay disabled, scoped ubus works only with server-owned test-mode marker. No public reachability claimed.
