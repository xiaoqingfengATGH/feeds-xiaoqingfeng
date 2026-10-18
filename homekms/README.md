# HomeKMS backend

See [integration and verification notes](../docs/HOMEKMS.md).

Local checks (Python executable is `python` on the Windows authoring host):

```
HOMEKMS_ARCHIVE=/path/to/source.tar.gz python homekms/tests/test_packaging.py -v
bash homekms/tests/test_lifecycle.sh
bash homekms/tests/test_discovery.sh
python homekms/tests/test_protocol.py --server-dir /path/to/py-kms --client /path/to/vlmcs
```

The protocol test requires an independently built Wind4/vlmcsd client and runs a disposable loopback server. It does not change Windows or Office license state.

## Service identity

`USERID:=homekms:homekms` requests dynamic UID/GID allocation. Do not pin 453:
the HomeLede build tree reserves that ID for dnsmasq. The VM's
`package/base-files/files/lib/functions.sh` parses missing numeric IDs and uses
`group_add_next` / `user_add` to select unused IDs starting at 32768, retaining
existing named accounts. procd resolves the `homekms` user/group by name.
The packaging regression checks this declaration; image/package installation
and target account resolution remain build/deployment acceptance checks.

## HomeStatus read-only probe

The backend package ships `/etc/homestatus-probes/homekms`, executed as root
with no arguments. Exit codes: **0 running**, **1 positively stopped**,
**2 observation unavailable/unknown**. It produces no output and writes no
configuration/runtime files; `python3 -B` also prevents bytecode cache writes.
The existing recursive `files/*` install includes it and the Makefile explicitly
sets mode 0755; no LuCI package or HomeStatus change is necessary.

Source trace: `luci-app-homekms/.../view/homekms.js` `getStatus()` calls
`homekms.status`; `homekms/files/usr/libexec/rpcd/homekms` reads procd
`homekms.instances.main.running/pid`, validates `homekms.main.port`, and checks
PID fd/TCP readability. LuCI gates status on `checked === true`, then displays
`running`; PID-owned TCP listening is a separate row. Therefore an observed
service process with no listener remains **running**, not stopped. Invalid
ports or inaccessible process observations are **unknown**. Missing port falls
back to 1688 exactly as the RPC does. Neither the configured enable switch nor
WAN/DNS health is used as proof that the process runs.

The probe MUST NOT invoke the RPC or `ubus service list`: it may execute inside
HomeStatus's rpcd handler and a recursive ubus call can deadlock. Instead it
reads `/proc/*/cmdline` and matches the exact Python/interpreter/script prefix
from this package's `init.d/homekms` main command. It reproduces the RPC's
`checked` fd/TCP-readability gate (tcp6 optional), without requiring a socket.
The only child command is bounded `/sbin/uci -q get homekms.main.port`.
Incomplete enumeration/permission errors/process-exit races return unknown
rather than incorrectly declaring stopped. This conservative fallback cannot
prove procd instance ownership: manually launching the identical command also
counts as running. Keep the prefix synchronized if the init command changes;
a future trusted local procd snapshot could remove this limitation without
re-entering ubus. This is a runtime indicator, not a KMS activation test.

Run isolated tests from the feed root:

```
python -B -m unittest discover -s homekms/tests -p test_homestatus_probe.py -v
```

Tests use a temporary fake proc tree and mocked read-only UCI observations;
they do not start/stop services or contact a router. Device/procd parity and
full IPK installation remain separate acceptance checks.
