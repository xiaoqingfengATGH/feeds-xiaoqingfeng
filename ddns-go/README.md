# ddns-go 6.17.7 private API (phase 1 only)

Self-feed replacement of upstream packages/net/ddns-go, pinned archive SHA256
`f7001004e092d9641aad5a94158e0b4cae4a53a7f5c7d96d5c6af3d246c56fcc`,
release 3. Attribution/service configuration follow upstream ImmortalWrt packaging.
Go package include uses the packages feed's absolute build-tree path.
No firmware selection, HomePublish integration, production installation, daemon
restart or provider write is performed by this package's tests.

## Opt-in and authorization

UCI `ddns-go.config.local_api=1` adds
`-local-api /var/run/ddns-go/local-api.sock`; the shipped default is **0**.
The daemon flag defaults to empty. The init wrapper creates a 0700 runtime
directory owned by ddns-go:ddns-go; the listener requires a private existing parent
and sets the socket to 0600. Root callers and the service identity can connect.
This is filesystem authorization, not a WebUI/password API. No TCP listener is
added. `-noweb` does not disable the private API. Listener startup happens before
upstream internet-readiness waiting; queued work waits for the DNS worker.
Regular files/live sockets are never removed. Only a refused stale Unix socket
may be removed. The daemon continues to run as ddns-go, not root.

## API version 1

A dedicated ServeMux exposes only:

* `GET /v1/health` → `{ "api_version": 1 }` (protocol availability, **not** DNS health).
* `GET /v1/profiles` → `{ "api_version": 1, "profiles": [...] }`.
  Each profile contains `profile_id`, `name`, `provider`, and `a`/`aaaa` objects
  with `enabled` and normalized `domains`. Query/custom parameters, provider
  credentials, credentials hashes, IP acquisition commands/URLs, WebUI password,
  webhook configuration and raw YAML are not returned.
* `POST /v1/domains/ensure`, Content-Type application/json:
  `{ "profile_id": "<from profiles>", "hostname": "new.example.com", "record_types": ["A", "AAAA"] }`.
  Requests are limited to 4096 bytes; unknown fields, extra JSON values, invalid
  hostnames, wildcard/IP/port/path input, unsupported/duplicate/empty families
  are rejected. ASCII DNS labels only; lowercase and one terminal dot normalize.
  Disabled families reject the whole request; no family is enabled implicitly.

Success: `{ "api_version": 1, "added": ["A"], "already": ["AAAA"], "update_queued": true }`.
An entirely idempotent request has empty `added` and false `update_queued`.
Existing `sub:zone?params` lines match their normalized full hostname and remain
byte-for-byte unchanged as domain strings. New lines contain only the hostname.
This acknowledges persisted intent and queued work, **never DNS success**.
DNSPod and other existing provider adapters perform creation/update normally;
no provider source file or external API implementation was modified.

Selectors contain position plus a fingerprint of the ordered public profile
name/provider labels, never credentials or their hashes. Renames/reorders stale
old selectors (409). Duplicate name/provider profiles reject mutation with
`ambiguous_profile_name`: assign distinct names first, even if there is only one
profile a future UI must use the returned selector. Credential-only rotation
intentionally does not change selectors. A stale selector must be rediscovered,
not silently replaced with another account.

Errors use a nonsecret `error` code: 400 validation, 405 method, 415 content type,
409 stale/ambiguous/disabled family, 503 unavailable configuration, 500 save failure.

## Deliberately bounded implementation

Local API read-modify-save transactions serialize with each other. All domain
slices are cloned before mutation; a failed upstream SaveConfig leaves cached
configuration untouched. All typed upstream configuration fields are retained;
upstream YAML reserialization semantics remain unchanged (comments/unknown YAML
keys are not round-tripped). Upstream's file save is not upgraded to crash-atomic
persistence. Do not edit the same configuration simultaneously in the old WebUI:
this patch does not add full-form revision control or change its save pipeline.

A bounded size-one channel coalesces updates into the timer worker; requests do
not run provider calls inline. RunOnce is mutex-serialized, with forced comparison
set inside that lock. Existing WebUI direct ForceCompareGlobal writes are outside
this scope; focused race tests do not certify all old WebUI concurrency paths.

## Verification

On a Linux Go >=1.25 host, with downloaded dependencies available:

```
sh ddns-go/tests/verify.sh /absolute/path/ddns-go-6.17.7.tar.gz
```

The runner checks the archive hash, extracts into a new private directory, applies
all patches with zero fuzz, runs focused race tests, the full upstream+new unit
suite, go vet, a standalone native build, and the mocked init harness. It retains
the workspace/binary and does not invoke OpenWrt make or run the daemon.

Tests are included in the patch so upgrades exercise the actual patched source.
Coverage: safe metadata, A/AAAA/both append and idempotence, custom-line matching,
protocol/hostname errors, disabled families, stale/ambiguous selectors, real
SaveConfig failure/cache isolation and successful supported-field preservation,
Unix socket permissions/route isolation/live listener protection, bounded queue,
RunOnce serialization; DNSPod real adapter against local httptest HTTP responses
covers absent-record creation, existing-record reuse/update and unchanged-IP
no-write. Mock adapter tests do not perform public DNS or use real credentials.

Actual validation on VM250 passed fresh-archive patch application, both race-test
packages, full `go test ./...`, `go vet ./...`, standalone binary version
`6.17.7-localapi1`, and the init harness. Private workspace:
`/home/homelede/ddns-go-local-api-phase1/ddns-go-local-api.Htjdjc`.
Binary: that directory's `ddns-go`. Go toolchain:
`/home/homelede/sources/xiaoqingfeng/Homelede5/staging_dir/hostpkg/lib/go-cross/bin/go`.
Package mirror/runner: `/home/homelede/ddns-go-local-api-phase1/package/tests/verify.sh`.
Initial RED observations: undefined New; ensure route 404; missing Listen;
missing RequestUpdate; ambiguous selector mutation triggered forbidden save.
Each corresponding implemented slice subsequently passed. Additional adapter and
regression tests passed against the existing provider/validation behavior.
## OpenWrt build integration and target smoke verification

The firmware's `prepareCompile.sh` selects this same-name package explicitly:
uninstall only `ddns-go`, then install it with `-f -p xiaoqingfeng`. CI calls
that same preparation script. `custom/tests/feed-selection.sh` checks replacement,
repeatability and fail-closed missing-source/failed-install behavior using stubs.
Do not run the full preparation script merely to rebuild this package: it updates
all feeds.

For an existing configured build tree, first ensure no other make is active,
back up `.config`, the package directory and any changed preparation files, then
stage this package at `feeds/xiaoqingfeng/ddns-go`. Inspect `scripts/feeds` for
`update -i` support and use only:

```sh
./scripts/feeds update -i xiaoqingfeng
./scripts/feeds uninstall ddns-go
./scripts/feeds install -f -p xiaoqingfeng ddns-go
[ "$(readlink package/feeds/xiaoqingfeng/ddns-go)" = '../../../feeds/xiaoqingfeng/ddns-go' ]
# This feeds implementation automatically refreshes an existing .config during
# metadata update/uninstall/install. Restore the saved baseline after selection;
# verify CONFIG_PACKAGE_ddns-go=y remains present. Do not regenerate all config.
cp -p /absolute/backup/config.baseline .config
make package/feeds/xiaoqingfeng/ddns-go/clean V=s -j1
make package/feeds/xiaoqingfeng/ddns-go/compile V=s -j2
cmp .config /absolute/backup/config.baseline
```

The package-only clean avoids stale same-version upstream release-2 source/stamps.
No firmware build, router IPK installation or production restart is required.

Actual VM250 build completed successfully with release `6.17.7-3`. Artifact:
`/home/homelede/sources/xiaoqingfeng/Homelede5/bin/packages/x86_64/xiaoqingfeng/ddns-go_6.17.7-3_x86_64.ipk`.
SHA256: `4c9a08bbf187447b4b331ab72e94b0339a15968cc5ef5fc8f5a028512a13813e`.
The extracted IPK contains four regular payload files; its config keeps
`local_api=0`. Prepared build sources matched a fresh archive plus zero-fuzz patch,
and a fresh native `go test ./...` passed, including the local mocked DNSPod
adapter cases. The original `.config` remained byte-identical after build.

The actual extracted IPK binary was transferred with matching SHA256 to router
192.168.1.2 and run privately as uid/gid 32768 (ddns-go), using a unique 0700
runtime directory, 0600 fixture config/socket, `-noweb`, disabled A/AAAA families,
dummy credentials and loopback-only DNS resolver. Health and redacted profiles
succeeded; ensure returned HTTP 409 `family_disabled` without changing the fixture.
This is real target socket/API smoke acceptance, not target DNS-provider write
acceptance: no external DNS updates were attempted. Successful ensure/provider
behavior remains covered by the native mocked unit suite. Production ddns-go PID
and start identity, production DDNS files and firewall config hashes were unchanged.
The private process and directories were removed. No IPK was installed.

Build, source comparison, payload hashes and router evidence are under
`docs/evidence/lua-store/ddns-go-phase1-build/`. VM backups are retained at
`/home/homelede/ddns-go-phase1-backup-20261017-202716`.

