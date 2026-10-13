# Requirements

## 当前授权与阶段

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

Status: continuous/temporary产品设计已确认；D2b1本地受控worker F2边界新增实际setsid逃逸RED→GREEN，fork/doublefork/exec树及单guardian/watchdog STOP/KILL关闭；19树场景+10启动故障+18生命周期、三角色foreign FD逐inode读回通过，core commit 4628cfcfa6d5a1101e70f6510badc404093cdea6。仅可信固定非root同UID/GID前台worker，继承seccomp/NNP，禁止逃组/namespace/凭据迁移/FD导入；非任意hostile代码或cgroup sandbox。READY仅native隔离监管就绪，typed ERROR packets待补；详见docs/HOMEPUBLISH-D2B1-CHECKPOINT.md。D2b2新增真实Nginx guard integrated RED gate：cached固定非root2worker、KILL重建/同master多窗口renew、双栈TLS及单controller/guardian/watchdog KILL/STOP断流均已观察，但内部recvmsg channel仍EPERM，正常SCM_RIGHTS channel收取/notify未通过。外来UNIX真实SCM_RIGHTS导入被现有全局禁令拒绝；未实现安全兼容例外，不能以该攻击测试声称新profile安全闭合。TLS/runtime文件仍harness清理，生产provider、controller health/scope、native TLS/journal/fw、恢复/boot/UPnP及target架构/时延仍待验收，详见docs/HOMEPUBLISH-D2B2-CHECKPOINT.md。两guardian同时STOP/KILL和内核失调度不在用户态覆盖范围。Start/Apply unsupported、activation_ready=false、helper exit78保留，产品未激活、非生产完成。

追加当前review pointer（保留上述D2b2历史RED）：D2b3 private STREAM socketpair真实Nginx内部channel兼容本地GREEN，generic仍拒recvmsg，test-only新profile拒外来UNIX连接；详见 docs/HOMEPUBLISH-D2B3-CHECKPOINT.md。D2c1父controller-stop清理失败已独立重复RED，根因双guard cleanup前互杀；FD-pinned文件/目录与cleanup-before-peer-kill关闭本地竞态，14 native cases+100 Stop重复、5连续Nginx矩阵及一次全套make exit0；兜底前metadata记录、foreign保全见 docs/HOMEPUBLISH-D2C1-CHECKPOINT.md。固定exec authority、生产SAN/health/controller、typed residual/durable crash recovery和目标验收仍未完成；禁激活不变。

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
