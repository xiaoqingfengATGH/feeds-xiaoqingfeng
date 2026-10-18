# REQ-007 配置与RPC契约 v2（P0冻结基线）

状态：设计契约，不代表已实现。现行schema_version=1及已安装RPC继续工作；只有P1完成迁移/校验/回归才启用v2。禁止客户端直接把本文示例发给旧save。

## 1. 顶层模型

保持现有数字版本字段，使用`schema_version: 2`，不另加重复字符串schema版本。顶层白名单：schema_version、services、access_profile、publication_policy、default_certificate_ref。服务0–16项；空服务可保存，不可Start。对象拒未知键，数组须稠密。标识符沿用当前canonical限制；端口为整数1024–65535（保持非root高端口约束，不悄悄开放1–1023）。

`access_profile` v2仅有`listeners`，数组1–2项，每族至多一个共享绑定。每个listener：

| 键 | 含义 |
|---|---|
| listener_id | 稳定身份，非数组位置 |
| family | ipv4 / ipv6 |
| network | 用户选择的真实逻辑网络名 |
| address | 该网络上精确单播地址，不含前缀；IPv6裸地址 |
| port | 共享TCP端口，双栈两项须相同 |

设备名/zone不能由浏览器作为可信事实写入。运行计划通过只读inventory解析network→device→zone，在预检时绑定当前实际设备/地址/区域及inventory摘要；缺失/多义则阻断，不猜测wan。zone变化、地址消失在Start/Apply/recovery重新检查。IPv6显式ipv6only=on；不接受通配、loopback、link-local、mapped地址。允许ULA但标内网；公网验证另记。

只有独立TCP服务时仍保存基础bindings，但不创建无人使用的共享socket。TCP服务的独立端口沿用每个binding的network/address/family，替换port；不增加同义interface字段。不支持给每个服务手工拼任意入口。

## 2. 服务判别联合

所有类型共有：service_id、name、enabled(boolean)、type、backend、authentication_review。后者保留authentication=confirmed/unconfirmed与management=boolean既有契约，不能自动确认。展示需要自然文案，不暴露内部字段名。

`backend`保持现有地址与范围语义：addressFamily(ipv4/ipv6/hostname)、host、port、allowed_ranges、可选backup。端口1–65535；后端hostname仅DNS A-label，不能含URL/路径。地址族UI自动推导，保存端仍显式携带并校验一致。家庭地址限制与allowed_ranges保留，DNS所有候选Start时校验，Save不发网络请求，不把新增解析结果自动加入范围。backup不代表重放请求许可，非幂等请求禁止重试。

| type | 专属字段 | 禁止字段 |
|---|---|---|
| https_proxy | hostname、upstream_scheme(http/https)、certificate_mode(inherit/override)、override时certificate_ref；https时upstream_tls | listen_port |
| tls_passthrough | hostname（精确SNI） | 本机certificate字段、upstream_scheme/upstream_tls、listen_port |
| ssh | 无专属字段 | hostname/certificate/upstream_tls/listen_port |
| tcp_forward | listen_port | hostname/certificate/upstream_tls |

HTTPS inherit不在保存模型冗余存解析后的certificate_ref，只保留mode，运行计划解析default_certificate_ref。默认/override证书引用沿用现有acme/import身份，RSA/ECC分开；缺失或过期等可保存为待完善状态，Start必须阻断并定位到服务。证书域名与服务域名不要求相等，按SAN覆盖校验。

`upstream_tls`固定verify=true、server_name为DNS A-label；使用系统CA，不提供任意服务器文件路径或insecure选项。即使backend是IP也必须有明确server_name，不能对IP回源自动关闭验证。此为本阶段必实现路径，尚未实现时必须报告unsupported，不能静默按HTTP运行。

域名路由仅精确匹配。对所有保存条目检查重复service_id；所有有域名条目检查归一化后重复域名（包含禁用项，避免启用时暗冲突）；每入口最多一个SSH。TCP独立端口不得等于共享端口、不得与其他TCP服务重复（同样包括禁用项）。用户保存两个暂时冲突的草稿需先编辑为不冲突，不依赖顺序优先级。

证书字段、域名字段不会为SSH/TCP自动生成。类型切换由客户端草稿清掉不适用字段；后端拒绝残留未知/错类型字段，而不是静默接受再忽略。

## 3. 策略与控制状态

publication_policy沿用mode=continuous/temporary，boot_restore默认false。temporary_duration=60–86400秒，仅temporary有效。保存时长不改变当前expires_at；Apply/recovery保留原截止。新期限只由先Stop再显式Start的新会话产生。

保存、活动、期望状态分离：saved_revision/config、active_revision/config、generation、pending、desired、expires_at、manual_stop_latch；保持当前store/controller已有字段实际名称，P1不得为了改JSON外观重写日志存储格式。服务状态必须按service_id且绑定generation，aggregate就绪不能替代逐服务就绪。

Stop先持久化意图，后关闭所有应用自有组件及已建立连接。读取失败返回unknown，不以false/空数组表示停止；清理失败与启动失败分开。恢复只有一个有界owner，普通procd不增加无界respawn。

## 4. RPC扩展（现有方法签名不变）

- status {}：现有返回继续兼容；新增schema_versions=[1,2]需等真实v2支持；未实现时不可发布能力。
- certificates {}：只读库存，增加usage不暴露私钥路径/内容。
- validate {config}：纯结构/语义校验，不DNS、不启动、不存盘。
- save {expected_revision,config}：并发校验、持久化；不Start、不全局apply。
- start/apply {revision,approved:true}：仅使用已保存且对应revision配置；预检重新解析网络、后端、证书、端口占用，不能相信旧预检。
- stop {}：对失败/残留可调用，不接受PID/path/generation作为任意清理授权。
- 新增network_inventory {}：只读，固定逻辑网络与当前地址/设备/区域关联；不接受ubus方法名/任意路径；独立scoped ACL。
- 新增preflight {revision}：检查保存版本，返回blockers/warnings、预期端点/服务/地址族/源地址策略与inventory摘要，不启动。不提供approved保存，不持有启动租约；Start必须重检。

统一错误结构新增`error_code`、`field`、`service_id`（可选）、`retryable`，保留既有error字符串供旧UI。不得返回堆栈、任意文件内容或密钥。错误码至少：INVALID_CONFIG、UNSUPPORTED_SCHEMA、REVISION_CONFLICT、NO_ENABLED_SERVICES、DOMAIN_CONFLICT、SSH_CONFLICT、PORT_CONFLICT、NETWORK_UNAVAILABLE、ADDRESS_UNAVAILABLE、ZONE_AMBIGUOUS、CERTIFICATE_UNAVAILABLE、CERTIFICATE_COVERAGE、BACKEND_OUT_OF_SCOPE、DEPENDENCY_UNAVAILABLE、STATE_UNKNOWN、CLEANUP_UNKNOWN。field为固定模型路径而非HTML。

## 5. 迁移

v1→v2由显式migrate_preview（P1内部函数，非直接写库）输出proposed_config、warnings、blocking_issues；用户确认后以原revision经save提交。自动识别v1并直接改存盘禁止。

- 原服务转换https_proxy，原回源默认http，原certificate_mode/ref语义保留（inherit去掉冗余解析引用）。
- 原listener完整遍历，不能只取第一个。interface必须从实机inventory确认是逻辑网络还是设备；无法唯一反查network则阻断迁移让用户重选。
- 同族多listener、不同共享端口、非手动/IPv6接入方式、UPnP/STUN旧配置：不截断/删除；预览明确阻断并保留原v1。不得为使v2通过悄悄丢第二项。
- external_port不进v2运行模型，原值仅保留在应用拥有的迁移备份及预览；不操作上级映射。
- 保存前原配置备份在应用拥有的私有路径，失败仍可读v1。没有不可逆DB变更。

## 6. 数据面与源地址边界

候选固定sslh2.3.1（commit d39388d1edcc9fe7a35449fc5c23d222d20d6f81）+libproxyprotocol1.3.3（commit 3e133b9602e59f47ceceef74fbd52a3b147e5874）。2.1.2不具备PROXY能力，不能作为混合Web入口依赖满足项。启动前实际能力检查，不以版本字符串代替。

- 共享入口不接受客户端PROXY头。仅sslh→内部Nginx HTTPS分支启用PROXY v1，内部监听仅loopback，不能作为可信公网入口。
- SSH/TLS透传/普通TCP默认不发送PROXY头，后端看到代理IP；不承诺原始IP透明保留。
- HTTP反代需Nginx HTTP realip模块、精确信任实际内部代理地址、重建可信X-Forwarded-For及X-Real-IP。loopback不是密码边界：其他本机进程可连接并伪造PROXY；普通OpenWrt本机权限模型接受此边界，不宣传抗本机恶意进程。此HTTP链在P3完整验证，P0stream日志只证明元数据到达。
- 未识别与超时明确拒绝，不依赖不存在的固定后端端口。P0保留拒绝socket仅证明可行；正式provider需应用自有拒绝端点并做readiness/lifecycle覆盖。
- 高端口可直接以非root运行；低端口不在当前canonical范围。Nginx私钥读取可按标准root master＋非特权worker处理，不引入broker。P0未证明证书访问/procd整合，不能照搬fixture的nobody拥有整个目录到产品。

## 版本选取规则（用户补充）

sslh优先选取上游最新稳定版，不以OpenWrt旧包版本为默认，也不追master/RC。每次准备发布依赖时核对上游正式下载页与tag，固定版本、commit和源归档哈希，再跑实机回归；若最新稳定版存在目标兼容性阻断，记录具体原因再决定回退，不静默降级。

本轮重新读取官方 https://www.rutschle.net/tech/sslh/download.html ，其最新下载项为 **2.3.1**，与刚完成私有构建/实机验证的版本一致；因此继续采用2.3.1，不回到2.1.2。GitHub releases/latest接口返回404不能解释成无稳定版，tag网页提取也可能不完整；正式下载页已提供2.3.1及签名链接。此次固定commit归档已拉取，未验证官方签名，不宣称签名验证通过。

## 7. 后续验收与风险

P1必须设备RED→GREEN验证v2正常四类型、稠密数组、未知字段、域名归一化、端口/SSH冲突、隐藏字段、v1预览不丢数据、并发保存与Save不Start。P2才能发布实际能力控件。P3必须真实TLS/SSH、HTTP可信源头、mTLS透传、procd所有进程/会话整组Stop。

P0私有Nginx1.26.1只是stream夹具，不能作为生产依赖冻结或安全公告审查完成。静态libproxyprotocol为LGPLv3+，若分发需完整许可证/对应源代码/重链接产物或改动态链接并审查包契约；P0不分发IPK，不据此宣布可发布。
