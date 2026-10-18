# HomePublish TCP P5 收口独立审查

## 结论与审查边界

**P5 仍未达到无保留完成；旧审查的生产 provider 缺失已被后续证据覆盖，不能继续列为当前缺陷。** 当前主要门禁是 S2 双 Web 域名/证书链、最终 Lua-store 候选的四协议普通 LuCI 成功链、完整包来源/内容验收和最终文档一致性。公网与安装/升级必须保持单独授权，不能通过擅自执行来关单；本报告不新增 P6。

本次仅独立读源码、读取现有证据、解析矩阵 JSON，并以严格主机校验 SSH 只读检查 192.168.1.2。没有启动/停止 runtime、修改 live 配置、运行生命周期测试、构建/安装、commit/push。父任务正在处理 UI/其他回归，另一 owner 负责构建；**其尚未归档的结果不在本报告通过结论内**。

工作树基线：HEAD `ee996bc8b9c16a49a88e4e5a984b1bc0e67a9a9c` 加既有未提交 Lua-store/Makefile/测试修改，不是该 HEAD 的干净发布来源。

## 证据优先级与历史覆盖

依据：冻结计划 `.hermes/plans/2026-10-15_143056-homepublish-tcp-ingress-luci.md` S1–S8、tasks28–32、最终清单289–301；入口 `docs/HERMES-HANDOFF.md`。证据以具体运行/源码 hash/读回为准，不按文档名中的 final/green 猜成功。

| 原结论 | 当前判定 | 可核证据 |
|---|---|---|
| P5-REVIEW B1：仅固定 profile，无生产 provider | 已由后续生产切片证据关闭；不再作为当前 blocker | `HOMEPUBLISH-TCP-P5-INTEGRATION.md`、`four-production-lifecycle-attempt.json`、`four-complete-final2.log`、`final-matrix-final.log` 及 parent 日志；固定正式 provider + 私有 journal，不是扩 fixture 白名单 |
| H1：真实 session ACL 完全未验 | 方法级门禁已验；角色映射/完整四协议普通页面成功链仍未全部证明 | `production-and-rpcd-final.log`；`ordinary-ui-run5.log`/`ordinary-ui.json` 是真实 HTTP ubus HTTPS 成功链，不是 P4 SSH 桥 |
| H2：仍用 Nginx1.26.1 | 旧版本问题不再代表实际主路径；安全维护闭包仍需签收 | `HOMEPUBLISH-TCP-P5-PACKAGING.md` 顶部版本/来源/公告适用性、`evidence/tcp-p5-packaging/`；本次实机 Nginx1.30.6/hash 相符 |
| Lua 迁移尚未切生产、fault/并发读待验 | 已被新证据覆盖，不能照抄旧 checkpoint | `evidence/lua-store/live-switch-experiment.md`、`parent-resume-final.{json,log}`、`parent-concurrent-reader.log`；本次 controller/maps/hash 读回 |
| final-matrix-green.log 是通过 | 否，该文件是失败尝试 | `HOMEPUBLISH-TCP-P5-FINAL-MATRIX.md` 明确最终使用 final-matrix-final.log；当前结果 JSON 又已由 Lua-store 实验复跑覆写，需与该实验区分 |

`HERMES-HANDOFF.md:14`、`HOMEPUBLISH-LUA-STORE-MIGRATION.md` 中“未切换”段、P5-INTEGRATION 内较早“仅 HTTPS”、PACKAGING 后半旧 C/旧依赖表均是历史阶段描述。最终整理需显式加 superseded/当前入口，不能改写失败历史。

## 本次实机只读读回

目标时间 `2026-10-16T21:26:07+08:00`，OpenWrt24.10.5/HomeLede x86/64，hostname HOMELEDE。

- journal `/etc/homepublish/product/state` SHA256 `6995a844e18ac2c9182b3e4f8035138ebe561aee168530d43c550d5ee14be7d1`，两次读取相同；与 live-switch 保存基线一致。本次未执行 journal 解码；rev3/intent10/手动停止状态来自 live-switch 与迁移账本，不冒称独立重解码。
- `product-store-core.lua` SHA256 `3fbc1531e19bbac954402ac39dc1e96740af60ebc8e8260ed919011303243a7c`；wrapper `69d87c25cc96afe529751d8855a69eb8ce0cc6f27e6fa9f7c0aabb50d3ce72c6`，均与本地原始字节 hash 相符。provider 实机 hash `77d5eb762ad2beb2182a6bc6b4288169c6a0086e96f0391d921cce8c58a1f41b`。
- idle `homepublish/controller` PID88890 running；该 PID maps 没有 homepublish_store。`homepublish-runtime` service `{}`，`/tmp/homepublish-runtime` 与 `/root/homepublish-p5/matrix-auth` 不存在。
- `/etc/homepublish` 与 product 目录 root0700，state root0600。旧 `/usr/lib/lua/homepublish_store.so` 仍在磁盘 root0644，**保留回滚不等于运行依赖**。
- 私有 nginx SHA256 `941b54d84fc4fd40b0257e42195899f0bd77895ec0486e3e263344c2fa8dc08a`；sslh `1b9746f96d31624eb2cfa4076ca7eb0b636979321dbec92947171f780ee38db7`，与组件账本相符。`nginx -V` 为1.30.6，HTTP SSL/realip + stream SSL/preread；构建 OpenSSL3.0.18、运行 OpenSSL3.6.4。不能把构建头文件版本误称正在加载的库版本。
- 首次 `stat` 不存在，未将该子命令计作通过；改用 `ls -ldn` 取得上述权限。其余只读项成功。没有观察本轮动态运行 UID/limits，因为 publication 已停，不为获取它而重启。

## S1–S8 证据映射

| 场景 | 已有证据及适用范围 | 仍需收口/不能外推 |
|---|---|---|
| S1 IPv6 HTTPS→IPv4 HTTP | `final-matrix-results.json` v6→v4，system CA+hostname marker；P3 task20 HTTPS upstream 正反例；ordinary UI HTTPS 成功链 | Lua-store 最终候选普通页面重验待父任务；设备本机访问 LAN/ULA 不是公网客户端 |
| S2 多域名 Web/继承覆盖 | renderer/证书模式 UI 有历史正例 | **未完成**：最终双域名、两条证书身份链、同口不串线；现有 RSA/ECC SAN 都仅 home.iwonderful.top |
| S3 TLS/SNI/mTLS透传 | P3 `task20-through16-stage-final.log` mTLS/指纹；P5 `four-complete-final2.log` 非HTTP payload、无/错SNI拒绝；新矩阵 opaque TLS | mTLS历史证据须标版本，最终 Lua 候选如有相关代码变化须定向重验，不把 readiness handshake 当应用认证 |
| S4 HTTPS+TLS同口 | P5 complete 与最终矩阵四协议混合、精确流量 | S2多Web未覆盖；内部PROXY本机信任边界需接受说明 |
| S5 原生SSH | complete 私有Dropbear真实公钥认证；矩阵 forced marker；系统authorized_keys不改 | fixture 客户端跳过临时hostkey检查不代表产品可忽略SSH身份校验；不发布设备管理SSH |
| S6 独立TCP v6→v4 | P3双向8192字节/双方先发/半关闭；P5真实独立TCP echo与Stop | Lua候选矩阵不单独证明所有旧半关闭/服务端先发用例重跑 |
| S7 地址族/LAN | 当前JSON前四case v4/v6入口×v4/v6后端；后三case无HTTPS仍正常 | 这七case**没有单case双栈同时绑定**证据；须检索/补最终生产双栈两socket同时可达，不能把四case组合当双栈同时运行 |
| S8 冲突/未知/超时/Stop/到期/共存 | P3 task21 identity/cleanup unknown，P4 task24/25/27 生命周期/负例/慢握手，P5 complete missing TLS拒启/held HTTPS TLS Stop，ACL方法拒绝 | 最终Lua候选到期/恢复/冲突及管理代理共存回归待父任务核；物理reboot、代理reload共存不在现有通过证据内 |

本次程序读取当前 `final-matrix-results.json`：精确7条，逐条 all_ready=true、traffic=true、cleanup=confirmed。其内容与 live-switch 所述七case一致；未在本次重跑，也没有将 JSON 文件自身当带完整来源的不可变 run artifact。

## 阻断项：可执行收口清单

| ID / 阻断对象 | 下一步与 owner | 关单验收物 |
|---|---|---|
| C1 S2，冻结场景290 | 父任务协调用户提供第二域名有效证书或明确授权独立测试CA/fixture方案；不得自签冒充系统CA、跳hostname、改ACME/DNS。两个精确Web域名同入口分别默认继承/服务覆盖；指定SNI+Host核marker、证书SAN/指纹、Save/Apply/Stop | 独立run-id配置摘要、源hash、逐域名TLS验证、marker不串线、证书权限/hash保持、Stop清理；无法获证书则明确P5条件未满足，不转P6 |
| C2 清单289，最终Lua候选普通四协议成功链 | 父任务从真实已认证LuCI→/ubus→rpcd→CLI→controller；保留svc_1，复用/显式添加不冲突服务。Save不启动/不换active；Start/Apply真实流量；Stop已有会话EOF；刷新与未保存草稿不丢 | 无route拦截/SSH桥的脱敏响应及DOM、四类型流量、journal revisions/manifest、管理基线和清理。旧HTTPS/native-store普通UI不代替当前全链 |
| C3 最终候选回归闭包，tasks29/清单290/296/300 | 父任务按改动影响重跑目标设备store+CLI错误分类、Stop/到期/手动锁/恢复/失败清理、关键冲突和管理共存；确认S7双栈同时绑定。无需无界压测或擅自reboot | 每项当前source hash/run-id/退出码，旧证据复用给出未变文件依据；至少两个显式socket实际连接，不能只列schema |
| C4 包与依赖/来源，task30 | 构建owner冻结实际dirty snapshot或获准commit，构建homepublish/engines/LuCI，解包检查control/data/权限/conffiles/Depends/NEEDED/源码许可材料；新包不编/不带自有store.so，不带fixture/keys/live state；release来源可区分 | 不可变source与IPK SHA、逐文件清单、版本/架构/依赖闭包、产物来源映射。仅nixio包/组件ELF构建不关单。安装升级未获准则保留“未安装”，不得宣传安装验收通过 |
| C5 自有C退休与runner安全，Lua替换约定 | 实现owner确认C源码删除范围、迁移/历史测试归档或改造；所有可能执行runner先确认固定Lua私有root，未隔离则在try/finally前fail closed；不得仅设置package.cpath | 仓库搜索/构建输出无活动native-store编译依赖，旧runner明确禁用或改造；真实负preflight不碰live journal。磁盘rollback .so可保留并披露，不是必须危险删除 |
| C6 最终安全/文档签收，tasks28/31/清单301 | owner固定本轮组件/传递库公告适用性与安全维护责任；更新handoff/需求/设计/checklist/REFACTOR/操作说明为当前Lua状态与验收范围，保留历史 | 有日期/来源的依赖判定，源IP非认证/外部IPv6与上游许可/独立TCP不加密/精确绑定/应用鉴权责任说明；本报告未联网刷新公告，不能宣称最新全部CVE排除 |

C1–C6是“无保留P5收口”的不同门禁，不全部等价于可利用安全漏洞。构建或父任务稍后产生新证据时逐项更新状态，不用“其正在做”关单。

## 非阻断风险 / 单独授权边界

1. **M1本机PROXY信任**：`sslh-renderer.lua:35–37` 实际信任127.0.0.1来源，不是sslh进程身份。低权限本机进程有条件伪造转发源IP；非互联网直接漏洞。应修正过强注释/文档，禁止后端据源IP单独授权。若威胁模型必须抵抗恶意本机进程，再授权隔离复现/约束，不要求引新guardian。
2. **资源最小权限**：`product-procd-group.lua:50–53` 未显式uid/group/rlimit；有P4 24慢连接/FD回落证据，不是任意并发抗DoS保证。本轮不运行publication，未获取其实际UID/limits。有限部署可记录风险，不把HAVE_LANDLOCK/HAVE_LIBCAP编译能力当运行隔离。
3. **Lua文件边界**：core固定生产root，0700目录/0600文件/root所有者、短锁、排他candidate、rename和冻结公开错误；现有真实fault/read/concurrent-reader证据已补，不再称待测。仍非native openat/inode身份同等保证，不承诺对root篡改/所有ancestor替换防护，也不承诺断电强持久性（未目录fsync）。这是声明边界，不是已证实远程提权。
4. **外网、独立LAN端、物理reboot、代理reload**：缺实测不应擅自执行；公网按task32允许标“实机v6→v4通过/公网未验证”，本身不要求阻塞获准范围内P5候选交付，但绝不能宣传公网已成功。物理reboot未验也不得由mock恢复测试替代。
5. **用户名→LuCI角色映射**：已验短期精确session方法ACL，不等于真实用户名只读角色映射。若不交付该角色功能，可作为明确限制；若要宣传只读用户支持，必须另做真实登录/角色回归，不新建用户或改auth来凑证据。
6. **系统Nginx fallback**：`product-system-provider.lua:5` 私有引擎优先但仍有系统路径fallback；包依赖应保证私有引擎存在，不能把目标系统旧Nginx视安全批准的后备。缺失私有引擎的发布能力与错误需在最终包门禁记录。

## ACL / 注入静态复核

- ACL恰列read六方法、write四方法，无任意ubus/file/UCI授权；RPC shell case白名单固定Lua文件，客户端不能提供provider/store-root/可执行路径。root SSH检查ACL注册/文件不代替session拒绝证据，后者使用已有真实HTTP日志。
- `product-provider.lua:6` 使用固定source下wrapper，wrapper固定`/etc/homepublish/product`；`core.new(root)`只是可信内部工厂，不能仅因参数化工厂报RPC任意路径漏洞。
- `product-procd-group.lua:4` shell单引号转义、固定服务名/owned runtime、snapshot目标固定pem，源路径限制字符且拒绝`..`；Stop比对完整procd command与PID starttime后才删自有root。不按字符串命中数报注入；本次未发现已证实的RPC任意shell执行路径，也未声称做了动态fuzz全覆盖。
- 旧runner实际仍有`test-controller*.py`、`test-product*.py`、`test-rpc.py`、`rpc-luci-fixture.py`编译product-store.c，`test-package.py`/`test-ipk.py`仍要求.so；P3/P4 runner也仍上传native fixture。这既是维护缺口，也是误跑写live journal风险，须由C5处理。它不说明当前生产加载了C。

## 建议执行顺序

先固定当前baseline/协调串行端口 → C1证书决策与C5 runner隔离 → 父任务C2/C3真实目标回归 → C6文档和安全签收 → 构建owner C4不可变包/内容核验 → 仅在另获许可后安装/升级或外网验证。测试结束保留服务/journal和非秘密配置，只清自有运行/短期秘密；禁止恢复历史rev1覆盖当前rev3。任何缺口不能完成时，在P5交付结论显式列未关闭与原因，不能凭本报告宣告P5完成。
