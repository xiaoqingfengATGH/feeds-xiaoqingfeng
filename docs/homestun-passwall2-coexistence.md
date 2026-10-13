# HomeSTUN 与常驻 Passwall2 共存：源码依据、永久架构与验收计划

归属：本 Feed `REQ-001` 的后续生产化工作；**设计/验收计划，不是已经实现或部署的功能**。本次仅修改文档，远端仅只读取证；不修改 Passwall2、防火墙、路由或运行中的服务，不提交、不推送。当前 HomeSTUN 分支 `feature/homestun`，基线 `2fd1e6a1a96f19fbd3295a5fef52c36f149f077a`；工作树已有其他并行工作，本文不覆盖它们。

## 1. 决策

**默认 HomeSTUN 数据面直连，而不是关闭 Passwall2，也不是让整台路由器或全部 root 流量直连。** 优先使用已经固定版本的 NATMap 自带 `-f`，由引擎在自己创建的外网 socket 上设置 `SO_MARK`。针对已取证的 Passwall2 nft 后端，候选值为完整值 `0x000000ff`；只有规则与策略路由兼容性检查成功才启用。它是此适配器的兼容约定，不是 Linux 通用“免代理”标记。

- 直连范围：TCP HTTP 映射保持连接、STUN 发现连接、NATMap 外部监听及其 accepted socket 的公网回复；另有专用直连 DNS 解析路径。
- 不标记：NATMap→`127.0.0.1` 专用 nginx 的转发连接、nginx→业务 upstream、Cloudflare publisher/curl、其他系统程序。
- 出口选择另设可选项。`SO_MARK` 的代理豁免与 `-i` 的接口/源地址绑定不是同一功能，不能用绑定网卡替代豁免。
- v1 仍为 IPv4 TCP。DNS 使用 UDP/TCP 不等于支持 UDP 业务穿透；IPv6 不借本方案顺带宣称支持。
- 本机没有透明代理且路由/DNS可证明干净时允许 verified-no-local-interceptor；存在未知拦截、冲突或无法检查时拒绝启用数据面，不能只显示 warning 后继续发布。

## 2. 证据与版本边界

### 2.1 实际已安装版本，不用旧 Feed 冒充

远端只读结果保存在 [artifacts/passwall2-coexistence-readonly-inspection.txt](artifacts/passwall2-coexistence-readonly-inspection.txt)：`luci-app-passwall2 26.10.1-r2`。实际 `/usr/share/passwall2/nftables.sh` 完整快照为 [artifacts/passwall2-26.10.1-r2-nftables.sh.source.txt](artifacts/passwall2-26.10.1-r2-nftables.sh.source.txt)，SHA256 `cd9faa91aaf695faece98b3cd9df96f66950d2b90196da9935916a7dbf830fb1`。下述行号均为该原始脚本的行号，不是上游最新版本的猜测。

| 位置 | 实际行为与意义 |
|---|---|
| 6、17 | 独立 `inet passwall2` 表；TPROXY 标记 `FWMARK=0x50535732`，不能把它当直连值。 |
| 129–148 | OUTPUT route 链 priority `mangle - 1`，OUTPUT NAT priority `-1`；需逐一检查所有 hook，而不是只看 fw4 filter output。 |
| 336–337 | 本机 `oif lo` 的 UDP/TCP 53 直接 redirect 到专用 DNS；发生在进入 TCP `PSW2_OUTPUT_NAT` 的豁免之前。仅给 NATMap 加 `-f` 不能修复 DNS。 |
| 798–804 | `PSW2_RULE` 将 ct mark 恢复到 packet mark，并写入代理标记/保存 ct mark；未在前面豁免就可能覆盖 socket mark。 |
| 808–815、827–834 | OUTPUT MANGLE / OUTPUT NAT 的 `meta mark and 0xff == 0xff` 在默认代理分流前 return。 |
| 857–858 | IPv4 `ip rule add fwmark 0x50535732 table 999 priority 999`，table 999 的 local default 到 lo。 |
| 862–870、891–899 | IPv6 有自己的回复/低字节豁免和条件策略路由；不能用 IPv4 通过替代 IPv6 验证。 |
| 660–685 | mwan3 集成豁免针对代理自己的 connmark 完整值 `0x50535732/0xffffffff`，不是对 HomeSTUN `0xff` 的兼容保证。 |
| 909–947、951–978 | 停止删除规则/策略路由；可 flush/delete 自己的表；include 保存并恢复 PSW2_RULE.nft。一次人工插入 Passwall 链不是持久接口。 |

同机先前完整规则证据 [homestun-realnat-routing-review.txt](homestun-realnat-routing-review.txt)：

- 7957–7974：实际 mangle output / nat output 跳转，loopback DNS→2004，TCP→PSW2_OUTPUT_NAT。
- 7982–7987：代理 ct mark 恢复/覆盖；8010–8022、8039–8050：低字节 `0xff` return 在 fallback proxy 前；8053–8065：IPv6 对照。
- 274–279、8040：`67.230.168.23` 是 VPS/代理节点例外。结合既有 real NATMap 实验得到该地址，只能说明当时发现路径受代理影响，**不是家庭宽带入口已可达的证据**。
- 本次只读 `ip -4 rule`：local priority 0，table 220 priority 220，代理完整 fwmark priority 999，main priority 32766；默认路由 `via 192.168.1.1 dev br-lan`，源地址 `192.168.1.2`。table 220 即使当前没有打印出路由也必须纳入后续策略检查。`br-lan` 是这台旁路由的实际出口，不能硬编码“wan”。

本地另一 Feed `D:/DevPortal/router/feeds-lienol-pw2` 固定 HEAD `82a74793589c0145942b8ee85b845fc818780d9e` 工作树干净，但 `luci-app-passwall2/root/usr/share/passwall2/nftables.sh:685,704,732` 使用 **exact `meta mark 0xff`、代理 mark 1/table 100**，与已安装版不同。旧版本更说明应选择完整 `0x000000ff`、不能任意拼上高位作为“通用方案”；它不是本机运行版本依据。

### 2.2 NATMap 已有能力与缺口

WSL 干净源码 `/home/eric/homestun-natmap-20260214`，revision **`f8d7996710677c9885c148dda80a42d626f0a17b`**；hev-task-system 子模块 **`8d83bbbf79557138726c8ee5a5fae99cbb978d61`**。保存七个相关源码（内附原文件行号与哈希）于 [artifacts/natmap-f8d7996-coexistence-source.txt](artifacts/natmap-f8d7996-coexistence-source.txt)。可对照固定 revision：`https://github.com/heiher/natmap/tree/f8d7996710677c9885c148dda80a42d626f0a17b`。

| 源码位置 | 结论 |
|---|---|
| `src/hev-conf.c:56,62,87,116–118,134–136,179–184` | 已支持 `-f <mark>` 和 `-i <interface or IP>`；上游 strtoul 不做完整严格输入校验，产品层不能照搬任意 mark 输入。 |
| `src/hev-sock.c:153–160,196–234,285–315` | Linux 使用 `setsockopt(SOL_SOCKET, SO_MARK)`，base/STUN socket 在 bind/connect 前设置；接口/mark失败关闭 fd 并返回失败。 |
| `src/hev-tnsk.c:98–117`，`src/hev-stun.c:297–316` | HTTP TCP keeper 和 TCP STUN 都传入 iface/mark；不能只豁免 STUN 服务器而漏掉 HTTP keeper。 |
| `src/hev-sock.c:381–434`，`src/hev-tfwd.c:87–112` | 外部 forwarding listener 在 listen 前设置 mark，accept 后交给 client task；源码没有再次给 accepted fd 调用 SO_MARK，Linux 继承行为须在目标验证。 |
| `src/hev-sock.c:343–377`，`src/hev-tfwd.c:48–71` | 转发到内部目标的 client socket **没有** iface/mark，这是所需边界，不应把 `get_sock()` 全部改成打 mark。 |
| `src/hev-sock.c:72–89,179–185,279` | getaddrinfo 先于 marked socket 创建；`-f` 不覆盖 libc DNS。 |
| 子模块 `src/lib/dns/hev-task-dns-proxy.c:75–81` | 最终调用 libc `getaddrinfo`，不是具有显式 SO_MARK 的自有 DNS socket。 |
| `src/hev-misc.c:186–210`，`src/hev-sock.c:216–225` | 端口碰撞 fallback 试图 pidfd_getfd 导入外来监听 fd 并改 SO_REUSEPORT；共存方案绝不能解除 HomeSTUN 现有禁止此导入的 seccomp 边界。 |

额外仅在 WSL 自有 loopback socket 的实际实验：listener SO_MARK=255，accepted SO_MARK=255，client SO_MARK=0；所有 socket 已关闭。这证明该 WSL 内核的继承行为，不是 OpenWrt 目标验收。

当前 HomeSTUN `homestun/src/lease-supervisor.c:68–88,280–291`：NATMap 子进程 exec 前安装继承的 seccomp/no_new_privs，现有 argv 没有 `-f`；`301–305` nginx 是另一个子进程。`homestun/src/publisher.c:48–53` publisher 的 curl 环境剥除应用层代理变量，但 **不能**绕开内核透明代理。不要因此把整个 supervisor 或其全部后代变成直连身份。

## 3. 建议数据路径与最小产品配置

```text
专用直连解析阶段 → 验证 IPv4 endpoints + 原始 HTTP Host
                            ↓
NATMap -4 -f 0x000000ff [可选 -i 真实设备/源IPv4]
  ├─ marked HTTP keeper / TCP STUN → 当前选定 WAN → 上级 NAT
  └─ marked 外部 listener / accepted replies ↔ 独立外网 TCP 客户端
       └─ unmarked 127.0.0.1 nginx TLS → unmarked 业务 upstream
映射 callback → unmarked publisher → Cloudflare HTTPS 控制面
```

建议产品配置是 `egress_mode=direct`（v1 固定数据面语义）、`proxy_adapter=auto|passwall2-nft|none-verified`、可选 `egress_interface` / `egress_source_ipv4` 与专用 `direct_dns_server`。这些是**拟议字段，尚未实现**。普通 LuCI 不提供任意 mark、任意 nft、任意 shell 或任意策略路由编辑器；root-owned 固定适配器选择 `0x000000ff` 并记录完整值和所验证的 mask。仍要求原有 enable、曝光批准及 TTL。不能添加“失败自动走代理”的降级。

仅 `-i 192.168.1.2` 会改变 bind source，不会阻止 OUTPUT redirect；仅 `-f` 会豁免已验证代理规则，却不选择 WAN。默认让已验证的系统策略路由决定出口；并不无条件添加 `fwmark 0xff lookup main`，避免绕过合法 VPN/企业策略。可选绑定必须先解析 OpenWrt logical interface→运行设备/源地址，验证回程、rp_filter、连接跟踪和 NAT；断链关闭/撤销映射，不悄悄迁移其他 WAN。切换出口必须新 generation、重建 mapping 并撤销旧 endpoint，保留原始到期时刻。

### 3.1 DNS 必须独立解决，不能谎称现有 -f 已解决

首选补一个受监督的 **专用解析阶段/小型 resolver**，只解析 HomeSTUN 的 STUN 与 HTTP keeper 域名；它自己的上游 UDP/TCP DNS socket 显式 SO_MARK，访问明确的非 loopback DNS IP，必要时绑定同一出口，严格响应解析、事务校验、超时、TCP fallback 和地址过滤。不复用被 Passwall fake-IP 污染的系统缓存，不修改全局 resolv.conf，不给全部 dnsmasq 流量直连。DNS服务器在上级仍可能被劫持，须拓扑验收；这不提供 DNS 加密/真实性保证。

解析结果拒绝 fake-IP `198.18.0.0/16`，拒绝不合适的 loopback/link-local/multicast/private endpoints（明确本地 fixture 仅测试例外），仅允许 v1 IPv4；固定至当前有界 session，按 DNS TTL 重新解析/重建，禁止在重试中偷偷退回系统 DNS。TTL 与 lease expiry 分开，重解析不续租。

**HTTP Host 陷阱**：直接把 `-h domain` 换成数值 IP 会使 `hev-tnsk.c:44–49` 发送数值 Host。推荐小范围 NATMap patch 增加“连接地址与原始 HTTP Host 分离”的显式选项，并以固定 patch/revision 打包；或在原有私有 chroot 中生成仅本 session 的 `/etc/hosts` 保留域名，证明目标 libc 不再发 DNS、无共享状态后才采用。只读系统 hosts 的作用和过期必须验证；不得修改全局 hosts。单纯 `resolveip`/shell预解析走系统DNS不是合格实现。

Cloudflare publisher 默认仍遵循用户的控制面代理策略；无需因数据面直连而强制其直连。若系统 fake-IP/解析污染影响其 TLS 控制请求，单独配置/验证专用控制解析策略，保留固定 HTTPS origin、SNI/Host、系统信任、鉴权与过期边界；不得通过跳过证书校验“解决”。控制发布失败必须保持门户不可用，不证明 NAT 失败，也不触发扩大 bypass。

## 4. root-owned 兼容性检查与运行期策略

在创建外部 listener / 发布 mapping 前，由不可被普通用户或 UCI字符串替换的 native/root-owned checker 读取结构化 `nft -j list ruleset`、IPv4/IPv6 rule/route、接口状态与版本信息；禁止 source 任意脚本、按 UI 字符串拼 nft 命令或仅 grep 出 `0xff` 就判 PASS。

必须核对：

1. 实际 hook/priority/跳转图覆盖 marked TCP keeper、STUN、外部回复与专用 DNS（包括 DNS早期redirect），每条可达拦截路径都在改 mark、redirect/tproxy 前明确 return；其它独立表和 legacy iptables 路径也须检测。一个独立 nft base chain 的 accept/return **不会**跳过后续 Passwall base chain。
2. 完整 mark `0x000000ff` 与所有 `ip rule` mask/优先级、mwan3/pbr/VPN、ct mark恢复、其他 nft mark写入兼容；用代表性 STUN/HTTP/DNS/外部客户端地址执行只读 `ip route get ... mark 0xff`（含 source/oif 约束），结果不可是代理 lo、错误WAN或意外策略出口。不能用 `0x50535732`，不能把未知高位与低字节合并后声称安全。
3. NATMap 二进制绑定到已测试 revision/构建，支持 `-f`；权限足够设置 SO_MARK且失败必须阻断。现有窄 seccomp 不阻止 setsockopt，但提权/能力精简必须实测。socket 的 mark，不是 argv 出现 `-f`，才是最终证据。已创建 fd 使用 CLOEXEC，不通过 foreign fd import、SCM_RIGHTS、LD_PRELOAD 或修改系统 nginx fd注入标记。
4. 独立 nginx loopback listener、端口占用及 TTL安全边界保持不变；不为共存扩大公网 input/forward 规则，也不全局放行任意 marked 流量。

建议状态：`disabled / checking / compatible / incompatible / active / invalidated / expired`，记录 adapter版本/源码hash、规则generation、出口和证据原因，不记录凭据。未知版本仅当具备受测试语义适配器可完整验证时允许；不能因包名相同就放行。无法检查（权限、JSON损坏、工具缺失、未知hook）为 incompatible，默认保持 disabled、不启动入口、不发布。纯诊断 UI可以 warning；实际曝光必须阻断。

运行期通过 firewall reload、Passwall restart/reconfigure、netifd/link/route变化事件重新验证，辅以有界watchdog。失去兼容性立即停止 owned NATMap/nginx、使入口无效并保留原因，不自动续租/respawn。若门户撤销请求失败，由短租约限制残留入口；本地先关闭真实数据面。

**不能承诺事件/watchdog实现零窗口隔离**：规则被任意root程序更改后到检测前存在竞态，且 SO_MARK不能阻止其他root组件重写 mark。若生产要求“重载时一个包也不得错误代理”，发布门槛必须包括与 fw4/Passwall 生命周期协调：重配置前关闭/冻结 HomeSTUN socket，完成规则构建和只读核验后，在原 lease expiry 内显式恢复/重建；或受测试的 owned后置drop guard加原子适配器协同。不要拿定时grep当原子保证。对不提供协调接口的未知配置，只能明确支持边界并失效关闭，不能宣传不中断保证。

使用现有 `-f` 的优点是 SO_MARK 保存在引擎拥有的 socket中，正常 Passwall reload后仍有自己的默认低字节 return，无需每次往 PSW2 链插规则。已有conntrack代理状态不会因为后来补 mark自动修复：启用新generation前停止旧NATMap连接，创建新socket；不 flush全局conntrack。Passwall源码的逐条 flush/add 与 include重放可能产生瞬态，仍须上述重载验收，不能仅因平稳态规则正确就判定永久共存。

## 5. 替代方案及安全边界

| 方案 | 判断 |
|---|---|
| 引擎自有 SO_MARK | 首选；固定版本已支持，作用范围符合外部socket，不覆盖内部转发/publisher。DNS另补。 |
| dedicated UID + nft `meta skuid` | 备选，仅适合单独 NATMap/专用 resolver 身份且 OUTPUT route hook在拦截前设置 mark；UID不是进程名，root UID绝不可整体豁免。规则、UID分配/回收、capabilities、accept继承、fw4生命周期都需设计。低权限daemon文件访问与callback publisher必须拆分；不要让token访问权限为了UID方案被放宽。单独链return无效，仍须Passwall已有兼容标记或受支持的同链豁免。 |
| 在 Passwall 内插 HomeSTUN豁免 | 仅在上游提供明确持久扩展接口、重载重建和所有路径测试后考虑；one-shot handles会消失，不能作为默认永久方案。 |
| STUN/HTTP目标 IP白名单 | 诊断可用，生产非首选；域名/CDN地址变化，不能覆盖任意外部客户端的accepted回复，也可能扩大其他程序直连。只豁免端口3478也会漏掉TCP HTTP keeper。 |
| 关闭本机代理/root全部直连 | 拒绝；破坏用户其他流量策略。 |
| network namespace/veth/独立路由域 | v1不需要；会引入额外NAT、DNS、防火墙/端口和TTL清理复杂度。仅明确复杂拓扑且上述方案不足时另行设计。 |

**上级网关限制**：本机 socket mark不随IP包在网线上传给 `192.168.1.1`。如果 Passwall/透明代理在另一台主路由的 PREROUTING/FORWARD，本机SO_MARK不能替它豁免；上级也看不到本机UID。必须在上级配置经授权的源主机/专用源IP或VLAN与目的/服务约束的直连ACL，覆盖STUN、keeper、DNS及回程；如需不影响该主机其他流量，需要专用源身份或上级真正支持的细粒度策略，不能伪称本机单一mark可跨路由器互通。不擅自下发上级规则；上级无权限/不支持时明确 blocker。即便代理全绕开，上游CGNAT、端口依赖过滤、防火墙或运营商策略仍可能使穿透失败。

## 6. 实施切片（另行授权后，按 RED→GREEN）

1. **配置与checker**：在 HomeSTUN本项目扩展config/init/native诊断，默认直连语义但仍disabled，固定适配器mark；建立上述真实nftJSON/route fixtures（含未知hook、早期DNS、masked policy rules、旧版exact mark、table220/多WAN冲突），不支持即拒绝。未经授权不改变路由器规则。
2. **引擎边界**：native supervisor两条NATMap argv统一添加已验证 `-f`，可选interface仅传NATMap；publisher/nginx argv不变；保留seccomp、TTL、guardian、独占端口。使用已测试NATMap package pin/patch，错误权限/setsockopt时退出；同步检查current code启动ack只代表seccomp成功，不代表mark/socket就绪，需要新增真实engine-ready/健康门槛再开放发布。
3. **专用DNS**：实现专用marked解析与原Host分离（或经验证的私有hosts方案），测试IPv4/fakeIP、超时、TTL、TCP fallback、重新解析；解析失败不得启动/发布。
4. **状态与事件**：增加root-owned兼容性状态、网络/代理变更失效路径、保持原expiry的重建；无协同接口不承诺零窗口。LuCI解释“仅数据面直连”和上级ACL限制，诊断读状态，不提供全局代理切换按钮。
5. **SDK/目标/外网**：真实SDK构建与ipk source hash绑定，目标最小纵向测试后才做下表外网矩阵；独立review，不把文档计划当验收完成。无自动修改Passwall配置、无全局conntrack清理。

## 7. 必须完成的验收矩阵

| 门槛 | 必需证据（未完成均不能标完成） |
|---|---|
| 代码回归 | 新增RED用例先失败：默认argv无mark、DNS未隔离、checker冲突放行、reload失效、继承mark丢失；GREEN后重跑原有TTL、guardian、publication、seccomp、token/TLS、LuCI持久化全套。 |
| 最小目标socket | OpenWrt目标读取自己listener/accepted的SO_MARK（getsockopt或受控测试instrumentation）；以抓包/trace证明SYN-ACK等早期回复直连。仅在accept后才打mark可能漏掉握手，不能替代listener预先mark。loopback forward/client与nginx/publisher不带mark。 |
| 常驻代理双向对照 | Passwall始终开启，先以独立无敏感标记probe证明普通对照流量仍按既有代理策略；同时STUN/keeper出口抓包在正确br-lan/WAN，未redirect/tproxy；snapshot计数结合socket/conntrack归属，不能用全局counter变化断言HomeSTUN命中。 |
| DNS | 系统DNS故意返回fakeIP/loopback重定向时，专用查询仍走选定直连服务器，UDP与TCP均验证，原Host保持；无DNS权限/解析失败不启动。publisher独立测试正常控制解析与TLS身份。 |
| 真正独立外网 | 独立于家庭NAT的客户端使用映射IP:端口、固定SNI/Host、可信测试CA与唯一响应marker；验证不是67.230.168.23代理出口且确为本session HTTPS响应。STUN响应/IP不同不是成功判据。错误Host/SNI/鉴权按原策略拒绝。 |
| 重载/故障 | 在保持连接与新连接探测下，Passwall stop/start/restart、TCP redirect↔tproxy（授权测试）、fw4 reload、规则重建、DNS服务restart、链路掉线、兼容性规则删除、mark冲突/mwan3策略变化；支持的平稳重载须维持直连，否则有界关闭并门户不可用，绝不可悄悄代理/续租。记录窗口和检测上界；零窗口要求单独证明协调/原子机制。 |
| 多WAN/拓扑 | 单WAN旁路由、可选绑定、mwan3/pbr/VPN冲突的reject；出口切换旧endpoint失效，新generation与原到期时刻；上级代理ACL缺失为明确失败，不伪报本机mark解决。 |
| TTL和回收 | 正常expiry、TERM/KILL/STOP、controller/guardian/engine/publisher故障；旧已建连接关闭且新连接失败，秘密/会话/自有规则清理，原始证书与foreign文件未改，管理SSH/80/443和其他Passwall流量未受影响。恢复操作不延长原lease。 |
| IPv6负面门槛 | v1禁用IPv6数据路径/AAAA fallback；不能因本机IPv6未开启代理而漏出未经批准入口。未来支持另测IPv6 hook/route/NAT差异与独立外网。 |

## 8. 当前交付与未证明事项

已完成：真实安装版源码/规则/策略路由只读取证，固定NATMap源码和DNS缺口核验，WSL仅loopback继承实验，本文与REQ-001后续计划登记。

未完成：上述任何产品改动、SDK新构建、目标SO_MARK与DNS验收、常驻Passwall条件下独立外网成功、重载无错误代理窗口、多WAN/上级网关ACL验证。本文不合并并行代理的临时bypass测试结论，也不把临时成功提升为永久共存成功。
