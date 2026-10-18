# P2 原生 LuCI 检查点

基线 a74c65b，feature/homepublish-product；仅 P2，无 commit/push/merge，无网络、防火墙、凭据或数据面修改。

## 已确认
- 已读阶段计划 §2 / P2 11–15、v2 契约、现有 product/entry/services/certificates。
- 设备 SSH 恢复通道可用，系统 OpenWrt 24.10.5；现有监听已只读记录。
- 现有 entry 只保留首 listener、有 external_port；services 只有 HTTP URL，collect 强制 v1，保存未 parse；均需修复。
- P1 实现的迁移签名是 canonical.migrate_preview(config, inventory)，不是 RPC migration_preview；当前 RPC 尚未暴露预览。不得伪造调用或自动迁移。

## 父代理独立复跑结果
`HP_CASE=dirty node luci-app-homepublish/tests/tcp-ingress-device-probe.cjs` 实际 exit0：显式迁移预览/取消/确认，入口保存刷新且不激活，TCP/SSH/TLS透传/HTTPS原生弹窗保存读回，删首刷新再新增稳定ID，modal Save/删除草稿保护与取消不污染均通过。实际官方设备LuCI+设备CSS→固定SSH公共JSON/wire CLI→私有native journal，不是合成API响应。

修复：原生modalonly语义；摘要DummyValue不强制必填（真实弹窗Save阻断根因）；稳定service_id独立于JSONMap行名；模型快照dirty保护；入口挂载前不读formvalue。

finally恢复四安装JS，父代理独立SSH逐文件cmp再次exit0。/tmp/homepublish-p2-ui保留供续跑，原安装static-backup不可提前删除。

子任务config-before直接cmp不成立；父代理回读实际配置SHA256，全部与P1基线一致：homepublish=43dbb7d14614af6c7a323b97cf24830d2d87533d9b1e03ecc9d56ba5d0ec725b，network=6ead1d3a553f28348a58b4a3055b8873aee4916b2fe3471b67e960cbfba2dacd，firewall=52a2755e9a380e1e6d526204ec443dcdd85639f07d2903f64839d073edd55795。无需恢复或写入live配置。

## 扩展矩阵暂停交接（部署优先）
用户新增要求成果可直接在 127.0.0.1:222 查看，父代理接管匹配 Lua/native/RPC/ACL/UI 部署。续跑子任务**尚未运行任何 browser probe**；Win32_Process 查询 `node.exe` + `*tcp-ingress-device-probe*` 返回空，exit0，没有本子任务 finally/服务/浏览器待清理。此前仅一次只读设备 network_inventory 查询。

新增 `luci-app-homepublish/tests/tcp-ingress-device-extended.cjs`，主 harness `HP_CASE=extended` 保留原 dirty/four-types，并追加真实 LAN 双栈控件/Save、双向跨页保存保留、真正第二浏览器页面并发保存及拒绝/reset、已有 HTTPS↔TCP 切换取消和隐藏字段序列化、证书只读六列/usage、375px overflow 断言。两个文件 `node --check` 均成功；**追加断言尚未执行，不是绿证据**。消失地址用例尚未编写。

为避免旧 static-backup 覆盖新部署，harness 已完全取消安装 JS stage/restore：启动只读取安装四文件并核对工作树，finally 只读比较本次 baseline，不写安装目录。原 static-backup 不删除、不再使用恢复。需等部署结束且 private Lua fixture 匹配新版本后，由 owner 执行：`HP_CASE=extended node luci-app-homepublish/tests/tcp-ingress-device-probe.cjs`。当前证书表 selector/窄屏/类型切换尚可能暴露问题，不能宣称矩阵闭环。

实际只读网络库存证据：lan / br-lan / up=true / zone lan；IPv4 `192.168.1.2/24`，IPv6 ULA `fd89:878e:a47f::1/60`。docker down 无地址，loopback 无可选地址；无公网 IPv6 证明。

## 扩展矩阵最终已通过（保持最新部署）

执行 `HP_CASE=extended node luci-app-homepublish/tests/tcp-ingress-device-probe.cjs` **exit 0**，完整原始输出：`docs/HOMEPUBLISH-TCP-P2-EXTENDED-GREEN.log`（16 条 PASS）。最终版本 `node --check` 两 harness 成功，`git diff --check` exit0，仅既有 autocrlf 提示。

- RED 已重现并保存 `EXTENDED-RED.log`：entry 网络切换调用 `widget.clearChoices` 抛 TypeError，IPv6 地址选项缺失。检查目标实际 ui.js：ListValue 使用 ui.Select，没有 Dropdown 的 choices API。修复为原绑定 select 上通过 dom.content 更新 option，保留事件、验证与显式失效地址，之后 setValue/triggerValidation。
- extended 还暴露两处真实窄屏缺陷：services 页面宽 693px、certificates 宽 556px。分别有 ATTEMPT3/4 RED；原生 GridSection 外加可键盘聚焦的横向滚动容器，不隐藏列或压掉动作。最终三个页面 viewport/body/html 均为 375px。
- 测试自身修正：IPv6 压缩与 canonical 展开按语义比较；六列表头选择实际 `cbi-section-table-titles`；原生非法字段 Save 的 Dismiss modal 按真实控件关闭。ATTEMPT1–5 保留各次失败，不冒充产品故障。
- 已通过：迁移 preview/cancel/confirm、四类型弹窗及类型字段序列化、ID 删除重建、dirty/cancel、实际 LAN IPv4+IPv6 双栈保存刷新、两页双向字段保留、临时 45 分钟、第二浏览器页真实冲突/reset、HTTPS↔TCP 取消及隐藏字段清理、真实不可用 docker 网络保留旧明确地址并拒绝 Save 不写 revision、不扩大 wildcard、证书两行六列无操作列与 default/inherit usage、375px 无整页横溢、无未捕获主页面 widget 异常。
- 永久上传本轮 `entry.js`、`services.js`、`certificates.js`；没有还原 static-backup，没有重启 daemon。真实用户入口仍为 http://127.0.0.1:1081/cgi-bin/luci/admin/services/homepublish/entry 。
- 最终只读独立核验：`python docs/evidence/tcp-p2-deployment/verify-extended.py` exit0，39 文件逐个匹配当前源码，6 JS 还核对真实 HTTP served bytes；完整 SHA 在 `docs/evidence/tcp-p2-deployment/extended-final-readback.json`。原部署 manifest 保持历史记录，最终 readback 为当前补丁版本。
- 同一回读验证 `/etc/homepublish/product/{lock,state}`、`/etc/config/{homepublish,network,firewall}` 与永久部署前备份哈希全部一致；live saved_revision=0 / intent_revision=7 / disabled / manual_stop_latch=true / stopped / cleanup=confirmed。浏览器仅写 `/tmp/homepublish-p2-ui` 私有 native journal，Save 未启动发布；未改防火墙/路由/认证，未 commit/push/P3。

## 真实首次打开空地址修复（无 live Save）

- 已在正式菜单路由 `/cgi-bin/luci/admin/services/homepublish/entry`、非私有 bootstrap、live `saved_revision=0` 无 `saved_config` 重现 RED。`NOCONFIG-RED.json`：IPv4/IPv6 **网络**列表有 lan/docker/loopback，两个**地址**列表 options=[]。实际 network_inventory 同时正常返回 LAN 双栈地址，故不是库存为空或缓存推测。
- 根因：entry.js 对不存在的 listener 初始化 `row[f+'_network']=''`；原生 ListValue DOM 隐式展示第一个网络 lan，但地址 renderWidget 从尚为空的 row 查库存，得到空集。既有测试总是先 seed v1→迁移，绕过首次打开分支。
- 修复仅 entry.js：创建 JSONMap 前，对缺少的地址族，从 up 且有该族精确地址的库存初始化 draft 网络和地址；保留已保存 listener，包括失效精确绑定，不做迁移/保存/启动或 wildcard 放大。已直接部署并 SHA256 读回匹配 `fb8b0607c4456d1ff57a99149003eda83f0ab780397b5c315ed40d5a18a8f867`，浏览器禁用 HTTP cache 后正式路由加载新实现。
- `tests/entry-no-config-browser.py` 是实际 browser_exec 原生控件回归（无 Save/Start），GREEN 保存 `NOCONFIG-GREEN.json`：首次 IPv4=`192.168.1.2`、IPv6=`fd89:878e:a47f::1`；IPv6→双栈→IPv4 显隐及地址保持；两族 lan→docker→lan onchange 与失效选择保留均通过。
- 本轮浏览器已有登录态的 origin 为 `http://127.0.0.1:1081`；用户 literal `http://localhost:1081/.../entry` 单独检查是登录页，未绕过认证或移动凭据。两者同一设备的路由；不要声称 localhost 已登录 DOM 验证。
- `HP_CASE=extended node luci-app-homepublish/tests/tcp-ingress-device-probe.cjs` 再跑 exit0，日志 `NOCONFIG-EXTENDED.log`，仅写私有测试 journal；未向 live Save。
- 最终 `python docs/evidence/tcp-p2-deployment/verify-extended.py` exit0，结果 `no-config-final-readback.json`：39 安装文件匹配当前源码，HTTP 静态字节一致；live journal/config 与 `/root/homepublish-backups/20261015-165134` 原始 SHA 不变。saved_revision=0 / intent_revision=7 / disabled / latch=true / stopped / cleanup=confirmed。`git diff --check` exit0（仅已有 autocrlf 提示）。
- 用户查看：在原地址登录后 Ctrl+F5 强制刷新；这只是加载已部署修复，不是把根因归咎缓存。IPv6 当前是 ULA，不能据此承诺公网可达。未改认证/防火墙/路由，无 P3/commit/push。

## 网络候选能力过滤最终闭环（覆盖以上旧候选语义）

- 正式菜单 `http://127.0.0.1:1081/cgi-bin/luci/admin/services/homepublish/entry`，live revision0 无 saved_config：`entry-network-switch-browser.py` 在旧安装 e54ac2a… 得到 FILTER-RED（exit1，两族都错误允许 docker/loopback）；上传最新 entry.js 后相同命令 FILTER-GREEN exit0。原始证据 `HOMEPUBLISH-TCP-P2-NETWORK-FILTER-{RED,GREEN}.json`。这是正式路由、实际库存，不是私有 bootstrap。
- entry.js 按 up=true 且有对应地址族可发布精确地址过滤，不按 lan/docker/loopback 名称黑白名单。当前实际只有 LAN 可选。已保存失效网络/地址以禁用诊断项保留；全部无候选时禁用空占位且 Save 验证阻断，不替换 wildcard。
- 永久部署 entry.js，源码/安装/HTTP SHA256 一致 `0a781cfe5d1bd2af44bbae1d3653b967d26ce471128e94c3964288040fd03f9e`。未恢复旧 static-backup。正式首次打开/IPv4→IPv6→dual 显隐及候选 `entry-no-config-browser.py` exit0，无 live Save/Start。
- 最终源码执行 `HP_CASE=extended node luci-app-homepublish/tests/tcp-ingress-device-probe.cjs` 连续两次 exit0：`HOMEPUBLISH-TCP-P2-FILTER-EXTENDED-VERIFIED.log`、`...-REPEAT.log`。保留全部迁移、四类型、ID、dirty、双栈私有保存、跨页保留、冲突/reset、证书表和375px回归；新增精确候选集合、注入 stale 网络 Save 拒绝、失效 saved 网络+地址 disabled、全空/no saved占位和Save阻断。
- 第二网络、库存消失、全空/no saved 是浏览器进程局部 RPC 响应 fixture，执行未修改的设备 UI 模块；**不是设备存在第二实际网络或真实接口变更**。第二网络仅IPv4，验证族过滤、真实 onchange 地址/zone 切换及返回LAN。所有写入只进 `/tmp/homepublish-p2-ui` 私有 native journal。
- 测试设施曾遇到未等待渲染的断言及 route 响应销毁，失败日志 FILTER-EXTENDED.log / FINAL.log 保留；修正为等待控件 attached、unrouteAll({behavior:'wait'})，最终两轮完整 exit0，无 uncaught widget errors。不是产品回归被隐藏。
- 最终 `python docs/evidence/tcp-p2-deployment/verify-extended.py > docs/evidence/tcp-p2-deployment/filter-final-readback.json` exit0：39文件源码/安装匹配、HTTP静态字节匹配，live journal/config 相对原部署备份 SHA 全未变；saved_revision0 / intent_revision7 / disabled / latch=true / stopped / cleanup=confirmed。node --check 与 git diff --check exit0，仅已有 autocrlf提示。没有 commit/push/P3、live migration/save/start、认证/防火墙/路由变更。

## 剩余验收边界
扩展 P2 浏览器矩阵本轮闭环，不等同产品生产发布。没有变更真实接口以模拟“已保存地址从系统消失”；动态库存变化及第二网络通过浏览器局部响应 fixture 验证，非实际系统接口变更。迁移本次走设备公共 JSON/wire/私有 native 链，正式 rpcd migration 写方法未改 live 配置；受限只读/写账号 ACL 分离仍有 deployment 文档所述缺口。P3 provider、公开 IPv4/IPv6 可达不在本轮。
