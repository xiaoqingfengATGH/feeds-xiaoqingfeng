# HomePublish 访问配置向导本地验收

## 当前功能入口：访问配置向导与分层状态（本地完成，非生产激活）

服务/域名/证书 → 接入方式与策略 → canonical 只读预检/Save → 独立 Start 与分层结果为同页四步向导，前后导航保留输入；保留服务及双栈监听增删编辑。旁路由 manual IPv4 优先；direct IPv6 路由/入站许可非 DNAT；UPnP/STUN 只保存现有 schema 允许方式，明确适配器未接入、不执行映射或实验。生产 Start/Apply 继续 disabled/unsupported、activation_ready=false。

概览轮询真实 status 的 saved/active/pending/attempted/candidate、内部 phase/active_verified/generation/readiness/cleanup、recovery attempt_count(预算3)/next_retry/reason、原 deadline、saved/active boot_restore、restore stage/clock/boot_id；外网 IPv4/IPv6 始终未验证，无假网络探测。Stop 原合同不变。

验收：真实 Windows Chrome → 官方 LuCI loader → loopback uhttpd/rpcd/ubus → fixed CLI/native journal。RED `wizard-red.log` 缺 hp-wizard-step 超时，make 非零（包装 shell rc 打印错误，不以包装 rc 作为 make 证据）。GREEN `wizard-final.log` browser exit0；只读 validate 不改 revision0、Save revisions1/2/3、两服务/双栈/UPnP gateway readback、back steps 未保存输入保留、reload、编辑/删除、duplicate/empty canonical 禁保存、pending 无 active、独立 Start 禁用、分层未知外网及 DOM Stop latch 全部 PASS；owned processes/mounts/listeners=[]、fixture directory_absent=true。普通 WSL 用户 `make product rpc` exit0，日志 `wizard-product-rpc.log`。日志在 `/home/eric/homestun-sdk-check/`；localcommit 后另跑 `wizard-committed.log`，结果由最终交接读回。

剩余功能：production provider/Start/Apply 权威 adapter、fw4/UPnP 有限租约、DNS/ACME/Passwall2 集成、真实 procd/BusyBox/matching SDK 和目标部署验收；SSH127.0.0.1:222 未恢复、不重试。安全统一复评留后，不展开安全深化。没有生产安装/fw/映射/公网/push/merge/PR。内部恢复/Nginx功能沿用已验切片，不把 UI 生产 unsupported 状态说成 running。

