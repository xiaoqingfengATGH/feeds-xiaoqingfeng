# Unified ingress / certificate slice — local source only

## Implemented
- One group-level optional `default_certificate_ref`; missing service bindings normalize into existing `acme:section` / `import:id` references. Explicit service overrides remain independent; shared references are allowed. Schema/journal version remains 1 and old explicit bindings remain valid.
- Service hostname ASCII case canonicalization and duplicate detection. Unicode is rejected rather than guessed; callers must supply IDNA A-labels (UI conversion still pending).
- DNS SAN matcher: exact wins over wildcard; `*.example.test` covers only one label, never apex/deeper names. Multi-SAN and A-label case tested. No CN fallback.
- Internal certificate metadata reader uses actual OpenSSL SAN and dates; does not return certificate contents, paths or private keys. Its current `valid` status is expiry-only, NOT complete notBefore/chain validation: this is a known unfinished acceptance gate; do not expose as full TLS readiness.
- Configured ACME-section inventory projects reference/domain/RSA-ECC/SAN/date metadata. Section lookup uses inventory domain + explicit type through the existing HomeVPN resolver, independently of service hostname. Wildcard inventory identities are quoted and accepted by that existing resolver. Resolver enforces cert/key public-key match; full chain/hostname still requires actual TLS readiness.

## TDD evidence
Each added behavior observed RED before implementation: canonical unknown default field; absent SAN module; missing metadata read; missing inventory/source API; wildcard inventory identity rejected. GREEN commands (WSL):
```
LUA=/home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1
$LUA homepublish/tests/test-certificate-model.lua <repository>
$LUA homepublish/tests/test-certificate-san.lua <repository>
$LUA homepublish/tests/test-certificate-inventory.lua <repository>
python3 homepublish/tests/test-certificate-metadata.py
cd homepublish/tests && make product rpc
```
Canonical tests run the old authority regressions too. Metadata test creates and removes a real isolated RSA wildcard/multi-SAN certificate/key using OpenSSL; fixture is not a device certificate. Inventory test injects UCI/resolver metadata: verifies adapter contract only, NOT actual installed inventory. `make product rpc` passed before final wildcard identity fix; rerun required/recorded by final commit validation. Existing recipe linker emits tmpnam warning; not pristine stderr.

## Exact unfinished work / next owner
1. Add notBefore/expiry/chain/key failure tests and actual resolver integration; avoid treating metadata expiry-only status as sufficient readiness. Bound inventory enumeration/openssl calls and check missing defaults/key_type conventions against actual UCI.
2. Connect `certificate_inventory` through fixed CLI/RPC/plugin/read ACL; read back real rpcd. No RPC inventory method added in this slice.
3. Wire `certificate_source` into installed plan/readiness while preserving server-owned test allowlist. Existing device provider still has exact historical business/fixture bindings; this slice does NOT make installed wildcard/shared runtime work. Shared snapshot reuse is pending.
4. Implement recommended A native LuCI list/edit dialogs and group entry form, certificate selection/default inheritance, actual capability Start/Apply controls, whole-group diff confirmation, unsaved action blocks, natural Chinese states and folded diagnostics. Current UI remains unchanged.
5. Real chroot/browser Save→refresh/revision, modal/errors/narrow DOM; matching SDK r7 and device acceptance require parent continuation. No automatic deploy in this slice.

## Inheritance persistence trade-off
Normalization expands inherited references into explicit service references, preserving the existing journal/provider contract. Changing only the default later does NOT retarget previously normalized services. UI must intentionally clear/rebind selected inherited services, or a later migration must preserve explicit binding mode. Do not silently present persistent inheritance semantics not implemented by this slice.

No device connection/deploy, firewall/UPnP/public/ACME issuance/proxy configuration changes, push/merge/PR. Existing actual device RSA/ECC certificates are only home.iwonderful.top; no business wildcard certificate claimed. Preserve sketches as design drafts.
