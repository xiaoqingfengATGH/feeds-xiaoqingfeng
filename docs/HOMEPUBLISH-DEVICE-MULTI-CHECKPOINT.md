# Installed simplified device provider: multi-service r6

## Outcome / authorization boundary
Actual installed Lua provider + standard procd dedicated Nginx supports the whole approved canonical two-service set, not merely configuration storage or the legacy complex guardian adapter. Server-owned allowlist remains `home.iwonderful.top` + `acme:home_rsa` (authorized existing HomeVPN RSA) and `service.home` + `import:fixture` (separate fixture certificate), backend loopback49285/49286 and listener narrowed to127.0.0.1:49284. No arbitrary client path/command/provider, no public-production activation. No Go/broker/C-guardian restoration or extra hardening matrix.

## Source and real SDK binding
- Runtime commit `92c8e33` (implementation c7bd340, readiness binding54d693b); subsequent harness/docs only. Accidental tracking of pre-existing Python caches in54d693b removed from index in92c8e33; local caches remain untracked.
- Official cached SDK24.10.5 x86_64; exclusive shared build.lock, explicit CONFIG_PACKAGE_homepublish=m, native `git -c core.autocrlf=false archive`, fresh ext4 device-r6-source; readback resolved package feed bound to that archive before clean/compile. WSL Git cannot resolve native Windows worktree .git pointer, so archive made with native Git, not a guessed WSL worktree.
- Artifact `D:/DevPortal/homelede/homepublish-r6-artifacts/homepublish_0.1.0-r6_x86_64.ipk`, SHA256 `ff91d951d6025c6aa83c2e1154ac0cde6abdadbd83bf4f775a5fc956d9953b18`. source.json and installed.sha256 alongside. All23 packaged source files equal archive and Git blobs; all24 installed files equal extracted IPK. Native store compiled with SDK TARGET_CC. Upload hash and opkg0.1.0-r6 read back. LuCI unchanged r3.

## Real target cases (final complete rerun exit0)
Harness `homepublish/tests/router-simple-multi.sh`; evidence `/tmp/homepublish-r6-evidence/multi-final.log`, procd-running.json, old-connection{,2}.log.
- Two distinct hostname TLS markers: business HP_R6_BUSINESS_A via system trust and hostname verification (no insecure/custom CA), fixture HP_R6_FIXTURE_B via fixture CA/hostname. Dedicated procd master PID124537, nobody worker124580 observed. Private runtime0700 and four independent cert/key snapshots0600.
- Both per-service readiness results bind the current generation; only whole-set success activates. Save one backend edit leaves old business marker A/pending; Apply whole generation switches business marker B while preserving service2 readiness.
- Two real already-established verified TLS connections alive before Stop and both exit after Stop; new connection refused, private snapshots/runtime removed. Duplicate Stop confirmed.
- Restart two-service set, delete service2 and Apply new generation: removed service.home SNI handshake rejected; remaining business still ready. Stop confirmed.
- Stop second backend; Start two-service configuration: first readiness true, second false, whole generation blocked/active_verified=false, cleanup confirmed and snapshots absent. No partial activation.
- Original authorized RSA cert/key hash+permissions compared server-only and equal. No private key contents/hash exported.

## Tests and final preservation
- RED two services rejected by old scope; GREEN multi-plan. Separate RED missing controller per-service results; GREEN result map. Unit mocks only exercise no-secret plan/readiness contract; actual target cases above prove Nginx/procd.
- `make product rpc` exit0; simple-device, simple-multi, business-provider pass local; installed actual-target simple-multi, business-provider, device-integrations pass. SDK/regression log `/home/eric/homestun-sdk-check/device-r6-build.log`.
- Exact final readback: revision0, desired disabled, phase stopped, cleanup confirmed; procd Nginx `{}`, both init disabled, fixture certificate sources/runtime absent. TCP listeners byte-identical to baseline (no49284/49285/49286), IPv4/IPv6 routes byte-identical, /etc/config/firewall SHA256 unchanged `52a2755e9a380e1e6d526204ec443dcdd85639f07d2903f64839d073edd55795`; management HTTP200 and 80/443/22 retained, Passwall2 enabled1/xray16371 retained. Independent SSH final readback succeeds.
- Known diagnostics: opkg previous-version prerm / generic init Stop when controller already absent prints channel connection-refused and service-delete Not found; harness cleanup has same existing init warning. Provider duplicate Stop itself passes. No pristine stderr claim. No broadened init/hardening repair added here.

## Not complete / next scope
Independent LAN client return path, actual-version proxy reload coexistence, production activation authority/firewall/UPnP/public reachability and UI Start/Apply remain unfinished. No proxy reload, firewall/UPnP mutation, global DNS/hosts/resolver modification, ACME issuance/config/permission mutation, public probe, push/merge/PR. Historical guardian multi intermittency remains unresolved historical evidence, not retested/stress-expanded and not used to prove this provider. This slice does not claim the entire product/features1–3 complete.
