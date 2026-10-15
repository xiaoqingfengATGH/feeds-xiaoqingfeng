# HomePublish TCP入口 P0 检查点

## 当前状态

REQ-007已登记。**P0原计划任务1–6已收口，P1业务实现未开始**。逐项结论与后续阶段归属见[退出清单](HOMEPUBLISH-TCP-P0-EXIT.md)。下文保留分轮历史记录；“P0余项”等描述只代表当轮状态，不覆盖退出清单。

本轮检查的worktree为 `D:/DevPortal/homelede/homepublish-product`，分支 `feature/homepublish-product`，HEAD `7db4c1f`。这是现有隔离工作树，保留此前证书列修复和TAB更名；不新建空工作树丢掉这些修改，也未切换到master或整合其他分支。本轮未fetch/commit/push。

## 实机证据

- 目标：既有测试设备 `root@127.0.0.1:222`，Homelede x86_64，Linux 6.18.55。
- 脚本：`homepublish/tests/device-tcp-prerequisites.sh`；scp到 `/tmp/homepublish-tcp-prerequisites.sh`，在设备用sh执行并删除。
- 原始日志：[device prerequisite output](evidence/tcp-p0-device-prerequisites.txt)。真实SSH命令退出码2。
- `SSLH_MISSING`：sslh-select/sslh均不在PATH；已装包查询无sslh。
- `NGINX_STREAM_BUILD_OPTION_MISSING`：Nginx1.21.3仅有HTTP/TLS，无with-stream配置；检查的常规模块目录未找到模块。
- 实际网卡br-lan：192.168.1.2/24、fd89:878e:a47f::1/60，无可见GUA。只可完成设备IPv6链路验证，不能宣称公网IPv6验收。
- 443实际被dropbear PID36655监听，管理22为PID34089。绝不能按“443通常空闲”默认占用；测试端口必须另选。
- uhttpd80 PID4308、xray PID16371存在。本轮未停止或重载它们。
- `ubus call service list '{"name":"homepublish"}'` 返回空对象；enabled=0。此前直接 init status 触发 product-channel.lua:31 connection refused，这反映controller不在运行，不是新功能回归；本轮未启动。
- 脚本前后firewall/network/homepublish配置SHA256逐项相同，见原始日志。

## 技术门禁处置方案

不全局替换系统Nginx，不运行现成sslh init（可能默认监听443）。优先准备应用私有路径的目标架构二进制，在loopback高端口验证；这与日常不编IPK不冲突，依赖二进制仅首次准备。

- sslh优先select构建，固定源码版本和哈希；本阶段不因此宣传UDP。
- Nginx stream需兼容模块或独立精简二进制。当前没有stream且版本较老，禁止将其他版本动态模块硬加载进系统Nginx；优先应用私有独立二进制，不覆盖`/usr/sbin/nginx`或`/etc/nginx`。
- 首先实测未知协议、无SNI、未知SNI、空连接超时。明确指定拒绝目标，不能信任默认fallback。
- 使用隔离后端/测试证书、loopback入口验证sslh识别与IPv6→IPv4，关闭并核对进程/端口后再进入下一阶段。
- 若准备组件需要安装系统依赖、替换全局包或开放非loopback监听，必须先报告具体范围并取得授权。

### 上游对照（仅源码结论，不是实机验收）

- https://raw.githubusercontent.com/openwrt/packages/master/net/sslh/Makefile ：当前2.1.2，默认fork，select需SSLH_SELECT，依赖libconfig/libcap/libpcre2。
- https://raw.githubusercontent.com/yrutschle/sslh/master/example.cfg ：TLS支持sni_hostnames；on-timeout默认SSH，可另设timeout目标。select有连接上限配置。master不是固定发布版本，正式构建必须再次核对所选tag。

## 接续顺序

1. 准备私有sslh/Nginx stream依赖，明确不触碰现有管理进程；交付源码版本/哈希/目标ABI。
2. 完成P0真实转发/拒绝门禁并保留请求、后端标记、清理记录。
3. 通过后冻结schema v2及RPC错误码再进入P1，不先放宽现有canonical或添加不能运行的服务选项。
4. 沿用详细计划的P1-P5；按每阶段完成停等用户指令。

## 最终实机探针结果（本轮授权范围）

用户补充授权：准备并上传私有组件，仅loopback高端口，不替换系统包。

- 构建脚本`homepublish/tests/build-tcp-private-components.sh`，OpenWrt SDK GCC13.3/musl静态交叉编译，未执行本地目标测试。使用SDK交叉编译补丁，避免Nginx configure运行目标探测程序。
- sslh选用上游v2.1.2 tag对应commit `e831b732dbd239d7805ec8ec113a926f0a9271b6`，libconfig1.7.3，SDK缓存Nginx1.26.1仅stream。此Nginx是隔离验证夹具，不作为生产版本定版或安全审计通过。
- 构建产物保存在`D:/DevPortal/homelede/artifacts/homepublish-tcp-p0/`，含源码/二进制SHA256及build.log。
- 实机脚本`homepublish/tests/device-tcp-p0-probe.lua`：两个SNI目标、SSH探针、独立stream服务端先发、分段ClientHello、无SNI、未知SNI、未知协议、空连接超时，最终9项PASS，进程退出0。真实输出见[evidence/tcp-p0-device-probes-final.txt](evidence/tcp-p0-device-probes-final.txt)。前次mkdir参数错误保留在初次日志，已修正，不伪造GREEN。
- 拒绝路径使用**bind但不listen的保留端口**，不是简单假设某端口空闲。所有未知流量明确走anyprot；超时同样指定anyprot，连接被拒且没有业务marker。最终实现必须由应用生命周期持有此端点，否则不能依赖固定“空端口”。
- sslh打印`Landlock: Failed to create a ruleset`但继续工作。源码landlock.c在create_ruleset失败后直接return，未实施沙箱；不能声称具备Landlock隔离。后续标准procd最小权限路径不依赖此可选能力。
- 所有测试监听为::1/127.0.0.1的49300–49309，不使用443，不写防火墙。
- 探针回收子进程；读回netstat无测试端口，ps无探针/私有sslh/nginx；删除临时目录后test确认不存在。管理22/443 Dropbear、uhttpd、xray PID保持，三个配置SHA256与初检一致。见[evidence/tcp-p0-device-cleanup.txt](evidence/tcp-p0-device-cleanup.txt)。

此结果证明组件识别/跨族转发路径可行，**不等价于TLS完整握手、SSH认证、业务证书、公网IPv6、真实IP传递、procd多进程停止及产品集成验收**。P0余项是契约冻结、PROXY协议/非root运行边界与独立审查；P1配置/UI尚未开始。本轮隔离验证切片到此交付，继续保持本阶段不自动进入P1。

## P0补充：源地址与非root实测

本轮补充脚本`device-tcp-p0-identity.lua`及`build-tcp-identity-components.sh`。真实设备先以旧2.1.2执行失败：配置proxyprotocol被报告Unknown settings，内部Nginx拒绝缺PROXY头的握手，退出1，见`evidence/tcp-p0-identity-red.txt`。这纠正了之前把master能力等同2.1.2的潜在误判。

升级候选为固定sslh2.3.1源码commit d39388d1edcc9fe7a35449fc5c23d222d20d6f81，libproxyprotocol1.3.3源码commit 3e133b9602e59f47ceceef74fbd52a3b147e5874；仅私有夹具，无系统安装。库/消费者一致-fshort-enums ABI，产物/构建日志在`D:/DevPortal/homelede/artifacts/homepublish-tcp-p0/identity/`。许可证重链接风险纳入契约，不作为发布包。

最终identity测试5项PASS、退出0：两进程四个UID均为65534；IPv6入口经sslh PROXY v1→IPv4内部Nginx消费头后后端收到原TLS首字节；SSH不插头；外部伪造PROXY请求不进入业务；Nginx日志同时记录原始::1与实际代理127.0.0.1。见`evidence/tcp-p0-identity-green.txt`。这不代表HTTP头可信链或真实TLS认证完成，正式内部HTTP监听不得扩大到非loopback，本机恶意进程不在此身份验证边界内。

新2.3.1再次执行原9项路由回归，退出0，见`evidence/tcp-p0-sslh231-regression.txt`。回收端口、遍历/proc确认无夹具可执行进程、原配置哈希相同、临时目录删除并读回，见`evidence/tcp-p0-identity-cleanup.txt`。

配置及RPC设计冻结在[HOMEPUBLISH-TCP-CONTRACT-V2.md](HOMEPUBLISH-TCP-CONTRACT-V2.md)。保持数字schema_version=2、四类型判别联合、显式双栈绑定、Save不发布、原截止不延长、完整v1迁移预览及稳定错误码；这是P1实施契约，尚未宣称运行端支持。

独立审查已返回，三个中级问题已修复：身份日志每轮清空并核对本轮唯一成功记录，加入“旧正确+新错误”断言反例；先终止/reap全部子进程再释放拒绝socket；消费者make clean后完整重编。重跑还发现fixture后端重复绑定与子进程错误被吞问题，已加SO_REUSEADDR（nixio要求整数1）和子进程错误输出。最终连续两轮identity均退出0、每轮仅一条正确200身份记录，见`evidence/tcp-p0-review-green.txt`；失败探索日志保留，不以旧GREEN覆盖。最新清理读回见`evidence/tcp-p0-review-cleanup.txt`。`git diff --check`退出0。

补充组最小化、依赖预期哈希/全新源码树重现性仍是正式发布前明确债务；本切片只证明UID非root和loopback元数据链，不声称生产最小权限/供应链验收。P0配置/RPC契约已形成实施基线，未进入P1；完整HTTP realip/证书/procd生命周期仍由P3验收。

## 未完成项

完整TLS/SSH会话、HTTP源地址可信头、procd运行、schema v2业务实现、LuCI新控件、数据面与生命周期均未验收。此检查点不可标“开发完成”。
