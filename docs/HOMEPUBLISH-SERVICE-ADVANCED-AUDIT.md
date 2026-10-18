# Service advanced-option audit

## Removed controls

- **允许连接的后端网段**: per-service self-restriction duplicated the backend destination. New/editor-saved v2 services omit `backend.allowed_ranges`; canonical validation, renderer selection, renewal and optional probe use the same built-in household policy instead. All DNS answers are checked before choosing/connecting. No wildcard/unrestricted fallback.
- **业务鉴权确认**: a declaration, not password/token/basic-auth enforcement. Its only production effect was `product-v2-runtime.runtime_plan()` refusing startup unless `confirmed`. Removed the control and the startup gate, not replaced with a hidden `confirmed` default.
- **管理服务**: a declaration, not a management-address blacklist. The same runtime gate refused every marked service. Actual production `product-system-provider.authorize_backend()` only delegates household-address checks; there is no endpoint management blacklist to remove. Removed this declaration/control and its startup effect.
- The now-empty **高级设置** service tab is removed. No replacement implementation paragraph is shown.

## Retained security and compatibility

- New/editor-saved services permit RFC1918 IPv4, IPv4 loopback and IPv6 ULA. Reject public IPv4/IPv6, link-local/metadata, multicast, unspecified and mapped-address bypasses. Existing canonical IPv6 loopback rejection is unchanged.
- Explicit old `allowed_ranges` remain accepted and enforced until a services-editor save removes them. This deliberately preserves existing saved configuration and its narrower permissions; it is **not complete removal of legacy API support**. Explicit legacy scoped global IPv6 retains existing compatibility; omission never enables global IPv6.
- Legacy `authentication_review` is validated and round-tripped if supplied, but is no longer an authorization or startup gate. Services-editor save emits neither field, and does not synthesize declarations.
- Certificate selection, upstream certificate verification and SNI are meaningful and remain. LuCI ACL, listener ownership, address authorization, port safety, INPUT-only firewall lifecycle, revision approval and save/apply semantics are unchanged. HomePublish adds no backend application authentication; the backend owns real login/access control.
- Schema-v1 legacy editor remains migration-only; its model/fixture-specific declaration checks were not changed.

## Acceptance and deployment

- RED observed for missing CIDR acceptance, missing declaration acceptance and frontend stale-field removal; then GREEN.
- Real installed-LuCI browser rendering: no advanced tab/removed controls; local modal save omits stale CIDRs/declarations; TLS certificate checks/SNI still work (both HTTP and HTTPS proxy).
- `run-device-service-simplification.py`: all 13 real private traffic checks passed on 192.168.1.2, with every save/start payload omitting both fields. Covers HTTP/HTTPS, TLS passthrough, SSH banner, TCP echo and upstream TLS verify-on/off. Production journal/source/UCI/fw4 structural baseline unchanged; private processes/listeners/root cleaned. Private fixture deliberately omits firewall management; no new firewall acceptance claim.
- `deploy-service-simplification.py`: seven files backed up and hash-read-back on 192.168.1.2; controlled controller deletion/start followed by existing-revision start. Saved/active configuration and revisions, desired intent, firewall/homepublish UCI preserved. Runtime running/active_verified and all four saved services ready. No configuration save, IPK, commit/push or full firewall reload.
- Backup: `/root/homepublish-lua-store/service-simplification-deploy-c24d1bac67d9/rollback.tar.gz`.
- Regression: all 10 targeted Python suites passed; 25 targeted Node cases passed. Full Node glob: 84/93 passed, 9 stale legacy failures. Reconstructed pre-change UI source via a read-only fs preload produced the exact same 9 failures (82/91 existing cases), recorded in `service-ui-regression-baseline.json`; no new failure was introduced.
- Deployed existing HTTPS ingress responds **502** for its retained loopback fixture backend (`127.0.0.1:50882`); do not present component readiness as healthy backend traffic. Private controlled traffic checks above passed.

Evidence: `docs/evidence/ui-simplification/service-simplification-traffic.json`, `docs/evidence/input-firewall/service-simplification-deploy.json`. Tests: `test-backend-scope-defaults.py`, `service-simplification.test.cjs`, `service-simplification-form-probe.cjs`.
