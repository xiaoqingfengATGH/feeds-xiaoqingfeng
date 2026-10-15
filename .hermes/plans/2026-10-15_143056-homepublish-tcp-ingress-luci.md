# HomePublish TCP 统一发布与原生 LuCI 页面实施计划

> **For Hermes:** 按任务逐项执行并独立审查；仅在获得实施授权后开始。遵循 homedirect-development，实机 RED→GREEN，禁止本地测试。本文是阶段冻结基线，不是完成报告。

**Goal:** 实现公网 IPv6 到家庭 IPv4 服务的直连发布，以及 HTTPS、TLS/SNI、SSH 的 TCP 共入口分流和独立端口 TCP 转发，以原生 LuCI 表单管理。

**Architecture:** Lua 控制层、标准 procd、专用 Nginx、按需启用的 sslh TCP 入口；入口与后端地址族解耦。HTTPS-only 保留直接 Nginx 路径；混合共享入口由 sslh 接管外部 socket，内部 Nginx 仅绑定本机专用端点。一个发布事务统一管理全部应用自有进程与连接。

**Tech Stack:** LuCI form.JSONMap / NamedSection / GridSection、tools.widgets.NetworkSelect、network/firewall 只读发现、scoped RPC、Lua、Nginx HTTP/stream、sslh select 候选、procd。

---

## 0. 文档状态、工作区与授权

- 工作目录：`D:/DevPortal/homelede/homepublish-product`；当前分支 `feature/homepublish-product`。
- 用户本轮授权：固定阶段范围、设计页面、制定计划；不等于授权执行代码、安装组件或增加公网暴露。
- 本次仅创建此计划，不修改业务代码、需求登记表、运行配置，不部署、commit、push、merge 或创建 PR。
- 当前已有未提交修改：certificates.js、entry.js、menu JSON；未跟踪 sketches 两目录与测试 __pycache__。实施时先读 diff 和确认归属，不清理或覆盖。
- 后续实施第一项将本基线登记到本项目 REQUIREMENTS.md，编号以当时完整登记表核对后分配，不猜编号。历史记录保留，顶部注明本阶段对旧设计的覆盖范围。
- 历史文档里“仅 Web / 不允许通用 TCP forwarder / 必须自定义 guardian”等与本基线冲突的条款，不作为新阶段要求；须显式登记 superseded，不能改写历史测试结果。
- 测试环境仅既有授权设备 `127.0.0.1:222`。源码直接上传实机、重载对应进程后验收；不迭代编 IPK、不跑本地 Lua/node/WSL 测试。里程碑 SDK 构建另行安排。
- 不修改认证，不清密码；登录失败走用户授权凭据流程。不得以页面调试为由修改系统安全配置。

## 1. 冻结的产品目标

### 1.1 必交范围

1. IPv6 入站 → IPv4 后端是核心验收路径，Web、TLS 透传、SSH、普通 TCP 都覆盖。
2. 模型支持 IPv4/IPv6/双栈入口与 IPv4/IPv6 后端独立组合；双栈为两个明确 socket，不依赖 v4-mapped 隐式行为。
3. 四种发布方式：HTTPS 反向代理、TLS 透传、原生 SSH 共入口、独立端口 TCP 转发。
4. 同一共享入口可组合多个不同域名的 HTTPS 和 TLS 透传，加一个原生 SSH 目标。
5. 监听接口、地址和区域来自真实设备，不硬编码 WAN/LAN；旁路由只有 LAN 是正常部署。
6. 保存不发布；明确启动/应用；持续或临时策略；手动停止锁；原临时截止不延长；普通 procd 生命周期与有界恢复。
7. 自动冲突检查和可解释链路状态，禁止把本地就绪当公网成功。

### 1.2 明确排除

UDP（包含 UDP v6→v4）、QUIC/HTTP3、OpenVPN 等额外探针的产品承诺、任意正则探针 UI、SSH over TLS、任意明文 TCP 的 TLS 包装、通用 NAT64、透明保留跨地址族源 IP、纯 IPv4 客户端访问 IPv6-only 家庭、云中继/隧道、控制上级路由器。

本阶段不开发 UPnP/STUN/门户。现有相关配置如存在，必须显示并给迁移选择，不删除或自动执行；不能进入新四种方式的主流程。

### 1.3 场景验收目录

- S1：IPv6 HTTPS → IPv4 HTTP 网站，入口 ACME 证书。
- S2：多域名 Web 共入口，默认证书继承与服务覆盖。
- S3：IPv6 TLS/SNI → IPv4 TLS 后端，端到端 TLS/mTLS 不被入口终止。
- S4：Web HTTPS 与至少一个 TLS 透传目标共端口，互不串线。
- S5：上述入口加入一个显式 SSH 后端，原生客户端连接，不修改设备管理 SSH。
- S6：独立 IPv6 TCP 端口 → IPv4 TCP 后端，包括服务端先发数据的普通 TCP。
- S7：IPv4/IPv6/双栈入口与后端地址族回归；旁路由只有 LAN 可配置。
- S8：冲突、未知协议、未知 SNI、超时、停止/到期、失败清理与真实管理/代理共存。

## 2. 页面导航与交互基线

沿用稳定路由，不为文案重命名 URL：

| TAB | 路由尾段 | 原生结构 | 职责 |
|---|---|---|---|
| 概览 | overview | 只读 JSONMap/NamedSection/DummyValue + 只读 GridSection | 运行态、待应用、启停、入口和服务链路 |
| 发布服务 | services | JSONMap + GridSection，原生新增/编辑弹窗 | 配置四种服务 |
| 发布入口设置 | entry | JSONMap + NamedSection；高级监听用 TableSection/GridSection | 统一入口监听、默认证书、策略 |
| 证书 | certificates | 只读 GridSection | ACME RSA/ECC 库存、使用关系 |

不引入向导替代主表单、不画自定义卡片控制台、不复制一套 JSON 编辑器。原生控件不足时，只扩展复合地址选择、跨行校验结果、发布确认摘要和只读链路信息。

所有描述面向用户，避免“canonical/后端权威/代次”等工程文案；技术细节折叠展示。编辑页有未保存修改时，跨页离开用 LuCI 原生确认机制；轮询不重建编辑表单、不覆盖草稿。

### 2.1 概览

顶部使用原生 cbi 控件和按钮：

- 发布状态：未发布/启动中/运行中/停止中/失败/状态未知。
- 配置状态：未保存修改（仅当前编辑页）、已保存待应用、运行配置一致。
- 发布策略：持续/剩余时间和绝对截止；未启动不伪造截止。
- 操作：启动发布、应用变更、停止发布、刷新；配置入口用原生链接。
- 只有保存后的配置可启动；有草稿时不隐式保存后启动。
- Stop 在“可能仍有进程/连接/清理残留”时可用，不仅在 running=true 时可用；状态读取失败显示未知，不宣称已停止。

只读入口表：入口名称、监听地址/端口、地址族、关联网络、监听状态、公网验证状态。

只读服务表：参与发布、名称、发布方式、匹配条件/独立端口、后端、地址族路径、当前运行状态。运行表读取 active 快照；另标 saved 待应用差异，不能混显示成已运行。

链路示例：`IPv6 / TCP 8443 → TLS 透传 → 192.168.1.10:443`。双栈显示两条路径；后端是域名且尚未解析时显示“待解析”，不可猜地址族。

仅 HTTPS 生成 https 链接，IPv6 literal 使用方括号；SSH 提供命令（不含凭据），TCP 仅提供端点。手工上级转发导致公网端口未知时，只显示本机端点和指引，不伪造公网 URL。

内部进程、配置版本、generation、失败步骤、清理残留、源地址传递方式放折叠详情；日志不包含业务载荷或秘密。

### 2.2 发布入口设置

#### 监听设置（共享 TCP 入口）

| 字段 | 控件 | 规则 |
|---|---|---|
| 地址族 | ListValue | IPv4、IPv6、IPv4/IPv6 双栈 |
| IPv4 网络 | widgets.NetworkSelect | 真实逻辑网络，单选，禁创建；只在 v4/双栈显示 |
| IPv4 地址 | ListValue/动态地址选择扩展 | 所选网络当前地址，显示前缀及状态 |
| IPv6 网络 | widgets.NetworkSelect | 可与 IPv4 不同，允许 LAN |
| IPv6 地址 | ListValue/动态地址选择扩展 | 真实 GUA/ULA，注明公网/内网；链路本地不作普通公网入口 |
| 监听端口 | Value datatype=port | 两个地址族默认同一端口；不暴露外网端口 |
| 防火墙区域 | DummyValue | 自动关联；缺失/多义时给出原因并要求解决，不猜 wan |

基础界面提供一个共享入口配置，不让每个服务重复填入口监听信息。独立 TCP 转发使用同一组基础绑定设置，服务只增加自己的端口；底层保留 listener_id，便于状态和冲突绑定，暂不开放任意多入口组合编辑。

地址失效保留原值并显示不可用，不静默切到其他地址。刷新地址列表须显式操作且保留未保存选择。

通配 `0.0.0.0`/`::` 仅作为高级候选：必须先验证实际来源范围限制，对新增网卡/已有 INPUT ACCEPT 不能越界；未能形成可验证限制之前不在 UI 开放。默认精确地址。IPv6 前缀变化时精确绑定失效应停止/标阻断，不能悄悄扩大为通配；地址变化自动跟随另行确认设计后再做。

IPv6 ULA 可用于局域网验收，但显示“内网 IPv6，不能据此直接公网访问”，不与 GUA 混淆。

#### 默认证书

- ListValue：ACME 域名 + RSA/ECC + 到期日期。
- 仅供 HTTPS 反代继承；TLS 透传/SSH/TCP 不要求证书。
- 只有透传和 TCP 服务时，可不选默认证书。
- HTTPS 服务没有可用证书或域名覆盖不匹配时，保存可给明确信息，发布预检必须阻止启动；不得自动改选其他证书。

#### 发布策略

- ListValue：持续发布 / 临时发布。
- 临时时长用原生 ListValue 常用时长 + 自定义 Value（分钟）；内部统一转换秒并保留明确范围。
- Flag：开机恢复，默认关。
- 临时已运行时编辑时长不延长当前截止；如要新会话，明确停止后重新启动。
- 本阶段政策作用于整组发布，服务 Flag 仅参与下次发布，不冒充即时单服务启停。

### 2.3 发布服务列表

原生 GridSection：addremove=true、anonymous=true、modalizable=true；本阶段不提供拖动规则优先级，防止用户误解顺序可解决冲突。域名路由按确定规则编译，拒绝重叠；兼容旧排序字段但不靠它决定业务。

列表列：参与发布（Flag）、名称、发布方式、域名/独立端口（DummyValue）、后端（DummyValue）、证书（DummyValue）、操作（原生编辑/删除）。目标控制宽度，长 IPv6/域名允许换行，窄屏不使按钮溢出。

新增/编辑弹窗使用原生 taboption：

1. 基本设置：名称、参与发布、发布方式。
2. 接入设置：按发布方式 depends 显示字段。
3. 后端设置：目标地址、端口及 Web 专属字段。
4. 高级设置：受控后端地址范围、必要的传输参数；仅放真实实现项。

#### 字段可见性

| 字段 | HTTPS反代 | TLS透传 | SSH | TCP转发 |
|---|---|---|---|---|
| 域名（单个、精确匹配） | 必填 | 必填 | 无 | 无 |
| 接入端口 | 继承共享 | 继承共享 | 继承共享 | 自填独立端口 |
| 后端地址/端口 | 必填 | 必填 | 必填 | 必填 |
| 后端 HTTP/HTTPS | ListValue | 无 | 无 | 无 |
| 证书模式/证书 | 继承/独立 | 后端提供，只读说明 | 无 | 无 |
| 后端 HTTPS 校验名/信任 | 按HTTPS显示 | 无（端到端客户端验证） | 无 | 无 |
| WebSocket 支持 | 随Web链路实现与验收 | 不适用 | 不适用 | 不适用 |

后端地址用 Value + hostname/IP 校验，端口独立 Value datatype=port；不再强迫用户拼 URL。IPv6 用户输入裸地址，展示端点时再加方括号。后端地址族由输入/解析推导，不要求用户填两次。

后端 allowed_ranges 是“允许连接的后端网段”，不是“允许访问服务的客户端来源网段”。当前 services.js 描述错误，本阶段纠正。用 DynamicList + CIDR 校验放高级区；可从用户选择的家庭网络推导建议值，但不能用猜测的 192.168.0.0/16 自动放宽已批准范围。

后端 HTTPS 必须有明确的证书验证与服务器名称策略；不默认关闭验证，不把 tls 透传与 HTTPS upstream 混淆。域名回源要验证解析结果、连接地址和 SNI/校验名。

第一阶段只允许精确 SNI 服务域名；证书可以是通配符证书。SNI 通配路由和用户 ALPN 编辑不是本阶段基础承诺，避免重叠优先级复杂化。

变更服务类型清除不适用字段时，仅在弹窗草稿上处理并提示，取消弹窗不污染已保存服务；回写采用白名单，不能让隐藏域名/证书参与 SSH/TCP 校验。

### 2.4 证书页

保留“列出可使用的证书列表（来自ACME）”。RSA/ECC 独立，已用优先，无编辑按钮。增加只读使用关系：默认入口/具体 HTTPS 服务。透传域名不冒充使用本机证书。表头/数据行列数与分隔线端点一致。

### 2.5 确认与错误交互

- 新增/编辑：原生弹窗；点击弹窗保存只更新表单草稿，页面保存再调用 scoped save。
- 页面底部只设保存、重置（重新载入已保存配置）；不使用原生 Save&Apply 去触发全局系统 apply。
- 启动/应用在概览通过 ui.showModal：列出地址/端口、服务类型、后端、证书归属、临时截止、变更范围；明确短暂断流，不承诺零停机。
- 冲突错误在字段旁与页顶摘要共同定位，使用稳定错误码映射中文，不把 Lua traceback 展示给用户。
- 不允许同一监听端点被独立 TCP 与共享入口双重占用；第二 SSH、重复域名、地址族通配重叠、系统占用均在保存和启动前校验。后台校验为权威，前端提前反馈。
- 状态 RPC 失败不清空表单、不用默认值覆盖原配置、不显示停止；提示重试。

## 3. 数据与运行架构

### 3.1 版本化配置

新 schema 建议命名 `homepublish.schema.v2`，具体键名在任务1契约冻结；需包含：

- 共享入口身份及按族 bindings：逻辑网络、实际设备、明确地址、端口、区域解析证据。
- 服务判别联合：`https_proxy | tls_passthrough | ssh | tcp_forward`。
- 稳定 service_id、名称、enabled、后端 host/port/安全范围。
- HTTPS 专属域名、upstream scheme/验证策略、证书 inherit/override。
- TLS 透传专属精确 SNI；SSH 不携带虚假 hostname/certificate。
- TCP 专属独立监听端口，与共享绑定联动；不存在 enabled 服务的共享入口不创建空监听。
- 发布策略、saved/active revision、pending 和原截止契约不变。

旧 HTTP 服务→https_proxy，证书引用保持；旧 external_port 不再参与运行或显示，不自动改上级映射。升级迁移先备份应用配置，预览差异，经显式保存/应用生效；拒绝静默丢第二个 listener。旧未知类型/未实现接入机制不强行转换。

### 3.2 编译与运行

- 配置→纯校验/冲突计划→确定 socket/路由图→Nginx/sslh 配置→运行就绪→active。
- HTTPS-only 可专用 Nginx 直听；有 TLS 透传/SSH 的共享入口由 sslh 直听，HTTPS 分支送内部 Nginx。
- 独立 TCP 入口优先 Nginx stream 直接转发，不必经过探针，能支持服务端先发协议。
- 上述路径必须同一 controller 管理，避免两套独立 Start/Stop 所有权。
- procd 自有实例身份固定，pid/argv/runtime 与 generation 可读回；不使用客户端传 PID。
- sslh→Nginx 内部链路可用 PROXY protocol，内部监听不暴露公网，只信任实际代理来源。其他后端默认不发送 PROXY 头，UI 准确标注源地址行为。
- IPv6→IPv4 为两段 socket，非透明源地址伪造；不引入 TPROXY/全局策略路由。

### 3.3 关键技术门禁

sslh 上游能力和 OpenWrt 现成包不是一回事；预检版本、select/ev/fork、构建依赖、IPv6、SNI、分包握手行为。核对 Nginx stream/SSL 模块是否实际可用，确认用可加载模块还是受控包构建，不覆盖管理 Web 的 Nginx。

必须实证 sslh 未匹配和超时的默认兜底，并设计有界拒绝路径；不以移除 anyprot 当作 fail-closed。候选为应用自有拒绝端点（立即关闭，不转业务），优先使用验证过的原生能力；如需轻量拒绝服务则明确 procd 所有权和资源限额，不自写全功能代理。

协议探测只是路由，不是认证。SSH 后端须用户指定、不得自动选系统22；明文 TCP 不自动加密。

## 4. 任务与交付顺序

每个任务细分为：准备实机失败用例→记录 RED→最小代码→scp 安装路径→必要 reload→同用例 GREEN→受影响回归→记录证据。实际阶段结束停等用户下一步指令；不因本计划存在自动进入下一阶段。

### P0：基线登记与技术可行性门禁

1. 读当前完整 git diff、需求/设计/最近 r9 checkpoint，冻结已有改动归属。
2. 将本计划登记需求，补“历史条款覆盖映射”，保留既有验收历史。
3. 定义入口/服务/RPC/schema v2 与错误码契约，说明迁移和保存并发冲突。
4. 只读探查实机 sslh/Nginx 包版本、资源、现有监听/procd/路由/防火墙基线；记录管理恢复路径。
5. 单独获准后在隔离实机端口验证 sslh SNI、SSH、v6→v4、分段握手、未知/超时拒绝。需要新包时说明实际工具链/源版本，不擅自替换全局 Nginx。
6. 评审拒绝路径、源IP、整组Stop边界后确定组件；不可行项先报告，不用UI掩盖。

### P1：配置模型与只读设备发现

7. canonical v2 判别联合、地址族绑定、冲突图、旧配置迁移，编写对应实机 RED/GREEN 脚本。
8. RPC 提供真实逻辑网络/设备/地址/zone 列表和可用状态；ACL 最小只读授权，不开放任意 ubus 或文件路径。
9. 共享 collect/serialize 纯转换保证多 listener 保留；保存 expected_revision 并发拒绝，不覆盖其他页保存。
10. 新增/修改服务与类型切换验证，保持其他页面字段及稳定 service_id。

### P2：原生 LuCI 配置页面

11. entry.js 改“监听设置”，真实双栈/接口联动/地址选择、移除外网端口、拆证书与策略区域。
12. services.js 原生四类型 GridSection 弹窗、depends、拆 host/port、证书条件、独立 TCP 端口。
13. certificates.js 保持只读列结构，展示 HTTPS 使用关系。
14. product.js 统一保存/重置/错误映射/草稿并发/确认摘要。加载失败禁保存，不回退默认配置覆盖。
15. 真实浏览器验证中文、控件类型、弹窗取消、类型切换、刷新持久化、跨页离开、表格窄屏；页面保存前后设备 listeners 必须无新增。

### P3：数据面纵向切片

16. IPv6 HTTPS→IPv4 HTTP marker，真实业务证书验收与快照保护；单独增加 HTTPS upstream 校验用例。
17. 混合 HTTPS＋精确 SNI TLS透传，后端证书/mTLS 原样、未知SNI拒绝、不串路由。
18. 原生SSH加入共享入口，实际SSH握手到隔离后端；管理SSH PID/配置/监听保持。
19. 独立TCP v6→v4，覆盖客户端先发、服务端先发、半关闭、双向字节与长连接。
20. 双栈与其余地址族组合，后端域名解析/地址变更和安全范围不放宽；非幂等请求不重放。
21. controller/procd 多进程整组readiness，任何必需组件失败不冒称全部active；清理unknown独立呈现。

### P4：概览、生命周期与安全闭环

22. overview.js 改原生只读状态表、active/saved分离、真实按服务就绪、折叠诊断。
23. 启动/应用确认与真实按钮门控；Stop 对残留/失败有效，无假能力禁用。
24. Save旧连接不变；Apply切换后端marker且承认短暂停机；停止关闭Web/TLS/SSH/TCP既有连接和新连接。
25. 临时到期、手动Stop、进程故障有界恢复、pending不偷用、截止不续期，boot恢复默认关。
26. 管理服务/Passwall2共存，应用自有资源清理与基线比对；不修改全局代理/路由。
27. 网络变更精确地址失效、zone缺失、端口冲突、读取失败、慢握手/资源上限和未知流量负向测试。

### P5：独立审查与里程碑

28. 对照冻结场景审查代码与证据，不接受只编译成功；复核组件版本与安全公告、ACL/注入/源IP信任边界。
29. 修复本阶段确认缺陷，重跑最终版本实机回归；未完成项逐条列出，不用历史PASS替代。
30. 仅里程碑构建IPK，核源码归档/权限/依赖和安装字节；安装或升级需用户授权。
31. 更新需求、产品设计、审查清单、REFACTOR checkpoint 与操作说明；本地提交经用户指令执行，不push/merge/PR。
32. 外网v6独立端验证另获范围授权；若缺外部IPv6来源，报告“实机v6→v4验证通过/公网未验证”，不可制造公网成功证据。

## 5. 文件与测试落点

现有主要修改路径：

- `REQUIREMENTS.md`
- `docs/homepublish-product-design.md`
- `docs/homepublish-design-review-checklist.md`
- `docs/HOMEPUBLISH-R9-REFACTOR-PLAN.md`（追加接续/覆盖说明，不抹历史）
- `luci-app-homepublish/htdocs/luci-static/resources/view/homepublish/{overview,services,entry,certificates,product}.js`
- `luci-app-homepublish/root/usr/share/luci/menu.d/luci-app-homepublish.json`
- `homepublish/files/usr/share/homepublish/{canonical,product-rpc,product-controller,product-system-provider,product-device-provider,direct-renderer,direct-backend,device-integrations}.lua`
- `homepublish/Makefile`、`luci-app-homepublish/Makefile` 及既有 init/rpcd/ACL 文件（实施时先定位精确现有路径）。

拟新增：

- `homepublish/files/usr/share/homepublish/tcp-route-plan.lua`：纯路由/冲突计划。
- `homepublish/files/usr/share/homepublish/sslh-renderer.lua`：确定生成，不拼用户任意指令。
- `homepublish/files/usr/share/homepublish/network-inventory.lua`：受限网络发现与归属规范化。
- `homepublish/tests/device-tcp-ingress.lua`：实机配置/冲突/渲染验证。
- `homepublish/tests/run-device-tcp-ingress.py`：实机端到端驱动，记录来源/目标/清理基线；本机仅作远程驱动，不跑本地被测业务实现。
- `luci-app-homepublish/tests/tcp-ingress-device-probe.cjs`：真实实机页面浏览器驱动，不构建本地替身页面。
- `docs/HOMEPUBLISH-TCP-INGRESS-ACCEPTANCE.md`：逐场景证据矩阵。

测试驱动接口和脚本参数在实现该任务时按实际设备路径落定；不得引用未创建脚本伪报运行成功。认证走vault/受支持会话，不写密码进argv、日志或计划。

## 6. 最终验收清单

- [ ] 四种发布方式从 LuCI 保存、重载、启动、应用、停止都走真实 RPC/controller，不止静态页面。
- [ ] S1–S8 对应配置、实际连接、后端标记、路由选择、清理读回均有证据。
- [ ] IPv6客户端真实连接IPv6入口，再由IPv4后端记录请求，不能用IPv4 URL代测。
- [ ] HTTPS系统CA/域名验证与TLS透传后端身份分开验；私钥不离服务器。
- [ ] 第二SSH/重复SNI/共享-独立端口重叠/系统占用均被拒，取消编辑不污染保存。
- [ ] 无SNI、未知协议、探测超时无业务默认落点，不泄漏管理入口。
- [ ] 非HTTPS服务不被强制配置证书或域名；后端HTTPS验证不默认关闭。
- [ ] Stop/到期关闭四类已建立会话；失败/残留不伪报停止。
- [ ] 草稿、saved、active、pending准确区分；页面读失败不回默认后覆盖。
- [ ] 所有只读表列结构正确；原生主题/窄屏/弹窗字段依赖通过DOM检查。
- [ ] 没有UDP配置入口或UDP能力宣传；不自动开公网，不自动修改上级路由。
- [ ] 管理Web/SSH/代理和非本应用监听、路由、防火墙保持基线。
- [ ] 用户手册明确外部需IPv6、上游入站许可、真实源IP限制、应用鉴权责任。

## 7. 风险与明确取舍

- **组件门禁先行**：sslh未知流量兜底、构建差异、Nginx stream模块是P0阻断，不能先堆UI再假定可用。
- **不追求单端口万能**：四类型之外不承诺；无法区分用独立TCP端口。
- **不引入过度架构**：标准procd与最小权限足够，不重启自定义broker/guardian/seccomp工程。
- **通配监听保守**：基本目标不依赖通配；若无法在允许网络范围内安全限制，保持精确地址。
- **规则域名精确**：证书通配与路由通配是两件事，本阶段仅前者。
- **公网验证独立**：设备ULA/loopback验收不能替公网GUA可达；无授权/来源时诚实标未验证。
- **阶段性停止**：本计划固定目标但不授予后续阶段自动执行权；每阶段交付后按用户指令继续。
