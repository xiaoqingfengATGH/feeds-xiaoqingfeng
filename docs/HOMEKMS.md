# HomeKMS

HomeLede integration version 1.0.0-r1 packages the upstream Python KMS protocol engine, not a HomeLede-authored protocol implementation. A valid software license remains necessary. This is not certification that every Windows/Office SKU activates; Home, retail Office and Microsoft 365 subscription products are not covered by a blanket compatibility claim.

## Immutable upstream payload

- Repository: https://github.com/Py-KMS-Organization/py-kms
- Release: v1.0.1; commit `b0e1615dec06293c927625006a99e6ec54a001aa`
- Archive: https://codeload.github.com/Py-KMS-Organization/py-kms/tar.gz/b0e1615dec06293c927625006a99e6ec54a001aa
- Archive SHA256: `cc247a590141120f81b1fe591d42867ae428792cfc459236431e61d6f94ad89c`
- Embedded `KmsDataBase.xml`: 72125 bytes; SHA256 `5dbb9e02471d854920e431298cfc9924b7e553fd3711b10235821a949dd80a30`
- Upstream license: Unlicense; shipped as `/usr/share/homekms/LICENSE`; installed provenance is `/usr/share/homekms/upstream.json`.

The package fetches the commit archive during build, ships the matching XML beside the modules, and performs no startup download. Database changes require a new tested package release. No SQLite persistence, web UI, GUI, fixed ePID, runtime pip or online updater is enabled. Upstream locates XML relative to `__file__`, so launch working directory does not determine the database path.

## Configuration and lifecycle

`/etc/config/homekms` is a preserved conffile containing named `homekms.main` (type `homekms`):

| Option | Default | Meaning |
|---|---|---|
| enabled | 0 | Whether procd creates the daemon instance |
| port | 1688 | TCP IPv4 port, **1024..65535** |
| wan_access | 0 | Publish router-local INPUT rule from zone `wan` only |
| auto_discovery | 0 | Reserved; not implemented in the initial release |

Keep `/etc/init.d/homekms` boot-enabled: this registers config triggers even with `enabled=0`; it does **not** launch Python while disabled. Save & Apply reloads the init through procd's UCI trigger. Reload submits a replacement service transaction, allowing procd to delete the previous instance when disabled or invalid. Temporary `stop` does not change UCI and removes the runtime service/triggers; explicit `start` or `reload` re-registers them. This differs from permanently disabling the init script.

The foreground command is `/usr/bin/python3 -B -u /usr/share/homekms/pykms/pykms_Server.py 0.0.0.0 PORT -F STDOUT`. procd owns the exact instance `homekms/main`, its PID, termination and respawn policy (3600-second threshold, 5-second delay, maximum 5 retries). User/group `homekms` (dynamically allocated through `USERID:=homekms:homekms`) is unprivileged; privileged ports are rejected rather than silently running as root. Logs go through procd stdout/stderr to the system log. IPv6 is not advertised as supported.

WAN rules live in **instance data**, not persistent firewall UCI sections. The actual HomeLede fw4 `18fc0ead` consumer was read at `root/usr/share/ucode/fw4.uc`: it obtains `service.get_data(type=firewall)` and parses `service[instance].firewall[]`. The firewall init registers `procd_add_reload_data_trigger firewall`, which consumes data changes. The emitted rule has `type=rule`, `family=ipv4`, `src=wan`, `proto=tcp`, selected `dest_port`, `target=ACCEPT`, and no destination zone (INPUT, not forwarding). Instance replacement/deletion removes its data. No arbitrary firewall sections are changed. A renamed WAN zone is deliberately not guessed; the initial integration targets the standard `wan` zone. Firewall behavior still requires live nft acceptance after deployment authorization.

LAN reachability follows existing zone INPUT policy; no automatic LAN allow rule is added. Automatic DNS SRV discovery is intentionally deferred: setting the reserved option only logs an explanatory warning and never edits DHCP or restarts dnsmasq. Use a manual LAN address. The UI should hide or clearly disable this option, not promise discovery.

## Dependencies and evidence scope

Declared split runtime packages: python3-light, logging, xml, uuid, multiprocessing, ctypes, sqlite3, pydoc and unittest, plus firewall4. The VM feed's Python split definitions were inspected: `pykms_Sql` imports sqlite3 unconditionally; `pykms_Filetimes` imports doctest (in python3-pydoc). XML also pulls urllib. Hashlib/hmac use the normal light-runtime hash backends; `_hashlib` is split into python3-openssl, so target payload/import validation must confirm SHA256 fallback availability before omitting openssl is considered proven. DNS client imports, Flask and Tk are not server requirements. tzlocal/pytz have an upstream fallback and are not required for the successful isolated tests.

Source hashes and database bytes passed local Python tests. Lifecycle shell simulation passed disabled/enabled start, trigger registration, non-root foreground command, WAN opt-in/scoping/port, invalid ports, disabled reload and missing database. These mocks do not prove real procd transactions, nft rule cleanup or boot behavior.

On the Linux build VM, an isolated scratch directory `/home/homelede/homekms-test` was used; no build-tree feed, .config or router changes were made. Independent Wind4/vlmcsd C client commit `70e03572b254688b8c3557f898e7ebd765d29ae1` was built there. Loopback interoperability passed protocol v4/v5/v6 against Server 2019 Standard, Windows 10 Enterprise and Office Professional Plus 2016, three requests for each pairing (27 checked responses). The harness requires exactly three parsed responses, ePID content, no error/failure output, and no server traceback/exception. vlmcs also warns that the server closes RPC connections; fresh connections (`-T`) are used. Persistent-connection reuse exposed an RPC response failure and is not claimed as supported. These are synthetic protocol exchanges, **not actual product activation**. Office 2024 and Server 2025 identities have not yet been independently exercised locally.

Public upstream context (not local certification):
- https://github.com/Py-KMS-Organization/py-kms/pull/130
- https://github.com/Py-KMS-Organization/py-kms/issues/126
- https://github.com/Py-KMS-Organization/py-kms/issues/128
- https://github.com/Py-KMS-Organization/py-kms/pull/143
- https://github.com/Py-KMS-Organization/py-kms/issues/138

## OpenWrt package build verification

The parent integration built all three IPKs on VM250 successfully after fixing dynamic USERID allocation and the LuCI feed scan signature. Backend IPK: 94260 bytes; frontend: 2795 bytes; Chinese translation: 1795 bytes. The extracted backend XML SHA256 matches the pinned value. Control metadata includes the Python split dependencies, `Require-User: homekms:homekms`, and `/etc/config/homekms` in conffiles; the Chinese LMO is present. Archive tests passed 3/3 with the actual downloaded source, frontend tests passed 5/5, and lifecycle simulation passed. The VM .config was restored byte-for-byte to its pre-build backup; package definitions remain in the VM custom feed as uncommitted build inputs. No firmware image was rebuilt and DEFAULT_PACKAGES was not changed.

## Remaining acceptance gates

The parent integration task owns OpenWrt package downloads/builds, IPK dependency/conffile/license/XML checks, target interpreter imports, USERID availability, real procd and nft lifecycle tests, UI/ACL tests, and image size measurement. No package build or router deployment was performed by the backend task. Installing this feed package alone does not replace firmware default vlmcsd; that is a separate authorized firmware transition. Verify alternate-port operation without disrupting an existing service first.
