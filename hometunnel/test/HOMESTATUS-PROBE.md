# HomeStatus probe

`files/etc/homestatus-probes/hometunnel` is installed executable (0755) by the
**hometunnel** package, without depending on luci-app-homestatus. Run as root.
Exit codes: **0** running, **1** positively stopped, **2** unknown. No stdout.

## Existing UI → RPC → backend

* `luci-app-hometunnel/.../view/hometunnel/status.js:13-27,56-68,123-139`
  calls `service.list(name)` and reads `res[name].instances[name].running`.
  It displays **Tunnel service** and, only in ondemand mode, **Switch daemon**
  separately. There is no existing single aggregate status in this page.
* `fs.exec('/usr/share/hometunnel/hometunnel.sh', ['status'])` is a separate
  rpcd file/exec path authorized by `luci-app-hometunnel.json`. Its backend
  `cmd_status()` calls both init scripts with `running`, queries the Worker
  `/cmd`, and checks the Cloudflare tunnel. Do **not** reuse that command from
  a probe executing inside rpcd: init status uses ubus, and remote queries
  would add latency and unrelated connectivity failure semantics.
* `files/etc/init.d/hometunnel-ctl:42-46` registers the named procd instance
  `/bin/sh /usr/share/hometunnel/ctl-loop.sh`.
* `files/etc/init.d/hometunnel:43-55` registers the named cloudflared instance,
  with `tunnel ... --config /etc/hometunnel/config.yml ... run`.

## Single application status policy

The summary preserves the page's **local process-liveness** meaning, selecting
its relevant component for each configured mode:

| Mode | Summary component | Idle / switch OFF |
| --- | --- | --- |
| ondemand (also absent mode option) | switch daemon | 0 when daemon is alive, even if the data plane is stopped |
| alwayson | locally-managed cloudflared data plane | 1 if that process is absent |

This mode-aware aggregation is an explicit summary policy, not a claim that the
UI already has an aggregate lamp. It does not report Worker reachability,
Cloudflare connection health, ingress reachability, wizard completion, or UCI
`enabled` intent. An already running process remains running even if config
was disabled but not yet applied. Invalid/missing UCI section, invalid mode,
missing procfs or persistent unreadable process entries return 2. A live
matching process is sufficient positive evidence despite other unreadable PIDs.

No service, init script, ubus, network client, credentials or application
backend is invoked. The script only reads UCI and procfs. Exact command
arguments distinguish this application's processes from unrelated cloudflared
instances and substring lookalikes. As with any procfs snapshot, processes can
change immediately after observation. A manually started process with the
identical command is indistinguishable from procd ownership; a future init
command/path change must update this probe and tests. BusyBox ash compatibility
is intended; local tests use Git Bash sh, not a live OpenWrt runtime.

## Isolated verification

Run `python hometunnel/test/test-homestatus-probe.py` from the feed root.
The harness rewrites only the procfs path in a temporary script copy, stubs UCI,
rejects known ubus/network/lifecycle commands, checks silent exit codes and
unchanged fake procfs, and executes the actual package install recipe into a
temporary staging directory (no OpenWrt SDK/build required).
