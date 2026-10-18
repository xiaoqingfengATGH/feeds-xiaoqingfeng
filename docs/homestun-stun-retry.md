# 真实 NATMap/STUN 有界重试终态

**完成3个源码支持的STUN-only变体；公网入站0/3通过，所有临时fixture及私钥已清理。没有UPnP/NAT-PMP Add/Delete，没有隐式fallback。**

详细机器证据：[homestun-stun-retry.json](homestun-stun-retry.json)。独立结束读回：[cleanup](homestun-stun-retry-cleanup.txt)。每变体另有result.json、stage/run/engine/log与4份header capture，前缀`homestun-stun-retry-{variant}`。原UPnP 53ticks成功证据独立且未覆盖，不算本轮STUN成功。

## 源码依据与选择

固定revision `f8d7996710677c9885c148dda80a42d626f0a17b`，实际SDK NATMap SHA256 `ba2df4ead5562b0bc0359881ffce1a07d65f62403b6e0b7e0980731be09c45b1`，原IPK lease payload不变。测试harness版本`stun-retry-v1`，未改/重编生产代码。

- [`hev-conf.c`](https://raw.githubusercontent.com/heiher/natmap/f8d7996710677c9885c148dda80a42d626f0a17b/src/hev-conf.c)：`-s IP:port`、`-h host:port`、`-k seconds`、`-i local-IP`、`-f mark`；没有独立HTTP Host参数。HTTP IP只写入隔离chroot的hosts，保留实际Host；STUN使用literalIP。国内目标经显式223.5.5.5解析，无生产DNS改变，捕获验证实际目的IP。
- [`hev-tnsk.c`](https://raw.githubusercontent.com/heiher/natmap/f8d7996710677c9885c148dda80a42d626f0a17b/src/hev-tnsk.c)：先建立HTTPkeeper，发送HEAD与Connection:keep-alive，再运行STUN；本轮5秒keep。
- [`hev-sock.c`](https://raw.githubusercontent.com/heiher/natmap/f8d7996710677c9885c148dda80a42d626f0a17b/src/hev-sock.c)：HTTP/STUN/listener使用相同本地endpoint192.168.1.2:18444，SO_REUSEADDR/SO_REUSEPORT；每个相关外部socket使用mark255。localhost backend不需代理bypass。外部不是同一已建立TCP连接。
- [`hev-stun.c`](https://raw.githubusercontent.com/heiher/natmap/f8d7996710677c9885c148dda80a42d626f0a17b/src/hev-stun.c)：TCP一次binding得到endpoint后关闭STUN socket；HTTPkeeper持续维持状态。回调不测试第三方入站、也不授权网关放行它。
- 上游[Wiki](https://github.com/heiher/natmap/wiki)/[FAQ](https://github.com/heiher/natmap/wiki/faq)明确任意外部主机可达依赖所有NAT层的相应宽松行为；程序不是能改任意NAT过滤行为的机制。

变体1换成国内长连接keeper，排除旧keeper选择；变体2对比变体1仅换独立STUN提供商，比较endpoint；变体3对比变体1仅换国内keeper，比较保持时序。最多3次，完成后停止同类重复。

## 真实执行

均原生TTL70秒，无自动续租/respawn；专用18444/TCP→loopback18443 TLS→18081合成marker。每次启动前精确网关18444/TCP emptyRemoteHost714，结束后714。TTL是native70秒；表内约71.6秒的本机观测包含SSH启动/回传，不是原生监管时长。

2026-10-12中国标准时间：

| 变体 | 启动–结束 CST | STUN literal | keeper Host与literal目的IP | 实际public endpoint | 本地CA/hostname/marker | 独立北京TCP/TLS |
|---|---|---|---|---|---|---|
| cf-baidu | 21:07:39–21:08:51 | 141.101.90.1:3478 | www.baidu.com → 110.242.70.57:80 | 60.20.170.34:18444 | PASS | refused10061 / curl7; 无TLS/marker |
| nextcloud-baidu | 21:09:25–21:10:36 | 46.225.95.169:3478 | www.baidu.com → 110.242.70.57:80 | 60.20.170.34:18444 | PASS | refused10061 / curl7; 无TLS/marker |
| cf-qq | 21:11:09–21:12:21 | 141.101.90.1:3478 | www.qq.com → 221.198.70.47:80 | 60.20.170.34:18444 | PASS | refused10061 / curl7; 无TLS/marker |

独立Windows裸TCP和curl均直接连接实际回调端点，不经SSH/环境代理；curl使用`-q --proxy '' --noproxy '*' -4 --resolve --cacert`，固定Host/hostname并严格测试CA。三次均TCP被拒绝（Windows10061/curl7），尚未进行TLS握手，响应marker为空。没有“握手失败”或“CA失败”假结论。本机IP直出literal/Host查询先后均123.118.214.120；本机联通CGNAT不阻止主动连接，不将其当失败原因。

## 捕获与新结论的强度

AF_PACKET SOCK_DGRAM ETH_P_ALL，br-lan精确IPv4/TCP18444及分别指定STUN/keeper/probeIP；仅IP+固定TCP头，无payload/promisc。三次STUN入/出计数4/6、4/5、4/6；同接口同端口的SYN/SYNACK和响应证明双向捕获有效。keeper入/出29/30、29/30、19/30，每次实际14次发出的data、14次响应，贯穿约65–66秒；live netstat均keeper ESTABLISHED。排除这些变体“keeper未建立或马上关闭”解释。localhost CA+marker成功实际走lo，未冒称独立LAN验证。

外部probe匹配123.118.214.120的br-lan捕获全部0包，未见SYN；但CGNAT针对不同目的地的出口源IP未直接捕获，且Windows拒绝不包含拒绝发出节点身份，因此不能仅凭这项捕获锁定小米/运营商拒绝，也不能判定某种NAT类别。两个STUN提供商同样返回60.20.170.34:18444只是这几个出站目的的映射观察，**不证明endpoint-independent filtering/full-cone，不证明公网可达**。

最强结论：成功出站STUN、正确本地source endpoint复用、活跃国内keeper、现有mark255绕过Passwall2(26.10.1-r2)和本地TLS转发均已证实，但第三方入站仍未通过。已有显式UPnP对照是另一机制，不能代替本轮。

## 清理与下一步

三次原nativeexit0，live NATMap `NoNewPrivs:1 / Seccomp:2 / filters:1`，foreign pidfd_getfd保护未解除。每次nft规则结构（忽略计数）、路由及network/firewall/passwall2持久配置哈希不变。21:13:41 CST再次独立SSH：fixture/父目录/owned进程/挂载/私钥/18444、18443、18081监听无；HomeSTUN service{}；22/80/443原管理监听保留，网关精确714再次确认。仅保存本地公开测试证书，无私钥。

无需再换几个STUN域名重复相同失败。下一步有价值的是**另行授权的只读上游过滤/连接跟踪诊断**，或用户明确授权并提供另一公网peer的协调实验；目前不执行TCP simultaneous-open、不硬编码任意第三方公网服务充当配合peer、不开放真实服务、不改网关规则。永久适配器、CF/DNS、安装、commit/merge/push/PR均未做。
