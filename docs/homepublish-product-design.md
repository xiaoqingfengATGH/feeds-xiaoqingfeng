# HomePublish · 家庭服务直连：最终产品、技术与交互设计

> **Current simplified architecture (supersedes historical guard/security gates below):** Lua controller + standard procd dedicated foreground Nginx, ordinary process lifecycle and private permissions; no device C broker/dual guardians/seccomp/memfd/short capability in active package. Normal Stop/temporary/controller lifecycle does not guarantee millisecond hard interruption or independent frozen-controller fail-close. Persisted Stop latch, Save pending, explicit Apply, original temporary deadline and bounded recovery remain. Real device scoped ubus Start/TLS A → Save pending A → Apply TLS B → Stop/keepalive EOF and SDK r3 source binding passed; fixed loopback test profile only. UI Start/Apply still disabled and public production unsupported. Feature3 ACME/DDNS/DNS/Passwall2 integration remains. See [simplified acceptance checkpoint](HOMEPUBLISH-DEVICE-SIMPLIFY-CHECKPOINT.md).


**最终设计基线，待独立实现审查；不是已实现、已部署或生产发布证明。** 本文整体替代旧强制短时、常驻延期、通用forwarder、所有会话固定deadline设计。需求：[REQ-001～REQ-005](../REQUIREMENTS.md)；自查：[设计审查清单](homepublish-design-review-checklist.md)。

## 1. 定位、决策与范围

以服务为中心配置家庭Web HTTPS直连：先服务、域名、证书、业务鉴权，再接入机制。不承诺任意网络直连、不隐藏公网端口、不绕过上级访问控制、不以门户登录替业务鉴权。

### 已确认方向与本文默认决策

- 已确认：HomePublish（家庭服务直连）；正常发布持续到用户停用，临时限时可选，STUN是有界高级实验。UPnP有限网关租约受控续租；开机恢复独立明确设置。
- 已确认：独立专用Nginx直接监听IPv4/IPv6，普通manual/UPnP/IPv6路径不使用通用TCP forwarder。首版双栈入站，IPv4/IPv6 literal/hostname后端，默认确定IPv4优先，不重放POST等写请求。IPv6真实外网验收可后放，不是功能future占位。
- 已确认：明确开启后默认精确owned TCP INPUT；主/旁路由IPv4固定上级转发优先，不可配置可授权UPnP，再授权STUN；IPv6是路由/入站许可，不是IPv4 DNAT。HomeTunnel不动，失败仅导航；真实ACME/DDNS-Go边界复用，CF门户可选。
- **本文选定产品默认，不是历史实验参数或新增口头批准**：首次未发布；策略默认持续；boot_restore默认关；temporary默认30分钟、快捷15/30/60分钟、自定义1分钟～24小时，后端有界验证、不自动延期。内部guard周期/网关单次lease按真实目标能力确定，不是用户发布时长。
- 一次明确开启授权覆盖策略、全部服务、入口family/address选择范围/interface/zone/port、允许机制和UPnP续租。健康续授权/同范围恢复不反复弹窗；添加服务、换网关、扩大scope必须显式Apply确认。

### MVP及本轮操作边界

MVP：家庭HTTP Web后端经专用Nginx HTTPS发布，manual IPv4/finite UPnP IPv4/direct IPv6，continuous/temporary、健康恢复/可选boot恢复、精确INPUT、受控DNS/证书快照替换、四页LuCI、分层诊断。

不做任意TCP/UDP转发、NAT-PMP、UPnP IPv6 pinhole、通用中继、自研登录、任意路径动态代理、扫描自动发布。HTTPS upstream、请求级GET/HEAD failover、逐服务独立运行组另批扩展。NATMap仅高级STUN依赖，不强制ACME/DDNS-Go/CF/HomeTunnel。

本轮仅文档：不改代码、不安装、不读秘密、不Add/Delete映射、不操作防火墙/路由、不公网测试、不部署CF、不commit/merge/push/PR。产品自动放行批准不等于本轮生产操作授权。

## 2. 旧实现事实与证据

| 旧实验层次 | 实际已有事实 | 不代表 |
|---|---|---|
| 配置/数据面 | core.lua私网HTTP IPv4 upstream、1..16 hostname、独立loopback TLS、未知host拒绝 | 新双栈直接监听/持续模式已实现 |
| 生命周期 | lease-supervisor.c、guarded provisioning、不可变snapshot、双监管回归；旧init无respawn/reload | 固定deadline引擎不改即可长期运行 |
| 状态/LuCI | 配置状态、mapped unknown/reachable unverified；真loader/Save、Node 10/10、SDK/IPK | 新live-state/统一向导/生产验收 |
| STUN | 三个有界变体发现endpoint，独立外网TCP拒绝 | STUN可用、确定NAT类型/拒绝节点或CGNAT必不可用 |
| UPnP实验 | 独立CA/hostname/marker、53持续ticks、native 120秒关闭、网关约300秒自然expiry | 正式renew adapter完成或所有网关兼容 |
| 共存/发布 | 隔离publication和Passwall2共存设计 | CF部署/永久共存完成 |

旧config.lua TTL 1..120秒、loopback listener、NATMap六/八字段plan是实现约束。**120秒只记录旧实验引擎能力，不是最终产品时长上限。** 新native/config/UI/init/RPC协同重构；TTL=0、绕过guardian、循环restart旧期限会话不是continuous。

证据：[续跑历史gate](HOMESTUN-RESUME.md)、[LuCI包绑定](homestun-luci-package-final.md)、[STUN终态](homestun-stun-retry.md)、[UPnP活跃截止](homestun-upnp-active-cutoff.md)、[guarded provisioning](homestun-guarded-provisioning.md)、[Passwall2共存](homestun-passwall2-coexistence.md)。旧报告/日志/JSON/artifact名称与哈希保持，历史forwarder不转成新产品推荐，旧PASS不替新gate。

## 3. Canonical数据模型与持久化（拟议schema，非现有实现）

前端反馈与后端权威校验同源，提交/启动重新验证整份committed配置。

| 对象 | 核心字段 | 约束/语义 |
|---|---|---|
| config | schema_version/revision/运行组/services | 严格已知字段，本应用commit，revision后端生成 |
| service | service_id/name/hostname/backend/certificate_ref/authentication_review | 每服务一个域名，拒绝重复/通配符/正则host，人工鉴权/管理角色审核 |
| backend | addressFamily=ipv4/ipv6/hostname、host/port、backup、允许地址范围 | 默认IPv4，不接任意URL/命令，不扫描 |
| access_profile | 有序methods_allowed、families、bind_addresses或已批准地址选择范围、interface/zone、TCP内外端口、gateway_ref | 入口/后端族独立，显式scope，无默认wildcard扩权 |
| publication_policy | mode=continuous/temporary、temporary_duration、boot_restore | continuous无用户总截止，temporary持久绝对截止，恢复默认false |
| approval | service_set/scope_hash/revision、机制与renew/delete权限 | 服务器绑定，不信前端布尔标志 |
| desired_state | disabled/enabled、manual_stop_latch、intent_revision | 初次Save disabled；Stop先持久撤销，与runtime分离 |
| runtime | generation/active_revision/capability_epoch/guard_valid_until/owner identities/phase | 重建新gen，内部有限权限与独立监管 |
| temporary_runtime | expires_at、可信时钟关联、本次monotonic_deadline | Apply/reboot不重算duration，剩余不可信停止 |
| gateway_lease | gateway identity/tuple/gen描述、requested/observed剩余、renew状态 | 与policy/internal guard分开，finite精确读回 |
| evidence | layer/family/endpoint/gen/revision/observed_at/source/status/失效原因 | unknown/unverified如实呈现 |
| pending_config | saved_revision/apply_required/diff_scope | 保存不Apply，active旧不可变snapshot |

运行组可同端口hostname分流，为首版最小启停单位；开启列出组内全部曝光服务，不能“启动一个”隐式曝其他。逐服务独立启停不作首版承诺。配置仅非秘密引用/意图；root-private原子journal保存guard/port/process/file身份与lease事务，journal非无限权限凭证。秘密不入UCI/argv/status/RPC/log/浏览器。active与saved revision分离。

## 4. 发布政策、状态机与监管

| 时间/策略 | 语义 | 续展边界 |
|---|---|---|
| continuous | 直到用户停用 | 不设用户总deadline，Stop/撤销/安全故障可关闭 |
| temporary | 默认30分钟、可验证有界自定义 | 不自动延期，显式改策略/新临时发布才另确认 |
| health capability/guard lease | 独立guardian在有限窗口检测失控并收回 | controller在旧权限有效、全量健康校验后有限续授权；不得越temporary截止 |
| UPnP finite lease | 一次精确网关映射期限 | continuous安全same-entry更新；temporary不越policy截止 |

DNS TTL/证书有效期/HTTP idle timeout不是曝光授权。持续运行不等于无限安全能力，必须新增可续授权native机制，不能硬复用旧immutable fixed-deadline supervisor。guard周期/请求超时/提前量按真实目标最坏耗时确定并可观测。

```text
disabled --Save--> disabled/已保存
disabled --明确开启--> validating -> provisioning -> starting -> running
running --Save--> running(旧快照)+pending
running --Apply--> controlled replace -> running(新gen)/safe failure
running --故障--> degraded/关闭 -> bounded recovery/blocked
running --Stop/临时到期--> 先撤意图 -> stopping/cleanup -> stopped/expired(残留单列)
```

开启重新核验committed revision、scope、全部服务、管理冲突、鉴权、证书、backend、INPUT、代理/网关能力；guardian/owner登记先于秘密复制和资源创建。listener门控/隔离状态验证本地TLS/backend，再开放批准INPUT/映射并读回；失败回滚owned资源。

Stop先原子desired disabled/manual_stop_latch=true并撤capability，再关listener/已有连接/引擎/门户、撤owned INPUT，后Delete/观察上级映射、清owned快照。安全停用不graceful linger拖延断流；本地/规则/上级残留分别报告。旧event/procd/reload/reboot不复活手动Stop。

temporary从首次批准算，准备/Add耗时计入；持久expires_at和本次单调deadline对齐，到期撤enabled、关闭新/已有连接。Apply/recovery/reboot不重置期限。

### 续授权与可用性

- desired enabled、no-stop、temporary有效、同scope/revision/epoch、controller/guardian健康、秘密/监听/规则/路由/映射owner有效才续有限capability；不要求浏览器在线。
- guardian独立于controller/RPC，controller SIGSTOP不能冻结guardian；续授权失败/卡死/guardian失联或身份不明则有限窗口收回数据面和规则。D-state/内核阻塞等关停极限诚实记录，不能保证绝对零窗口。
- crash后guardian关旧gen；procd可重启控制器，不能裸respawn旧Nginx/NATMap或expired session。新controller读intent/stop/deadline/journal、核验回收owned残留，全量revalidate、新gen同scope恢复。
- 合法continuous enabled允许健康自动恢复，无每次manual开启；每轮有限次数、指数backoff/上限、稳定期重置，超阈值blocked等待修复，禁thrash/crash-loop/blind Add。旧mapping unknown不恢复曝光。
- boot_restore独立于运行期crash recovery，默认false：boot只显示已保存/等待开启，不曝光，即使上次enabled。用户开启恢复后仅enabled/no-stop/有效policy及全量revalidate可恢复，不每次强制人工确认。
- temporary保留原expires_at；未同步/回拨/剩余不可信即停，不用uptime/原duration重算。boot_restore不复活过期临时；实验不自动常驻/boot恢复。

## 5. LuCI四页与交互

| 页面 | 内容/操作 |
|---|---|
| 家庭概览 | desired/runtime、策略、全服务、active/saved revision、双族listener、lease/证据；添加/开启/停止/Apply。continuous显示直到停用，temporary显示剩余 |
| 服务 | backend族/host/port、域名/证书、业务鉴权/backup；保存/禁用/删除仅pending，撤销曝光独立立即Stop |
| 接入方式 | 主/旁路由、manual IPv4/UPnP/direct IPv6、高级STUN、scope/有序授权；编辑不切换，检查无Add/Delete |
| 设置与诊断 | continuous/temporary、独立boot恢复、ACME/DDNS/门户、代理、分层诊断/脱敏导出，无旧强制短时 |

### 四步发布向导

1. 服务/域名/证书：明确家庭Web目标与域名，核验证书、鉴权/更新/管理角色；导航ACME/DDNS，不暗改其他应用。
2. 接入/scope：主/旁IPv4固定转发优先，选可信IGD或IPv6，显示TCP端口/family/address/interface/zone、上级许可；单种/有序机制与renew/delete权限，IPv6无DNAT误导。
3. 校验/保存：只读preflight返回blocker/warning/unknown，选策略/boot恢复（关），Save只本应用commit；取消/刷新不开放，修改失效旧preflight。
4. 明确开启/结果：确认全部服务/策略/scope/INPUT/网关副作用/残留，一次授权防重复；配置/backend/TLS/listener/INPUT/gateway/DNS/external分层结果，不另造参数页。

健康续租不重复弹窗，首次/扩scope/未认证风险复核不藏Save。无独立probe不强制block全部manual用户，复制链接醒目标外网未验证，不假绿灯。

### 按钮契约

- Save：session暂存→canonical→scoped commit→刷新，不start/reload/global apply/Add/renew；坏配置可保存禁用恢复，禁用保存不称active已停，给立即Stop。
- Check：固定有界只读DNS/IGD/能力，无隐含曝光/扫描。
- Start：服务器核验并持久enabled/approval/policy、新gen，幂等key绑定revision，刷新不重复Add。
- Apply pending：显示active→saved差异/全服务，扩scope或服务集合另确认，受控replace、不重置temporary；失败保合法旧snapshot或安全关，不混版。
- Stop：先撤意图/恢复权，立即断流，简洁防误触不每次繁重确认；清理/残留分别呈现。
- Verify：固定用户认可独立来源/已运行endpoint，无新lease/延时；hairpin标回环。

commit成功/状态刷新失败分别显示；pending明确旧snapshot。未实现能力按钮禁用。UI角色限制不替rpcd授权，保留真实TypedSection handleAdd/remove语义。

## 6. 数据路径与组件契约

```text
LuCI -> scoped RPC -> config+approval+desired state
 -> controller(事务/健康/恢复/续授权)+independent guardian(有限权限/owner/收回)
 -> dedicated Nginx直接IPv4/IPv6 HTTPS -> 家庭HTTP backend
 -> precise INPUT + access adapters + DNS/ACME snapshots + optional portal
IPv4: 客户端 -> 公网TCP -> manual/UPnP上级映射 -> 专用Nginx -> backend
IPv6: 客户端 -> 家庭GUA路由/上级许可 -> 专用Nginx -> backend
STUN高级: NATMap受监管有界入口 -> Nginx，不泛化普通forwarder
```

| 组件 | 契约 | 禁止越界 |
|---|---|---|
| validator | committed revision→typed plan/errors | 不信前端、不执行字符串 |
| controller | desired+approval→事务/有限续授权/恢复 | 不无限权限、不扩scope |
| guardian | 有限capability/owner journal→断流/清理证据 | 不仅shell trap，不依赖controller活性，不删foreign |
| renderer | 安全地址/host/证书snapshot→独立Nginx | 不共享管理server/通用forwarder |
| INPUT | typed family/interface/zone/address/port/gen→handle/readback | 无任意nft/全局ACCEPT/FORWARD |
| manual/direct-v6 | 路由/许可/入口→endpoint或unknown | 不伪上级可读性/发UPnP Add |
| UPnP | 可信IGD/finite lease/tuple→create/renew/readback/残留 | 不blind retry/覆盖foreign/搜端口 |
| DNS/ACME | 真实受限metadata/snapshot→证据/候选 | 不猜API/取provider秘密/fork |
| portal | endpoint/gen/sequence/finite显示lease→导航状态 | 不承载业务，不以门户expiry替本地Stop |

门户失败独立降级/撤指引，不自动改已合法本地直连；门户登录不保护直连目标。

## 7. 双栈Nginx与确定backend

显式绑定路由器核验专属IPv4/IPv6地址与port，IPv6 `ipv6only=on`/IPV6_V6ONLY防v4-mapped冲突。loopback只测试/内部用途，非公网入口。检查SSH/LuCI/uhttpd/已有Nginx socket和服务管理角色，不替换/共享管理22/80/443、不只靠黑名单；不默认0.0.0.0/::扩scope。

首版v4→v4/v6、v6→v4/v6，v6→v4 HTTP反代不是NAT64。IPv6真实解析器校验，URL用 `[address]:port`；拒绝注入、zone-id/link-local、multicast/unspecified/v4-mapped绕过。backend仅明确审核loopback/私网/ULA/归属确认家庭GUA，GUA不自动信任，管理/外部未批准目标拒绝。

hostname受限resolver查A/AAAA，校验全部结果安全地址/归属，稳定顺序优先安全健康IPv4 primary；无合法健康IPv4只在已允许IPv6范围选IPv6。显式IPv6 primary支持；backup是启动/受控替换前候选，不是写请求重试目标，不靠Nginx DNS顺序。

backend静态不可变snapshot记录resolver/TTL/时间；TTL到期有界只读refresh验证，不变可续证据，变更在既定backend范围全量校验/健康检查后受控replace新gen，不让Nginx任意runtime解析。越scope/不能安全刷新则stale/关闭待修复，不无限缓存；无可信TTL每次start/replace重查并声明有界再检、不跨gen无限缓存。

默认 `proxy_next_upstream off`，禁止 `non_idempotent`；POST/PATCH/PUT不自动重放。运行故障错误/降级，controller可有界健康检查为未来新请求安全replace选backup，不重试已接受请求/不保证无损。GET/HEAD请求级failover后续独立方法隔离review。

TLS检查SAN/chain/有效期/key匹配/文件owner权限，未知Host/SNI拒绝；用户certificate_ref非任意路径。保留不可变secret snapshot、foreign-fd/seccomp/锁/file identity，去NATMap不删共有安全边界。

## 8. 入口机制与切换

### manual IPv4

主路由确认专用listener/INPUT/家庭WAN/回程，旁路由先指导主路由精确TCP DNAT到旁路由专用Nginx；WAN/DDNS A非代理VPS/STUN出口。上级人工规则unknown只降级证据，不一律block本地安全运行。

Stop显示本地已关闭/上级静态转发用户维护；静态映射仍在，内端口保留风险占用，不交管理/其他服务复用，明确人工确认撤销或可信读回才解除。不承诺整个网络无外露。

### direct IPv6

稳定GUA/路由/本与上级入站许可/客户端v6分列，不UPnP Add/DNAT/默认写AAAA。临时隐私地址不推荐长期入口，本机INPUT不证明上级允许或external通过。

prefix/address变更先旧endpoint/AAAA/external stale、门控旧listener，再核验新GUA归属/interface/zone/回程。approval可明确该接口稳定家庭GUA选择范围，符合既定范围可revalidate后replace和已授权DNS更新；literal授权或范围扩大待Apply，不能跨interface/zone自动扩权。

### 有序授权尝试

manual→已授权UPnP→已授权STUN，无隐式fallback/默认并行双曝光。continuous沿同scope与有限每轮预算，不虚构总deadline；temporary共享原截止；STUN即来自continuous也只有独立有界实验预算，不能循环restart成常驻。

先关旧数据面/连接/引擎/发布/owned INPUT，确认旧mapping absent或安全清理。UPnP残留/owner unknown/非原子Delete无法安全处理则停止fallback、禁危险port复用，不能换gen跳过。STUN callback只发现endpoint，未外网验证标实验运行/未验证，不称穿透。全失败显示本网络未建立/未证实与分层原因，仅导航HomeTunnel，不改配置/启停。

## 9. UPnP有限lease、续租和清理

可信本地IGD限定interface/gateway identity/control URL，拒绝任意URL/redirect/未知来源SSRF。tuple=gateway/TCP/external port/RemoteHost（首版空）/internal address/port，gen description仅辅助非不可伪造owner。预检冲突拒绝，不覆盖/永久lease/自动换port/改全局miniupnpd。

### create

read-only、finite Add/renew、Delete、persistent权限分列；Start一次批准same-entry renew不每次弹窗。guardian/journal先就绪，有限请求后精确读回tuple/description/gen/实际剩余，成功响应不等owned；未知/永久/超允许期限则关本地报残留。

Add/update timeout=效果未知，精确query优先；证实owned/已更新可接受，absent需完成旧事务清理/全量preflight新事务恢复，unknown/conflict停止。不blind重复Add，不以description相同假设原子安全；每gen至多一个在途mutation，严格sequence/epoch。

### continuous renew

- 始终非零finite；按实际读回剩余算renew提前量，覆盖调度/请求超时/有界重试，不到期才刷，lease边界/读回能力真目标确认。
- renew前desired enabled/no-stop、scope/approval/gen/epoch、controller/guardian健康、gateway identity和精确owned tuple/finite剩余均核验；确认支持same-entry更新契约才刷新同entry，不变port/目的、不覆盖foreign。
- 再读回写journal/next renewal；conflict/identity变化/unknown/stale completion即关，旧Add/renew不套新gen。
- UPnP通常无compare-and-update，query→update竞态必须有实施确认受控/排他owner契约；无法建立标该网关不支持安全持续UPnP，可有限临时/manual，不用blind Add维持，description不能解竞态。
- read-only短故障只在可信finite lease/guard内有界重查；剩余/renew效果不能证实就关。安全边界取最早guard失效/policy截止/可信mapping边界，不为availability无限容错。

### temporary/Stop

temporary申请/renew的网关到期不越policy截止；剩余不足网关最小合法lease不再renew、安全关闭。舍入/不遵守则不称严格匹配，关闭并处理残留，不延本地迎合网关。

Stop先撤意图、关本地数据面/INPUT，再按已授权Delete owned或观察自然expiry。Delete前重核gateway/tuple/gen；无排他契约默认不主动删，明确query→delete竞态。foreign替换保留，受控网关获准Delete后也精确读回，不成功响应冒充absent。714证明当时无，自然expiry最后存在—首次不存在区间。

residual/unknown内port保留，不fallback/交其他服务；gateway reboot/entry loss使证据stale、先关、确认absent后同scope有限新事务恢复，不blind Add。gateway expiry不等本地秘密/process自动清理。

## 10. INPUT、代理与controlled reload

明确Start/Apply后helper按TCP/family/interface/fw4 zone/精确destination或批准选择范围/port创建owned INPUT，无全局ACCEPT/FORWARD/管理或foreign修改。Save/install/postinst/inactive include不开；handle+tuple+gen+journal owner校验，不能只comment；先登记再Add、失败rollback/readback、foreign替换保留并报unknown/residual。

fw4真实hooks/order/ABI决定chain/include；不轮询冒称零风险协调。Stop/expiry/失控/卸载先关data再撤owned规则、精确readback。

reload先门控防宽规则临时可达，重读zone/interface/hooks/revision/policy/approval/ownership，仅同scope精确规则恢复并readback后放开，不延temporary/不盲Add。不一致或scope变化则关；合法enabled条件恢复后有限自动恢复，不所有reload永久要求manual；Stop不得恢复。network/prefix按第8节重新核验GUA，旧证据失效。

Passwall2一直开启，不以关闭交付；实际版本nft mask/order/ip rule-route/DNS interception/SO_MARK/回程实证。不复制历史mark255通用默认/不全root或全路由器bypass；Nginx回复/机制socket按数据路径，loopback/本地IGD SOAP/publisher/DNS不乱套全局mark。不兼容是具体能力blocker。

Save形成pending；Apply或已授权维护事件受控candidate事务：SAN/key/有效期/权限验证、受监管copy/owner登记、渲染/`nginx -t`、安全DNS/backend/健康检查、新gen、原子journal/capability提交再开放。失败保仍合法旧snapshot，否则关；无明文fail-open/扩大host/scope/未验证DNS上线。同域名scope证书renew可自动replace不每次重开，续期告警、过期关；首版可短中断，不保证跨gen长流无损，安全/temporary截止不graceful拖延。candidate私钥也guardian cleanup，不init无监管复制窗口。

## 11. 实际ACME/DDNS-Go与可选portal

本feed `luci-app-homeacme`保留UCI/service `acme`、view `acme/acme`、object `luci.acme` 的 `getCertificates` inventory元数据，可列表/导航；新HomePublish ACL、安全root-private导入/续期通知轮询须实现核验。签发/renew/provider秘密ACME管，不fork/改其配置/返回key。

DDNS-Go目标资源只证明UCI/service `ddns-go`/WebUI，本feed未确认源码/record-write RPC。MVP外部维护DNS/已有导航+受限只读A/AAAA；自动更新先查真实package/version/API/凭据边界，不猜path/port。缺ACME/DDNS可manual DNS/严格导入，不硬依赖。

URL `https://service.example:<port>/`明确非默认port，A/AAAA不带port。家庭页/CF DNS-only/Worker可选路标非业务/鉴权；默认不标未verified为可达，用户可明确展示未验证链接，变更/Stop撤销。gen/sequence+finite显示lease可健康刷新，旧event不复活endpoint。portal故障独立，不改合法本地直连；旧publication非新adapter或云部署证明。

## 12. 安全不变量与最小权限RPC

1. 默认未发布，Save/Check/install无曝光。
2. explicit enabled+有效scope+有限健康capability才开，continuous非无限权限。
3. Stop latch/temporary截止/旧gen防护优先恢复续租，reboot不续时。
4. 独立Nginx/精确INPUT/owned，管理/foreign files-rules-mappings不动。
5. 本地关停先于gateway，residual unknown不fallback/危险port复用。
6. host/address/port/ref/gateway/协议返回权威校验，拒注入/SSRF/rebinding/未知字段。
7. 无秘密UCI/argv/status/log/export，descriptor/type/owner/mode/inode/snapshot监管清理。
8. TLS无明文fallback、未知Host/SNI拒绝、业务写请求不replay。
9. configured/listening/INPUT/mapping/DNS/TLS/external分层，不绿灯掩unknown。
10. 产品能力不等于本轮生产写入授权。

首版依赖服务已有认证（账号/MFA/权限）与更新，不自研login。未确认鉴权默认block公开，独立风险复核明确未认证服务/data/scope才能解除该项；管理冲突等硬blocker不可勾选绕过。成熟可选gateway auth后续，非MVP。TTL不能代鉴权/最小权限/更新。

| 拟议RPC（未注册） | 角色/契约 |
|---|---|
| status/validate/diagnostics | read，本应用allowlist真实状态/typed config/固定check、有界/限流/无secret |
| save_config | config，scoped commit/禁用恢复，无global apply |
| start_publication | exposure，revision/service_set/policy/scope/确认token，后端gen/幂等 |
| stop_publication | exposure，owned组，先持久撤意图后分层cleanup |
| apply_pending | exposure，active-saved差异，扩scope另confirm，不重置temporary |
| verify_external | 固定认可source/endpoint/timeout，无任意URL/renew |
| internal renew/reconcile | 不向浏览器开放，核验epoch/gen/finite窗口 |

read/config/exposure分离，不任意exec/file/service restart/nft。UI scoped Save不证明目标`uci.commit`拒绝其他config，真rpcd受限会话测试、必要scoped wrapper；客户端不任意path/command/control URL/secret/权威scope标志，helper fixed argv无eval，root/CAP_NET_ADMIN独立review。

## 13. 分层状态与故障矩阵

status真实读取desired/policy/boot_restore、active/saved revision、phase/gen、两族listener、backend/TLS/DNS/INPUT、gateway lease/internal guard、external、cleanup/residual/last_error/next_retry。UTC观测，单调remaining本次期限不跨主机比较。external记录source/family/endpoint/CA/hostname/marker/time/age。

endpoint/gen/revision/证书/prefix/路由/规则变化stale，成功有限新鲜度。安全能力缺失可block，未知external/上级静态读回不等安全能力缺失，无probe可安全manual运行/未验证链接；STUN result非reachable。

| 事件 | 立即动作 | 恢复/结果 |
|---|---|---|
| Save校验/commit失败 | 不start/改active | 字段错/禁用恢复；commit/刷新失败分述 |
| 管理listener冲突/INPUT缺能力 | 不开、owned rollback | 硬blocker不可风险绕过 |
| TLS/SAN/key失败/过期 | 拒candidate，合法旧版可保持，失效关 | 同scope replace，无明文 |
| backend/DNS不安全 | 不任意新地址，写请求不retry | 降级，候选仅未来请求 |
| external未知/失败 | unverified/failed分层 | 不假可达，不一律停manual |
| Add/renew timeout | query不blind，不能证实关 | unknown/residual保port |
| mapping conflict/foreign | 关本地，不覆盖/删foreign | block fallback |
| lease永久/拒绝 | 关/报残留 | 不lease=0/永久fallback |
| read-only短失败 | 可信lease/guard内有界重查 | 到边界关，不无限容错 |
| controller KILL/STOP | guardian窗口关 | enabled同scope新gen恢复，Stop后禁恢复 |
| guardian失联/身份不明 | 独立监测撤销/关 | 重建监管再恢复，禁裸进程 |
| Nginx crash | 关scope/INPUT、stale | controller全量revalidate，不裸respawn |
| fw4/proxy reload | 门控核scope/hooks/回程 | 同scope合法恢复，不延期扩权 |
| v6 prefix/interface变 | 旧endpoint/AAAA stale，关旧listener | 范围内revalidate，扩大待Apply |
| reboot/时钟不可信 | 默认不开，temporary不可信关 | boot_restore+全条件恢复 |
| Stop/temporary到期 | 先撤意图，断全部连接/规则 | 禁renew/旧event，残留单列 |
| Delete竞态/清理失败 | 保foreign，unknown/residual | readback/自然expiry，不假全清 |
| portal/DDNS缺失 | 降路标，非伪支持 | manual独立，无自动HomeTunnel |
| uninstall/rollback | Stop→核验→clean owned include | 不旧lease复活/删foreign原证书 |

诊断配置→鉴权→backend→TLS→listener/INPUT→DNS→代理回程→gateway→external→guard/lease/cleanup，TLS与TCP refused/timeout分开；hairpin非独立外网，上级unknown不推断拒绝节点/NAT类型。

## 14. 命名、依赖、迁移

目标`homepublish`/`luci-app-homepublish`，同批受审查迁移，不历史全局replace。

| 旧身份 | 新身份/同步项 |
|---|---|
| homestun/Makefile PKG/Package/conffiles/install | homepublish/Makefile、新依赖/默认 |
| config/init/procd homestun | UCI/init/procd homepublish，controller恢复非旧session裸respawn |
| /usr/share/homestun core/config/CLI/render/runtime | /usr/share/homepublish、typed plan/state |
| native/publisher、/usr/libexec/homestun-* | 新guardian/controller/helpers，CLI/path/权限 |
| /etc/homestun、/tmp和/var/run锁/snapshot | 专属新path，owner/cleanup/引用全同步 |
| LuCI Makefile/menu/ACL/ubus/view | 新包/object/view homepublish、四页/schema/state |
| tests/fixture/install断言 | 新协议/path/source binding，历史manifest不改 |

core按实际native/Lua/UCI/Nginx/fw4直接provider声明；UPnP库工具审查finite lease/readback/same-entry/license/ABI/包可用性，NATMap仅高级/curl-CA仅相关HTTPS。ACME/DDNS/CF/HomeTunnel非硬依赖，标准LuCI scan signature/menu/ACL一致，无曝光postinst。

旧包未生产安装，无需双daemon/双UCI热兼容。Conflicts/替换真实package.mk/luci.mk核验，不force-overwrite。offline dry-run allowlist非秘密diff、审核后只新配置；旧TTL可转temporary但新desired/approval/boot_restore全关闭，不静默continuous/UPnP；旧配置保留，不copy key/token/删旧secret。secret迁移另批准descriptor/identity/权限验收。

迁移先停旧owned会话，新锁/cleanup不误删旧runtime；rollback默认关闭旧实验包、不恢复旧lease。HomeTunnel/HomeACME/DDNS身份/历史docs/artifact/hash不变。

## 15. 分阶段实施与验收

本轮只有设计，父review后代码，TDD先RED再GREEN，旧PASS非新gate。

| 阶段 | 交付 | 验收 |
|---|---|---|
| D0文档 | 本文/REQ/README/resume/清单 | 无当前强制短时/forwarder矛盾、链接、历史保护、无代码设备操作 |
| D1 canonical/迁移 | schema/scoped Save/policy/desired/approval/journal | 默认关/秘密隔离/注入/地址port/未知字段、迁移禁开、pending-active分离 |
| D2 runtime双栈 | 新有限续授权guardian/controller/直接Nginx/确定backend | 四组合/IPV6_V6ONLY/DNS TTL-rebinding/POST零replay，continuous多guard周期、temporary断流/KILL/STOP/foreign |
| D3 INPUT/UPnP/recovery | fw4/finite same-entry renew/残留/boot | fake IGD冲突/竞态/timeout/永久lease/旧event；rollback/reload门控/同scope恢复/stop锁/temporary reboot不续时/残留禁fallback |
| D4 LuCI/RPC | 四页/wizard/buttons/state/roles | 真loader/baseclass/TypedSection/browser/rpcd，read不能start/commit越界拒绝、Save不曝、pending Apply、unknown非绿灯 |
| D5维护/代理 | ACME/DNS snapshot replace/Passwall2 | candidate secret KILL/STOP清理，无fail-open/扩scope，同scope不反复确认，代理一直开启/回程/DNS/reload |
| D6 SDK/目标 | matching SDK/IPK/TARGET_CC/runtime依赖/权限ABI | 真feeds update/install/menu/ACL/minified JS source binding、真BusyBox/procd/fw4，无host替代/GNU注入 |
| D7授权实网 | manual/UPnP两层清理、v4公网/v6外网可后放 | 独立CA/Host/marker/持续流、renew前后readback、Stop/temporary cutoff/新连接拒绝/源仍输出、foreign管理不变 |

完整首版本地矩阵：主/旁路由×IPv4/IPv6；入站v4/v6×backend v4/v6与hostname v4-first；Save/default inactive无规则；INPUT精确scope/rollback/foreign；双族listener/Stop/已有连接关闭；continuous多次guard/UPnP renew与temporary最后lease不越截止；controller/guardian/preparation KILL/STOP、journal原子性/旧event/重复点击；fw4/proxy reload/prefix变更；boot默认关/开启/手动Stop/temporary可信时间；DNS/证书replace/POST不重放；迁移/卸载/危险port保留；真rpcd拒越权。

最终版本确认测试文件存在/数量/source hash，重跑对应全套，不host ELF/宏桩recipe smoke/WSL static/旧IPK替matching SDK。Linux/chroot适当权限；BusyBox/procd/fw4需真目标，无GNU stat注入冒称依赖满足。目标写入/防火墙/新lease/Delete/公网另具体授权；本轮只文档静态核验。

IPv6本地功能实现后可标本地已验证/外网未验证，不公网可用；本轮未实现仍标设计范围。发布review汇总各层已验/未验，不拼旧PASS。

## 16. 最终基线与工程review

产品方向已收敛无需再问：continuous/temporary、独立boot恢复、直接双栈Nginx、精确INPUT、finite controlled UPnP renew、IPv4优先/写不重放、HomeTunnel不动、可选ACME/DDNS/portal。

仍需工程证据：UPnP库/same-entry及delete受控契约、fw4 owner chain/reload ABI、native独立续授权/失控预算、procd controller恢复、rpcd scoped commit、Passwall2支持版本、ACME私有snapshot交接、DDNS实际API。不能证明禁具体能力或blocked/unknown，不造已支持；不能借工程未定回退所有强制短时/reload永久manual/通用forwarder。

完成标准是产品/生命周期/安全/权限/目标包/分层验收同时成立。持续发布提供长期可用性，有限内部能力和精确owner提供失控边界，两者一起实现。

