# HomeStatus probe

Installed path: `/etc/homestatus-probes/homevpn` (root:root, 0755).
LuCI's `luci.mk` calls `Build/Prepare/luci-app-homevpn` after copying `root/*`
into the build directory. That hook uses `INSTALL_BIN` to set the probe to
0755 even with a 0644 Windows checkout; package installation preserves it
with `cp -pR`, and ipkg-build normalizes ownership to root:root. Do not use
`PKG_FILE_MODES` here: it applies to translation IPKs too, which contain no
probe and would fail with a missing-file chown error.
No HomeStatus dependency is needed; the probe is inert unless executed.

## Status source and meaning

`htdocs/luci-static/resources/view/homevpn/overview.js` declares
`homevpn.status` and displays `st.running` for the strongSwan/charon process.
`root/usr/libexec/rpcd/homevpn`, in its `status` branch, computes `running`
with `pidof charon`. The probe uses that same process test directly:

- exit 0: `pidof charon` succeeded (running).
- exit 1: `pidof charon` returned 1 (no matching process; stopped).
- exit 2: pidof is unavailable or returned another error (unknown).

The UI's enabled/disabled switch, connection-loaded flag, certificate readiness,
UDP listeners and connected clients are distinct information. The switch banner
requires additional readiness conditions; this probe deliberately reports the
UI's **running field**, not that readiness banner. In particular a disabled
HomeVPN with charon still present reports running, and a running charon without
clients still reports running. HomeVPN assumes exclusive strongSwan ownership;
an unrelated charon would also satisfy the existing UI's process predicate.

The full RPC status path is NOT a read-only probe: it calls PKI recovery,
checks init/firewall state and writes temporary SA data. Do not invoke it,
source the RPC plugin or call init scripts here. The probe never calls ubus
(recursive rpcd calls can deadlock), swanctl, UCI, service lifecycle commands,
certificate helpers or network tools. Both output streams are silent and the
probe creates no files. No config, key or service is changed.

## Isolated regression test

From the package directory:

```sh
sh tests/homestatus-probe-test.sh
```

The actual installed-source probe runs under an isolated PATH containing only
a fake `pidof`. Cases cover running, stopped, unexpected errors (2, 3, 126,
127), missing dependency, exact `charon` argument and silent output. Any extra
external command fails closed in this fixture. The test also executes the actual
prepare hook against a 0644 source, checks the copied app probe is 0755 without
changing the source, and rejects global file modes that break translation IPKs.
It requires GNU make, install, sed, grep and stat on the test host. Set
`TEST_SHELL` to an absolute alternative shell path if needed.
Tests create and remove temporary fixtures only; they do not access a router.
This is not live-router E2E or proof that the VPN accepts client connections.
