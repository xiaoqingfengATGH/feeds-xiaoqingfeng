# Installed-resource browser acceptance (explicit integration entrypoint)

Run from the repository root. These tests require the authorized device, SSH key, a reviewed known-host entry, installed Chrome and Playwright. They are not offline unit tests; missing prerequisites are errors, not successful skips. No deployment or production Save/Apply/Start/Stop is performed.

```bash
# Install tooling outside the repository if necessary.
npm install --prefix "$BROWSER_DEPS_DIR" --no-audit --no-fund --ignore-scripts playwright
export HP_PLAYWRIGHT="$BROWSER_DEPS_DIR/node_modules/playwright"
export HP_DEVICE_URL="http://$AUTHORIZED_ROUTER"
export HP_SSH_KEY="$AUTHORIZED_SSH_KEY"
export HP_EVIDENCE_DIR="$BROWSER_EVIDENCE_DIR"
# Optional: HP_SSH_TARGET=root@host, HP_SSH_PORT=22,
# HP_PIN_FILE=/absolute/path/to/reviewed-installed-pins.json
node luci-app-homepublish/tests/installed-browser/run.cjs
```

`pinned-installed.json` freezes the reviewed installed provider/store/core hashes. Refuse mismatches; do not update pins automatically or copy worktree product code to the device just to satisfy a test. Each invocation records a fresh production baseline, creates UUID-private journal/script roots, verifies production identity and deletes only its own fixture roots. The Lua fixture substitutes only the store dependency; lifecycle methods are excluded. The upstream production session has read-only UCI grants and no HomePublish save grant. Installed UI bytes and hashes are archived and compared before/after. Evidence goes to `HP_EVIDENCE_DIR`, not the source tree.

## Focused Host differential

```bash
# Validator API contract, with blur validation and an awaited/caught parse Promise.
HP_HOST_NEGATIVE_MODE=caught-parse node luci-app-homepublish/tests/installed-browser/backend-host-header-native.test.cjs
# Actual native modal button event path. Never waive pageerrors.
HP_HOST_NEGATIVE_MODE=click node luci-app-homepublish/tests/installed-browser/backend-host-header-native.test.cjs
```

Both modes use actual installed loader, form and HomePublish modules; fixture RPC rejects production writes. Each tests eight invalid Host inputs, four valid Host inputs, retained values, type visibility/stripping, SNI independence and unchanged DNS semantics. Click mode checks visible validation feedback, waits for the native button Promise to settle and preserves all pageerrors. `host-*-diagnosis.json` records parse/save settlements and unhandled-rejection stacks. Instrumentation only observes and rethrows the same errors: it does not call preventDefault, replace the modal handler, or suppress pageerror events. A corrected product can pass click mode; existing errors keep exit 1.

Direct parse needs an explicit input blur: Playwright fill emits input events but LuCI validation is attached to blur/keyup. Without blur the direct parse negative test can read stale widget validity. Clicking the native completion button naturally blurs the input. This test-driver issue does not explain away native-click exceptions.

## Verified fix acceptance

The HomePublish modal event boundary now consumes the failure after retaining inline validation; failures without an invalid field also receive an explicit error notification. Generic LuCI handlers and pageerror collection remain unchanged. `HP_SERVICES_OVERRIDE=/absolute/path/to/services.js` enables a pre-deployment services-only override in the local loader (never the production page).

Verified evidence: `C:/Users/xiaoq/AppData/Local/hermes/cache/scratch/hp-modal-fix/acceptance.json`. Native-click RED reproduced eight pageerrors; local override GREEN and deployed-resource suite GREEN (7/7). The click probe also injects an unexpected rejected modal save and verifies visible notification, retained modal, and zero pageerrors. Single-file deployment SHA256: `c70d0fdda87fd2e3cc8a8699ca0bee2643eecaa639f7192d266dec2e48abc14a`.

Separate ordinary authenticated production UI acceptance performed a reversible AI name edit: Only Save 5→6 (active5/generation15 unchanged; CA-verified HTTPS200), Apply→7/generation16, Stop (cleanup confirmed, zero ingress rules/listeners, HTTPS connection rejected), Start→generation18, UI restore original name and Apply→saved/active9, intent/generation19. Original saved/active configuration content and enabled/running intent restored, not old journal revisions. HTTPS200 with normal hostname/CA verification. SSH/RDP remain ready; no protocol-specific end-to-end traffic claim. Explicit Start/Apply calls the existing ddns-go ensure only for the configured vmware.innonext.win; no hostname or certificate issuance changes. The suite below remains an isolated-resource test, not this separate production lifecycle evidence.

## Historical RED result and root cause

Pre-fix repository run (historical RED, superseded by the verified fix acceptance above): `repository-final2/summary.json` under the investigator's configured evidence root. Seven probes: base, extended, caught-parse Host contract, native-click Host acceptance, page-save fixture, loading fixture, DNS fixture. Six pass; native-click Host acceptance fails. Overall runner deliberately returns 1. Do not report overall browser acceptance as PASS.

For all eight invalid Hosts, the native modal stays open, inline validation is shown and the invalid Host does not enter the serialized draft. There are nevertheless eight unhandled rejections/pageerrors. Caught-parse mode rejects the same eight values with zero pageerrors. Native-click failure also reproduces in the original, uninstrumented scratch script.

Exact installed-code chain (archived resources retain device line numbering):

1. `form.js:143` returns a rejected Promise for invalid `CBI.AbstractValue.parse()`.
2. `form.js:74` and `form.js:48-50` aggregate child/section parse Promises. `Map.save()` awaits parse and catches then rethrows validation failures at `form.js:50-51`. This is **not** a forgotten await on the parse call.
3. HomePublish `services.js:33` starts `activeMap.save(null,true)`, `:35-38` catches the rejection and displays inline feedback, then `:39` returns `Promise.reject(e)`. The same lines are present in the worktree `htdocs/luci-static/resources/view/homepublish/services.js`.
4. The modal button is wired through `ui.createHandlerFn` at `form.js:256`. Installed `ui.js:372-375` calls the handler inside `Promise.resolve(...).finally(...)` for spinner cleanup but attaches no rejection handler; the resulting rejected Promise is unobserved. The displayed validation error therefore escapes as an unhandled rejection.

Classification: genuine HomePublish/native-LuCI event-boundary error-handling defect, not Playwright failing to await a parse Promise. `locator.click()` awaits the browser interaction, not the application's asynchronous event-handler Promise. An `await locator.click()` cannot catch an unhandled Promise created by that native handler.

Historical recommendation (subsequently implemented and deployed as documented above): after showing the expected field-validation feedback, consume that known validation failure at the HomePublish modal event boundary; retain proper explicit reporting/handling of unexpected failures. Alternatively fix the generic LuCI handler rejection policy upstream. Do not globally ignore pageerror or swallow every error. Keep the native-click regression red until an independently authorized product fix is verified.

## Scope and limitations

- Base/extended: installed resources through a local HTTP loader, HomePublish RPC routed by POST payload across `/ubus` and `/cgi-bin/luci/admin/ubus` into a UUID-private real target Lua journal. Native forms save/read/reload private state; publishing is never activated.
- Other probes: installed resources with local fixture RPC. Their simulated Save/Apply/spinner lifecycle is **not** production persistence/lifecycle acceptance.
- Process-local network-inventory fixtures are not actual device interface changes.
- Input newlines in single-line HTML text fields can be sanitized by the browser; this is not backend CRLF-injection acceptance.
- No authenticated ordinary-production save/start/apply/stop, real forwarding traffic, reboot, upgrade or public certificate acceptance is claimed. No user's existing tab or draft is accessed.
- Before/after protected production journal/config/generated-nginx/provider/store/UI hashes and stable revision/runtime projections must match. This proves those observations unchanged; it is not a claim that the harness exercised production save lifecycle.

The loading-fixture POST splice now targets the actual `fetch` marker and asserts both splice markers exist. This prevents a missing historical `const local=` marker from silently cutting the generated script at index -1. Machine-specific tooling paths, stale fixed journal hashes and fixed private roots from the scratch adapters have been removed.
