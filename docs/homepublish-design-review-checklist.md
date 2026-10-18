# HomePublish 最终设计审查清单

> **Current simplified architecture (supersedes historical guard/security gates below):** Lua controller + standard procd dedicated foreground Nginx, ordinary process lifecycle and private permissions; no device C broker/dual guardians/seccomp/memfd/short capability in active package. Normal Stop/temporary/controller lifecycle does not guarantee millisecond hard interruption or independent frozen-controller fail-close. Persisted Stop latch, Save pending, explicit Apply, original temporary deadline and bounded recovery remain. Real device scoped ubus Start/TLS A → Save pending A → Apply TLS B → Stop/keepalive EOF and SDK r3 source binding passed; fixed loopback test profile only. UI Start/Apply still disabled and public production unsupported. Feature3 ACME/DDNS/DNS/Passwall2 integration remains. See [simplified acceptance checkpoint](HOMEPUBLISH-DEVICE-SIMPLIFY-CHECKPOINT.md).


状态：D0文档审查项目；勾选仅表示设计条文已覆盖，**不是实现/测试通过**。基线：[完整设计](homepublish-product-design.md)、[REQ-001～005](../REQUIREMENTS.md)。后续工程证据按D1～D7补齐。

## 产品与交互（设计覆盖）

- [x] continuous持续到停用；temporary可选、默认30分钟/有界自定义；STUN仍有界。
- [x] 默认未发布，Save不Start/Apply/reload，active/saved快照与pending分离。
- [x] 明确开启一次授权，同scope健康维护/恢复不反复确认；扩大服务/scope另Apply。
- [x] 独立boot_restore默认关，开启后revalidate；临時原截止持久，时钟不可信停止。
- [x] 四页/四步向导，Start/Stop/Apply/Check/Verify副作用与角色明确。
- [x] 外网unknown不强制阻止全部manual用户，链接醒目标未验证；硬安全能力缺失仍block。

## 架构和安全（设计覆盖）

- [x] 独立Nginx直接双栈、明确专属router地址，普通路径无通用forwarder、不碰管理。
- [x] IPv4/IPv6/hostname backend，确定IPv4优先，受限resolver/TTL/安全候选snapshot。
- [x] proxy_next_upstream off，无POST等写请求重放；backup只安全选未来请求。
- [x] policy、internal guard capability、UPnP lease、DNS TTL/证书有效期分别定义。
- [x] 独立guardian、有限健康续授权、desired/stop latch/epoch/gen、有限backoff恢复；不旧expired session respawn。
- [x] 精确TCP INPUT的family/address/interface/zone/port与owner/readback/rollback，Save inactive。
- [x] reload门控→同scope reconcile，prefix变化重验GUA、不借网络变化扩大授权。
- [x] UPnP finite same-entry renew提前精确读回tuple/gen/owner，update/delete非原子竞态/超时unknown不blind Add。
- [x] temporary gateway renew不越policy截止；Stop先本地/规则后gateway，残留保port禁fallback复用。
- [x] manual静态上级规则人工维护/风险保留，IPv6许可非DNAT，不NAT-PMP/IPv6 pinhole。
- [x] DNS/ACME candidate受监管、atomic replace/nginx -t/SAN/key校验，失败无fail-open。
- [x] 应用已有鉴权，未认证独立风险复核，TTL非认证；无秘密UCI/argv/status/log。
- [x] read/config/exposure角色和scoped commit；无任意exec/file/service/nft/URL。
- [x] HomeTunnel不动、ACME/DDNS真实边界、CF可选；Passwall2始终开启。

## 证据与后续工程门槛

- [x] 旧120秒仅历史约束，不作为产品上限；历史日志/artifact/hash/实验结论保留。
- [x] schema/接口都是拟议，未冒称新功能完成；默认值明确为设计选择。
- [x] 分阶段迁移/回退默认关闭，matching SDK/真目标不host替代。
- [ ] UPnP库/安全same-entry与Delete受控网关契约实证。
- [ ] native双监管续授权/失控时间预算/guard故障真目标验证。
- [ ] fw4 hooks/owned链/reload门控、目标procd controller恢复和rpcd scoped权限实证。
- [ ] 四种入站/后端组合、主/旁双栈、INPUT rollback/foreign/renew/boot/Stop/expiry完整TDD矩阵。
- [ ] DNS/ACME安全交接及Passwall2目标版本的回程/DNS/reload共存。
- [ ] matching SDK/IPK/TARGET_CC/权限/直接provider/source binding、真BusyBox/procd/fw4。
- [ ] 获具体操作授权的独立外网CA/hostname/marker/持续流、停止/临时断流/续租及精确清理读回；IPv6外网可独立后验。

D0静态核验只检查内容、链接、空白diff和历史保护，不运行代码/SDK/公网测试。未勾选工程门槛不得被历史PASS或文档勾选替代。
