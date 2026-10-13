# Genuine target-assets browser acceptance — PASS

Executed Chrome against a newly started `homestun-luci-browser-server.py`, real router LuCI assets, current HomeSTUN view/schema, and separate chroot ubusd/rpcd/uhttpd. No mocked form values, no formvalue overrides. Legacy persistence.cjs now delegates to genuine DOM acceptance.

- Actual DOM check/fill/Save commits enabled=1, ttl=75, browser.example and upstream. Session readback matches committed UCI, backend plan and refreshed configured status. Unrelated `other` stays committed=before and pending=staged-other.
- Damage ttl=broken and hostname=INVALID in fixture, reload, uncheck enabled and click Save: committed and session enabled=0, damaged values preserved, status disabled, backend plan disabled.
- Request audit contains only homestun-scoped commits; no apply/reload/start/restart; no lease runtime or natmap/supervisor.
- `docs/artifacts/luci-browser-acceptance.json` is actual PASS with zero page errors, source SHA256 bindings, RPC audit, DOM, session/committed/status/plan evidence. Screenshots: luci-browser-save.png and luci-browser-disabled.png.
- Final run through `docs/homestun-luci-browser-final.py` succeeded, verified hashes still match current source, and always executed scoped cleanup in finally. `docs/artifacts/luci-browser-cleanup.txt`: exact chroot processes terminated; known urandom mount unmounted; no matching root/exe/cwd, mount/tree or router18992 listener remained. Production22/80/443 retain same PIDs. Local server/tunnel exited; local18991/18992 connection checks refused.
- Node UI regression: 4 passed, 0 failed.

Fixture root cause found: missing /etc/passwd and /etc/group caused ubus connect failure despite a listening socket; copy them inside fixture only. Add minimal fixture luci config to prevent real LuCI startup RPC not-found errors. Checkbox IDs are randomized by actual ui.Checkbox, so acceptance locates checkbox inside stable cbid container rather than fabricated widget IDs.

Changed only fixture/harness/docs in this browser task. Existing product ACL commit grant was read and exercised, not changed here. No product settings edits, production configuration writes, activation, router install, IPK rebuild, git commit/merge/push/PR. Prior IPK remains unrebuilt; package rebuild is a separate gate. The setup script's detached daemon lifecycle is not the lifecycle used for final acceptance: final run used tracked foreground SSH daemon sessions and explicitly verified remote cleanup.
