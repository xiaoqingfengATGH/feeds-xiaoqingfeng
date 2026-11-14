# 非 Python 测试与夹具审查

> 最新决定以 CURRENT-IMPLEMENTATION-CLEANUP.md 为准：本轮另删除 43 个已退出实现的测试/夹具/驱动；不是继续禁用保留。当前本机为 86 tests、54 subtests，另有 8 项 Worker 与目标证书两组；已纳入 current suite。下文旧数量和保留说明为此前记录，不再作为当前状态。

> 历史记录/初步审查，非当前执行指南。R8/R9 危险生产驱动已删除，历史生产写入入口已禁用；最终保留/删除决定及有效命令见 homepublish/tests/TEST-AUDIT-DECISIONS.md 与 TEST-SUITE.md。

范围：tests 目录内 Lua、shell、C、JavaScript 与二进制夹具；不含 Python、文档、Makefile 和生成的 __pycache__。引用为文件名文本匹配，动态拼接或间接调用可能遗漏；依赖为静态证据，不保证穷尽。未执行任何设备测试。

判定规则：出现历史路径或里程碑仅表示需复核，不足以证明断言被替代；即使同主题，也不视为逐断言等价。未发现经证明完整替代且可安全删除的文件，因此全部保留。对于无法确认当前适用性或替代覆盖的项，列为待复核；引用存在也不证明成功运行。

| 文件 | 定位 / 静态依赖 | 本仓库直接引用（最多 4 个） | 过时及替代覆盖判断 |
|---|---|---|---|
| `build-r8.sh` | 历史构建脚本；shell；make, flock；SDK/源码/构建环境 | 未找到文件名字面引用（不排除动态调用） | 历史硬编码/旧里程碑，当前适用性待复核；无逐断言替代证据，保留 |
| `build-r9.sh` | 历史构建脚本；shell；make, flock；SDK/源码/构建环境 | 未找到文件名字面引用（不排除动态调用） | 历史硬编码/旧里程碑，当前适用性待复核；无逐断言替代证据，保留 |
| `build-tcp-identity-components.sh` | 历史构建脚本；shell；nginx, curl, make, flock；SDK/源码/构建环境 | 未找到文件名字面引用（不排除动态调用） | 历史硬编码/旧里程碑，当前适用性待复核；无逐断言替代证据，保留 |
| `build-tcp-p3-nginx.sh` | 历史构建脚本；shell；nginx, make, flock；SDK/源码/构建环境 | 未找到文件名字面引用（不排除动态调用） | 历史硬编码/旧里程碑，当前适用性待复核；无逐断言替代证据，保留 |
| `build-tcp-private-components.sh` | 历史构建脚本；shell；nginx, curl, make, flock；SDK/源码/构建环境 | 未找到文件名字面引用（不排除动态调用） | 历史硬编码/旧里程碑，当前适用性待复核；无逐断言替代证据，保留 |
| `controller-adapter.c` | C 测试夹具/探针；C 编译器；guardian-nginx-fixture.c, lua.h, lauxlib.h | `tests/test-controller-recovery.py`, `tests/test-controller.py` | 未证实过时；无完整替代证据，保留 |
| `controller-host.lua` | Lua 辅助夹具；Lua；模块 direct-renderer, homepublish_controller_test, product-controller, product-wire | `tests/test-controller-multi.py`, `tests/test-controller-recovery.py`, `tests/test-controller.py` | 未证实过时；无完整替代证据，保留 |
| `device-backend-host-header.lua` | Lua 设备夹具；Lua；模块 direct-renderer, luci.jsonc；OpenWrt 目标及对应运行器 | `tests/run-device-backend-host-header.py` | 未证实过时；无完整替代证据，保留 |
| `device-ddns-bridge.lua` | Lua 设备夹具；Lua；模块 nixio, nixio.fs, product-json；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-ddns-lifecycle.lua` | Lua 设备夹具；Lua；模块 nixio.fs, product-json；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-ddns-rpc.lua` | Lua 设备夹具；Lua；模块 product-json；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-ddns-schema.lua` | Lua 设备夹具；Lua；源码路径/运行器参数；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-http-provider.lua` | Lua 设备夹具；Lua；模块 product-system-provider；OpenWrt 目标及对应运行器 | `tests/run-device-http-runtime.py`, `tests/test-http-runtime.py` | 未证实过时；无完整替代证据，保留 |
| `device-legacy-lua-scope.lua` | Lua 设备夹具；Lua；源码路径/运行器参数；OpenWrt 目标及对应运行器 | `tests/device-tcp-p3-controller-cli.lua`, `tests/device-tcp-p3-installed-cli.lua`, `tests/device-tcp-p4-installed-cli.lua`, `tests/device-tcp-p4-negative-cli.lua` 等 10 处 | 未证实过时；无完整替代证据，保留 |
| `device-lua-store-capabilities.lua` | Lua 设备夹具；Lua；模块 nixio, nixio.fs；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-lua-store-provider.lua` | Lua 设备夹具；Lua；模块 nixio.fs；OpenWrt 目标及对应运行器 | `tests/run-device-lua-store-provider.py` | 未证实过时；无完整替代证据，保留 |
| `device-lua-store.lua` | Lua 设备夹具；Lua；模块 nixio, nixio.fs；OpenWrt 目标及对应运行器 | `tests/run-device-lua-store.py` | 未证实过时；无完整替代证据，保留 |
| `device-p1-lua-scope.lua` | Lua 设备夹具；Lua；源码路径/运行器参数；OpenWrt 目标及对应运行器 | `tests/device-tcp-p1-backup.lua`, `tests/device-tcp-p1-errors.lua`, `tests/device-tcp-p1-provider.lua`, `tests/run-device-tcp-p1-lua.py` 等 6 处 | 未证实过时；无完整替代证据，保留 |
| `device-rdp.lua` | Lua 设备夹具；Lua；模块 canonical-v2, direct-renderer；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-renew-classification.lua` | Lua 设备夹具；Lua；模块 product-controller, product-firewall-system, product-v2-runtime；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-restart-daemon.lua` | Lua 设备夹具；Lua；模块 nixio, nixio.fs, product-channel, product-json, product-provider, product-restart；OpenWrt 目标及对应运行器 | `tests/device-restart-procd.lua` | 未证实过时；无完整替代证据，保留 |
| `device-restart-marker.lua` | Lua 设备夹具；Lua；模块 nixio, nixio.fs, product-json, product-restart；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-restart-procd.lua` | Lua 设备夹具；Lua；源码路径/运行器参数；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-restart.lua` | Lua 设备夹具；Lua；模块 nixio.fs, product-controller, product-provider, product-wire；OpenWrt 目标及对应运行器 | `tests/TEST-SUITE.md` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p0-baseline.sh` | 设备/路由器脚本；shell；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p0-identity.lua` | Lua 设备夹具；Lua；模块 nixio, nixio.fs；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p0-probe.lua` | Lua 设备夹具；Lua；模块 nixio, nixio.fs；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p1-backup.lua` | Lua 设备夹具；Lua；模块 nixio, nixio.fs；OpenWrt 目标及对应运行器 | `tests/run-device-tcp-p1-lua.py`, `tests/test_p1_lua_runner_safety.py` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p1-errors.lua` | Lua 设备夹具；Lua；源码路径/运行器参数；OpenWrt 目标及对应运行器 | `tests/run-device-tcp-p1-lua.py`, `tests/test_p1_lua_runner_safety.py` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p1-json.lua` | Lua 设备夹具；Lua；源码路径/运行器参数；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p1-model.lua` | Lua 设备夹具；Lua；源码路径/运行器参数；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p1-network.lua` | Lua 设备夹具；Lua；源码路径/运行器参数；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p1-provider.lua` | Lua 设备夹具；Lua；源码路径/运行器参数；OpenWrt 目标及对应运行器 | `tests/run-device-tcp-p1-lua.py`, `tests/test_p1_lua_runner_safety.py` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p2-ui.lua` | Lua 设备夹具；Lua；源码路径/运行器参数；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-controller-adapter.lua` | Lua 设备夹具；Lua；模块 canonical-v2, direct-renderer, product-procd-group；OpenWrt 目标及对应运行器 | `tests/run-device-tcp-p3-controller.py`, `tests/run-device-tcp-p4-lifecycle.py`, `tests/run-device-tcp-p4-policy.py` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-controller-cli.lua` | Lua 设备夹具；Lua；模块 device-tcp-p3-controller-adapter, product-controller, product-json, product-provider；OpenWrt 目标及对应运行器 | `tests/run-device-tcp-p3-controller.py`, `tests/run-device-tcp-p4-lifecycle.py`, `tests/run-device-tcp-p4-policy.py`, `tests/test_legacy_lua_runner_safety.py` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-https-matrix-render.lua` | Lua 设备夹具；Lua；模块 canonical-v2, direct-renderer；OpenWrt 目标及对应运行器 | `tests/device-tcp-p3.sh` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-installed-cli.lua` | Lua 设备夹具；Lua；模块 product-controller, product-device-provider, product-json, product-provider；OpenWrt 目标及对应运行器 | `tests/run-device-tcp-p3-controller.py`, `tests/test_legacy_lua_runner_safety.py` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-matrix-render.lua` | Lua 设备夹具；Lua；模块 device-integrations, direct-backend, direct-renderer, nixio；OpenWrt 目标及对应运行器 | `tests/device-tcp-p3-matrix.sh` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-matrix.sh` | 设备/路由器脚本；shell；lua, nginx, openssl, curl, ssh；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-mixed-render.lua` | Lua 设备夹具；Lua；模块 direct-renderer；OpenWrt 目标及对应运行器 | `tests/device-tcp-p3-mixed.sh` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-mixed.sh` | 设备/路由器脚本；shell；lua, nixio, nginx, openssl, curl；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-post-render.lua` | Lua 设备夹具；Lua；模块 device-integrations, direct-renderer, nixio；OpenWrt 目标及对应运行器 | `tests/device-tcp-p3-matrix.sh` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-reject.lua` | Lua 设备夹具；Lua；模块 nixio；OpenWrt 目标及对应运行器 | `tests/device-tcp-p3-matrix.sh`, `tests/device-tcp-p3-mixed.sh`, `tests/device-tcp-p3-ssh.sh` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-render.lua` | Lua 设备夹具；Lua；模块 canonical-v2, direct-renderer；OpenWrt 目标及对应运行器 | `tests/device-tcp-p3.sh` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-ssh-render.lua` | Lua 设备夹具；Lua；模块 direct-renderer；OpenWrt 目标及对应运行器 | `tests/device-tcp-p3-ssh.sh` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-ssh.sh` | 设备/路由器脚本；shell；lua, nixio, nginx, openssl, curl, ssh；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-tcp-render.lua` | Lua 设备夹具；Lua；模块 direct-renderer；OpenWrt 目标及对应运行器 | `tests/device-tcp-p3-tcp.sh` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-tcp-sockets.lua` | Lua 设备夹具；Lua；模块 nixio；OpenWrt 目标及对应运行器 | `tests/device-tcp-p3-tcp.sh` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3-tcp.sh` | 设备/路由器脚本；shell；lua, nginx, ssh；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p3.sh` | 设备/路由器脚本；shell；lua, nixio, nginx, openssl, curl；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p4-installed-cli.lua` | Lua 设备夹具；Lua；模块 product-controller, product-device-provider, product-json, product-provider；OpenWrt 目标及对应运行器 | `tests/device-tcp-p4-negative-cli.lua`, `tests/run-device-tcp-p4-lifecycle.py`, `tests/test_legacy_lua_runner_safety.py` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p4-negative-cli.lua` | Lua 设备夹具；Lua；模块 nixio, product-controller, product-device-provider, product-json, ubus, uci；OpenWrt 目标及对应运行器 | `tests/p4_negative.py`, `tests/test_legacy_lua_runner_safety.py` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p4-policy-rpc.lua` | Lua 设备夹具；Lua；模块 nixio, nixio.fs, product-controller, product-device-provider, product-json, product-provider；OpenWrt 目标及对应运行器 | `tests/run-device-tcp-p4-policy.py`, `tests/run-device-tcp-p4-ui.py`, `tests/test_legacy_lua_runner_safety.py` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p5-four-cli.lua` | Lua 设备夹具；Lua；模块 product-controller, product-json, product-provider, product-system-provider；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p5-matrix-cli.lua` | Lua 设备夹具；Lua；模块 product-controller, product-json, product-provider, product-system-provider；OpenWrt 目标及对应运行器 | `tests/run-device-tcp-p5-matrix.py` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p5-production-cli.lua` | Lua 设备夹具；Lua；模块 product-controller, product-json, product-provider, product-system-provider；OpenWrt 目标及对应运行器 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `device-tcp-p5-readiness.lua` | Lua 设备夹具；Lua；模块 product-v2-runtime；OpenWrt 目标及对应运行器 | `tests/test-startup-components.py` | 未证实过时；无完整替代证据，保留 |
| `device-tcp-prerequisites.sh` | 设备/路由器脚本；shell；nginx；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `direct-boundary-fixture.lua` | Lua 辅助夹具；Lua；模块 direct-renderer | `tests/test-direct-boundary.py` | 未证实过时；无完整替代证据，保留 |
| `direct-fixture.lua` | Lua 辅助夹具；Lua；源码路径/运行器参数 | `tests/test-direct.py`, `tests/test-guardian-nginx.py` | 未证实过时；无完整替代证据，保留 |
| `guardian-nginx-fixture.c` | C 测试夹具/探针；C 编译器；renewable-guard.h, owned-runtime.h, trusted-nginx.h, assert.h, errno.h, fcntl.h | `tests/controller-adapter.c`, `tests/test-guardian-nginx.py`, `tests/test-trusted-provider.py` | 未证实过时；无完整替代证据，保留 |
| `owned-runtime-probe.c` | C 测试夹具/探针；C 编译器；renewable-guard.h, owned-runtime.h, assert.h, fcntl.h, stdio.h, string.h | `tests/test-owned-runtime.py` | 未证实过时；无完整替代证据，保留 |
| `preparation-fault.c` | C 测试夹具/探针；C 编译器；unistd.h, errno.h, stdlib.h, sys/stat.h | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `private-pair-probe.c` | C 测试夹具/探针；C 编译器；renewable-guard.h, assert.h, errno.h, fcntl.h, netinet/in.h, poll.h | `tests/Makefile` | 历史硬编码/旧里程碑，当前适用性待复核；无逐断言替代证据，保留 |
| `product-store-fault.c` | C 测试夹具/探针；C 编译器；dlfcn.h, unistd.h, stdlib.h, string.h, errno.h, sys/stat.h | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `publication-bridge.mjs` | Node 测试夹具；Node.js；node:readline, ../files/usr/share/homepublish/worker/worker.mjs | `tests/test-publication.py` | 未证实过时；无完整替代证据，保留 |
| `publication-fixture.mjs` | Node 测试夹具；Node.js；../files/usr/share/homepublish/worker/worker.mjs | `tests/publication-worker.test.mjs`, `tests/worker.test.mjs` | 未证实过时；无完整替代证据，保留 |
| `publication-worker.test.mjs` | Node 测试；Node.js；node:test, node:assert/strict, ./publication-fixture.mjs | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `renewable-guard-fixture.c` | C 测试夹具/探针；C 编译器；renewable-guard.h, assert.h, arpa/inet.h, poll.h, signal.h, stdio.h | `tests/test-renewable-guard.py` | 未证实过时；无完整替代证据，保留 |
| `renewable-start-faults.c` | C 测试夹具/探针；C 编译器；renewable-guard.h, assert.h, errno.h, poll.h, stdarg.h, stdlib.h | `tests/test-renewable-guard.py` | 未证实过时；无完整替代证据，保留 |
| `renewable-tree-fixture.c` | C 测试夹具/探针；C 编译器；renewable-guard.h, assert.h, arpa/inet.h, errno.h, poll.h, signal.h | `tests/test-renewable-guard.py` | 未证实过时；无完整替代证据，保留 |
| `router-business-tls.sh` | 设备/路由器脚本；shell；lua, openssl, curl；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-dns-replan.sh` | 设备/路由器脚本；shell；lua, nixio, nginx, openssl, curl, make；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-failure.sh` | 设备/路由器脚本；shell；nginx；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-faults.sh` | 设备/路由器脚本；shell；nginx, openssl；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-guarded-provision.sh` | 设备/路由器脚本；shell；procd；隔离目标/专用路径 | `README.md` | 未证实过时；无完整替代证据，保留 |
| `router-guardian-stop.sh` | 设备/路由器脚本；shell；nginx；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-integrations.sh` | 设备/路由器脚本；shell；lua, nginx, openssl, curl；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-lock-window.sh` | 设备/路由器脚本；shell；nginx；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-preparation-crash.sh` | 设备/路由器脚本；shell；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-preparation.sh` | 设备/路由器脚本；shell；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-publication-uci.sh` | 设备/路由器脚本；shell；lua, uci, curl, procd；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-r7-browser-setup.sh` | 设备/路由器脚本；shell；uci, openssl；隔离目标/专用路径 | `tests/run-r8-overview.py`, `tests/run-r9-device.py` | 历史硬编码/旧里程碑，当前适用性待复核；无逐断言替代证据，保留 |
| `router-sdk-native.sh` | 设备/路由器脚本；shell；lua, uci, nginx, openssl, curl, procd；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-simple-multi.sh` | 设备/路由器脚本；shell；lua, nginx, openssl, curl, procd；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-smoke.sh` | 设备/路由器脚本；shell；uci, nginx, openssl, curl；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-source-cleanup.sh` | 设备/路由器脚本；shell；procd；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-term.sh` | 设备/路由器脚本；shell；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `router-trust.sh` | 设备/路由器脚本；shell；nginx, curl；隔离目标/专用路径 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `run-publication-security.sh` | shell 测试入口；shell | 未找到文件名字面引用（不排除动态调用） | 历史硬编码/旧里程碑，当前适用性待复核；无逐断言替代证据，保留 |
| `sdk-target-probe.c` | C 测试夹具/探针；C 编译器；sys/socket.h, sys/syscall.h, sys/prctl.h, linux/seccomp.h, linux/filter.h, stddef.h | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `startup-owned-contract.c` | C 测试夹具/探针；C 编译器；renewable-guard.h, owned-runtime.h, assert.h, errno.h, fcntl.h, poll.h | `tests/test-startup-owned.py` | 未证实过时；无完整替代证据，保留 |
| `startup-owned-faults.c` | C 测试夹具/探针；C 编译器；renewable-guard.h, owned-runtime.h, assert.h, arpa/inet.h, sys/socket.h, errno.h | `tests/test-startup-owned.py` | 未证实过时；无完整替代证据，保留 |
| `test-business-provider.lua` | Lua 测试；Lua；模块 device-integrations, product-device-provider | `tests/Makefile` | 未证实过时；无完整替代证据，保留 |
| `test-canonical.lua` | Lua 测试；Lua；源码路径/运行器参数 | `tests/run-device-tcp-p1-lua.py`, `tests/test-certificate-model.lua`, `tests/test-startup-components.py` | 未证实过时；无完整替代证据，保留 |
| `test-certificate-inventory.lua` | Lua 测试；Lua；模块 certificate-metadata, device-integrations, product-json | `tests/Makefile` | 未证实过时；无完整替代证据，保留 |
| `test-certificate-model.lua` | Lua 测试；Lua；源码路径/运行器参数 | `tests/Makefile`, `tests/test-startup-components.py` | 未证实过时；无完整替代证据，保留 |
| `test-certificate-san.lua` | Lua 测试；Lua；模块 certificate-metadata | `tests/Makefile`, `tests/test-startup-components.py` | 未证实过时；无完整替代证据，保留 |
| `test-config.lua` | Lua 测试；Lua；源码路径/运行器参数 | `README.md` | 未证实过时；无完整替代证据，保留 |
| `test-core.lua` | Lua 测试；Lua；源码路径/运行器参数 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `test-device-dns.lua` | Lua 测试；Lua；模块 product-device-provider | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `test-device-integrations.lua` | Lua 测试；Lua；模块 device-integrations | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `test-device-stop.lua` | Lua 测试；Lua；模块 product-device-provider | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `test-direct.lua` | Lua 测试；Lua；源码路径/运行器参数 | `tests/test-direct.py`, `tests/test-startup-components.py` | 未证实过时；无完整替代证据，保留 |
| `test-product-provider.lua` | Lua 测试；Lua；源码路径/运行器参数 | `tests/run-device-tcp-p1-lua.py`, `tests/test_p1_lua_runner_safety.py` | 未证实过时；无完整替代证据，保留 |
| `test-product-review.lua` | Lua 测试；Lua；源码路径/运行器参数 | `tests/run-device-tcp-p1-lua.py`, `tests/test_p1_lua_runner_safety.py` | 未证实过时；无完整替代证据，保留 |
| `test-publication-config.lua` | Lua 测试；Lua；源码路径/运行器参数 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `test-publication-service.sh` | shell 测试入口；shell；lua, uci, curl, procd, flock | `tests/router-publication-uci.sh` | 未证实过时；无完整替代证据，保留 |
| `test-req013.lua` | Lua 测试；Lua；模块 canonical-v2, direct-renderer, tcp-route-plan | `tests/Makefile` | 未证实过时；无完整替代证据，保留 |
| `test-service.sh` | shell 测试入口；shell；lua, uci, procd | `README.md` | 未证实过时；无完整替代证据，保留 |
| `test-shared-provider.lua` | Lua 测试；Lua；模块 device-integrations, product-device-provider | `tests/Makefile` | 未证实过时；无完整替代证据，保留 |
| `test-simple-multi.lua` | Lua 测试；Lua；模块 device-integrations, product-device-provider | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `token-io-injection.c` | C 测试夹具/探针；C 编译器；unistd.h, fcntl.h, errno.h, stdarg.h, stdio.h, string.h | `tests/test-token-validation.py` | 未证实过时；无完整替代证据，保留 |
| `uci-lease.bin` | 二进制夹具；预编译目标产物；架构/来源待核实；SHA256 5670dc04f5b1e5d8 | 未找到文件名字面引用（不排除动态调用） | 未证实过时；无完整替代证据，保留 |
| `worker.test.mjs` | Node 测试；Node.js；node:test, node:assert/strict, ./publication-fixture.mjs, ../files/usr/share/homepublish/worker/worker.mjs | `README.md` | 未证实过时；无完整替代证据，保留 |

## 未解决项

- 逐断言比对历史用例与现行架构及替代测试仍需完成；本表不将主题相似或名称相似当成替代证明。
- 路由器/设备脚本可能读写目标文件、启动进程或占用端口，必须先审查具体运行器与隔离条件并获得授权；本次未连接生产设备。
- 历史构建脚本硬编码 SDK、工作区、制品路径和版本，需针对现有构建环境重新核验；不要直接运行。
- 二进制夹具的构建来源、目标架构和当前依赖需进一步核验；保留以免破坏间接调用。
- 本次运行 `node --test homepublish/tests/worker.test.mjs homepublish/tests/publication-worker.test.mjs`：8 个测试通过；其余文件仅静态审查，未声明运行通过。
