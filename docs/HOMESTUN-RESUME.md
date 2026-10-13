# HomeSTUN 关机续跑入口

## 最新授权范围：HomePublish最终完整设计基线（待独立实现审查）

最终基线：[REQ-001～REQ-005](../REQUIREMENTS.md)、[产品/技术/交互完整设计](homepublish-product-design.md)、[设计审查清单](homepublish-design-review-checklist.md)。本轮只文档，不改代码、安装、映射、路由器、防火墙或Cloudflare，不公网测试，不commit/merge/push/PR。父review后实施，真实操作另定范围，当前新功能未实现。

用户最后确认正常发布持续直到停用，临时可选；有限UPnP受控续租，独立boot恢复设置。本文默认选择：初始未发布、持续策略、临时30分钟/有界自定义、boot_restore关；Save不Start，明确开启可长期运行，健康维护/同scope恢复不反复确认。持续不是无限guard，native新增有限health capability续授权，失控fail closed；desired enabled/manual-stop锁/gen防旧事件，控制器有界backoff恢复，procd不裸复活旧expired session；boot开启后revalidate才恢复，临时截止持久且时间不可信停。

独立专用Nginx直接IPv4/IPv6监听，普通路径无通用forwarder；单服务v4/v6/hostname、确定IPv4优先/写请求不replay。首版本地双栈gate，v6独立外网可后验非功能延期。精确owned TCP INPUT限定family/address/interface/zone/port；fw4 reload门控reconcile，prefix换代旧证据失效/新GUA再核验，不扩大scope。DNS/证书受控candidate快照替换无fail-open，Save形成pending、Apply独立。UPnP提前精确readback/owner/gen再same-entry有限renew，竞态/unknown不blind更新，Stop先本地后gateway，残留禁fallback/危险port复用；manual静态规则由用户维护。主/旁IPv4固定转发优先，再授权UPnP/STUN，v6路由/入站许可非DNAT。HomeTunnel不动，ACME/DDNS-Go真实接口复用、CF可选，未知external不阻止所有合法manual运行但链接醒目标未验证。

**下方全部是历史实验及原阶段记录，保留事实/证据/哈希，不是当前产品限制或新功能通过证明。** 旧120秒只为原native实验约束，不能作为最终发布时长上限；旧forwarder/无respawn/固定TTL仅原实验架构。恢复本项目先读上述最新基线，再检查工作树；不得按下方旧“当前阻断/恢复顺序”自动恢复Add或生产操作。历史PASS不替代新continuous/renew/双栈/精确INPUT/真实SDK验收。

## 最新：STUN-only 3个有界真实变体完成，公网入站未通过，已清理

见 [STUN retry终态](homestun-stun-retry.md)、[聚合JSON](homestun-stun-retry.json)及[独立清理](homestun-stun-retry-cleanup.txt)。2026-10-12 21:07–21:12 CST，原native每次70秒/pinned NATMap/mark255/seccomp不变，CF+Baidu、Nextcloud+Baidu、CF+QQ三次STUN均实际60.20.170.34:18444，本地严格CA/hostname/marker成功，但独立北京裸TCP10061、curl7拒绝，无TLS/marker。国内keeper实际保持约65–66秒并14次双向响应；br-lan同端口STUN/keeper双向捕获校准通过，指定probeIP捕获0包（不能据此锁定拒绝节点/NAT类型；probeCGNAT的目的相关源IP尚未直接捕获）。21:13:41 CST独立读回owned fixture/进程/挂载/私钥/测试监听无、service{}，管理22/80/443保留；网关精确18444/TCP初始/各次结束/最终均714；nft结构/路由/持久配置不变。没有UPnP/NAT-PMP Add/Delete、fallback、安装或commit。停止同类换域名重复；如进一步做公网peer协调打洞需另行明确授权与凭据。下方UPnP 53ticks PASS独立保留，绝不是STUN成功，也不得恢复下方Add实验。

## 最新：2026-10-12 真实目标 Nginx 公网持续活跃 HTTPS 截止验收 PASS

见 [active cutoff 最终证据](homestun-upnp-active-cutoff.md)、[时间线 JSON](homestun-upnp-active-cutoff.json) 与 [独立清理读回](homestun-upnp-active-cutoff-cleanup.txt)。本轮仅一次 generation `homestun-upnp-20261012T122756Z` 的 18444/TCP 有限 UPnP Add（请求300s、读回余额299s），无续租、无主动Delete、无永久fallback。**真实路由器 Nginx 1.21.3**（非 WSL SDK 1.26.1）先在 Add 前验证 TLS 六次2秒heartbeat，跨度10.001s；独立北京公网 CA/hostname/marker 验证成功，held HTTPS 实际收到 **53个连续tick、4619 bytes**，最后tick约native开始后119.292s，EOF约120.129s、最后tick距EOF0.837s，启动时钟关联不确定度约±0.159s。原IPK native监管120s/exit0、socket-only mark255 forwarder/seccomp不变；无limit_rate，Nginx timeout240s。独立loopback源每连接182s、守护210s，并在native截止后仍实际产生两次tick，排除源TTL/EOF混淆；新公网连接随后curl7 Connection refused，而映射仍live。网关在Add+296.911s仍余额3s，+312.275s首次观察714，再次714。原生snapshot先无后删除owned fixture/私钥；独立SSH读回fixture/owned进程/挂载/测试监听无，服务{}，22/80/443保留，持久配置/路由/nft规则结构不变。无安装/防火墙/DNS/CF/生产源/commit改动。**连续流量下截止gate已关闭**；不是STUN通过或永久UPnP适配器。执行脚本已保存，未经新的明确授权不要重跑Add；下方零字节未验收记录均为历史。

## 最新：2026-10-12 有界 UPnP 复测终态

见 [最终证据](homestun-upnp-lease-final.md) 和 [时间线 JSON](homestun-upnp-lease-final.json)。唯一 generation 的显式 UPnP 18444/TCP→192.168.1.2:18444 获 300s 有限租约并精确读回；本机 native 300s 被拒，实际监管期 120s。北京独立外网固定 Host、测试 CA 的 HTTPS 与 marker 通过。持有连接约 120.284s EOF，然而应用字节/heartbeat 为 **0**，故无法排除 idle 类因素，**连续流量下硬截止未验收**；本机到期后新连接拒绝。网关余额逐次下降并在 Add 后约304.651s 自然 714，未主动删映射；测试 fixture 已清除，测试端口/owned 进程/挂载无，管理端口保留、配置与规则/路由结构不变。非 STUN 通过、非永久适配器。旧首轮/第二轮描述均为历史。

## 最新：2026-10-12 关机中断后的 UPnP 测试状态与恢复

用户确认当前本机位于北京联通 CGNAT 公寓（光猫拨号、小米二级路由），只是独立外网探测端；Homelede 仍在另一城市 `192.168.1.2`，其小米网关 `192.168.1.1` 持公网 `60.20.170.34`，原 `127.0.0.1:222` SSH 已恢复。不要混淆两个家庭网络，也不要重测已确认的 `60022→22` 静态转发。

关机前第一轮 UPnP 实验原始记录 `homestun-upnp-lease-summary.json`：小米接受唯一描述 `homestun-upnp-20261012T103350Z` 的 `18444/TCP→192.168.1.2:18444`，请求有限租期 300 秒、读回剩余 299 秒；本机独立外网通过固定 Host、测试 CA 校验 TLS 并取得合成 marker。测试本地原生监管期实际设为 **120 秒**（300 秒配置被拒绝），已建连接 EOF 约 120.76 秒，新连接到期超时；但关机前日志明确指出该次长连接可能受 Nginx 默认 60 秒上游 timeout 干扰，不能将它作为严格的截止期限关闭验收。此前日志提及网关映射自然到期，但第二轮启动于中断前、没有终态结果；**不得将第二轮记为通过**。

本次恢复时 parent 只读核对：远端 `/tmp/homestun-test/upnp-lease` 曾残留原生 fixture、测试证书和私钥，但无相关进程、挂载或 `18443/18444/18081` 监听；小米精确 `GetSpecificPortMappingEntry(18444/TCP, empty RemoteHost)` 返回 714（映射不存在）。核实无 owned 进程后仅删除该 owned fixture；随后再次读回 fixture absent、测试监听 absent、22/80/443 保留、小米 714。未新增/删除网关映射或更改路由、防火墙。下一步如要重测长连接，必须重新确认授权范围、用不同于上游 idle timeout 的持续流量与明确监管 deadline 证据，并先核对 IPK/测试脚本最终版本；永久 UPnP 适配器尚未实现。旧 `HOMESTUN-RESUME` 下方状态为历史，不代表最新网关映射状态。

## 最新：step1 真实 NATMap 短租约实验已清理，公网入站未通过

见 `homestun-real-natmap-summary.md`、`homestun-real-natmap-result.json` 与 `homestun-real-natmap-final-readback.txt`。真实 pinned20260214 NATMap 使用 matching24.10.5 SDK 构建，原 core IPK 精确lease payload不变；90秒原生双监管租约正常exit0，单调观测90.810秒包含SSH启动/回传。真实STUN回调 `67.230.168.23:37314`；独立Windows固定Host+显式测试CA curl连接超时28，无TLS/marker/已建外网连接证据。只读发现该IP属于既有Passwall2 VPS集合，OUTPUT NAT默认将非国内TCP重定向至2001；国内出口查询家庭真实IP `60.20.170.34`，本机 `61.148.12.162`。因此这是代理出口映射，不是家庭WAN穿透成功，不能据此判定家庭CGNAT类型或不可穿透。需要parent决定下一次有界尝试如何确保引擎直出（例如已存在bypass mark，但本次未使用、未改变规则）。16:22:33 CST再次SSH读回fixture absent、测试监听/进程无、22/80/443保留；firewall UCI hash unchanged。无安装/持久配置/防火墙/DNS/CF/提交改动；所有证书私钥随owned fixture删除，保存的本机PEM仅公钥测试证书。

## 最新：corrected LuCI SDK 包与真实浏览器证据已对齐

见 [最终包检查点](homestun-luci-package-final.md)：当前真实SDK LuCI IPK **4239 bytes**，SHA256 `9fb1269c6b8f3c679d07aa8631caa1e3ea3a817670402a039b37e6f4178949b2`；全LuCI源码→隔离feed绑定与SDK minified JS逐字节核验。真实target-assets浏览器Save/损坏配置禁用已PASS且源码哈希一致，最终Node **10/10 PASS**。构建修复仅isolated feed权限归一化+包clean，消除DrvFS0777；core IPK `84087e...`及生产源保持不变。无HomeSTUN激活hook（有标准LuCI cache/rpcd刷新脚本），SDK active make []。最终独立review及真实enabled引擎/procd、目标HTTPS、STUN/公网TCP、Cloudflare仍独立gate。此次仅本地打包/检查/文档，无路由器写入安装/激活/CF/防火墙/提交。下方旧最小LuCI与SDK阻断描述均为历史，不代表当前状态。

## 历史：LuCI 最小实现已落盘，SDK 打包阻断

见 [homestun-luci-checkpoint.md](homestun-luci-checkpoint.md)：独立设置/校验/诚实配置状态与最小 ACL/RPC 已实现，最终 Node 4/4 PASS（adapter harness，非真实 LuCI 浏览器）。三次 SDK 尝试因 feed index 未发现新 LuCI 包失败；direct DUMP 成功，未生成 IPK。实际 WSL ACTIVE_MAKE []；无路由器写入/激活/安装。续跑须修 feed discovery，再验真实打包/render/rpcd，不将本切片称完成。

## 最新：SDK native checkpoint 已完成清理，开始独立 LuCI 最小切片

- corrected SDK IPK 17095 bytes，SHA256 `84087e052d2cefacc7ac943ef9bc74000206379d80ca31b4de5f9c58d0ca4c22`；原生 target musl/seccomp/真实 nginx loopback 矩阵见 [homestun-sdk-native-target.md](homestun-sdk-native-target.md)。仅 syscall mock NATMap，非真实 STUN/公网/Cloudflare。
- 最终 cleanup script exit0；[homestun-sdk-native-cleanup-final.txt](homestun-sdk-native-cleanup-final.txt) 已读回原始/foreign 哈希不变、fixture/service/process 已无、22/80/443 保留。Parent 另一次 SSH 确认 `/tmp/homestun-test` absent、service `{}`。无需继续历史 cleanup pending。
- 本次仅新增独立 `luci-app-homestun` 设置与配置状态；默认禁用、不输入 token、不开放/关闭服务、不安装路由器、不改防火墙/NAT/CF、不 commit/merge/push/PR。状态必须保持 mapped unknown / reachable unverified，直到真正 live-state 接口存在。测试与 SDK 打包仅隔离 fixture。

## 最新：UCI publication 隔离注册完成与最终清理（2026-10-12）

见 [homestun-publication-uci.md](homestun-publication-uci.md)：真实目标 BusyBox/UCI/Lua/procd JSON builder **23 service PASS行 + 1 config suite PASS**，ubus仅本地捕获、未提交/启动真实服务。最终同源 WSL **token2/security3/publication3/socket4/lifecycle1/recipe1/package1/cleanup30**、Worker **8** 全通过；旧package断言失败日志不再作为验收。12:59:23 CST先读回原始cert/key不变且runtime/service/process已无；12:59:25 CST独立SSH确认仅owned UCI fixture清理，22/80/443保留、测试端口无。哈希manifest区分immutable payload与测试故意修改的UCI config。token严格EOF/short-read/EINTR循环已验证；目标历史28 case矩阵另列，不冒充本次重跑。默认三个开关仍0；独立review、SDK/ipk/ABI、真实enabled引擎+ubus、目标HTTPS、CF与公网可达仍独立gate。无生产配置/网络/安装/提交改动。

## 前次：publication token 最终目标补测通过（2026-10-12）

见 [homestun-publication-router.md](homestun-publication-router.md)：最新 token 修复本机 child **native45 / Worker8**、parent **token2 / Worker8**，与本子任务目标补测分开记录。真实路由器 BusyBox/no-stat + 实际 procd，`--provision ... publish` 七项 lifecycle（含 token snapshot 后 controller/preparation KILL/STOP）通过；严格 token **14输入×publisher/provision=28断言**通过，非法输入在 snapshot/transport/sequence 副作用前拒绝。目标真实 Lua5.1.5 隔离运行 **core16 + config suite**通过。最终 procd PID6875；12:38:47/48 CST读回 owned runtime 已先清理、原始cert/key/token与foreign未变、fixture/service/process已无，22/80/443保留、测试端口无。源码/目标传输哈希匹配。native为WSL static，curl/renderer/engines为无网络fixture；非目标SDK ABI/实际HTTPS/真实enabled集成/公网验收。未生产修改、安装、激活、部署或提交。

## 最新：authenticated publication 本机隔离切片

见 [homestun-publication.md](homestun-publication.md)：native opt-in callback→真实隔离HTTP→实际Worker→固定viewer redirect；Worker8 / publication3 / socket4 / lifecycle1 / recipe1 / package1 / cleanup30通过。旧两字段发布协议改为transactional generation/session/sequence，拒绝旧更新；默认仍publication off；config opt-in源码/隔离注册已在上方最新checkpoint验过，独立review仍待。无远程部署/公网可达验收，mapped不等于reachable。SDK/ipk与真实enabled完整集成仍缺。

## 最新：guarded provisioning 最终隔离回归通过

见 [homestun-guarded-provisioning.md](homestun-guarded-provisioning.md)：init 只读注册 native `--provision`，guardian 先于 mkdir/copy/render；旧 watcher 前窗口的 expected failure 已由真实通过测试替代。最终 WSL cleanup **30通过，无xfail**；真实路由器 BusyBox/libc/libgcc、无stat，native expiry/TERM/KILL/STOP、preparation render KILL/STOP、隔离真实procd STOP→TERM→KILL 均通过，PID102659、exit0。11:28:06 CST读回fixture/service/process均无，22/80/443保留、测试端口无。完整stdout、原始fixture证书前后哈希及源码/传输哈希已落盘。native/engine为WSL static测试产物，Lua/engines为无网络stub；不是SDK/目标libc/实际enabled HomeSTUN集成或公网验收。下方阻断/测试数为历史记录，不代表当前状态。

## 2026-10-12 已恢复核验（历史）

- cleanup 独立交接已补齐：[homestun-resume-cleanup.md](homestun-resume-cleanup.md)。当前源码在目标 BusyBox shell + 隔离 chroot 下 expiry/TERM/KILL/STOP 四项及真实 procd 独立 namespace STOP→TERM→KILL 清理均通过；最终保存的 router run exit=0，PID 82350。
- 修正 router-source-cleanup.sh 的 ubus pretty-printed 空 JSON 比较；目标简化 tr 不支持字符类，使用显式空白字符。未改生产 adapter/init/native/package。
- **新增明确阻断：目标固件没有 stat 命令/BusyBox stat applet。上述 chroot 使用独立 GNU stat 及库 fixture，不代表原样包可启用；需 parent 决策依赖/目标工具补齐并验证。** `/tmp` nodev 的 /dev/null fixture 使用普通文件 sink，不改 mount。
- 最终 10:44:18 CST readback：`/tmp/homestun-test` 已无；fixture ubus 服务及 PID 无；无匹配存活进程；22/80/443保留，18443/18444/18081/18082无监听。见 cleanup-final.txt 完整证据链接于交接文档。
- Parent 已提供最新 WSL isolated boundary4/lifecycle1/recipe1/package1/cleanup15/Worker6 全通过证据；本 cleanup 子任务没有重复执行或冒称其独立重跑。
- README 缺失 socket-boundary 链接已有正式证据入口补齐。SDK/ipk、真正 enabled HomeSTUN procd、真实 NAT/mapping/publication/external reachability 仍待验；不可称生产可用。未 commit/merge/push/PR。

## 历史暂停记录

用户要求临时关机暂停。两名子代理已收到立即保存、停止新实现/测试、清理测试进程并结束的指令；子代理收到指令有工具边界延迟，独立检查点是否落地须恢复后检查。

## 工作区
- D:/DevPortal/homelede/feeds-xiaoqingfeng-homestun
- 分支 feature/homestun；基线8953489；无commit/push/merge/PR。
- 原仓库 D:/DevPortal/homelede/feeds-xiaoqingfeng 不改。
- 项目 REQ-001，详见 REQUIREMENTS.md。

## 已实现与验证边界
- core.lua 严格配置校验与独立nginx多域名TLS生成。
- Worker 分角色鉴权、固定域名、bounded lease failclosed，6测试已通过。
- 原生lease-supervisor.c controller/guardian/preparation隔离与单调截止时间。前一版本通过9脚本33PASS及Lua16；独立审查批准仅隔离slice，不是生产批准。
- OpenWrt Makefile/TARGET_CC源码、默认禁用UCI、config adapter、procd独立服务及NATMap+nginx联动。
- package/recipe/lifecycle harness通过；真正SDK/IPK未验证。
- 临时TLS清理适配器正常expiry/failure/TERM已有8WSL测试，但crash覆盖不足。
- NATMap源码已构建但未安装/在路由器运行；真实外网穿透未验证。
- LuCI、authenticated mapping publication、Cloudflare部署均未完成。

## 当前两条阻断修复
1. NATMap上游root在bind失败后使用pidfd_getfd操作其他服务socket SO_REUSEPORT，须强制禁止，端口preflight不是充分防护。子代理sa-0-f0af7e7d：scope native/seccomp或专用patched engine，端口占用及race回归。期望检查点 docs/homestun-resume-natmap.md。
2. TLS source cleanup adapter被SIGKILL时可能残留。子代理sa-1-3fb79562：scope lease-run/init/tests，独立watcher/所有权清理、BusyBox验证，避免与native agent冲突。期望检查点 docs/homestun-resume-cleanup.md。

## 恢复顺序
1. git status及读取以上两个检查点；不要假设子代理完成，也不要覆盖当前修改。
2. 检查测试进程与路由器临时路径，再决定恢复测试。
3. 继续两阻断修复；最终版本重跑回归、parent独立核验及review。
4. package SDK、真实enabled procd验证仍独立gate；公网测试需确认具体范围。

## 环境与命令
SSH: ssh -F /dev/null -i D:/DevPortal/CloudHosts/HomePri.key -p 222 -o BatchMode=yes -o ConnectTimeout=10 root@127.0.0.1
路由器 Homelede x86_64 192.168.1.2 defaultgw192.168.1.1，现有22/80/443不可修改。key只引用路径不读取。
测试仅/tmp/homestun-test隔离路径、loopback18443/18081/18082。上一完整清理已删除fixture；新代理是否重建必须实查。
node --test homestun/tests/worker.test.mjs
wsl.exe --exec bash -lc 'cd /mnt/d/DevPortal/homelede/feeds-xiaoqingfeng-homestun && python3 homestun/tests/test-package.py && python3 homestun/tests/test-recipe.py'
wsl.exe -u root --exec bash -lc 'cd /mnt/d/DevPortal/homelede/feeds-xiaoqingfeng-homestun && python3 homestun/tests/test-lifecycle.py && python3 homestun/tests/test-source-cleanup.py'
Linux lifecycle/chroot tests必须WSL root；Windows没有make，不把环境错误当实现失败。

## 禁止事项
不覆盖现有HomeTunnel，不开放NAS/打印机/LuCI，不装包/改防火墙/Cloudflare，不合并推送或创建PR。host test binaries已由homestun/.gitignore忽略，不提交。

## 当前子代理完整记录
C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/delegation/live/deleg_296f42ee/task-0.log
C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/delegation/live/deleg_296f42ee/task-1.log
