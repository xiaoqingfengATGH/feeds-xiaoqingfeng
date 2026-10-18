# REQ-007 P0 退出清单与组件决策

范围：原计划P0任务1–6的基线登记与技术可行性门禁，不代表P1–P5产品实现。P0关闭后等待用户指令，不自动启动P1。

## 逐项核对

| 原任务 | 状态与证据 |
|---|---|
| 1 工作区/已有改动归属 | feature/homepublish-product，既有certificates.js只读表修复、entry.js及菜单标题更名保留，不并入本轮组件试验修改；sketches、__pycache__不删除。当前未commit/push/merge。 |
| 2 REQ登记/历史覆盖 | REQUIREMENTS.md REQ-007；明确覆盖旧仅Web/向导约束，UPnP/STUN排除而非删除旧配置，普通procd继续有效。 |
| 3 模型/RPC契约 | HOMEPUBLISH-TCP-CONTRACT-V2.md：四类型、双栈绑定、保存并发、显式迁移、错误码与源地址边界。设计冻结，不假称已实现v2。 |
| 4 只读实机基线 | prerequisite与baseline-confirmed日志：监听/组件、网卡/路由/策略规则、procd、内存/文件系统、配置SHA256。controller未注册，设备有IPv4默认路由及ULA、无可见IPv6默认路由/GUA。恢复通道是既有root@127.0.0.1:222密钥SSH；不改22/443 Dropbear。 |
| 5 私有组件隔离验证 | 固定sslh2.3.1源码与libproxyprotocol1.3.3；实机9项探针及连续两轮5项identity通过。未知/超时明确拒绝、SNI分段、v6→v4、源地址头消费。所有监听loopback高端口；证据见检查点。 |
| 6 组件/源IP/拒绝/Stop边界评审 | 采用下述决策；独立只读审查发现的日志隔离、清理顺序、旧对象ABI问题已处理并重跑；不把本轮探针当成产品procd验收。 |

## 组件决策

1. 共享混合TCP入口采用sslh-select **2.3.1**（当前官方最新稳定版）；不退回缺PROXY功能的2.1.2，不跟随master。每次发布准备重新核对稳定版。
2. HTTP-only/HTTPS-only不必强制经过sslh；混合时仅HTTPS终止分支向内部Nginx发送PROXY v1。其他类型默认后端只见代理IP；不引入TPROXY/策略路由，不承诺透明源IP。
3. 专用Nginx负责HTTP/TLS终止与独立TCP stream转发；不覆盖系统Nginx。当前1.26.1仅stream夹具，不是产品HTTP/SSL/realip模块交付，不是生产版本选型完成。产品进入P3必须准备有HTTP SSL/realip与stream能力的合适稳定版本并验收。
4. 未知协议、未知SNI及静默超时均走应用拥有的拒绝目标。fixture以bind不listen端口证明拒绝，正式运行不得依赖固定“空端口”；provider启动前持有目标、readiness检查、入口退出后才能释放。若使用轻量立即关闭服务须有固定身份/资源上限，与发布事务共同管理。
5. loopback PROXY端点只隔离外部访问，不认证本机进程。HTTP X-Forwarded-For/X-Real-IP必须由精确信任内部代理的HTTP realip路径重建，P3实测；不能把stream日志当已认证客户端身份。

## 整组Stop实现边界（评审契约，非已实现声明）

- 同一controller拥有sslh、Nginx master/workers、拒绝端点及对应generation runtime；禁止分别独立Start/Stop。
- Stop先持久化manual_stop/desired意图并阻止恢复，然后停止共享/独立入口及存量会话，等待应用自有进程消失，最后释放拒绝端点及证书快照/runtime。TERM有界，必要时仅对所有权已核实的进程执行KILL；不能只杀master或只看pidfile。
- 清理结果必须核对固定procd实例、generation进程归属、监听与已建立连接。未知/超时返回cleanup_unknown并阻止重启或危险端口复用，不宣称已停止。不得采用客户端PID/路径作为清理授权。
- 失败启动、正常Stop、Apply和临时到期均采用同一所有权链。恢复只有一个有界owner，不叠加无界procd respawn；临时截止不续期。
- P0验证的是私有组件退出后无残留与边界评审；P3验证procd集成和多组件readiness，P4验证真实Web/TLS/SSH/TCP存量连接整组关闭、到期及恢复。无需在P0提前编写产品controller。

## 未完成项按阶段归属

| 阶段 | 尚未实现/验收 |
|---|---|
| P1 | canonical v2、显式迁移、冲突图、只读网络发现/RPC、并发保存与序列化 |
| P2 | 四类型原生LuCI、条件字段、双栈地址选择与草稿保护 |
| P3 | 真实TLS/SSH/mTLS、HTTP可信源头、正式私有Nginx及sslh/procd集成、全服务readiness |
| P4 | 概览/Apply/Stop存量连接、临时截止与有界恢复、共存与异常链路 |
| P5/发布前 | 组件安全公告、官方源码签名验证、完整可复现来源关联、许可证与静态库重链接材料、正式包安装字节核对 |

补充组清理/核对必须在实际生产身份切换路径验收；P0只证明UID为65534。libproxyprotocol固定commit归档预期SHA256已补校验；哈希以本轮已下载归档建立，只证明后续一致性，不替代上游签名认证。已解压树与复用libconfig/Nginx的完整独立复现仍未证明，保留发布前风险，不将其伪装为P0阻塞或发布验收通过。

## 本次收口证据

- `evidence/tcp-p0-baseline-confirmed.txt`：实机只读基线，P0_BASELINE_READBACK_OK、退出0。先前因shell JSON引号与无独立/overlay挂载导致的失败保留在final-baseline日志，不当作成功证据。
- 最终构建脚本增加libproxyprotocol预期哈希后再次完整交叉编译退出0；日志`/home/eric/homestun-sdk-check/tcp-ingress-p0/build-p0-final.log`。不执行本地目标测试。
- `evidence/tcp-p0-review-green.txt`：最终脚本连续两轮实机identity通过。`tcp-p0-review-cleanup.txt`：无私有进程/测试监听、目录已删除，三项配置哈希保持。

**结论：P0原任务1–6可关闭。它只批准进入配置实现阶段的技术基线，不批准生产发布、系统包替换或防火墙变更。P1未开始。**
