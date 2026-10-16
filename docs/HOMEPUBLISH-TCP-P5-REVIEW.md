# HomePublish TCP P5 独立代码与证据审查

审查日期：2026-10-15（UTC+08）。仓库 `D:/DevPortal/homelede/homepublish-product`，授权分支 `feature/homepublish-product`，基线 HEAD `7ac1fe8` 加现有 P4 工作树。此报告仅为独立审查，不是 P5 修复、安装包或上线验收。

## 结论

**不通过最终产品验收。** 已有证据支持隔离设备上的四协议数据面和 controller/procd 生命周期切片，不支持“任意批准的真实网络配置已经能经生产 provider 启动”或“完整 LuCI rpcd/session ACL 生命周期已通过”。主要阻断是产品执行路径仍限固定测试 profile；另有真实 RPC 验收边界、Nginx 依赖安全门禁和 S2 最终版本证据缺口。没有将 legacy PASS 当作产品通过，也没有把未验证边界写成已利用漏洞。

本次不修改业务、计划、既有证据，不启动共享端口测试，不改防火墙/路由/DNS/auth/UPnP/公网，不构建或安装 IPK，不 commit/push/merge。设备只执行只读目录、哈希、版本、RPC 对象枚举。设备现有测试配置保持原样。

## 依据与完整性

冻结依据：`.hermes/plans/2026-10-15_143056-homepublish-tcp-ingress-luci.md`，S1–S8 在 44–51 行，P5 tasks28–32 在 256–260 行，最终清单在 289–301 行。

主要证据：`docs/evidence/tcp-p3/task20-through16-stage-final.log`、`task21-installed-stage-final.log`；`docs/evidence/tcp-p4/task24-final-after27.log`、`task25-final-after27.log`、`task27-parent-final.log`、`ui-lifecycle-final-after27.log`、`ui-overview-final-after27.log`、`services-modal-final-after27.log`。

独立执行的校验：`docs/evidence/tcp-p4/p4-stage-final-source-sha256.json` 的 **15/15** 个源码哈希与当前工作树一致（9 个 installed Lua、3 个 private 驱动、3 个 installed UI）。这不是全仓库或 IPK 字节绑定。设备只读确认 `ubus -v list homepublish` 已注册十个 scoped 方法；注册成功不证明 ACL。设备 `/etc/homepublish` 与 `/tmp/homepublish-tcp-p3` 当前均 root 0700；当前没有观察到 `controller-runtime`/`controller-fixture`，不是断言之前的运行不存在。

设备只读版本：私有 Nginx `1.26.1`，OpenSSL `3.0.18`；编译包含 HTTP SSL/realip、stream/stream SSL/preread，无 HTTP/3 编译参数。`sslh-select.private -V` 返回 `d39388d1edcc9fe7a35449fc5c23d222d20d6f81`，与上游 v2.3.1 tag 对应，列出 HAVE_PROXYPROTOCOL/HAVE_LIBCAP/HAVE_LANDLOCK 等编译能力；编译存在不等于运行时已启用降权或 Landlock。

## Blocking / High / Medium

### B1 — Blocking：生产执行 provider 仍缺失（功能缺失，不是已证实漏洞）

位置：
- `homepublish/files/usr/share/homepublish/product-system-provider.lua:10–13`：plan 返回 `production provider unavailable`，start/readiness/renew 均 false。
- `homepublish/files/usr/share/homepublish/product-provider.lua:85–88`：本地 start/apply 权威拒绝 `runtime requires the device controller channel`。
- `homepublish/files/usr/share/homepublish/product-cli.lua:16–24`：只有 device-test/enabled 且 status/start/apply/stop 走 device channel；其余走 provider。
- `homepublish/files/usr/share/homepublish/product-daemon.lua:6`：固定 device provider。
- `homepublish/files/usr/share/homepublish/product-device-v2-profile.lua:4–27`：私有 `/tmp/homepublish-tcp-p3` 二进制；仅单一 LAN 地址 `fd89:878e:a47f:0:0:0:0:1:49543`、固定 loopback 后端/fixture 域名端口；25–26 行还把监听缩窄为 `::1`。

复现条件：保存一个合法但不等于上述白名单的真实 LAN/后端配置，不能由现有固定 profile 激活。移除 fixture 或未启用 device-test channel 时，也不应宣称生产 Start 已完成。测试地址被缩窄不是越权扩张，且此处不要求取消全部权威安全校验；缺的是正式生产适配器及其限定能力。

复跑：实现经授权范围的固定生产 adapter 后，走安装路径 CLI→rpcd→controller，至少选择两个非 fixture 的实际网络地址/后端组合；记录 preflight、Start、Save pending、Apply、新旧 marker、Stop 和资源读回。不得将修改 fixture 白名单本身作为生产完成证据。需要设备写入/运行授权和独立端口协调；本次不运行。

### H1 — High：真实 rpcd/session ACL 生命周期未验证（验收阻断，不是 ACL 绕过结论）

位置：`luci-app-homepublish/tests/p4-lifecycle-browser.cjs:5–7,15–17`。浏览器的 homepublish ubus 请求被 Playwright route 截获，经 SSH root 执行私有 `device-tcp-p4-policy-rpc.lua`，再人工包装 JSON-RPC 成功响应。测试自身第7行明确排除 public rpcd/session ACL acceptance。真实 LuCI loader、表单和真实 controller 数据面均有价值，但此桥跳过了对应 homepublish rpcd 调用的 session 授权与正式 CLI 路由。

静态正面证据：`luci-app-homepublish/root/usr/share/rpcd/acl.d/luci-app-homepublish.json:1` 将 status/validate/certificates/network_inventory/preflight/migration_preview 置 read，将 save/stop/start/apply 置 write，没有任意 ubus 或文件权限；`root/usr/libexec/rpcd/homepublish:3–9` 方法固定、执行路径固定。SSH root 的 `ubus list` 不检验任何受限 session。**没有证据证明未授权用户实际可以调用 start。**

精确复跑：禁用所有 `page.route('**/ubus**', ...)` 生命周期拦截，在原生页面对真实 `/ubus` 记录脱敏 method/result；使用已批准的现有匿名、只读和写会话分别验证：匿名拒绝；只读可 status/inventory/validate 而不可 save/start/apply/stop；写会话可在批准测试配置上 Save/Start/Apply/Stop。同时测试陈旧 revision、approved=false、缺失字段拒绝，以及拒绝前后 journal、进程/监听未变化。会话不得写入日志，不新建用户、不改 auth。本次没有可直接使用的受限会话授权，未实施此矩阵。

### H2 — High：Nginx 1.26.1 不能直接升为已完成安全门禁的产品依赖

位置：`homepublish/tests/build-tcp-p3-nginx.sh:2–3,13–22` 明确仅私有测试构建，固定 1.26.1、三个 cross-build 补丁，并没有显示后续安全 backport。第13行只是计算本地 tarball 哈希，不是与独立可信上游期望值比对。

上游真实检索（下附来源）：CVE-2026-1642 为 SSL upstream injection，官方影响 1.3.0–1.29.4，修复 1.29.5+/1.28.2+。`direct-renderer.lua:59–66` 支持 TLS upstream，满足相关功能条件；F5 要求 upstream 侧 MITM 及其他条件，不应将现有错误证书 502 测试理解为已覆盖此漏洞，也不声称本次已利用。另有 CVE-2025-23419 SSL session reuse，1.26.1 落入版本范围，需结合默认拒绝 vhost 与未来 mTLS 配置判断；CVE-2024-7347 需要 MP4 模块/指令，当前配置未启用。HTTP/3、mail、DAV 等功能相关公告不能仅按版本号算当前可利用漏洞。

特别注意：上游当前公告还列 **CVE-2026-42533（map 与 regex buffer overflow，major，0.9.6–1.31.2；修复 1.31.3+/1.30.4+）**。`direct-renderer.lua:43–49` 实际生成含 regex 的 map，须按 F5 原文与修复补丁继续核对精确触发条件，不能以“没有任意用户 regex”直接关闭此项。该项本次尚未做漏洞触发复现。最新网页包含更多 2026 条目；应保存评审时公告快照并逐项适用性判定，不能靠选定一个旧修复版本就宣告全部安全。

复跑：正式选择受维护组件版本或有可审计 backport 的包，记录 release/tag、可信归档/签名或独立 expected digest、完整补丁和工具链、最终 ELF 哈希/编译模块；重点重跑 HTTPS upstream 正反例、Host/SNI map、混合 PROXY identity、四协议及半关闭/Stop。不覆盖管理 Nginx。本报告不授权升级安装。

### M1 — Medium：PROXY 来源信任是 loopback 地址信任，不是 sslh 进程身份

位置：`sslh-renderer.lua:31–37`，HTTP 内部 `127.0.0.1:<https>` 接收 PROXY 并 `set_real_ip_from 127.0.0.1`。注释“Only the exact loopback sslh peer”比实际保证强。外部伪造 PROXY 已有 P3 拒绝证据，但任何能够建立本机 TCP 连接的进程，原则上也可直接向该端口发送伪造 PROXY 后再 TLS 握手，从而污染 X-Real-IP/X-Forwarded-For。

这是明确前置条件下的源地址信任风险，不是互联网直接注入，也不证明当前设备存在低权限攻击者或仅源IP鉴权的业务。后端不得据此把客户端 IP 当认证。复跑应在隔离混合运行组、获准已有低权限执行身份下，直接连接内部端口，发送伪造 PROXY + 正确 SNI/Host TLS，观察后端源地址标记；普通外部共享入口必须仍拒绝 client-PROXY。依据部署 threat model 决定是否限制本机连接者或接受并文档化；不要求新 guardian/全局 sandbox。

### M2 — Medium：S2 最终版本端到端证据不足

P3 最终日志有 `deterministic/override/disabled/...` renderer 回归（`task20-through16-stage-final.log:53`）；P4 已有证书模式表单依赖验证。但当前 installed v2 profile `:15–17` 只允许同一个 Web hostname/ref。不能从该 profile 的单 Web A→B marker 推导“两个不同域名共入口，继承与独立覆盖都在最终四协议版本实证”。历史 r6 多 Web 证据不自动覆盖本轮 v2。

复跑：最终安装版本，同一入口两个精确 Web 域名，分别使用默认继承与独立覆盖的不同证书，证书均校验 SAN/链和指纹；逐一指定 SNI/Host 验证不串线，Save/Apply/Stop 后检查 marker/证书、私钥快照及源文件权限。可用非业务 fixture 证书，不新增公网 DNS 或 ACME 操作。本次仅判证据不足，不判 renderer 必然错误。

### M3 — Medium：高负载与运行最小权限仍有边界

`sslh-renderer.lua:42` 提供 timeout=1，无显式总体 TCP 连接限额；`product-procd-group.lua:50–53` 无显式 user/group/rlimit。不可仅从 procd 默认推断最终 uid；Nginx 内建默认 worker 身份和 sslh 自行降权要实机查看。P4 27 已测24个慢客户端、FD 5→29→5、RSS 528→532→528KiB，合法业务仍通、PID不变，这是有界压力通过，不是任意并发抗 DoS 或系统资源上限证明。

SUSE 评审明确两项 2025 DoS 已修复后仍建议管理员考虑资源约束。复跑先只读记录父/worker UID/GID、capabilities 和 `/proc/<pid>/limits`，在隔离端口逐级增加连接并观察限额、合法请求和清理；限制总量和总时长，不做共享设备无界压测。不泛泛要求新守护器或 sandbox。

## 注入、路径、秘密、精确绑定与清理

- 未发现已证实的 RPC→任意 shell 执行路径。不能把 `os.execute/io.popen` 搜索命中数量当漏洞数。方法白名单、canonical hostname/address/port 校验、trusted provider 固定路径共同构成边界。
- `product-procd-group.lua:4,9,42–44,49,53,66,78` 使用 shell 单引号转义，证书源路径限定字符且禁 `..`；目标必须为自有 runtime 下固定 pem。RPC 不接受 Lua 回调、可执行文件或证书路径。这里的 provider options 是服务端代码，不要将其宽于用户输入的类型断言单独报远程注入。
- `direct-renderer.lua:13,18–23,30–34,61–66` 限制快照路径、地址/端口、精确 hostname、证书引用和 HTTPS upstream verify=true；不会把客户端原样配置片段写入 Nginx。forwarded headers 覆写，不向普通 SSH/TLS/TCP 后端添加 PROXY。
- `product-procd-group.lua:36–44` 对不存在的固定 runtime mkdir、umask077，复制快照0600；读出的当前 fixture 父目录0700加强本地边界。没有本次证实的 symlink/任意路径写入漏洞；不要将可信 root 已能修改 profile/源证书的情况误当独立提权。
- `product-procd-group.lua:17–22,57–78` 在 stop 前比对 procd command、记录 PID/starttime、等待组消失才删除 runtime；不按同名 PID 盲杀。P3 task21 foreign identity 测试确实保持外来实例并报 cleanup unknown，unknown 后拒绝启动。该保证仍是普通 procd 生命周期，不是 root 攻击者模型下的不可伪造 owner。
- 精确地址读取失效、占用第二端口、inventory 失败、foreign listener 保留均有 P4 负例；固定 profile 25 行 loopback 缩窄不能替代真实 ULA/GUA 入站。没有通配 fallback 的证据。当前实现不提供全局防火墙入站自动许可，本次也未授权创建规则。
- P3/P4 日志记录证书/私钥源文件哈希、权限前后相同及 runtime 快照删除；本次没有导出私钥。证书库存是引用/元数据，不接受客户端秘密文件路径。源私钥读取与测试快照仅服务端进行。

## S1–S8 与最终清单判定

| 场景 | 可接受的现有证据 | 仍不覆盖 |
|---|---|---|
| S1 IPv6 HTTPS→IPv4 HTTP | P3 final:55–69，系统CA/域名、marker，HTTPS upstream 正反例 | 实际对外IPv6来源、生产 adapter |
| S2 多 Web/继承覆盖 | renderer 和 UI 模式证据 | 最终版本双域名/不同证书完整连接链，见 M2 |
| S3 TLS/mTLS透传 | P3 final:15–17，后端指纹保持，无客户端证书拒绝 | 任意生产配置 |
| S4 混合入口 | P3 final:14–19、39–45，精确路由与未知拒绝 | 真实 RPC ACL；本机 PROXY 信任边界见 M1 |
| S5 原生SSH | P3 final:20–21，隔离dropbear真实密钥认证；管理PID不变 | 不据此声称设备管理SSH可发布 |
| S6 独立TCP | P3 final:27–32，8192字节双向、双方先发、半关闭 | 完整生产路径 |
| S7 地址族矩阵 | P3 final:1–8,60–67，v4/v6入口和后端组合；真实网络库存 | fixed profile 非双真实生产入口；旁路LAN配置≠实网接入 |
| S8 负例/停止/共存 | P3 task21 + P4 task24/25/27，整组Stop、旧连接EOF、有界恢复、pending、cleanup unknown | 匿名/只读 ACL 和更高负载/权限矩阵 |

最终清单逐项：289 **未满足**（真实 rpcd/session 全生命周期）；290 **部分**（S2/生产路径缺口）；291 **隔离设备路径通过，公网未验证**；292 **已有分离证据**；293 **已有负例与取消证据**；294 **有隔离负例**；295 **类型与TLS校验有证据**；296 **设备profile已证实**；297 **有状态/保存/UI证据但ACL未闭环**；298 **当前原生页面/窄屏DOM证据通过**；299 **本次未开放UDP或公网**；300 **既有账本基线通过，本次仅只读**；301 **正式用户说明须补准确边界**。不勾改冻结原清单。

## 当前上游资料与适用性

检索时间为本次审查日期，引用是实际上游页面，不引用搜索摘要替代公告：

1. Nginx 官方安全总表：https://nginx.org/en/security_advisories.html 。当前页面列出 CVE-2026-1642、CVE-2026-42533 等版本范围；必须结合当前编译模块和渲染配置判断。
2. F5 CVE-2026-1642：https://my.f5.com/manage/s/article/K000159824 。正文明确 TLS upstream + upstream侧MITM及额外条件；无已知 mitigation。不是只靠 verify=true 即可排除此公告。
3. sslh 官方 v2.3.1：https://github.com/yrutschle/sslh/releases/tag/v2.3.1 。tag 对应 `d39388d1edcc9fe7a35449fc5c23d222d20d6f81`；发布说明含 fork 崩溃/继承FD修复、混合地址族 PROXY 处理。网页显示签名 verified 但签名 key 已过期；本次未做离线签名信任验证，不据此声明归档供应链已闭环。
4. SUSE Security Team：https://security.opensuse.org/2025/06/13/sslh-denial-of-service-vulnerabilities.html 。CVE-2025-46807（FD耗尽崩溃）和 CVE-2025-46806（OpenVPN UDP未对齐访问）均在 v2.2.4 修复；不能错误报告为 v2.3.1 未修。当前仅TCP探针，不启 OpenVPN UDP。整体负载资源边界仍需部署级验证；不能承诺绝对抗 DoS。

未发现上述材料支持“sslh 2.3.1 必须降级”或“1.26.1 在本项目所有CVE均可利用”的结论。组件安全修复适用性需单独闭环，不能以P3功能连接成功替代。

## Tasks28–32 与后续复跑顺序

- 28：此报告完成独立静态/证据审查；列出上述未完成动态安全验证。未修改既有证据。
- 29：**未执行**；先处理 B1/H1/H2，再补 S2 与 M1/M3 定向验收，最终版本重跑 P3/P4。不要直接运行会覆盖既有 evidence 输出的 browser 驱动；输出必须改到新的获准 run-id 目录，保存源码和组件哈希，不覆写原账本。
- 30：**未执行**；无 P5 IPK，无安装。需新授权后核依赖、权限、源码归档/补丁、包提取/安装字节。
- 31：**待 owner**；需求/设计/清单/r9 与用户操作说明尚须按最终真实状态同步，本审查不改这些文件，不提交。
- 32：**公网未验证**；隔离设备 IPv6 socket→IPv4 backend 不是公网IPv6成功，不申请或改 DNS/防火墙/路由。

复跑安排不得打断现有共享服务：协调固定端口/运行组、读回管理基线、只使用用户许可的测试配置与现有认证；任何 auth/fw/routes/DNS/UPnP/public 修改另行授权。未完成验收不得用旧 PASS、模拟 JSON-RPC 成功或临时扩 fixture scope 关单。
