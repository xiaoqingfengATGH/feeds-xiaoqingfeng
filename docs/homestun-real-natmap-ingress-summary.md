# NATMap 入站失败边界：Homelede br-lan 未观察到外网 SYN

## 结果

- 最终实验 UTC 2026-10-12 09:36:57 起，原生 supervisor TTL90s，exit0；真实六字段映射仍为 `60.20.170.34:18444` → `192.168.1.2:18444`。
- Windows 独立出口只读查询为 `61.148.12.162`；直连 socket 和禁用代理、固定 SNI/Host/CA 的 curl 都在 TCP 建连阶段超时，curl exit28。没有外网 TLS/HTTP 成功。
- 同时运行的 br-lan 精确外网 peer+TCP18444 捕获：**0 packets，0 inbound SYN，0 outbound SYNACK**。
- br-lan 的 `192.168.1.2`+TCP18444 对照捕获：**23 packets（9入/14出），0 inbound SYN**，可见 NATMap 自己的 HTTP discovery/STUN TCP SYN、SYNACK及后续收发，证明同接口、同端口的双向捕获有效；这些 SYNACK 是出站连接的回应，不是外网主动入站成功。
- Homelede 对自身 LAN 地址 `192.168.1.2:18444` 的证书验证 HTTPS 经 NATMap 转发到 loopback18443/18081，返回准确随机 synthetic marker。lo 对照30条记录（包含出/入双份），看到了客户端 SYN和服务端 SYNACK。**这是自身LAN地址的本地转发验证，不冒称独立LAN客户端入站验收。**

因此观察边界已缩小为：外网主动连接没有出现在 Homelede br-lan TCP18444 捕获点；未见对应回复 SYNACK 离开。不能据此把原因定为 Homelede INPUT、防火墙、rp_filter、CGNAT或运营商某一具体设备，也不能定位外网发送端、路径、上游网关或上游NAT中的哪一跳。未做发送端SYN抓包，未登记packet-socket丢包统计，需保留这些证据限制。

## 只读路径与策略证据

- Homelede 仅有 `192.168.1.2/24` br-lan，默认上游 `192.168.1.1`，邻居MAC `cc:d8:43:96:e2:f8`。到Windows公网IP，无mark及mark255均走192.168.1.1/br-lan。
- all/br-lan rp_filter均为0。fw4 input：lo accept、established/related accept、syn_flood、br-lan→input_lan→accept_from_lan。accept_from_lan原有counter增长；NAT泄漏drop原有counter127packets/6663bytes未变。syn_flood drop、input policy drop、handle_reject本身没有专门counter，未添加counter，不能用其他背景计数替代试验归因。
- `-f 0xff` 是未修改上游 NATMap 的 SO_MARK，仅覆盖其拥有的discovery/base、STUN、监听/accepted回复socket；loopback backend未标记，DNS仍用既有resolver，不能宣称全链路DNS绕过。Passwall2低字节255返回规则及route兼容性沿用前次已证据化方式，没有rule/route写入。
- 完整nft table/chain/rule定义（仅counter归零）前后相同；ip rule/全表route输出相同；firewall/Passwall2 UCI文件SHA256前后相同。动态set元素不在定义比较承诺内。

## 工具、纠正与清理

- 目标无tcpdump，使用既有OpenWrt24.10.5 SDK gcc13.3 musl编译静态临时AF_PACKET/SOCK_DGRAM helper；没有opkg安装。内核BPF限定IPv4 TCP18444与单个peer，仅返回IP头+固定20-byte TCP头，无payload/秘密捕获，不启用promiscuous模式；每个helper自行90s退出。
- 第一次捕获使用ETH_P_IP，只观察到incoming。保留 `*-attempt1.*`，修正为ETH_P_ALL加IPv4/TCP/peer/port内核过滤，重新编译 `-Wall -Wextra -Werror` 成功并重跑整次90s实验。最终结论只以修正后双向捕获为依据。
- supervisor expiry及fixture进程/root/exe/cwd扫描后移除精确 `/tmp/homestun-test/realnat-ingress` 和父目录；独立SSH读回fixture不存在、无capture/fixture进程，18081/18443/18444监听不存在，管理22/80/443监听保留。
- 未改上游gateway、防火墙、policy route、persistent服务、DNS/Cloudflare；未commit/merge/push/PR，未改production实现。

## 下一步权限边界

现有会话没有192.168.1.1的已授权管理会话、凭据或WAN接口信息，没有猜测凭据/用户名或尝试登录。下一步需要用户提供安全方式建立的**上游gateway只读管理访问**并授权限定测试端口的WAN/LAN短时抓包及WAN地址/NAT/既有过滤规则读取；最好同步Windows发送端精确目的IP/18444 SYN抓包，区分发送端、gateway WAN入站与LAN转发。独立LAN客户端还需明确授权的可用客户端。即使只读结果指向缺少转发，任何gateway port-forward/firewall/policy-route变更仍须单独授权，不能在本任务中修复或开放端口。

Evidence: `homestun-real-natmap-ingress-{test.py,result.json,evidence.json,log.txt,engine.txt,run-output.txt,final-readback.txt,capture-external.txt,capture-local-br.txt,capture-local-lo.txt}`；`homestun-ingress-header-cap.c`；`artifacts/homestun-ingress-header-cap-sdk` 与仅公开测试证书 `artifacts/realnat-ingress-test-cert.pem`。临时certificate private key已随router fixture移除。
