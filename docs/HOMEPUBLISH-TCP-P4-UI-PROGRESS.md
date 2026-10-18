# P4 UI 当前最终验收（优先于以下历史快照）

本轮完整串行复跑已完成。`ui-lifecycle-final-after27.log`：真实installed LuCI Start→原生services编辑Save保留active1/HTTPS A→Apply active2新代/HTTPS B→Stop关闭四条真实held sessions与listeners/snapshots，取消Start/Apply均不变更。**请求通过测试固定SSH bridge送往设备private Unix RPC/installed controller，不是public rpcd/session ACL生命周期验收。** `ui-overview-final-after27.log`：完整矩阵GREEN，mutationCalls=0/errors=[]/navigationAbortErrors=[]，无变化轮询childList=0且row/cell/focus/scroll保持。`services-modal-final-after27.log`：四协议字段依赖、空默认值、继承/覆盖、中文必填及取消无残行，零mutation，live status不变。

`verify-final-after27.log` exit0：15项installed/private/UI SHA匹配，详见`p4-stage-final-source-sha256.json`；当前live revision1/intent7/disabled/latch/stopped，SHA等于本轮baseline，不恢复历史rev0。tasks22/23在上述明确设备/私有通道边界内完成；public ACL、production能力、独立LAN/代理reload/公网仍未验。总账与精确复跑命令以`HOMEPUBLISH-TCP-P4-PROGRESS.md`顶部为准。无P5/commit/push/merge。

---

## 历史记录：用户报告轮询重绘（最终已安装并实跑）

- 用户新增授权：可在正式测试机实际 Start/Apply 做必要测试；这不授权 fw/routes/auth/global DNS/UPnP/公网配置。本轮优先只读 UI 修复，未调用生命周期变更，后续由父协调真实点击链；旧账本“未授权实际启动”的范围不再适用。
- 根因实证：每2秒 `reload→draw→new JSONMap→m.render→dom.content(body,node)` 替换整个 Map。`ui-dom-stability-red.log` 在正式设备路由明确 exit1：`poll replaced native Map DOM`，不是只看源码推断。
- 修复：首次才 render Map；后续 summary/output、按钮 disabled/reason、诊断 JSON 仅值变化时更新。服务/入口以 stable ID 对齐；成员不变不 render Grid，成员增删/重排只用原生 GridSection 生成所需行并复用已有行、表格、表头及 viewport。保留 epoch/renderEpoch、diff 摘要、缺 generation 拒绝、四协议 readiness、失败快照/retry。操作失败弹窗尚开时暂停自动轮询，避免下一新 poll 擦掉待用户处理的失败（完整矩阵曾在本轮暴露该时序）。
- 删除概览常驻“保存不启动；启动与应用均需确认”和 retry 的重复限制提示；Save 不自动启动语义、Start/Apply 原生确认不变。product.js 未改新内容。
- 最终命令：`node luci-app-homepublish/tests/p4-overview-browser.cjs > docs/evidence/tcp-p4/ui-dom-stability-final-green.log 2>&1`，exit0，`P4_UI_INSTALLED_NATIVE_GREEN`，mutationCalls=0、errors=[]、navigationAbortErrors=[]。真实初始 status 连续轮询 Map/按钮 identity、焦点、纵向 scrollY 120→120、诊断 open 稳定；labelled status fixture 两轮无变化 childList mutations=0，readiness 改值仍同 row/cell identity 与焦点、非零水平滚动；增删重排保留 proto-1 节点。全部旧矩阵一并通过。
- 测试细节：主题会添加 `.table-responsive`，实际水平滚动节点是此内层而非外 viewport；最终断言强制 scroll>0，避免0→0假通过。首屏主题布局延迟须等待稳定后记录 scroll。迭代中原生 Grid 单独 render 未先 load 导致“无”值、DummyValue 表格是直接 td 文本非 output，均已修复并完整复跑，不计作最终 GREEN。
- 只部署 `/www/luci-static/resources/view/homepublish/{overview,product}.js`，不 restore/重启。最终 backup `/root/homepublish-p4-ui-backup/20261015-213537`；`ui-dom-stability-readback.json` 已验证本地/installed SHA：overview `73e297b698d07f475f60ed4643acf5fd3c9c0cb5718d2719946aea3be2b2e2d6`，product `8ab25a3dd5efd0d73b5e76543444d3f2984f89578f7c25296f9a3a07f40b8b10`。live rev0、disabled、manual_stop_latch=true、stopped，before/after saved/active config、revision、desired_state 相同。
- 待父独立最终复跑；真实 UI Start→Save保留A→Apply B→Stop 仍待接续，不把上述 status fixture 当作生命周期证据。本轮未运行task24/25，无 commit/push/merge/P5。

# P4 UI checkpoint — tasks22/23 bounded slice

## 当前结论

**已安装的原生概览 UI 原型通过；不是 P4 完成，也不是实际 RPC 生命周期点击链完成。**

基线 `7ac1fe8`，分支 `feature/homepublish-product`。本 owner 仅修改 overview.js、product.js、新增 p4-overview-browser.cjs 与本账本；未改 controller/provider/profile。没有 commit/push/merge/P5，也没有 live Save/migrate/Start/Apply/Stop、fw/routes/DNS/UPnP/auth 修改。未并发执行同端口生命周期。

页面：`http://127.0.0.1:1081/cgi-bin/luci/admin/services/homepublish/overview`

## 已实现与证据

- 正式独立 overview 路由，原生 JSONMap/NamedSection/DummyValue/Button、两个只读 GridSection；不是设置页内 tab，也不是自绘卡片或输入表单。
- 已保存/运行版本、待应用分离；运行服务显示 active 快照，saved 只标参与下次发布/待应用。逐服务以 service_id 查询 runtime.services，ready=true 且 generation 与当前一致才显示内部就绪。旧 generation 明确不计就绪。
- 入口使用 schema2 network/address/port；IPv6 endpoint 加方括号，不伪造公网端口/URL。
- 内部诊断默认折叠，轮询保留 details.open；轮询后 overview 节点数仍为1。
- 原生 ui.showModal 确认列出实际监听、发布类型、目标后端、证书归属、策略与原截止，明确整组短暂停机。确认执行前重新读取版本/generation/门控，操作后读回状态；**本轮未点击确认提交，因此该执行链尚未验收**。
- shared actionGates 读取真实 capabilities、保存状态、dirty、cleanup、运行/待应用/手动停止锁。Stop 在失败/残留或状态未知而有 stop capability 时可用，不限 running。
- 原生 Grid 表头/行均去操作列。fixture 实际 DOM 为入口6/6、服务7/7，无 action cell。
- 1280px document.scrollWidth=1280；375px document.scrollWidth=375，内部表格 viewport client331/scroll824，横向滚动，不隐藏列。

## 精确复跑

```sh
node luci-app-homepublish/tests/p4-overview-browser.cjs
```

测试使用本机 Chrome Playwright 驱动**设备正式 LuCI 页面**，复用设备已有认证 session，未生成登录、未猜密码、未修改授权。browser_exec local profile 因用户 Chrome profile 锁定不能复制；改用独立 Playwright browser 复用现有认证 session。没有本地 fake HTML/bootstrap，也不在本机执行设备业务逻辑。

- `docs/evidence/tcp-p4/ui-native-red.log`：原页面0个原生 cbi-map，明确 assertion RED。
- `ui-gates-red.log`：shared actionGates 缺失，明确 RED。
- `ui-confirm-red.log`：确认弹窗/服务 Grid 边界迭代失败；其中有测试选择器误用 `.cbi-modal` 与路由匹配问题，不算产品 RED。真实 JSONMap 不能用扁平 `.type` 对象代替数组 Grid；实机表空后改成 arrays。
- `ui-final-green.log`：最终版本完整 exit0，P4_UI_INSTALLED_NATIVE_GREEN，pageerrors=[]，mutationCalls=0。
- `ui-final-readback.json`：两个源文件与 installed SHA256完全一致；live rev0/intent7/disabled/latch/stopped/cleanup confirmed，配置未动。
- `git diff --check` exit0，仅既有 autocrlf warning。

**fixture 与真实边界**：初始 no-saved 页面与轮询为真实 status RPC。pending/active 分离、旧generation、确认摘要与表格列测量使用明确 labelled status response fixture，仍在设备正式页面和真实 LuCI loader中渲染；不冒充真实运行组或 provider/RPC 生命周期。只打开并取消确认，拦截防止任何 mutation RPC。

## 部署与剩余事项（非空）

- 设备原文件首次备份 `/root/homepublish-p4-ui-backup/{overview.js,product.js}`。当前安全 UI 保持安装，不恢复旧 UI；两个 installed 文件与源字节一致，未重启其他 daemon。
- 实际私有 provider RPC bridge 尚待 backend owner 固定服务端接入；禁止用客户端 provider selector 或 live global approval 冒充能力。live rev0 status 目前 capabilities start/apply=true，但这不证明 schema2 production provider 已授权/可用；前端从不绕过服务端拒绝。
- 下一批须在固定私有 journal/真实 provider、后端 owner 结束生命周期后，验证浏览器 Start→Save保留A→Apply到B→Stop 的真实 RPC点击/读回链，以及失败重试和截止不延长。
- 已补全提交中跨轮询竞争、四协议同代 readiness、removed active 服务、读取失败恢复矩阵，见下方当前批次证据；真实 RPC 变更点击链仍未验收。
- SSH/TCP 无 hostname 的 diff 摘要已修复（名称/类型/service_id，并列类型及独立端口变更）；仍不宣称图形产品最终完成。

## 当前批次：概览交互缺陷与负向矩阵（最终版本已运行）

- **父级独立验证已登记**：交接时父级命令 `node luci-app-homepublish/tests/p4-overview-browser.cjs > docs/evidence/tcp-p4/ui-parent.log` exit0；已读该日志末项 P4_UI_INSTALLED_NATIVE_GREEN、mutationCalls=0、errors=[]。这是上一版父级验证，不冒充本批最终版父级复核。
- `ui-diff-red.log` 精确复现 SSH/TCP 新增/删除/修改的 undefined；修复后 `ui-diff-green.log` exit0。摘要保留 stable service_id，新增发布方式与独立监听端口变更，不能靠 hostname 匹配身份。
- `ui-race-red.log` 精确失败 `submission busy state absent after poll`。actionDialog 新增可选 submitting 回调，overview 将 actionBusy 与 status 读取分开；提交中暂停轮询与全部动作/重试，旧 status epoch 和旧异步 Map render 不得覆盖新状态。确认按钮原 busy guard 保留。测试双击提交但仅延迟 status；版本不符在命令前拒绝，未调用任何变更。
- `ui-matrix-red.log` 精确失败 `missing generation must not count ready`；原逻辑 undefined===undefined 误判 ready，现要求当前 generation 非空且相同。四协议正向同代、旧代拒绝、缺代拒绝、已保存删除但仍 active 的行都已覆盖。
- 附加回归：Start/Apply/Stop 的 unsaved、pending/no-pending、dirty、busy、cleanup unknown、failed、unknown 能力门控；运行中 status transport abort 保留最后已知配置但 readiness 标未知、Start/Apply 禁用而 Stop 仍按能力可用，刷新恢复；首屏 status 读取失败不注入 defaults，重试回到真正 status。
- **最终复跑**：`python docs/evidence/tcp-p4/deploy-ui.py > docs/evidence/tcp-p4/ui-matrix-final-readback.json` exit0；`node luci-app-homepublish/tests/p4-overview-browser.cjs > docs/evidence/tcp-p4/ui-matrix-final-green.log 2>&1` exit0；`git diff --check` exit0（已有 autocrlf warning）。最终结果 P4_UI_INSTALLED_NATIVE_GREEN、mutationCalls=0、errors=[]。`navigationAbortErrors` 单独记录了故意 reload 时 LuCI 旧 XHR 的 `XHR request aborted by browser`；只在 navigation 窗口且精确文本才分类，不吞其他 pageerror。之前 ui-race-green.log 的 modal 遮罩阻止点击及首次 ui-matrix-final-green 尝试的导航 abort 是 harness 问题，修 harness 后完整重跑通过。
- 最终原生表头/行仍 6/6、7/7、actions=0；1280px document=1280，375px document=375，内部 client331/scroll824。最终真实正式 route 单一 hp-overview、单一 cbi-map，轮询保持折叠诊断 open。
- **部署只含两个静态文件**：`/www/luci-static/resources/view/homepublish/{product,overview}.js`，无重启、无 auth 改动；最后备份 `/root/homepublish-p4-ui-backup/20261015-210947`。readback SHA256：product.js `8ab25a3dd5efd0d73b5e76543444d3f2984f89578f7c25296f9a3a07f40b8b10`，overview.js `b08b6e55ea05dc6e3240e3e0fef007608493247b35f54019c25cbdbef9b5bed0`。readback live revision0、disabled、manual_stop_latch=true、stopped、cleanup confirmed 未变；没有 live Save/Start/Apply/Stop/migrate/fw/routes/DNS/UPnP。
- **边界仍非空**：所有四协议、pending、错误、竞争输入都是正式 loader 中的 labelled status fixtures（或 deferred status），不是 provider/RPC lifecycle 成功证据。当前确认范围四协议覆盖来自早先 TCP scope 与本批 HTTPS/TLS/SSH scope，两者均未发变更。后端 owner 结束后由父级协调私有真实 RPC bridge；仍须 Start→Save保留A→Apply到B→Stop 真实点击与读回，及真实 stop failure/retry/截止不延长。tasks22/23 未全验收，P4 未关闭，无 P5、commit/push/merge。

