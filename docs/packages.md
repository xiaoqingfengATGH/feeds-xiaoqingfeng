# feeds-xiaoqingfeng 固件内置包说明

本 feed（`src-git xiaoqingfeng https://github.com/xiaoqingfengATGH/feeds-xiaoqingfeng`）收录 HomeLede 原创与定制软件包。本文档说明**当前固件（24.10.5，v2026.10.01）实际启用的包**——它们通过 `target/linux/x86/Makefile` 的 `DEFAULT_PACKAGES` 与 `include/target.mk`（router 段）选包，全部进 x86_64 镜像。

> 启用状态以构建树 `.config`、镜像 manifest 与 247 实机三处交叉验证为准（2026-10-04 核对）。
> feed 中 `adguardhome`、`luci-app-ikev2-manager` 仍保留源码但**未启用**：前者是历史 DNS 方案遗留、已被 dnsmasq-full 原生方案取代，后者已被 `luci-app-homevpn` 取代。

## 包总览

| 包 | 版本 | 类别 | 一句话 |
|---|---|---|---|
| homelede-autoconfig | 20261001-6 | 系统基础 | 首启自动配置（时区/主机名/语言/镜像源/版本标识） |
| HomeRedirect | 2.0-1 | 端口转发 | socat 前端的跨协议端口转发，CGNAT/IPv6 时代方案 |
| luci-app-homeredirect | 2.0-r1-20260930 | LuCI (Lua/CBI) | HomeRedirect 管理页（含 zh-cn） |
| hometunnel | 1.0.0-1 | 内网穿透 | Cloudflare Tunnel 按需启停的免费内网穿透 |
| luci-app-hometunnel | 1.0.0-r1 | LuCI (JS) | HomeTunnel 向导/状态/拓扑/ingress/使用指南（含 zh_Hans） |
| luci-app-homestatus | 1.0.0-r1 | LuCI (JS/ucode) | 定制驾驶舱：总览页磁盘/关键应用/互联网 KPI 扩展 + WoL |
| luci-app-homevpn | 2.0.0-r5 | LuCI (JS) | strongSwan IKEv2 一体化 VPN 服务器（EAP 用户/证书/客户端描述文件） |
| p7zip | 16.02-1-xiaoqingfengMod | 工具 | 7z 命令行（GCC17 适配定制版） |
| softethervpn5 | 5.2.5188-1 | VPN 备用 | SoftEther SSL-VPN/L2TP 多协议 VPN 服务器（来自官方 packages feed） |

---

## homelede-autoconfig — 首启自动配置

**职责**：HomeLede 首次开机的品牌化与基础配置，`lean` 时代 `zzz-default-settings` 的继任者（只保留了对 HomeLede 有价值的条目，每项都有守卫，不会覆盖管理员已做的显式配置）。经 `include/target.mk` DEFAULT_PACKAGES.router 选包。

**首启执行一次**（`START=13`，`/etc/config/homeledeInit` 标记防重复）：

- 时区 `Asia/Shanghai` + 国内 NTP（aliyun/tencent/ntsc/time.apple）
- 主机名 `HOMELEDE`（即时写入 `/proc/sys/kernel/hostname`）
- LuCI 默认界面语言 `zh_cn`
- root 默认密码 `homelede`（sha512crypt 预散列；仅首启未改密时）
- opkg/apk 源替换为腾讯镜像
- dnsmasq 只服务 br-lan；日志入 `/dev/null`（未显式配置时）
- 版本标识：从 `/etc/buildmark` + `DISTRIB_RELEASE` 生成 `DISTRIB_REVISION='v2026.10.01 based on OpenWrt 24.10.5'`

**v20261001-6 变更**：移除了遗留 Go 二进制 `homeledeCore`（29MB，mosdns/AdGuardHome 旧体系遗留，全树无引用），包体积从 10.4MB 降到 17KB；同包 `/etc/brand` 为装饰性 PNG，无脚本引用，保留。

## HomeRedirect — CGNAT 时代端口转发

**为什么需要它**：家宽普遍失去公网 IPv4（CGNAT），能拿到的是 IPv6。想把 v6 可达的服务转发给只有 v4 的内网设备（或反之），传统 fwkmod-redirect 做不到跨协议转换——HomeRedirect 用 **socat** 在传输层完成转换。

**支持矩阵**（`/etc/config/homeredirect` 每规则 `config redirect`）：

| proto | 监听 | 转发目标 |
|---|---|---|
| tcp4 / udp4 | v4 端口 | v4/v6/域名 |
| tcp6 / udp6 | v6 端口（默认 ipv6only，纯 v6） | v4/v6/域名 |
| tls4 / tls6 | OpenSSL 监听 + cert/key | v4/v6/域名 |

- 每条规则一个 procd 实例（respawn 3600 5 5），日志 `/tmp/hr/<id>.log`
- 防火墙由 init 自动同步：UCI `firewall.hr_<id>` 规则（src=wan、target=ACCEPT），fw3/fw4 通吃，启停自动增删
- v6 监听默认 `ipv6only=1`（CGNAT 世界纯 v6 入口）；`ipv6only=0` 时接受 v4-mapped
- 目标端域名由 socat 每连接重新解析；裸 v6 字面量自动加括号
- TLS 监听需在 `@global` 配 cert/key 路径，缺则跳过该规则并记录

**LuCI**：服务 → Home Redirect（Lua CBI 页）。设置页可加/删规则、全局 TLS 证书、总开关；状态列实时读 procd 实例运行态。菜单可通过页面内入口隐藏（`/etc/config/homeredirect_show` 存在即显示，隐藏后从 `admin/status/overview` 顶部提示恢复）。

## hometunnel / luci-app-hometunnel — Cloudflare Tunnel 内网穿透

**全免费内网穿透**：Cloudflare Tunnel 不限流量 + Workers 免费额度，无需公网 IP、无需端口转发、路由器上零 API Token（只需 cloudflared login 证书 + 自生成 CTL_KEY）。

**核心设计——按需启停（ondemand，默认）**：

```
外网浏览器 ──HTTPS──> Cloudflare 边缘
  ├─ ctl.<domain>  → Worker (DO 单例, 状态机: on/off/TTL/beat 续期)
  │                    ▲ 10s 轮询 /cmd + 有流量时 /cmd/beat?traffic=1
  └─ app.<domain>   → cloudflared tunnel ──> 内网服务 (192.168.x.x:port)
                         ▲ procd 拉起/停止
                     hometunnel-ctl 守护
```

- 平时隧道**不运行**；外网点书签 `https://ctl.<domain>/on` 即开（状态页有书签按钮 + 二维码）
- TTL 到期自动关；使用中有真实流量自动续期（cloudflared metrics 判定）
- **三层关停**：手动 `/off` → Worker TTL（默认 45s 起步，max 240s）→ 本地 hard_cap 熔断（默认 4h，可设 0 不限）
- `alwayson` 常驻模式：开机即连，不做按需管理

**LuCI**（服务 → HomeTunnel，JS 页面）：六步向导（授权→创建→DNS→部署控制面 Worker→校验→启用）、状态页（开关书签/二维码）、拓扑图、ingress 规则（每条一个 `subdomain.<domain>` → 内网服务）、设置、内置使用指南页（含与 FRPS-IPv6 方案对比表）。

**凭据全在 `/etc/hometunnel/`（600）**：cert.pem、`<tunnel-id>.json`、ctl.key、config.yml。依赖 cloudflared + curl（hometunnel Makefile DEPENDS），Worker 部署包在 `/tmp/hometunnel-worker-*.tar.gz` 供电脑端 wrangler 部署。

**TTL 漂移自动重部署**：快照 `/etc/hometunnel/worker-ttl.snapshot` 与 UCI 比对，不一致时 route-and-regen 末尾自动重下发。

## luci-app-homestatus — 定制驾驶舱

**职责**：接管/扩展 LuCI 总览页（`admin/status/overview`，菜单改称“驾驶舱”），把原版稀疏的首页变成家庭网关仪表盘。rpcd ucode 插件 `luci.homestatus`（1722 行）+ JS 视图，`BUILD16` 起入 x86 默认包。

**面板区块**（UCI `homestatus.@global[0].show_*` 逐块开关，关掉即不渲染、后端也不再探测）：

- **磁盘**：`/proc/self/mountinfo` + `/sys/class/block` 自动发现挂载点（伪文件系统已过滤），容量条 + warn(80%)/crit(90%) 全局阈值告警，计入顶部摘要
- **关键应用**：进程探针监视（probe 四法：`exe` argv[0] 基名 / `cmd` 命令行子串 / `port` LISTEN 端口 / `path` 运行时产物存在），默认监视 passwall2(1070)、hometunnel 控制面、dnsmasq、mwan3、nlbwmon、dockerd、vsftpd、wsdd2；可逐项 restart
- **互联网 KPI**：路由器本地双路探测（`curl --parallel` 并发测 baidu=国内直连 / google=海外），exitcode+失败阶段映射中文原因（DNS 失败/连接拒绝等），UCI `probe_cn/probe_intl` 可覆写目标；passwall2 localhost_proxy 开启时海外探测走代理链，与 LAN 客户端同路
- **WoL 唤醒**：目标列表存 `/etc/config/luci-wol`，一键 etherwake，邻居表判定在线

**要点**：插件跑在 rpcd 进程内，**不调** ubus `rc/service`（会死锁），一律直读内核接口；设置页走标准 uci 表单（Save & Apply 免费获得），后端每次调用重读 UCI，改配置无需重启。

## luci-app-homevpn — IKEv2 一体化 VPN 服务器

**定位**：turnkey strongSwan IKEv2 服务器——iPhone/iPad/Mac/Android/Windows 原生支持 IKEv2，不装任何客户端软件，用户名密码（EAP-MSCHAPv2）拨入即成完整 LAN 成员（DHCP 池 + farp ARP 代理）。v2.0 取代了原 `luci-app-ikev2-manager`（上游 naughtyGitCat，其 EAP 用户管理 UI 思路被继承）。

**三证书模式**：

| 模式 | 说明 |
|---|---|
| `selfsigned`（默认） | 首启自建 PKI（CA+服务器证书），开箱即用 |
| `import` | 手工放置 `/etc/swanctl/{x509,x509ca,private}` |
| `acme` | 同步 luci-app-acme 签发的证书（Let's Encrypt，配合 DNS-01 可无公网 v4） |

**首启供给**（init.d `START=99`）：自签 PKI → swanctl 连接（DHCP pool + farp）→ INPUT 链放行 500/4500/ESP（`firewall.homevpn_*`，路由器本机 charon 场景，与库存 dest=lan 转发规则不冲突）→ 加载连接。IKE proposal 默认 AES-256-GCM/SHA2-384/modp2048（可配）。

**LuCI**（VPN → HomeVPN，单页 overview）：服务器状态徽章（charon 运行/监听/SAN 匹配/防火墙/连接加载/在线客户端）、EAP 用户增删（随机密码生成）、客户端描述文件下载（iOS/macOS `.mobileconfig`、strongSwan App `.sswan`、CA 证书）。rpcd 后端 `homevpn`（bash+jshn）。

**UCI**（`/etc/config/homevpn`）：`cert_mode/remote/vpn_name/ike_enc/ike_int/ike_dh`。无 po 目录，界面英文直出（词为技术词，刻意保持）。

**依赖**：strongswan-swanctl + eap-mschapv2 + gcm + openssl + curve25519 + pkcs8 + dhcp + farp + openssl-util + libopenssl-legacy（已全在 x86 DEFAULT_PACKAGES strongSwan 段）。

## p7zip — 7z 命令行

GCC 17 适配定制版（上游 hubutui/p7zip-lede，16.02）。仅 `7z` 命令，SFX/自解压等未含；在路由器上解包 docker 镜像层、驱动包等场景常用。进 `DEFAULT_PACKAGES` 系统工具段。

## softethervpn5 — SoftEther 多协议 VPN（备用）

SSL-VPN/L2TP-over-IPsec 多协议 VPN 服务器，作为 IKEv2 不可用环境（极端 NAT/企业防火墙）的兜底。四子包 `-libs/-server/-bridge/-client` 全家进镜像，服务名 `softethervpnserver`（`/var/softethervpn/`，`vpncmd` 管理）。

> 注意版本事实：**实装 5.2.5188-1 来自官方 packages feed**（构建 feed 优先级使然）；本 feed 内的 5.02.5185-xiaoqingfengMod 保留源码但被遮蔽，未进镜像。文档以实装为准。

## 附：已退役但保留源码的包

| 包 | 状态 |
|---|---|
| adguardhome | 源码保留，未启用（.config not set）。DNS 方案已由 dnsmasq-full 原生栈取代 |
| luci-app-ikev2-manager | 源码保留，未启用。功能并入 luci-app-homevpn 2.0（2026-10-03 换装） |
| softethervpn5（feed 内 5.02.5185 版） | 被 packages feed 5.2.5188 遮蔽，未进镜像 |

## 附：近期清理记录

- **v20261001-6**（2026-10-04）：`homelede-autoconfig` 移除 29MB 遗留二进制 `homeledeCore`（mosdns/AdGuardHome 旧体系遗留，全树零引用；feed 提交 c4af62a）
- **2026-10-04**：`luci-lib-docker` 整包移除（feed 提交 cfd5fe7）——新版 dockerman 为 ucode 实现、自带 `luci.docker_socket`，不再需要该 Lua 库；247 实机验证 dockerman 页面与 7 个 docker ubus 对象移除后全部正常
- **2026-10-03**：`luci-app-ikev2-manager` → `luci-app-homevpn` 换装（DEFAULT_PACKAGES :126），`.config` 残留 =y 已清
