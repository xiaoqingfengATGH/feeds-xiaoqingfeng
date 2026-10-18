# open-vm-tools 13.1.0 (HomeLede override)

Source: VMware stable-13.1.0, build 25218885.
Archive SHA256: `67a23d505aca77127b081445f758e269b1009e8824cf7f6f2d6efafb0b14d0fd`.
The downloaded archive matches the GitHub release asset digest.

Packaging and musl patches are based on OpenWrt packages master (13.0.0),
retaining original attribution. HomeLede service/config/hotplug files are retained
from the existing 12.0.0 package. GTK4 is explicitly disabled alongside GTK3/X;
VGAuth, container info and kernel modules remain disabled. This does not update
VMware kernel drivers or enable shared folders by default.

`prepareCompile.sh` selects this source after `feeds install -a`, using the same
explicit uninstall/install/provider-link check as ddns-go. Both `open-vm-tools`
and `open-vm-tools-fuse` must originate from this source directory. Do not delete
the packages feed source or reorder all feeds to override one package.

For an existing tree (no other make active), back up .config first, then:

```sh
./scripts/feeds update -i xiaoqingfeng
./scripts/feeds uninstall open-vm-tools
./scripts/feeds install -f -p xiaoqingfeng open-vm-tools
# feeds operations refresh .config; restore the saved baseline if unchanged
# firmware selections are required, before invoking make.
make package/feeds/xiaoqingfeng/open-vm-tools/prepare V=s -j1
make package/feeds/xiaoqingfeng/open-vm-tools/compile V=s -j4
```

Run HomeLede `sh custom/tests/feed-selection.sh` for isolated provider regression
coverage. Verify generated package metadata has only one provider for each binary
package. The x86 target already defaults to open-vm-tools; FUSE stays opt-in.

Runtime acceptance must separately cover vmtoolsd/procd, toolbox version, guest
IP reporting and host-initiated operations. A successful package build alone is
not VMware interoperability acceptance. No router installation is automatic.

## Verified on VM250

Both x86_64 IPKs built successfully with GCC 13.3.0 and musl.
All 12 OpenWrt musl patches applied without rejects/fuzz (some line offsets).
The old 0015-i386-time patch is not carried by the official 13.0.0 recipe;
32-bit x86 has NOT been build-tested in this change.

Extracted IPK binaries were invoked on VM250 using the matching cross-toolchain
musl loader and staged target libraries (not the host glibc):
- vmtoolsd --version: VMware Tools daemon, version 13.1.0.0.25218885 (exit 0)
- vmware-toolbox-cmd -v: 13.1.0.0.25218885 (exit 0)
- vmhgfs-fuse --version: exit 0

Provider metadata and generated Kconfig each contain exactly one definition for
each binary package, from xiaoqingfeng. The original .config was restored
byte-for-byte; FUSE was enabled as a temporary module solely to validate its IPK.
The pre-existing nikki -> missing mihomo metadata warning remains unrelated.
No firmware image rebuild, router install, daemon start, host RPC or HGFS mount
has been performed. Version smoke tests are not full runtime acceptance.

## VM247 runtime acceptance / release 2

Runtime testing of release 1 found `libguestStoreClient.so.0` missing: vmtoolsd
loads it dynamically for its GuestStore/GlobalConfig client. Release 2 includes
that built library (no additional external dependencies) and protects tools.conf
with conffiles. tests/verify-ipk.py prevents regression in the actual artifact.

VM247 was upgraded from 12.0.0-1 to 13.1.0-2. Exact procd instance running;
GuestStore initialization succeeds without the former critical dlopen error;
hosttime/speed RPC reads and guestinfo.ip query succeed. Guestinfo reports
192.168.1.43 (eth1), an actual WAN-side address, rather than 192.168.224.247
(br-lan); interface priority was not changed. Time synchronization remains
Disabled, matching the original state. All installed regular package files
match the IPK; tools.conf, network and firewall config hashes are unchanged.
Only open-vm-tools changed in the package inventory. Boot enablement retained.

The current host does not enable the ESX Guest API for balloon/memlimit stats;
those commands return unsupported (75). Host UI display, shutdown/reboot,
suspend/resume, crash respawn and FUSE mounts were not tested. No router reboot.
Backup/config/opkg metadata and a rollback IPK reconstructed from the target's
original installed files are at /root/open-vm-tools-upgrade-13.1.0, together with
a rollback.sh script (syntax checked, not executed).
