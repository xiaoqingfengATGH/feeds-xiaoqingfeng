# 小米 UPnP 阶段一只读发现（真实目标证据）

时间：2026-10-12 18:17:48–18:18:09（UTC+08）。分支 `feature/homestun`；未提交、合并或推送。

## 结果

- 从 Homelede `br-lan` / `192.168.1.2` 发送 **一次** SSDP M-SEARCH，接收窗口 4.5 秒、无重试。仅接受源 `192.168.1.1`。
- 小米设备：`MiWiFi router`，manufacturer `Xiaomi`，model `MiWiFi Router` / `20250514`；`InternetGatewayDevice:1`。
- 实际服务：`urn:schemas-upnp-org:service:WANIPConnection:1`，无 WANPPP 服务被选用。
- 描述 `http://192.168.1.1:5351/rootDesc.xml`；SCPD `/WANIPCn.xml`；control `/ctl/IPConn`。5351 来自实际 SSDP 广告；每次 HTTP 读回 peer 均为 `192.168.1.1:5351`。
- `GetExternalIPAddress` 返回 `60.20.170.34`，仅用于服务身份佐证，不是新的 WAN/公网入站测试。
- `GetGenericPortMappingEntry` 上限 32，实际读取 **9 条**，索引 9 返回 HTTP 500 / UPnP **713 SpecifiedArrayIndexInvalid**，枚举完整、未截断。无关映射的 IP、端口、描述仅留本地原始证据，不在本文披露。
- 对空 RemoteHost 的 **18444/TCP** 查询返回 HTTP 500 / UPnP **714 NoSuchEntryInArray**：查询时无该 UPnP 条目，**不是原子预留，也不能排除非 UPnP 静态规则或并发抢占**。

## 能力边界

SCPD 广告动作：`SetConnectionType`、`GetConnectionTypeInfo`、`RequestConnection`、`ForceTermination`、`GetStatusInfo`、`GetNATRSIPStatus`、`GetGenericPortMappingEntry`、`GetSpecificPortMappingEntry`、`AddPortMapping`、`DeletePortMapping`、`GetExternalIPAddress`。**只有三个 Get 动作被调用**；未调用任何写动作。`AddAnyPortMapping` 未广告。

`NewLeaseDuration` 参数存在，只能证明描述中的租约接口；未证明短租约被接受、不会转永久或按时到期。阶段二必须单独授权，不能据本次发现执行创建/删除映射。

## 安全与实现

使用 SDK 编译的最小单包 SSDP 客户端，HTTP 复用目标现有 curl，XML 在本机 ElementTree 解析。未采用 miniupnpc 自动发现/取描述路径，以避免其多 ST 自动搜索或隐式 URL 请求突破单次搜索、严格 origin 边界；没有安装任何包或启动 miniupnpd。

HTTP 仅允许已广告 `http://192.168.1.1:5351` origin、无凭据；绑定 `ifhost!br-lan!192.168.1.2`，禁用代理和 curlrc，不跟随重定向、不进行 DNS origin 变更。连接超时 2 秒、每请求 4 秒、响应上限 256KiB。只读 SOAP 动作白名单；DTD/entity 声明拒绝，XML 转义由解析器处理，不使用 shell eval。六个越界 URL、非默认广告端口、DTD 拒绝及转义解码的本机测试通过；C helper 通过 SDK `-Wall -Wextra -Werror`。

共 2 次 HTTP GET、1 次外部地址读取、10 次有界枚举调用（含结束错误）、1 次候选查询。所有响应 SHA256 已重新核对。

## 清理与差异

远端 `/tmp/homestun-upnp-readonly-20261012` 的唯一 helper 已删除、目录不存在；本机 scratch 临时源码、二进制及控制脚本也已删除。审计仅保留非执行 `.source.txt` 文本。读回未发现 helper 或 miniupnpd 进程。未执行 NATMap、opkg 安装、配置/路由/防火墙修改，未触碰公网 60022 映射。

前后 firewall/network/passwall2/homestun 配置哈希、IPv4 rule/route 一致；全部 TCP 监听一致，SSH/Web 管理仍在。**完整 UDP 快照并非逐字一致**：已有进程的临时 UDP 端口变化 43989→39963；后续带 PID 的 netstat 显示现有 chinadns-ng/xray 在使用轮换 UDP 端口。因此不宣称全部进程或全部 UDP 端点不变。

## 文件与隐私

- 结构化报告：`docs/homestun-upnp-readonly-summary.json`。
- 原始响应/SSDP、前后快照、私有映射明细及审计源码：`docs/artifacts/upnp-readonly-private/`。这些仅在本地工作树保存，**不得直接提交、上传或公开**（含设备标识及无关用户映射描述）。
- 本文和 JSON 不含鉴权秘密，且不披露无关映射详情；未改动既有产品代码和其他工作树修改。
