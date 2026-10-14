# HomeTunnel theme-unified IPK checkpoint

Scope: luci-app-hometunnel only; no theme/HomeStatus deployment, merge, push or PR.

Package source base: 3681a77878f8b103e672aed5d5fae3d328dc91d1.
Candidate package: 1.0.0-r2 (source was r1). JavaScript minification is explicitly disabled so SDK output can be compared against the frozen Git blobs.

At preparation time the authorized SSH mapping 127.0.0.1:222 refused connections twice. Installed version and collision check are therefore NOT verified. Do not install until connectivity, installed version, dependencies, root-private backup, pending UCI changes and lifecycle scripts have been inspected.

Cache caveat: application PKG_RELEASE is not evidence that LuCI module URLs change. Previously observed global resource_version was 26.268.60624~3e89467-1791937154. No global loader/theme/luci-base changes are made. A first cache-bypassing navigation plus actual HTTP response hashes is required for acceptance; automatic invalidation for all users is not claimed.

Runtime tunnel control, setup steps, configuration writes and service restarts are out of scope. Preserve active configurations and running/enabled service states; keep opkg sidecars separate. Any deployment must first audit the real built postinst/prerm and the target default_postinst.
