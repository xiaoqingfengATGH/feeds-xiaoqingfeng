# HomePublish package slice (experimental, activation blocked)

REQ-001, branch `feature/homepublish`. No commit/push/PR in this task. Real SDK core and corrected LuCI `.ipk` artifacts are built and inspected; this remains experimental, not installation/activation-approved or production-ready.

## Latest: corrected LuCI package and browser evidence

[Final package checkpoint](../docs/homepublish-luci-package-final.md): LuCI IPK **4239 bytes**, SHA256 `9fb1269c6b8f3c679d07aa8631caa1e3ea3a817670402a039b37e6f4178949b2`; current full LuCI source/feed bindings, exact SDK minification, class export, scoped Save commit, ACL, payload allowlist and safe modes verified. Existing genuine target-assets browser Save + damaged-disable PASS is bound to the same source; final Node **10/10 PASS**. Core IPK SHA256 `84087e052d2cefacc7ac943ef9bc74000206379d80ca31b4de5f9c58d0ca4c22` preserved. No active SDK make, no router installation/activation. Standard LuCI cache/rpcd-refresh scripts exist, no HomePublish activation hook. Final review and real enabled engines/procd, target HTTPS, STUN/public TCP and Cloudflare deployment remain gates. Historical slice statements below do not override this checkpoint.

## Latest: default-off UCI publication completed

[Canonical UCI evidence](../docs/homepublish-publication-uci.md): target actual BusyBox/UCI/Lua/procd JSON builder passes 23 service PASS lines plus one config-suite PASS, with ubus captured locally and no real service submission. Final root WSL token2/security3/publication3/socket4/lifecycle1/recipe1/package1/cleanup30 and Worker8 pass. At 12:59:25 CST separate SSH readback confirms owned UCI fixture/service/process absent, management22/80/443 retained, test ports absent. Immutable payload hashes match; fixture UCI mutations are recorded separately. Native token readers prove bounded EOF/short-read/EINTR loops, not a single-read prefix check. No production activation. Independent review, SDK/ipk/target ABI, real enabled engines/ubus integration, target HTTPS, Cloudflare and public reachability remain separate gates.

## Earlier final publication token checkpoint

Latest token-fix local child evidence is **native45 / Worker8**; parent independently reported **token2 / Worker8**. Supplemental [genuine-router evidence](../docs/homepublish-publication-router.md) now verifies `--provision ... publish` seven BusyBox/no-stat/procd cleanup cases, including controller/preparation KILL/STOP after token snapshot; strict whole-file tokens pass14 inputs through native publisher and provisioning (28 assertions), rejecting invalid input before snapshot/transport/session mutation. Genuine target Lua5.1.5 passes core16 + config suite in isolation. Final12:38:47/48 CST readback confirms originalcert/key/token/foreign preserved, owned runtime removed before fixture deletion, no service/process survivors, management22/80/443 retained and test ports absent; source/payload hashes match. Native binaries are WSL-static, transport/renderer/engines are non-networking fixtures: not SDK ABI, real HTTPS, actual enabled integration or public reachability. Production init/UCI remains publication-off; Config opt-in source/isolated registration has since been verified in the latest checkpoint above; independent review and actual enabled integration remain gates.

## Delivered

- OpenWrt recipe compiles `src/lease-supervisor.c` with `TARGET_CC` and installs only that build output. Test binaries and Worker source are not shipped.
- Independent UCI defaults: disabled, exposure approval off, loopback nginx, different high ports, no host/upstream defaults and no credentials.
- Strict Lua UCI adapter/CLI; status exposes only configuration validity, `mapped=unknown`, `reachable=unverified`, never a secret or discovery result presented as reachability.
- Independent procd instance registers the native guarded provisioner; no cloudflared/management-nginx coupling, reload auto-restart, respawn, DNS updates or firewall hooks.
- One manual start is one bounded lease, maximum 120 seconds. Both foreground TCP NATMap and dedicated nginx are in the native guardian's monitored process group. Unexpected engine exit fails closed; expiry closes both. The nginx-only tested interface remains compatible.

## NATMap investigation

Sources:
- https://github.com/heiher/natmap/tree/20260214
- https://github.com/openwrt/packages/blob/master/net/natmap/Makefile
- https://github.com/heiher/natmap/blob/20260214/README.md

Inspected/built revision `f8d7996710677c9885c148dda80a42d626f0a17b` with recursive task-system submodule `8d83bbbf79557138726c8ee5a5fae99cbb978d61`. Native static compilation succeeded, with the upstream glibc static getaddrinfo warning. No NATMap process ran on the router; no public mapping/listener was opened.

Forward mode, TCP (absence of `-u`), IPv4:

```
natmap -4 -b <bind-port> -s <stun-server> -h <http-server> -t 127.0.0.1 -p <nginx-TLS-port>
```

Do not use `-d`, NATMap's separate service, bind-mode port reuse of management nginx, or DNS scripts. NATMap's optional `-e` callback receives `{public-addr} {public-port} {ip4p} {private-port} {protocol} {private-addr}`. Callback/publication is now wired only through the default-off source opt-in (independent review still required) (see latest evidence): a discovery event is NOT an independent inbound TCP probe, and publishing a Worker lease before readiness/lease-expiry coordination is unsafe. No real Cloudflare credentials/deployment are present.

## Enforced NATMap socket-safety boundary

Upstream `src/hev-sock.c:216-219` retries a failed bind after `hev_reuse_port`; `src/hev-misc.c:193-206` uses `pidfd_getfd` to set `SO_REUSEPORT` on an unrelated process's socket. Separate configured ports or a port preflight cannot prevent a startup race.

The native helper now installs a kernel seccomp-BPF filter **in the NATMap child before exec**, with `PR_SET_NO_NEW_PRIVS`. `pidfd_getfd` returns `EPERM`; the filter survives exec/fork and cannot be removed by the engine. A native audit-architecture check rejects other syscall ABIs, including x32 on x86-64. Target headers supply syscall numbers; unsupported ABIs/headers fail compilation. No new userspace library or patched system-wide NATMap package is required. The parent waits for a private boundary-ready acknowledgement before launching nginx; failed installation executes neither engine and the guardian removes the snapshot.

OpenWrt must have kernel `CONFIG_SECCOMP` and `CONFIG_SECCOMP_FILTER` enabled. Kernels lacking filter support fail closed at runtime, not by silently falling back to root execution. Actual target SDK/ABI and kernel acceptance remain approval gates; WSL proves the x86-64 Linux path only. This is a narrow boundary against the inspected upstream's foreign-descriptor reuse, **not a general sandbox for malicious root**. It does not prohibit sharing with sockets that another service has deliberately already made reusable; configure genuinely dedicated ports. No mapping readiness, full NAT traversal or public reachability claim follows from these tests.

The isolated regression compiles the unmodified pinned upstream `set_reuse_port` implementation into a deterministic engine fixture (rather than mocking the dangerous syscall), exercises a busy listener and a successful-preflight/losing-startup race, and verifies `SO_REUSEPORT` remains zero, bidirectional original traffic survives and the helper exits unsuccessfully. The negative control removes only the boundary in a temporary source copy and demonstrably mutates both victim sockets. See `../docs/homepublish-socket-boundary.md` for evidence and scope.

## Validation and operation boundary

Use `lua /usr/share/homepublish/config-cli.lua status` for non-secret configuration diagnostics. UCI configuration files can be tested using the CLI's second argument (an isolated directory); `plan` emits validated fixed arguments, `render <config-dir> <isolated-runtime>` emits only dedicated nginx configuration.

`/etc/homepublish/cert.pem` and `key.pem` must be root-owned single-link regular non-symlink files mode0600 in private mode0700 directory; unsafe originals are rejected, not repaired. Init now performs read-only plan/trust checks and registers native `homepublish-lease --provision`, so failed later ubus submission/init death creates no generated TLS copies. Controller/guardian precedes monitored runtime creation/copy/render; inode-scoped cleanup removes unchanged owned sources/snapshots while preserving originals, replaced files/directories and foreign entries. The legacy lease-run adapter remains supported but is not the current registered service command. Native `--identity/--metadata` replaces stat with no new dependency. [Final guarded evidence](../docs/homepublish-guarded-provisioning.md): 30 WSL source-cleanup tests pass with no expected failures; genuine router BusyBox/no-stat native expiry/TERM/KILL/STOP, preparation render KILL/STOP and isolated real procd STOP→TERM→KILL all pass. Original fixture cert/key hashes survive, owned runtime absent before fixture deletion, final service/process/listener readback clean. Native/engine fixtures are WSL static builds, renderer/engines are non-networking stubs; this does not verify SDK/target-libc ABI, installed enabled HomePublish integration or public mapping. Power loss, blocked filesystem/D-state, malicious concurrent root pathname mutation and secure erasure are outside this scoped proof. Never delete live runtime to force restart.

The package depends on `lua`, `libuci-lua`, `nginx-ssl`, `natmap`; a real OpenWrt SDK build must verify target dependency names, ABI and init registration. The macro harness actually compiles and installs the recipe, but is not an SDK build or install test. No usable SDK/config/staging toolchain was found in the given firmware tree.

## Reproducible tests

- Windows: `python homepublish/tests/test-package.py`
- Linux/WSL: `python3 homepublish/tests/test-recipe.py` (temporary macro harness; real compile/install, no packages installed)
- Root Linux/WSL: `unshare -n sh -c 'ip link set lo up; python3 homepublish/tests/test-socket-boundary.py -v'` (isolated namespace enforced; pinned upstream checkout from `NATMAP_SOURCE` (default set by the environment); occupied-port/race real-socket checks and seccomp-install fail-closed checks). Set `HOMEPUBLISH_SECURITY_NEGATIVE_CONTROL=1` and select the two socket tests to reproduce the vulnerability only inside the namespace.
- Root Linux/WSL: `python3 homepublish/tests/test-lifecycle.py` (chroot fixture binaries, no networking)
- Root Linux/WSL: `python3 homepublish/tests/test-source-cleanup.py -v` (30 final native/legacy cleanup cases; read-only init registration/submission rejection, concurrent provisioning, exec failures, render fault matrix and inode preservation; procd/Lua stubbed).
- Genuine router isolated fixture: `homepublish/tests/router-guarded-provision.sh` (no-stat assertion, native provision expiry/TERM/KILL/STOP, preparation render KILL/STOP and real unique-service procd deletion; see final guarded evidence for fixture setup, hashes, cleanup and limits).
- Router Lua in isolated fixture: `test-config.lua`, `test-service.sh` (UCI writes only to the supplied `/tmp` config directory; disabled start invokes zero procd commands)
- `node --test homepublish/tests/worker.test.mjs`
- All original `router-*.sh` tests rerun against final modified helper: 9 scripts, router Lua 16 checks; isolated loopback TLS backend only. Test directories and ephemeral certificates removed afterwards.

## Next approval gate

Parent independent review must first verify enabled-instance procd lifecycle, the coordinated-engine failure/kill/stopped-controller matrix, temporary TLS-source cleanup and a true SDK `.ipk` build. LuCI minimal settings/status is deferred, not delivered. Authenticated mapping publication and default-off UCI registration are delivered as isolated slices, not activated or deployment-approved. After those pass, request explicit user approval for package installation and any temporary NATMap/firewall/external-probe experiment. Do not enable `enabled`/`exposure_approved` or test mapped NAS merely because the recipe builds. Public TCP feasibility requires an independent external probe; Cloudflare deployment is another separately authorized gate.
