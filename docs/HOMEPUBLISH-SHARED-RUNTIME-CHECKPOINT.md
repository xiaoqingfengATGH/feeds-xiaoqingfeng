# Shared certificate runtime source slice

Branch feature/homepublish-product; baseline 19ecc30. Local source/tests only; no target connection or deployment.

## Verified outcomes
- Installed product-device-provider now resolves explicitly allowed ACME section refs through actual certificate_source. Inventory identity may be *.fixture.home while service SNI is a.fixture.home/b.fixture.home. Existing authorized business identity remains ONLY home.iwonderful.top/acme:home_rsa; no ECC business key read.
- Two server-owned fixture hosts permit acme:fixture_rsa/fixture_ecc only. Arbitrary wildcard-covered hosts and refs remain denied. Shared cert/key sources use the same private snapshot paths but retain independent hostname/service readiness bindings; independent refs use different snapshots.
- Fixed trusted resolver paths containing literal wildcard characters: certificate metadata, hash and copy quote paths rather than glob-expand them. Real test first failed trusted certificate path required; then passed after fix. SAN-only validation rejects deep wildcard mismatch; fixture CN is deliberately wrong.invalid.
- Readiness executes verified-hostname curl for every binding and returns the complete map plus aggregate result. Fixture trust uses that binding's snapshot, not a single global fixture certificate. Business trust remains system CA.
- Empty certificates/sans arrays encode as JSON [] (observed RED on empty inventory assertion).
- LuCI Save now checks coverage/validity for all existing service bindings after global default edits. Real browser RED previously saved cleared default; GREEN rejects without revision mutation.

## Final execution
Windows -> WSL root, cached tools, no installation:
```
HP_PLAYWRIGHT=D:/DevPortal/homelede/artifacts/palette-switch-cache/test-deps/node_modules/playwright WSLENV=HP_PLAYWRIGHT wsl -u root -- bash -lc 'cd /mnt/d/DevPortal/homelede/homepublish-product/homepublish/tests && make browser product rpc shared-runtime > /home/eric/homestun-sdk-check/shared-final.log 2>&1'
```
Exit 0. Product/RPC regression, real Chrome official LuCI loader/rpcd/ubus/native journal, narrow375/pageerror=[], Save RSA->ECC inherited retarget/override unchanged/refresh, cleared-default rejection with saved_revision2 unchanged, and chroot cleanup passed. Metadata in browser fixture is injected, not real TLS evidence.

Separate shared-runtime test creates actual isolated RSA/ECC wildcard + apex SAN certificates, executes actual HomeVPN shell resolver with supported isolated state-directory overrides, unchanged metadata and provider source-selection logic, copies private snapshots, runs actual SDK Nginx and unchanged curl readiness for both services. Both shared wildcard and independent RSA/ECC SNI/backend markers, unknown SNI rejection, listener closure, source hashes unchanged and fixture removal passed. Test UCI enumeration is an explicit inventory fixture. Copied module changes only resolver/runtime/nginx paths; local os.execute adapter replaces enabled-file test and procd start with actual SDK Nginx startup. This is NOT installed procd/target lifecycle or system-CA business TLS acceptance. Cleanup is harness-driven, not proof of provider Stop on target.

## Remaining functional acceptance (do not call complete)
- Capability-enabled real browser Start -> Save pending -> concrete field diff Apply -> Stop with real controller/provider is NOT tested this round. Existing unsupported public Start/Apply remain disabled; no fake-active fixture introduced.
- Confirmation still lists backend-only changes; detailed name/domain/certificate/listener/policy/auth diff needs implementation and enabled-browser verification.
- Browser edit/delete/independent picker, listener add/delete/restricted scope choices and status polling/focus need continuation.
- Matching SDK r7/IPK and actual BusyBox/procd target acceptance required. Device remains historical r6/luci r3; this source was not deployed.
- Whole-generation readiness failure/expiry/Stop connection closure for the new certificate refs needs actual target verification. Existing metadata validity tests pass, but no new future/expired real certificate or second-service failure injected into this local runtime test.
- Historical controller-multi intermittent failure not rerun or resolved. No firewall/UPnP/ACME issuance/DNS/proxy/public/push/merge/PR changes. Preserve untracked sketches and __pycache__.
