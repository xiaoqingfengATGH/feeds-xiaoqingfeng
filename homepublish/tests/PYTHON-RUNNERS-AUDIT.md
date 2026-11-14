# HomePublish Python 入口与夹具逐文件审查

> 最新决定以 CURRENT-IMPLEMENTATION-CLEANUP.md 为准：本轮另删除 43 个已退出实现的测试/夹具/驱动；不是继续禁用保留。当前本机为 86 tests、54 subtests，另有 8 项 Worker 与目标证书两组；已纳入 current suite。下文旧数量和保留说明为此前记录，不再作为当前状态。

> 历史记录/初步审查，非当前执行指南。R8/R9 危险生产驱动已删除，历史生产写入入口已禁用；最终保留/删除决定及有效命令见 homepublish/tests/TEST-AUDIT-DECISIONS.md 与 TEST-SUITE.md。

## 范围、方法与结论

范围为 `homepublish/tests` 递归现存、文件名不以 `test` 开头的全部 `.py`，包括未跟踪的当前入口，共 61 个；不包括测试文件本身。基于工作树静态检查源码、import、动态加载、设备操作、已有文档及调用者；没有连接设备、运行任何设备脚本或写设备。保留用户现有未提交修改。引用搜索包含仓库代码/文档的字面文件名及模块名，但无法发现仓库外调用、构造字符串和人工操作；无引用不等于无依赖。以下“保留”不是认证可安全执行，私有设备写入同样违反本次零设备写入要求。

当前架构以 Lua store/provider、显式清单宿主测试与可选私有设备测试为主；P3/P4/P5/R8/R9 则包含历史环境和旧隔离假设。线上真实配置、服务和外网不可用静态代码代替验证。网络、SSH、openssl/nginx、root chroot、第三方 Lua/Python/Node 及历史硬编码路径均是实际运行前提。`assert` 承担大量保护和验收，不应使用 `python -O` 运行。不要盲目 import：多个脚本顶层执行远程或本地操作。SSH 密钥路径/IP 只是硬编码配置，不代表本次授权或设备实际状态。

**删除决定：本次没有删除。** 旧 native/R8/R9 工具明确存在架构过时或危险操作，但仍有历史调用、专用覆盖或证据链；未证明所有调用和覆盖已被当前方案替代，不能将“当前白名单未包含”当成安全删除依据。R8/R9 的删除应先逐项迁移普通 UI 生命周期和故障覆盖、修复引用并验证，再做；禁止执行其生产目录恢复脚本。高风险与特定缺陷见各项。状态是静态结论，不是设备验证结果。

## 逐文件

每项依次列作用、依赖/调用/风险与保留理由；缺失动态调用不能据此断言无调用。相对路径均在 `homepublish/tests/`。

### `check-current-ipk.py`

- **作用**：当前 IPK 内容、元数据与源码核对。
- **依赖、调用与风险**：stdlib tarfile/hashlib；由 TEST-SUITE 指引；替代已删除旧 test-ipk 的明确意图，实际 IPK 未验证。
- **决定**：保留：当前包级检查入口。

### `check-input-firewall-fw4.py`

- **作用**：读取目标 firewall4 并通过 Lua 模拟规则。
- **依赖、调用与风险**：SSH、lupa.lua51、opkg；只读固件探测，不等价真实 nft 提交。
- **决定**：保留：固件兼容探针。

### `check-input-firewall-isolated.py`

- **作用**：隔离 INPUT 规则与连通性验收。
- **依赖、调用与风险**：SSH、nft、私有控制器及监听器；实际修改目标 nft/进程，依赖空所有权命名空间。
- **决定**：保留：真实防火墙负例尚无确认等价替代，非只读。

### `check-listener-isolated.py`

- **作用**：隔离 procd 监听器验收。
- **依赖、调用与风险**：SSH、目标 Python/Lua/procd，PORT-CHECK-ACCEPTANCE；复制代码与私有服务。
- **决定**：保留：真实端口所有权验证。

### `check-owned-listeners-device.py`

- **作用**：注入源代码验证 socket 所有权。
- **依赖、调用与风险**：SSH、目标 Lua/nixio、私有 loopback socket；不是零设备写入。
- **决定**：保留：已安装监听器判定的针对性覆盖。

### `controller-health.py`

- **作用**：测试用本地 TLS/后端健康探针。
- **依赖、调用与风险**：socket、ssl；以脚本参数提供探针；不是生产 SAN 权威。
- **决定**：保留：专用测试夹具，动态调用无法排除。

### `dependency_maps.py`

- **作用**：解析进程 maps 并验证依赖信任。
- **依赖、调用与风险**：test-audit-regressions.py、test-guardian-nginx.py；系统路径；provider 信任非 UID 沙箱。
- **决定**：保留：现有测试直接引用。

### `deploy-access-method-help.py`

- **作用**：部署三份接入方式 LuCI JS。
- **依赖、调用与风险**：SSH、目标文件、备份及受保护状态哈希；直接写线上文件。
- **决定**：保留：历史定向部署回执不可等价于新部署，可疑一次性但尚未证明无外部调用。

### `deploy-backend-host-header.py`

- **作用**：部署后端 Host override 源码和 UI。
- **依赖、调用与风险**：SSH、ubus、目标服务；被 finalize/receipt/verify 动态载入；会启动服务。
- **决定**：保留：多个后续工具依赖；重新运行可能影响生产。

### `deploy-ddns-phase2.py`

- **作用**：部署 DDNS phase2 源码。
- **依赖、调用与风险**：SSH、rpcd、homepublish、已有状态；resume-ddns-phase2 动态提取代码；会 reload/start。
- **决定**：保留：恢复脚本存在，注释不证明无 DNS 副作用。

### `deploy-host-port-nat.py`

- **作用**：部署 Host/端口 NAT renderer。
- **依赖、调用与风险**：SSH、目标 renderer 和服务；verify-host-port-nat 使用部署回执；会 start。
- **决定**：保留：验收回执链；历史脚本不是通用部署器。

### `deploy-overview-public-entry.py`

- **作用**：备份并部署 overview.js。
- **依赖、调用与风险**：SSH/scp、LuCI 目标与保护哈希；直接写线上。
- **决定**：保留：历史部署恢复线索，未证实可安全删除。

### `deploy-save-recovery.py`

- **作用**：部署 UI 保存恢复功能。
- **依赖、调用与风险**：SSH、ubus 和生产快照；直接覆盖 UI 文件。
- **决定**：保留：定向部署回执，未核实外部调用。

### `deploy-service-simplification.py`

- **作用**：部署服务简化 Lua/UI。
- **依赖、调用与风险**：SSH、目标状态、服务启停；SERVICE-ADVANCED-AUDIT 引用。
- **决定**：保留：历史审计追溯；禁止假定可直接复用。

### `deploy-services-description.py`

- **作用**：部署服务描述 UI。
- **依赖、调用与风险**：SSH、生产文件与快照；会清 LuCI 缓存。
- **决定**：保留：历史操作追溯；不能视为只读。

### `deploy-services-loading.py`

- **作用**：部署服务加载反馈 UI。
- **依赖、调用与风险**：SSH、controller/status；直接写 UI。
- **决定**：保留：功能专用历史部署记录。

### `deploy-services-save-fix.py`

- **作用**：从 upstream-tls 部署器改写并执行 canonical loader 修复。
- **依赖、调用与风险**：读取 deploy-upstream-tls-source.py 并 exec 文本；强依赖精确字符串与原脚本行为。
- **决定**：保留：脆弱但尚无经验证替代；运行会部署。

### `deploy-upstream-tls-source.py`

- **作用**：部署 upstream TLS Lua/UI。
- **依赖、调用与风险**：SSH、服务和保护哈希；被两 deploy 包装和 verify 动态加载；会 start。
- **决定**：保留：现有调用链基础；依赖特定生产环境。

### `deploy-wildcard-certificate.py`

- **作用**：复用并改写 upstream TLS 部署器部署通配证书。
- **依赖、调用与风险**：文本替换 exec deploy-upstream-tls-source.py；对源码格式脆弱。
- **决定**：保留：未证实行为被其他入口覆盖；执行有生产写入。

### `deploy-wildcard-entry-label.py`

- **作用**：更新证书入口标签。
- **依赖、调用与风险**：SSH、特定历史备份目录和目标 JS；期望文本硬编码。
- **决定**：保留：历史追溯，硬编码备份使当前可运行性未经证实。

### `fetch-browser-deps.py`

- **作用**：获取 OpenWrt 发行版浏览器依赖到私有 overlay。
- **依赖、调用与风险**：urllib/tarfile、24.10.5 下载站；rpc-luci-fixture 依赖下载产物。
- **决定**：保留：浏览器 fixture 前置；网络及供应链校验需要单独核验。

### `finalize-backend-host-header-deploy.py`

- **作用**：核对并整理 Host 部署结束证据。
- **依赖、调用与风险**：动态加载 deploy-backend-host-header、目标已安装文件及证据目录。
- **决定**：保留：部署回执链；动态加载安全性取决于被载入模块顶层行为。

### `finalize-ddns-deploy.py`

- **作用**：整理 DDNS 部署后的运行和文件证据。
- **依赖、调用与风险**：依赖 deployment.json、SSH、目标 Lua 和历史状态。
- **决定**：保留：历史部署凭证闭环；不可假定适用当前设备。

### `investigate-installed-backend-save-apply.py`

- **作用**：已安装代码下私有保存、应用及流量排查。
- **依赖、调用与风险**：动态加载 upstream TLS traffic helper、目标源码、私有 journal/服务。
- **决定**：保留：覆盖保存到应用边界；私有设备写入及流量非生产 UI 证明。

### `legacy_lua_runner_support.py`

- **作用**：P3/P4 私有 Lua 隔离前置与哈希校验。
- **依赖、调用与风险**：p5_resume_support.upload；被 P3/P4 三 runner 导入，检查目标服务/端口并上传。
- **决定**：保留：安全前置不可拆掉；固定私有路径可能冲突。

### `p4_negative.py`

- **作用**：P4 生命周期有界负例。
- **依赖、调用与风险**：由 run-device-tcp-p4-lifecycle 导入；目标 procd、Lua helper，创建/删除 blocker。
- **决定**：保留：独立负例依赖，未证明当前其他测试替代。

### `p5_resume_support.py`

- **作用**：P5 SSH 上传和备份辅助。
- **依赖、调用与风险**：被 legacy helper、P3/P4/P5 使用；SSH 私钥路径可由环境覆盖；目标备份。
- **决定**：保留：共享依赖；备份行为不是只读。

### `receipt-backend-host-header-deploy.py`

- **作用**：Host 部署后验证流量及回执。
- **依赖、调用与风险**：动态加载 deploy-backend-host-header；SSH 和证据状态。
- **决定**：保留：历史回执与部署工具有真实依赖；不推断覆盖现网。

### `resume-ddns-phase2.py`

- **作用**：从历史 DDNS 部署脚本选取代码续跑。
- **依赖、调用与风险**：exec 脚本片段，依赖 def main 和文本边界；继承原脚本副作用。
- **决定**：保留：历史恢复链；脆弱且需要重新授权。

### `rpc-luci-fixture.py`

- **作用**：WSL root chroot 运行真实 rpcd/ubus/uhttpd 和 LuCI。
- **依赖、调用与风险**：test-browser-lifecycle、fetch-browser-deps、SDK、gcc、mount/chroot；仍编译 product-store.c。
- **决定**：保留：调用者存在；native-store 夹具与当前 Lua store 架构不一致，不能当当前架构验收；本机需特权。

### `run-current-suite.py`

- **作用**：白名单执行当前宿主/可选目标测试。
- **依赖、调用与风险**：pytest、lupa、Makefile 和 TEST-SUITE；--target 会写设备私有根。
- **决定**：保留：当前明确入口；当前审查未运行 --target。

### `run-device-backend-host-header.py`

- **作用**：后端 Host 持久化及真实 nginx vhost 流量。
- **依赖、调用与风险**：动态导入 upstream TLS traffic helper、私有 store/服务；设备写及监听。
- **决定**：保留：Host 与默认 vhost 负例针对性覆盖。

### `run-device-ddns.py`

- **作用**：隔离根执行 DDNS backend 测试。
- **依赖、调用与风险**：SSH、目标 Lua、staged 源码、生产哈希；宣称不 POST 生产 DNS。
- **决定**：保留：DDNS 目标适配覆盖；注释不能证明所有生产状态不变。

### `run-device-http-ingress.py`

- **作用**：HTTP 合同及真实 nginx 配置检查。
- **依赖、调用与风险**：导入 test-http-ingress，SSH、目标 nginx、私有根；nginx -t 可能绑定端口。
- **决定**：保留：源码至目标引擎语法验证。

### `run-device-http-runtime.py`

- **作用**：目标 Lua HTTP runtime 合同。
- **依赖、调用与风险**：从本地测试抽取内容、SSH、私有目录和状态哈希。
- **决定**：保留：真实 Lua 运行依赖覆盖，设备有私有写入。

### `run-device-http-traffic.py`

- **作用**：HTTP/HTTPS/TLS/SSH/TCP 私有流量与生命周期。
- **依赖、调用与风险**：SSH、真实 nginx/sslh/procd、私有 journal；私有 provider 去掉防火墙。
- **决定**：保留：真实多协议流量；不验证实际 firewall 或外网。

### `run-device-lua-store-provider.py`

- **作用**：目标私有 Lua store provider 测试。
- **依赖、调用与风险**：SSH、当前 Lua 源码、private root、生产状态哈希。
- **决定**：保留：当前架构 provider 覆盖。

### `run-device-lua-store.py`

- **作用**：运行真实 OpenWrt Lua store 测试。
- **依赖、调用与风险**：run-current-suite --target、SSH、nixio、私有目录；Lua-store migration 文档引用。
- **决定**：保留：当前存储专项入口。

### `run-device-private-wildcard-tls.py`

- **作用**：已安装 nginx 私有通配证书 TLS 正反例。
- **依赖、调用与风险**：SSH、已安装证书 provider/nginx、私有根和端口；生产只读不代表设备零写。
- **决定**：保留：证书 hostname/CA 真实引擎覆盖。

### `run-device-restart.py`

- **作用**：隔离 procd 重启语义。
- **依赖、调用与风险**：run-current-suite --target、SSH、私有 init/journal/procd。
- **决定**：保留：不重启生产但设备有写入；不是整机重启验收。

### `run-device-service-simplification.py`

- **作用**：复用流量 runner 验证简化服务 payload。
- **依赖、调用与风险**：动态加载 run-device-upstream-tls-traffic，替换 request；SERVICE-ADVANCED-AUDIT 引用。
- **决定**：保留：特定 payload 仍有覆盖价值；依赖被包装代码内部接口。

### `run-device-tcp-p1-lua.py`

- **作用**：目标 P1 Lua/nixio 合同。
- **依赖、调用与风险**：test-product/test-product-review 引用、SSH、已安装源哈希、私有 store。
- **决定**：保留：有调用证据；历史覆盖尚未逐项映射到当前 suite。

### `run-device-tcp-p3-controller.py`

- **作用**：P3 私有 controller 多协议生命周期。
- **依赖、调用与风险**：legacy_lua_runner_support、p5_resume_support、目标 procd/SSH；固定路径与端口。
- **决定**：保留：P3 特定真实链路及安全测试引用，需当前架构重新验收。

### `run-device-tcp-p4-lifecycle.py`

- **作用**：P4 生命周期及负例。
- **依赖、调用与风险**：legacy helper、p5 support、p4_negative；固定服务/端口；可写目标私有状态。
- **决定**：保留：负例及已有安全回归直接依赖。

### `run-device-tcp-p4-policy.py`

- **作用**：P4 策略、期限及故障。
- **依赖、调用与风险**：legacy helper、p5 support、目标 procd 和私有进程；含 kill -9。
- **决定**：保留：策略边界/故障注入未证实有等价替代；有设备副作用。

### `run-device-tcp-p4-ui.py`

- **作用**：以真实 LuCI 点击运行 P4 fixture。
- **依赖、调用与风险**：AST 修改并 exec run-device-tcp-p4-policy.py，调用 Node 浏览器测试。
- **决定**：保留：UI RPC 覆盖与 P4 进程链；对 AST/源码结构脆弱。

### `run-device-tcp-p5-complete.py`

- **作用**：P5 四协议和真实 SSH/TLS 端到端。
- **依赖、调用与风险**：p5_resume_support、目标私有服务/端口、证书和 SSH tunnel。
- **决定**：保留：真实协议认证覆盖；历史状态及清理假设需复核。

### `run-device-tcp-p5-four.py`

- **作用**：P5 四协议与保持连接的 stop 验收。
- **依赖、调用与风险**：p5_resume_support、历史 backup/four-cli 和目标 procd。
- **决定**：保留：连接保持/关闭覆盖；要求先前历史工件。

### `run-device-tcp-p5-matrix.py`

- **作用**：IPv4/IPv6 和四协议目标矩阵。
- **依赖、调用与风险**：p5 support、device-tcp-p5-matrix-cli.lua、真实引擎与证书。
- **决定**：保留：矩阵覆盖尚无证明完全替代；私有进程及端口有副作用。

### `run-device-tcp-p5-production.py`

- **作用**：P5 production tracer 与 rpcd 会话授权。
- **依赖、调用与风险**：SSH localhost:222 tunnel、历史 native-store 模块/production-cli、目标 procd。
- **决定**：保留：session 授权证据尚无替代；明确依赖旧 native-store，与当前 Lua 架构不匹配，不能直接当现行验收。

### `run-device-upstream-tls-traffic.py`

- **作用**：隔离真实引擎流量及 upstream TLS 自签证书验证。
- **依赖、调用与风险**：被 Host runner、调查和服务简化 runner 动态导入；SSH/procd/私有 journal。
- **决定**：保留：共享真实引擎基础设施；模块文档仍误写 HTTP runner 命令。

### `run-r8-overview.py`

- **作用**：历史 R8 设备 UI 生命周期。
- **依赖、调用与风险**：SSH localhost:222、router-r7-browser-setup、overview-lifecycle.cjs；停止/禁用服务并删除重建生产 product 目录。
- **决定**：保留但禁用使用：高危历史工具，无证据证明 UI 覆盖被完整替代；恢复旧备份可能覆盖新配置。

### `run-r9-device.py`

- **作用**：历史 R9 设备 UI 生命周期。
- **依赖、调用与风险**：SSH localhost:222、router-r7-browser-setup、r9-device-lifecycle.cjs；停止/禁用服务并删除重建生产 product 目录。
- **决定**：保留但禁用使用：高危且旧架构；未证明全部回归有替代，不能按名称直接删除。

### `verify-backend-host-header-deploy.py`

- **作用**：已安装 Host UI + 只读 ubus 验证。
- **依赖、调用与风险**：动态加载 deploy-backend-host-header、Node 原生 UI 测试、目标状态。
- **决定**：保留：安装字节和验证链；依赖载入模块顶层无意副作用需小心。

### `verify-backend-host-modal-readonly.py`

- **作用**：已安装 modal 到验证 payload 诊断。
- **依赖、调用与风险**：SSH、Node page-save-native fixture、状态哈希。
- **决定**：保留：实际 UI 序列化边界；仅验证不证明生产保存。

### `verify-ddns-installed-ui.py`

- **作用**：运行已安装 DDNS UI 的 Node fixture。
- **依赖、调用与风险**：SSH、已安装静态文件、Node 与本地 preload/证据。
- **决定**：保留：安装字节 UI 覆盖；产生本地证据，非设备保存。

### `verify-ddns-live-readonly-ui.py`

- **作用**：使用真实只读 DDNS profiles/status 驱动已安装 UI。
- **依赖、调用与风险**：历史 deployment.json、SSH、Node preload、生产哈希。
- **决定**：保留：真实只读响应与 fixture 边界；依赖历史证据文件。

### `verify-host-port-nat.py`

- **作用**：部署后核查 Host/NAT 行为。
- **依赖、调用与风险**：依赖部署记录、SSH/curl、固定域名与历史 UCI 哈希。
- **决定**：保留：定向验收链；固定旧状态使可复用性未经证实。

### `verify-overview-public-entry.py`

- **作用**：生产 overview 与监听配置只读核查。
- **依赖、调用与风险**：SSH、ubus、目标 sslh 配置、固定监听器断言。
- **决定**：保留：实际安装态检查；固定端口/IP 可能过期。

### `verify-r8-package.py`

- **作用**：将 R8 包内容与历史 git commit 对比。
- **依赖、调用与风险**：tarfile、git.exe、外部 D:/DevPortal/homelede/homepublish-product 和固定 commit。
- **决定**：保留：历史二进制来源核查；外部仓库及旧版本尚未证实存在。

### `verify-upstream-tls-deploy.py`

- **作用**：已安装 upstream TLS 部署完成检查。
- **依赖、调用与风险**：动态加载 deploy-upstream-tls-source、SSH 和原部署证据。
- **决定**：保留：后续核验依赖部署模块；动态载入不会自动证明安全。

## 未验证与后续边界

- 未执行任何设备、SSH、网络、部署、服务、nft、chroot 或私有目标测试；亦未证明各历史工具在当前设备上运行成功、清理完整或与当前生产配置兼容。
- 本报告不把既有文档中的历史 GREEN、私有引擎结果或源码注释当作本次运行证据；`rpc-luci-fixture.py` 和 P5 production 的 native-store 依赖需专门迁移、对照实际调用后再裁撤。
- 私有 fixture 的监听、文件、procd 与 nft 修改均为设备写入；实际执行需要新授权，先检查冲突、隔离与清理，再分别验证生产保护状态。deploy/finalize/resume 中的历史假设不能自动延续。
- `run-r8-overview.py` / `run-r9-device.py` 的恢复代码删除 `/etc/homepublish/product` 并复制历史备份，不具备对并发新配置的保护；不要运行。
