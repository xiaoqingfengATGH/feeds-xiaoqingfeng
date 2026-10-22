# Feed 需求登记

登记前核查：本隔离 Feed worktree 在基线 `8953489` 无已跟踪 REQUIREMENTS 文件，已跟踪 Markdown 未发现 `REQ` 数字编号或“需求编号”登记。采用组件前缀 `REQ-HS-001`，不推断其他仓库的全局编号。

## REQ-HS-001 — HomeStatus 驾驶舱第一阶段代码归属迁移

- 状态：源码迁移与本地回归完成；待 SDK/IPK 与生产浏览器验收。
- 基线：Feed `8953489`；主题 `d0bddb3`。
- 分支：两个独立 worktree 均为 `refactor/homestatus-phase1`。
- 需求：将驾驶舱主体 JS/CSS 归属迁入 `luci-app-homestatus`，主题删除旧副本并引用应用资源。保留现有布局、数据判断和交互，LAN 交互不改。
- 允许保留：主题 footer 启动、`ng-page-rendered`、经典状态 include DOM 搬移依赖及 palette 视觉适配；不要求完全跨主题。
- 构建要求：主题依赖应用，应用依赖经典状态包；通过 package feed 链接发现 CSS，不猜 feed 名，允许显式覆盖；独立生成器无默认本机路径。
- 本地验收：三份 Node 测试 10/10；Build/Prepare GNU make 宏桩 fixture 3/3；JS 语法、palette 一致性和两边 diff 空白检查通过；可复现 package.json/pnpm-lock.yaml，不提交 node_modules。
- 部署验收：未执行。SSH 已恢复且只读核查旧安装版本；不得据此标记新版本真机验收成功。
- 文档：`luci-app-homestatus/README.md`；`docs/homestatus-phase1-verification.md`；主题包 `README-homestatus-phase1.md`。
- 回滚：成对恢复旧主题/应用，先旧主题后旧应用；保留配置，清缓存，再检查经典入口与 RPC。
- 范围外：部署、改远程配置、合并、推送、PR、LAN/WOL 交互重设计。

## REQ-HS-002 — LAN 四设备概览与宽幅完整查询面板

- 状态：阶段2源码与本地自动化验收完成；待独立审查、真实浏览器/设备验收。
- 基线：应用阶段1提交 `c108e8f`；独立分支 `feature/homestatus-lan-detail`。
- 已确认结构：WAN/LAN 保持半宽；LAN 最多四设备、不等高限高、不内部滚动。完整设备列表放在独立宽幅 modal；手机全屏。
- 完整查询：设备名、IPv4、MAC 和真实 IPv6 地址搜索；按实际接口网络筛选、保留空网络与其他/未分类、上游与未划入网络端口事实。
- 刷新：原5秒轮询；保持面板、搜索与筛选控件身份、输入、焦点和列表滚动；选中网络暂时消失不重置筛选，恢复后自动显示。
- 访问性：对话框语义、Tab/Shift-Tab 焦点圈、Esc/关闭按钮/遮罩关闭、背景 inert/aria-hidden 与锁滚动，关闭恢复原值、焦点及页面位置；文档监听器随面板清理。
- 数据边界：normalize/在线判定/数量口径保持基线；IPv6 只在详情读取已采集 hints；保留 conntrack 当前/上限、条件式 WiFi、DHCP 深链和无租约说明。
- 资源：应用 r3，CSS `v=2`；应用原位升级主题已预载 `v=1` link，不重复插入；body portal 复用 `.ngov` 组件/palette 并覆盖根布局副作用，不修改主题。
- 本地验收：Node 三份共20/20、JS/测试语法、WSL资源打包 fixture 1/1、现有四配色生成器只读 `--check`、`git diff --check`。
- 文档：`luci-app-homestatus/README.md` 与 `docs/homestatus-phase2-verification.md`。
- 未执行：浏览器布局/视觉、真实 LuCI/RPC/设备、SDK/IPK、部署、合并、推送、PR。CSS契约/jsdom不是视觉验收。

## REQ-HT-001 — HomeTunnel 横幅、设置下拉与向导主题适配

- 状态：已验收修复及重复标题移除已冻结为 `luci-app-hometunnel 1.0.0-r3` 源码，准备 squash 发布 master；本轮不构建、不安装 r3。
- 基线：Feed `9730a0a`；主题只读 `0bc8b5a` r13；分支 `fix/hometunnel-theme-unified`。
- 范围：共享 ui.js 实时 --bs-* 角色桥，三视图说明横幅，原生设置/domain select 完整颜色配对与焦点环，六步向导状态 class；移除内容区重复 h2，保留外壳标题、说明、步骤与控件。保留 QR 白底与后端行为；既有共享 alert/button/label/pre 成对兼容。
- 验收：五配色 Edge 915 检查零失败；无主题 fallback 183 检查零失败；wizard 10/10；diagram 30/30。测试机此前 r2 加 wizard 热修复已验收六步、说明与控件，内容 h2=0；不是 r3 安装证据。原生 OS option 弹层视觉及真实主题菜单缓存切换未验，不扩大声明。
- 缓存：模块 ?v= 使用 LuCI 全局 resource_version，不随应用 release 自动变化；不修改全站键，不声称 r3 自动失效缓存。
- 包边界：仅 LuCI 包 release 2→3；runtime hometunnel 版本/源码不改，配置仍由 runtime 所有；保留 LUCI_MINIFY_JS:=0。r2 IPK 不含标题移除，r3 尚未构建，不能声明字节等价或已部署。
- 证据与命令：`docs/hometunnel-theme-unified.md`；`docs/hometunnel-r3-publication.md`；`luci-app-hometunnel/test/theme-browser-test.py`。

---

# Requirements

## REQ-011 — 控制面自愈与重启恢复闭环（boot_restore 界面露出 + daemon respawn + 部署程序修正）

2026-10-22 路由器重启后 HomePublish 管理面全死（LuCI 状态页报错、Start 不可用）暴露的三层缺口，用户已确认三项一起修：

1. **boot_restore 界面露出**：`publication_policy.boot_restore` 在 canonical schema v1/v2、收集侧（product.js `collectConfig`）、diff 文案（"运行方式 / 开机恢复"）里都存在，但入口设置页「运行方式」区段未渲染任何表单控件——用户无法开启"重启后自动恢复发布"。在 entry.js 运行方式区段加 Flag（`depends('mode','continuous')`），文案「重启后恢复发布」，说明"设备重启后自动恢复到发布状态（限定时长模式重启后不恢复；重启前处于已停止则保持停止）"。限定时长模式强制 false（现有收集逻辑保留）。
2. **controller daemon respawn**：`/etc/init.d/homepublish` 无 `procd_set_param respawn`，daemon 崩溃后管理面死锁（只能 SSH 恢复）。加 `procd_set_param respawn 3600 5 0`——daemon 是空闲控制进程，不等于发布；respawn 只拉起控制面，发布恢复仍由 journal desired_state + boot_restore 决定，不违反「Never respawn expired intent」契约（该注释指发布意图，不是控制进程）。
3. **部署程序修正**：此前 IPK 部署用 `IPKG_NO_SCRIPT=1` 绕过 default_postinst（避免自动 enable/start），导致 init 从未被 enable——重启后没人拉起 daemon。修正：日常部署保留 `IPKG_NO_SCRIPT=1` + 明确 `enable && start`；里程碑 IPK 用标准安装（default_postinst 只 enable+start 空闲 daemon，不碰发布）。
4. **关机路径不写 manual latch（实机验证发现）**：原 init `stop_service` 经 CLI `action:stop` 写 `manual_stop_latch=true`，而正常关机走 `K10homepublish → shutdown → stop` 同一路径——boot_restore=true 时正常重启后发布也不恢复（开关被关机路径整体废掉）。修正：init 覆写 `shutdown()`，关机时仅 `procd_kill homepublish`（杀进程不写 latch），journal 保持 desired_state=enabled，开机 daemon restore 判定（`desired_state=='enabled' or phase~='stopped'`）通过。用户手动 Stop 仍走 CLI 显式 latch，语义分层完整。实机循环验证：boot_restore=true + running → `shutdown`（latch 保持 false、desired=enabled）→ `start` → 自动恢复 running + HTTPS 200。

分层语义（本轮固化，写入文档）：LuCI「启用」开关=停/起发布（journal desired_state）；init enable=控制面常驻（基础设施，随安装而非随发布开关）；`boot_restore`=发布策略（随保存的配置）；卸载=彻底停用（default_prerm 自动 disable+stop）。停发布不 disable init——否则管理面死锁、boot_restore 通道被破坏。

验收：TDD（Lua/node 测试先红后绿）+ 实机 127.0.0.1:222 scp 直传验证（rpcd reload 后浏览器/LuCI 路由渲染、Flag 控件、保存回读、daemon kill 后 respawn、模拟重启：stop daemon→start，journal/revision 保持）。不 push/merge/PR，不改防火墙/公网暴露。

基线：master `aa8f2fc`（设备实跑 r9 + e40a679 canonical 修复已含）。证据：本轮对话实机诊断记录。

## REQ-007 — TCP 统一发布与 IPv6→IPv4（P0/P1完成；P2配置UI与部署切片提交；下一阶段P3）

用户已确认四种发布方式：HTTPS反向代理、TLS/SNI透传、一个原生SSH目标共享入口、独立端口TCP转发。IPv6入站→家庭IPv4后端为核心验收路径；入口/后端地址族解耦，支持双栈和只有LAN的旁路由。页面优先原生LuCI JSONMap/NamedSection/GridSection、真实网络地址选择和条件字段。保存不启动、明确应用、整组停止、原临时截止不延长、未知流量不兜底业务。

不承诺UDP/QUIC、任意协议探针、多个原生SSH按域名分流、通用NAT64、上级路由控制或云中继；本阶段不开发UPnP/STUN。精确SNI路由与通配证书分开，HTTPS回源不得默认关闭证书验证。

基线：[详细设计与实施计划](.hermes/plans/2026-10-15_143056-homepublish-tcp-ingress-luci.md)。进度：[TCP入口P0检查点](docs/HOMEPUBLISH-TCP-INGRESS-P0.md)。当前仅授权从P0开始，实机127.0.0.1:222源码直传验证，不跑本地测试；不改管理SSH/Web、认证、防火墙、路由、UPnP、DNS或生产，不push/merge/PR。阶段完成停等指令。

**覆盖映射（保留历史记录）**：REQ-001“仅Web/不用普通TCP forwarder”被本条四方式覆盖；REQ-002旧四步向导被四TAB原生表单覆盖；REQ-003 UPnP在本阶段排除，不代表删除历史需求；REQ-004普通procd生命周期与持久Stop继续有效，旧自定义guardian条款不作为新架构前置；REQ-006证书继承继续有效，仅作用HTTPS反代。下文旧“当前定位/本地测试授权”等为历史快照，以本条和最新用户指令为准。

Current native LuCI/RPC source follow-up: persistent certificate inheritance and notBefore metadata fixed; certificates read RPC, Chinese service list/dialog/entry tabs and real Save/readback locally browser verified. Capability-enabled Start/Apply UI contracts, installed certificate_source/shared runtime, SDK/target and production/public remain unverified. Additional controller-multi run failed provider start (cleanup confirmed), not resolved. See docs/HOMEPUBLISH-CERTIFICATE-UE-CHECKPOINT.md current follow-up ledger. No deployment or network mutations.

## REQ-006 — 家庭统一入口与证书共享（源码切片，待完整验收）

Nginx 是家庭统一入口；入口监听/IPv4-IPv6策略/端口/发布期限为全局设置，服务是域名→后端→证书绑定的虚拟主机。证书库存域名与服务域名分开；支持通配符单层匹配、多SAN、多服务共用引用以及服务独立覆写。私钥仅服务端，不接受客户端路径或上传。推荐 A 原生LuCI列表/编辑对话框，B仅首次新增辅助。本轮先落 canonical/证书匹配与库存内部适配器切片，RPC/UI/安装provider共享运行与真实浏览器仍未完成，详见 [证书UE checkpoint](docs/HOMEPUBLISH-CERTIFICATE-UE-CHECKPOINT.md)。无公网操作。

> **Current r6 simplified-device multi-service acceptance:** Installed conventional Lua provider now renders the complete approved canonical set (two distinct allowed hostnames) into one procd-managed dedicated Nginx generation. Actual target Start/readiness → Save-pending old marker → Apply → two established TLS connections closed on Stop → delete/Apply old-SNI rejection → second-service readiness failure closes the whole generation passed. Business certificate is ONLY `home.iwonderful.top` / `acme:home_rsa` (RSA, system CA); `service.home` uses a separate fixture certificate. Not the historical guardian adapter. Final revision0/disabled/stopped/cleanup confirmed, fixture/runtime absent, both init disabled, routes/listeners/firewall and proxy PID unchanged. SDK r6 source `92c8e33`, package/extracted/installed bytes verified. See [r6 checkpoint](docs/HOMEPUBLISH-DEVICE-MULTI-CHECKPOINT.md). Production/public activation, UI Start/Apply, independent LAN return path and proxy reload remain unverified/unimplemented; no firewall/UPnP/DNS configuration/public writes. Historical r5 single-service limitations below are superseded by this acceptance.


> **Current DNS closure (installed r5, tests/docs only):** Controlled libc getaddrinfo feed A+AAAA→AAAA drives the unchanged installed resolver/selection, real 30-second renew and bounded controller recovery: old master stops, new generation serves IPv6 backend TLS marker, pending Save is not consumed, original temporary deadline persists, POST executes once per backend and Stop removes private snapshots. Non-installed fixed fixture adapter narrows canonical ULA range to ::1; this is controlled answer-change acceptance, NOT changed public DNS records. Source `make controller-multi product rpc` exit0; previous two historical multi failures remain unresolved intermittent evidence (original raw failed logs not recovered). Installed simplified provider explicitly rejects >1 service; no runtime change/rebuild/deploy. Features1–3 are not fully complete: production/UI Start/Apply, installed multi-service, independent LAN/proxy reload, firewall/UPnP/public remain unimplemented/unverified. See DNS section of device integrations checkpoint.



> **Current r5 acceptance:** authorized HomeVPN RSA business certificate now connected and installed: system-CA/hostname TLS A→Save pending A→Apply B→Stop old/new connections and private snapshot cleanup pass; original source cert/key hash+permissions equal server-only. Runtime commit59b7af8, installed homepublish0.1.0-r5; final revision0/disabled/stopped. Passwall enabled/xray16371 unchanged. Historical local multi-controller regression failed; controlled DNS-answer-change, independent LAN/proxy reload and production/public readiness remain unverified. See [current device integration checkpoint](docs/HOMEPUBLISH-DEVICE-INTEGRATIONS-CHECKPOINT.md).


Feature3 business RSA system-trust TLS is now accepted on installedr5 (see current acceptance above). Controlled DNS-answer-change, independent LAN return path and proxy reload remain unverified; do not call Feature3 complete.

> **Current simplified architecture (supersedes historical guard/security gates below):** Lua controller + standard procd dedicated foreground Nginx, ordinary process lifecycle and private permissions; no device C broker/dual guardians/seccomp/memfd/short capability in active package. Normal Stop/temporary/controller lifecycle does not guarantee millisecond hard interruption or independent frozen-controller fail-close. Persisted Stop latch, Save pending, explicit Apply, original temporary deadline and bounded recovery remain. Real device scoped ubus Start/TLS A → Save pending A → Apply TLS B → Stop/keepalive EOF and SDK r3 source binding passed; fixed loopback test profile only. UI Start/Apply still disabled and public production unsupported. Feature3 ACME/DDNS/DNS/Passwall2 integration remains. See [simplified acceptance checkpoint](docs/HOMEPUBLISH-DEVICE-SIMPLIFY-CHECKPOINT.md).


## 当前安装包切片（2026-10-14，本地，不是目标部署）

实际官方 OpenWrt 24.10.5 x86/64 SDK 构建两只 IPK，源码归档 ec46452/6798609，无测试 adapter 入包。修复真实解包发现的 rpcd plugin 0644（RED）为 Git executable 0755（GREEN）。全部 product Lua（含 JSON/RPC/controller/lifecycle）、native ELF、依赖、menu/ACL/default disabled 已实际解包验收。详见 [安装包 checkpoint](docs/HOMEPUBLISH-PACKAGE-CHECKPOINT.md)。

init 不再走旧 UCI→NATMap lease：固定 lifecycle start 在 disabled 时无实例无曝光；stop 调真实 controller，先持久撤意图/latch，再固定 system provider；status 读持久 journal。生产 provider 尚缺，历史 active/attempted 不能证明清理时保留 unknown/blocked，不伪报成功；生产 Start/Apply 仍 unsupported。未注册/运行 procd daemon，未做真实 BusyBox/procd 目标安装验收；此项明确待验，不以 shell/包测试替代。普通用户 make product rpc 与实际 IPK 验收 exit0。fw4/UPnP、DNS/ACME/Passwall2、生产 provider/目标部署/公网及统一安全复评仍未完成。SSH 未恢复未重试，未部署/映射/防火墙/push/merge/PR。


## 当前功能入口：访问配置向导与分层状态（本地完成，非生产激活）

服务/域名/证书 → 接入方式与策略 → canonical 只读预检/Save → 独立 Start 与分层结果为同页四步向导，前后导航保留输入；保留服务及双栈监听增删编辑。旁路由 manual IPv4 优先；direct IPv6 路由/入站许可非 DNAT；UPnP/STUN 只保存现有 schema 允许方式，明确适配器未接入、不执行映射或实验。生产 Start/Apply 继续 disabled/unsupported、activation_ready=false。

概览轮询真实 status 的 saved/active/pending/attempted/candidate、内部 phase/active_verified/generation/readiness/cleanup、recovery attempt_count(预算3)/next_retry/reason、原 deadline、saved/active boot_restore、restore stage/clock/boot_id；外网 IPv4/IPv6 始终未验证，无假网络探测。Stop 原合同不变。

验收：真实 Windows Chrome → 官方 LuCI loader → loopback uhttpd/rpcd/ubus → fixed CLI/native journal。RED `wizard-red.log` 缺 hp-wizard-step 超时，make 非零（包装 shell rc 打印错误，不以包装 rc 作为 make 证据）。GREEN `wizard-final.log` browser exit0；只读 validate 不改 revision0、Save revisions1/2/3、两服务/双栈/UPnP gateway readback、back steps 未保存输入保留、reload、编辑/删除、duplicate/empty canonical 禁保存、pending 无 active、独立 Start 禁用、分层未知外网及 DOM Stop latch 全部 PASS；owned processes/mounts/listeners=[]、fixture directory_absent=true。普通 WSL 用户 `make product rpc` exit0，日志 `wizard-product-rpc.log`。日志在 `/home/eric/homestun-sdk-check/`；localcommit 后另跑 `wizard-committed.log`，结果由最终交接读回。

剩余功能：production provider/Start/Apply 权威 adapter、fw4/UPnP 有限租约、DNS/ACME/Passwall2 集成、真实 procd/BusyBox/matching SDK 和目标部署验收；SSH127.0.0.1:222 未恢复、不重试。安全统一复评留后，不展开安全深化。没有生产安装/fw/映射/公网/push/merge/PR。内部恢复/Nginx功能沿用已验切片，不把 UI 生产 unsupported 状态说成 running。


当前bounded recovery/boot本地功能切片完成：approved active snapshot恢复不偷用Save pending，确认清理后1/2/4秒退避、每轮3次budget耗尽blocked；Stop抢占retry/stale事件、cleanup unknown禁恢复。boot_restore默认关，开启后固定scope重验/readiness新generation；temporary仅注入可信同boot时钟恢复且原expires_at不变，不确定/变boot/到期关闭。真实Nginx PID KILL后短断、新代TLS marker和跨controller重启continuous off/on/latch已验证。详见[恢复checkpoint](docs/HOMEPUBLISH-CONTROLLER-RECOVERY-CHECKPOINT.md)。历史恢复切片时生产adapter/向导/部署未完成（向导现已由顶部本地验收更新），生产禁激活与统一安全复评风险清单不变。


当前多服务controller本地功能切片通过（接续56bc5fa）：canonical保存的两服务进入同一专用guarded Nginx实例，独立SAN/证书/key、IPv4/IPv6入口到IPv4/IPv6 backend四组合真实TLS marker通过；逐服务readiness绑定整体generation，全部成功才提交active/running。Save修改单服务仍pending旧流量，Apply先stop/reap旧整代再启动新整代（有短暂停机，非零停机reload）；删除服务后旧SNI不再提供业务。第二服务readiness失败关闭全实例，历史active仅记录、attempted/candidate独立、active_verified=false。Stop断两服务已建立stream并关闭双栈listener/native runtime。temporary首次deadline经Save/Apply保持；原单服务60秒自然到期回归本轮一次通过。详见[多服务checkpoint](docs/HOMEPUBLISH-CONTROLLER-MULTI-CHECKPOINT.md)。production Start/Apply unsupported与activation_ready=false不变；内部固定test-only adapter不等生产支持。安全深化暂停，下一步bounded recovery/可信时钟/boot接口、向导/生产provider/目标验收；SSH127.0.0.1:222仍未恢复未重试，未安装/公网/fw/UPnP/push/merge/PR。

当前功能主线：D2 controlled Apply/temporary/readiness 本地切片完成，源码 `926311e`。内部明确approval与固定scope核验后stop/reap旧代、启动新generation，真实TLS+HTTP readiness成功才提交active/running；失败保留历史active、attempted/candidate并标active_verified=false、stage/error/cleanup，不假保旧仍运行。两backend marker/counter证明Save仍旧流量、Apply真实切换。真实60秒temporary首次绝对截止经Save/Apply不延，持续stream与新listener到原截止关闭、desired撤销；修复长会话双guard心跳队列累积导致约9秒误关。committed源码 `make controller product direct guardian-nginx` exit0（64条PASS输出，非64独立用例），证据 `/home/eric/homestun-sdk-check/controller-apply-committed.log` 及 `.exit`。下一功能方向scoped RPC/UI状态/Save/Stop与内部受控入口；双栈多服务controller、bounded recovery/时钟可信/重启仍未完成。安全深化暂停，最终统一复评清单保持未完成；production CLI Start/Apply unsupported、ENOTSUP/helper78、activation_ready=false不变，非产品完成。

## 当前授权与阶段

Current r7 continuation: actual-device Chrome official single LuCI view lifecycle / scoped RPC / real procd Start → shared RSA TLS → Save pending old traffic → Apply independent ECC + original deadline → Stop both held TLS connections and new listener/private snapshots PASS. Target restored revision0/disabled/latch/cleanup confirmed, ACME backup exact, fixtures gone, controller/backends stopped, both init disabled, management/proxy/listeners/routes/firewall preserved. See docs/HOMEPUBLISH-R7-BROWSER-ACCEPTANCE.md. Natural expiry and second-readiness-failure r7 rerun not tested; public activation remains unsupported.

**HomePublish（家庭服务直连）最终设计基线已整理。** 用户确认正常发布持续直到停用，临时限时可选，UPnP有限租约受控续租，开机恢复独立设置；直接双栈专用Nginx，不通用forwarder。详见[完整设计](docs/homepublish-product-design.md)和[审查清单](docs/homepublish-design-review-checklist.md)。当前用户已授权隔离分支源码开发、本机/WSL测试与local commit；禁止生产操作、安装、Add/Delete映射、公网测试、防火墙/路由/Cloudflare操作，以及merge/push/PR。先前仅文档授权已由本次源码授权取代，真实生产操作仍须另定范围。默认未发布、Save不启动，明确开启可持续运行；产品自动INPUT能力不是本批生产写授权。命名迁移源码已完成；canonical校验、固定stdin CLI及原生私有持久化最小切片已本地验证，产品仍未完成，历史实验不是生产验收。当前证据与续跑入口见[checkpoint](docs/HOMEPUBLISH-PROGRESS.md)。

## REQ-001 — 家庭Web HTTPS直连（当前定位）

Status: 产品方向确认；D1 canonical/journal/CLI与D2a纯内部直接Nginx/安全静态backend本地切片已验证。D2a真实loopback TLS四组合、controlled hostname IPv4优先及POST零重放通过；仍无controller/guardian、生产权威DNS/TLS/归属角色provider与TTL刷新。Start/Apply继续unsupported，产品未完成、无生产集成；证据见docs/HOMEPUBLISH-PROGRESS.md。

- 服务/域名/证书/业务鉴权优先，首版IPv4/IPv6双栈独立Nginx直接监听，manual IPv4/finite UPnP/direct IPv6；STUN仅有界高级实验。IPv6功能本地gate必做，真实外网可后验并标未验证。
- 单服务backend IPv4 literal/IPv6 literal/hostname，默认确定IPv4优先，受限resolver验证所有A/AAAA结果与归属、TTL快照/安全刷新；显式IPv6 primary和backup候选，默认proxy_next_upstream off，不重放POST/PATCH/PUT。
- 不共享/修改管理SSH/Web，不用普通TCP forwarder；显式地址绑定/IPV6_V6ONLY。保留native独立监管、secret snapshot、foreign-fd/seccomp、owned清理。
- 默认未发布，Save仅本应用commit，无global apply/start/reload；持续/临时见REQ-004，旧120秒仅实验实现约束，非产品上限。
- 开启后精确owned TCP INPUT限定family/address/interface/zone/port，无全局ACCEPT/FORWARD。主/旁IPv4固定转发优先→获准UPnP→获准STUN；IPv6路由/许可非DNAT。切换先清旧曝光，残留unknown阻止fallback/危险port复用；HomeTunnel仅导航、不动。
- ACME/DDNS-Go复用实际接口，不猜record API、不fork；Cloudflare可选，应用已有认证优先、不自研login，TTL不替鉴权。
- 配置/实际监听/INPUT/DNS/TLS/mapping/external分层；无独立probe可安全manual运行并标未验证链接，不假可达；安全能力缺失仍block。
- 历史：STUN三变体公网TCP拒绝；UPnP独立HTTPS/53tick/native 120秒截止/网关约300秒expiry；旧LuCI/SDK证据入口[resume](docs/HOMESTUN-RESUME.md)，均不替新验收。

## REQ-002 — 命名迁移与统一LuCI

Status: 源码命名迁移已完成；canonical/scoped Save/原生journal/CLI本地切片完成，新四页交互与真实rpcd权限未实现。Start/Apply明确unsupported，Stop只持久撤意图并报告未实现或cleanup_required，不声称真实运行/已清理。

- homepublish/luci-app-homepublish/UCI/ubus/init/path同批迁移，保留旧报告/artifact/hash；不双daemon、不默认copy秘密/启动。
- 四页家庭概览/服务/接入方式/设置诊断；四步服务证书→接入scope→只读校验与Save→明确开启及分层结果。
- canonical同源权威校验；active/saved revision分离，Save后pending，显式Apply受控replace，扩大scope/服务需确认；不每次健康renew/recovery弹窗。
- 角色read/config/exposure最小权限，无任意exec/file/service/nft；真实rpcd scoped commit测试，不仅UI约束；坏配置禁用恢复/Save不冒称active已停。
- 默认未发布，开启/停止/临时expiry/boot恢复、unknown/warning明确交互，无单绿灯；真实loader/TypedSection/Save/browser/rpcd验收。

## REQ-003 — UPnP有限映射与受控续租

Status: 正式模式方向确认；最终生命周期设计已整理，adapter尚未实施。

- read-only discovery、finite Add/renew、Delete和persistent权限分列；可信IGD/interface/identity/control URL，精确TCP/RemoteHost/内外tuple，冲突拒绝、不覆盖/搜port/永久lease。
- continuous按实际finite剩余提前renew同entry；核desired/no-stop/approval/scope/gen/epoch/guardian与tuple，单在途mutation/sequence，renew后精确readback，非每次确认。temporary lease申请/renew不得越原policy截止。
- UPnP query→update/delete常非原子，description非不可伪造owner；需支持的受控/排他契约，否则禁具体unsafe能力、自然expiry/manual，不能blind Add。timeout=效果unknown，先query，unknown/conflict关，不盲重复。
- Stop先数据面/已有连接/owned INPUT，再经授权safe Delete/readback或自然expiry观察；最后存在—首次不存在区间。residual/unknown保留危险port，禁fallback/复用/foreign删除。
- gateway reboot/entry loss先关闭、核absent后同scope有限新事务恢复；procd只恢复controller非expired旧session。租约/guard/policy分别记录。
- 协议fixture及真目标测试：finite/永久/timeout/conflict/竞态/stale event/multiple renew/temporary cutoff，KILL/STOP/reload/owned rollback、独立外网持续流/Stop/两层清理；不复跑旧Add实验。

## REQ-004 — 持续/临时发布、内部有限能力及恢复

当前功能主线：D2 controlled Apply/temporary/readiness 本地切片完成，源码 `926311e`。内部明确approval与固定scope核验后stop/reap旧代、启动新generation，真实TLS+HTTP readiness成功才提交active/running；失败保留历史active、attempted/candidate并标active_verified=false、stage/error/cleanup，不假保旧仍运行。两backend marker/counter证明Save仍旧流量、Apply真实切换。真实60秒temporary首次绝对截止经Save/Apply不延，持续stream与新listener到原截止关闭、desired撤销；修复长会话双guard心跳队列累积导致约9秒误关。committed源码 `make controller product direct guardian-nginx` exit0（64条PASS输出，非64独立用例），证据 `/home/eric/homestun-sdk-check/controller-apply-committed.log` 及 `.exit`。下一功能方向scoped RPC/UI状态/Save/Stop与内部受控入口；双栈多服务controller、bounded recovery/时钟可信/重启仍未完成。安全深化暂停，最终统一复评清单保持未完成；production CLI Start/Apply unsupported、ENOTSUP/helper78、activation_ready=false不变，非产品完成。

最新恢复补充：`7c9e8d2` 后正式接入 actual-Nginx `openssl-engine` 回归，SDK constructor恶意module在旧环境fixture RED真实open/maps/marker，当前固定空config GREEN无ambient/module访问；八target完整本地make exit0，证据与命令见 docs/HOMEPUBLISH-D2D2-CHECKPOINT.md，当前入口 docs/HOMEPUBLISH-RESUME-CHECKPOINT.md。observer仅隔离观测、bind前终止，不代表native guardian cleanup或sameUID边界。仍仅本地subset/自检，父独立审查待；production ENOTSUP、helper78、Start/Apply unsupported、activation_ready=false保持；安装签名、不可变库路径/musl fallback、controller/TLS、typed durable residual/partial prepare与matching SDK/真目标仍blocked。

Status: continuous/temporary产品设计已确认；D2b1本地受控worker F2边界新增实际setsid逃逸RED→GREEN，fork/doublefork/exec树及单guardian/watchdog STOP/KILL关闭；19树场景+10启动故障+18生命周期、三角色foreign FD逐inode读回通过，core commit 4628cfcfa6d5a1101e70f6510badc404093cdea6。仅可信固定非root同UID/GID前台worker，继承seccomp/NNP，禁止逃组/namespace/凭据迁移/FD导入；非任意hostile代码或cgroup sandbox。READY仅native隔离监管就绪，typed ERROR packets待补；详见docs/HOMEPUBLISH-D2B1-CHECKPOINT.md。D2b2新增真实Nginx guard integrated RED gate：cached固定非root2worker、KILL重建/同master多窗口renew、双栈TLS及单controller/guardian/watchdog KILL/STOP断流均已观察，但内部recvmsg channel仍EPERM，正常SCM_RIGHTS channel收取/notify未通过。外来UNIX真实SCM_RIGHTS导入被现有全局禁令拒绝；未实现安全兼容例外，不能以该攻击测试声称新profile安全闭合。TLS/runtime文件仍harness清理，生产provider、controller health/scope、native TLS/journal/fw、恢复/boot/UPnP及target架构/时延仍待验收，详见docs/HOMEPUBLISH-D2B2-CHECKPOINT.md。两guardian同时STOP/KILL和内核失调度不在用户态覆盖范围。Start/Apply unsupported、activation_ready=false、helper exit78保留，产品未激活、非生产完成。

追加当前review pointer（保留上述D2b2历史RED）：D2b3 private STREAM socketpair真实Nginx内部channel兼容本地GREEN，generic仍拒recvmsg，test-only新profile拒外来UNIX连接；详见 docs/HOMEPUBLISH-D2B3-CHECKPOINT.md。D2c1父controller-stop清理失败已独立重复RED，根因双guard cleanup前互杀；FD-pinned文件/目录与cleanup-before-peer-kill关闭本地竞态，14 native cases+100 Stop重复、5连续Nginx矩阵及一次全套make exit0；兜底前metadata记录、foreign保全见 docs/HOMEPUBLISH-D2C1-CHECKPOINT.md。固定exec authority、生产SAN/health/controller、typed residual/durable crash recovery和目标验收仍未完成；禁激活不变。

追加 D2c2 startup review 修复见 docs/HOMEPUBLISH-D2C2-CHECKPOINT.md：pidfd EMFILE 注入在真实写入后残留已正式 RED→GREEN；server-owned provisioning barrier 与 startup cleanup责任闭环本地验证，24新增fault+三连续committed-source真实Nginx矩阵；非自然资源耗尽证据，typed durable residual/生产authority/target gates仍blocked，禁激活不变。

追加当前errno review pointer：a794446 invalidargs/binding独立review通过后的LOW错误语义收尾见 docs/HOMEPUBLISH-D2C2-CHECKPOINT.md Early startup errno/residual closure；正式random missing/foreign及controller pidfd RED→GREEN，统一early cleanup tail/residual优先级，79 startup runs+两contracts与全套真实本地回归通过；本次仅自检，生产activation继续false，Start/Apply unsupported/helper exit78不变。

追加 D2c2 独立复审：原秘密残留修复通过；LOW 无效参数遗留empty anchors已五项正式RED→GREEN，cleanup责任仅本次prepared binding，active重入/claimed ledger拒绝且不误删，foreign replacement保留residual。11 fault正式regression及25 delayed ACK重复，总65 startup runs+两ownership contracts；详情/命令见 docs/HOMEPUBLISH-D2C2-CHECKPOINT.md LOW closure，最终commit复验由报告读回。新修复独立复审仍待，Start/Apply unsupported、activation_ready=false、helper exit78保持。

追加 D2d1：固定可信host provider可运行subset与真实依赖映射验收见 docs/HOMEPUBLISH-D2D1-CHECKPOINT.md；exec替换正式RED→GREEN，14拒绝回归、sealed exec/loader及5库verified native-owned readonly snapshot、环境清除/8真实Nginx故障清理与全套make本地通过。库path/kernel immutable authority与目标安装manifest仍未闭合，production API ENOTSUP；未宣称生产trust closed，禁激活保持，parent/独立review待。

- continuous无用户总deadline；temporary默认30分钟、15/30/60快捷、自定义1分钟～24小时，后端验证，准备/Add计入首次批准截止，Apply/recovery/reboot不得续时。
- desired enabled/disabled与runtime/generation独立，manual_stop_latch持久化优先。guard capability始终有限，controller健康核验续授权，失控fail closed；不能TTL=0/循环旧fixed-deadline达成持续。
- 合法enabled同scope自动健康恢复，每轮有限尝试/指数backoff/上限、超阈值blocked，不thrash/blind Add。Stop/过期/stale事件不得复活；STUN仍有界无自动常驻。
- boot_restore默认关，用户开启后boot全量revalidate才恢复；controller运行期crash恢复与boot恢复分开。temporary expires_at持久、剩余时钟不可信即停止，不重算duration。
- 验收continuous跨多guard/UPnP周期、controller/guardian失联/STOP、Stop latch与旧event、boot开关/临时重启与时钟回拨、故障恢复边界。

## REQ-005 — 安全维护、证据与分层发布gate

Status: 最终设计纳入首版；尚未实施/实网验收。

- fw4/proxy/network reload先门控再同scope reconcile/readback，合法enabled可恢复，不永久每次manual、不宽规则临时暴露、不重置temporary截止。
- prefix变化旧endpoint/AAAA/external失效，重新确认GUA；既定接口稳定地址选择范围内可安全replace，literal或扩大scope待Apply。
- DNS/ACME candidate受监管copy、SAN/key/权限/有效期/nginx -t/backend安全验证、原子journal/gen replace，失败保合法旧版或关，绝不fail-open；candidate secrets也清理。
- Passwall2一直开启，真实版本mark/mask/order/route/DNS/回程验证，不全路由bypass或复制历史mark默认。
- 鉴权审核不可由TTL代替，未认证服务显式独立风险复核，管理冲突硬blocker不可绕过；unknown外网不冒充安全能力缺失。
- D0文档→D1canonical迁移→D2runtime双栈→D3INPUT/UPnP恢复→D4真LuCI/RPC→D5维护代理→D6matching SDK/真BusyBox-procd-fw4→D7授权实网。四种入站/后端、主旁双栈、owned INPUT rollback/reload/boot/renew矩阵完整，真SDK不host替代；IPv6真实外网单独后验状态。
---

## REQ-001 历史原文 — Independent HomeSTUN TCP HTTPS entry

> 下方保留最初需求与当时 gate 的追溯，不代表当前 gate；以顶部当前 REQ-001/002/003 和统一设计为准。历史产品名、测试域名及旧阻断叙述不做追溯替换。

Status: implementation, experimental first slice (not deployable end-to-end).

- Independent `homestun` and `luci-app-homestun`; no cloudflared dependency.
- NATMap TCP forwarding to a dedicated nginx HTTPS listener, multiple explicitly configured hostnames/upstreams; no UDP in v1.
- One Worker portal `stun-test.innonext.win`; DNS-only `nas-stun-test.innonext.win` and `files-stun-test.innonext.win`.
- Authenticated mapping publication, fixed redirect host allowlist, bounded leases, fail closed on missing/expired/invalid mappings.
- Router expiry/closure must terminate the actual dedicated listener and NATMap process; portal expiry alone is insufficient.
- Never alter management SSH, nginx 80/443, existing firewall/tunnels, or expose NAS/printer/LuCI during tests. No secrets in git.
- NAT feasibility acceptance requires an independent external TCP probe; a STUN IP is not proof.
- Acceptance of this first slice: real RED/GREEN tests for validation, isolated nginx generation, Worker lease enforcement; safe router read-only inspection and isolated loopback test where feasible; documented blockers/cleanup. Full lifecycle/NATMap/UI deployment remain separate acceptance gates.
- Package/UCI/procd source slice delivered experimentally: target-built helper only, default disabled and exposure-approval off, independent bounded TCP engine group, strict UCI and configuration-only diagnostics. Real enabled procd, SDK/ipk, LuCI, publication, TLS-source cleanup and external TCP acceptance are still blocked pending independent review/authorization.

### REQ-001 follow-up — permanent Passwall2 coexistence (planned, not implemented)

- Architecture and acceptance gates: [`docs/homestun-passwall2-coexistence.md`](docs/homestun-passwall2-coexistence.md).
- Keep Passwall2 enabled; default only HomeSTUN's external NATMap discovery/keeper/listener replies and dedicated DNS on verified direct egress. Use engine-owned SO_MARK via pinned NATMap `-f`; do not bypass nginx, publisher, all root processes, or the entire router.
- Fixed mark is adapter-specific, not universal: verify installed nft hooks, bypass mask/order, all policy-route masks/priorities, DNS interception, and optional interface routing before exposure. Unknown/incompatible/uninspectable state fails closed without starting/publishing an entry.
- Preserve existing seccomp foreign-fd-import prohibition, bounded TTL, guardian cleanup, original expiry and disabled/exposure-approval defaults; proxy/firewall/network changes must revalidate or close the owned data plane, never silently proxy or renew it.
- Acceptance requires target socket/DNS and ordinary-proxy controls, independent external TLS/marker proof with Passwall2 running, reload/failure/expiry matrices, and explicit upstream-gateway ACL limitations. Source review or a temporary bypass experiment is not permanent-coexistence acceptance.
- Documentation-only follow-up registered here; no implementation, remote configuration changes, commits, or deployment implied.

## r8 actual overview correction
Previous UI completion claims described the settings-internal tab; the actual menu overview route still used a 15-line English diagnostic text renderer. This was an omission, not accepted overview UI. The dedicated overview now renders Chinese cards, saved service table, entry/certificate summary, pending notice, shared capability-gated Start/Apply/Stop confirmation, retryable unknown errors and collapsed diagnostics. No settings editor duplicated or redirect used. RED Chrome official installed loader (one view node) failed waiting for hp-overview-services. Local source GREEN passed against genuine target RPC; final SDK/install/readback evidence is recorded in docs/HOMEPUBLISH-R8-OVERVIEW-ACCEPTANCE.md. Public activation/reachability/firewall/UPnP remain unsupported/unverified.


