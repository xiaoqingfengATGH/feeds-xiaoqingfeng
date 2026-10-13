# HomeStatus 阶段2验收与续跑入口

## 范围

- Worktree：`D:/DevPortal/homelede/wt-homestatus-phase2`。
- 分支：`feature/homestatus-lan-detail`；基线 `c108e8f`。
- 应用：`1.0.0-r3`，CSS 缓存 `v=2`。
- 只修改本分支应用/需求文档；未修改阶段1 worktree、主题或原始仓库，未合并/推送/PR/部署。
- 配对主题只读检查：`D:/DevPortal/homelede/wt-homestatus-theme/luci-theme-infinityfreedom-ng`，其 HEAD `8f5cc6b`。

## 实现状态

四设备精简 LAN 概览 + 独立宽幅完整面板已实现，不是无样式 stub。完整列表独立滚动、表头 sticky、工具栏固定在滚动区域之外；≤700px全屏。保留原网络/连接上限/WiFi/DHCP 事实。名称/IP/MAC/IPv6搜索、实际网络筛选、空组/上游/未分类/未划入端口均保留。5秒刷新不替换控件与 scroller，保留焦点和滚动；关闭恢复背景属性/body样式/焦点/位置，监听器移除。

主题预载 CSS v1 的 link 原位升级至 v2，无重复；首次安装仍须清 JS 缓存获取新应用脚本。body portal 同时带 ngov 和专用 shade class，复制根节点解析后的变量并覆盖根布局；既有 palette 的组件选择器仍能匹配，未引入新固定色。

## RED → GREEN 与最终证据

- 接续已有6项DOM行为测试：CSS契约先运行7项，6 PASS / 1 RED（缺 `.ngov-device-panel`）。加入实际桌面/移动面板CSS后 GREEN。
- 本轮统计保留与body palette scope测试2项先 RED（缺conntrack上限/缺ngov scope），实现后 GREEN。
- release/cache测试2项先 RED（r2/v1），更新至r3/v2后 GREEN。
- 补充空设备/网络暂时消失与恢复、监听器精确清理/已有背景属性恢复测试，最终GREEN；这些补充测试检查接续实现已有行为，并非声称新功能先RED。
- 阶段2原实现完整 Node：20 tests / 20 pass / 0 fail（migration 5、regression 4、DOM 11）。
- 审查两项小缺口分别完成 RED → GREEN：概览测试先因缺 `（含上游）` 失败，再验证1客户端+1上游标题仍为1台、概览2/2台带说明，无上游时1/1台不带说明；完整列表测试先因Tab跳过scroller失败，加入 `tabindex=0` 与 `aria-label="全部接入设备列表"` 后验证Tab/Shift+Tab可达、循环焦点及刷新后原节点/焦点/纵横滚动保留。已有focus trap选择器包含 `[tabindex]`，直接复用，不引入新框架或更改业务计数。
- 小修后最终完整 Node：**22 tests / 22 pass / 0 fail**（migration 5、regression 4、DOM 13）；两项新增测试各自单跑GREEN。overview.js、三份cjs `node --check` 及 `git diff --check` 全部exit0。
- 本轮小修仅改overview.js、DOM测试与本验收文档；未重跑既有打包fixture/palette检查，未构建SDK、部署、改主题、合并或推送。JS缓存仍依赖首次强制刷新，沿用下方验收前提。
- 应用 overview.js 与三份 cjs `node --check` 全部exit0。
- WSL Ubuntu-24.04 资源打包 fixture：**Ran 1 test / OK**，真实LuCI24.10宏上下文、无minify及安装字节保护；不是SDK/IPK。
- 主题四palette对当前应用CSS只读 `--check` exit0，无漂移、未写主题。
- `git diff --check` exit0。
- 提交前新增行安全扫描：无秘密赋值、shell注入、pickle/innerHTML；唯一eval命中为jsdom测试加载仓库固定脚本的 `w.eval(code)`，非用户输入。自查通过；独立审查留父任务执行，提交不使用独立审查通过标记。

## 可复跑命令

在worktree根目录（Windows Git Bash）：

```sh
export HOMESTATUS_THEME=D:/DevPortal/homelede/wt-homestatus-theme/luci-theme-infinityfreedom-ng
node --test luci-app-homestatus/tests/migration.test.cjs luci-app-homestatus/tests/regression.test.cjs luci-app-homestatus/tests/dom.test.cjs
node --check luci-app-homestatus/htdocs/luci-static/resources/view/homestatus/overview.js
node --check luci-app-homestatus/tests/dom.test.cjs
node --check luci-app-homestatus/tests/migration.test.cjs
node --check luci-app-homestatus/tests/regression.test.cjs
HOMESTATUS_OVERVIEW_CSS=D:/DevPortal/homelede/wt-homestatus-phase2/luci-app-homestatus/htdocs/luci-static/resources/view/homestatus/overview.css python "$HOMESTATUS_THEME/scripts/gen-palettes.py" --check
git diff --check
wsl.exe -d Ubuntu-24.04 -- bash -lc 'cd /mnt/d/DevPortal/homelede/wt-homestatus-phase2/luci-app-homestatus && mkdir -p /home/eric/homestatus-phase2-scratch && TMPDIR=/home/eric/homestatus-phase2-scratch python3 tests/test_resource_packaging.py'
```

## r4：LAN 概览高度反馈修复

- 根因证据：r3 概览仍复用四列详情表，半宽下名称/接入方式允许任意换行；3–4 个双层统计 mini 被两列网格排成两排。无高度 cap 后这些真实内容自然将右卡撑高。没有证据指向主题 palette 或上游卡；只读 SSH 核实目标为应用 `1.0.0-r3`、主题 `2.0-ucode-r11`、`luminousblue`。
- 隔离 Edge 真实布局复现（非 jsdom 高度）：旁路由、9 客户端+1上游、WiFi、长名称，1600px/16px 字体，上游 `349.34px`、旧 LAN `423.86px`；1200px/24px 字体，上游 `429.03px`、旧 LAN `665.27px`。这不是用户当前主题下的实际像素测量。
- 最小修复：统计改成可换行的单层事实摘要；概览仅名称/IP/状态三列，四行完整呈现。长文本单行省略但 DOM 文本、title 与全部设备详情保留；接入证据/MAC/IPv6仍在完整面板。未增加卡片高度上限、内部滚动或 ResizeObserver，没有撑高左卡，也没有藏入口。独立 modal 宽高与全部设备空间未改。
- TDD：三列/紧凑统计 DOM 先 RED（旧四列表头）→GREEN；无 cap 单行 CSS 契约先 RED（缺 flex stats）→GREEN；release/cache 先 RED（r3/v2）→GREEN，源版本 `1.0.0-r4` / CSS `v=3`。最终 Node **24/24 PASS**，包括原22项回归；palette generator `--check`、JS语法、diff check均通过。
- 真实布局 smoke：`tests/layout-smoke.cjs` 以 actual view/jsdom 的刷新后 DOM快照交隔离 headless Edge测量，覆盖旁路由/单WAN/三WAN ×1600/1200/390px ×根字体16/20/24px，共27项通过；桌面 LAN 均不高于左卡，无概览滚动、无页面水平溢出，入口可见；6项独立 modal 桌面/移动宽高与完整设备数量通过。旁路由1600/16修后 LAN `280.38px`，1200/24为 `348.59px`。仅紧凑对齐，不承诺不同内容左右严格等高，多WAN左卡自然更长。
- 重跑：先将 Playwright 安装在自有 scratch；`HOMESTATUS_PLAYWRIGHT=C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch/homestatus-layout/node_modules/playwright node luci-app-homestatus/tests/layout-smoke.cjs`。使用系统 Edge，但独立无用户 profile；不关闭用户浏览器。
- 验证边界：用户浏览器 profile locked，未关闭或接管；上述 real-layout 为应用CSS隔离fixture，不是 luminousblue 真机LuCI/RPC视觉验收。未构建IPK，未改主题/配置/原仓库，未merge/push/PR。按用户追加授权只热更目标两个应用静态文件，部署读回记录见下。

## 真机静态热更读回

- 用户授权后仅备份并替换 `/www/luci-static/resources/view/homestatus/overview.js` 和 `overview.css`，权限 `644`；未执行 opkg、服务重启或配置写入。
- 备份：`/root/homestatus-hotpatch-522aacf/overview.js` 与 `overview.css`（目录700，原权限保留）。旧JS SHA256 `4db72548d859cec1f31c0f024ffc3ff9bf494690c204daecd0d3850700e15830`；旧CSS `1382ababd2e4790d8e0849470bf738ae047a0b5f0bb9479e7c57962c20f53b6a`。
- 热更源提交：`522aacf43da6d383a44a1c6128b795fd213410ca`。工作树 JS、SSH目标读回、HTTP200资源三者SHA256相同：JS `5541ae693fec6597703396bd456c6baae8e9e02502ca76918d45b6fea7dfc4cc`，CSS `bad09e3f4f864d5c8cafd3669d415a7ec509403c44b4792ac43dc274bab94d0f`。
- 源 Makefile 为 `1.0.0-r4`，目标opkg仍显示 `1.0.0-r3`：本次是静态hotpatch，不是r4包安装。主题仍r11、palette仍luminousblue，两个应用/主题config部署前后hash未变。
- 用户现在可在驾驶舱按 **Ctrl+F5** 强制刷新后验高度；必须取得新JS，再由JS原位升级CSS至`v=3`。HTTP校验使用 `?hotpatch=522aacf` 绕缓存；没有改主题footer的旧JS版本查询，不能保证普通刷新自动更新。
- 用户真机视觉尚待确认；回退时只将上述备份两个文件覆盖原静态路径并`chmod644`，然后再次强制刷新。

## 独立审查/后续验收

父任务应独立读最终diff并复跑同一最终版本测试。r4已完成隔离浏览器真实布局fixture和授权静态热更（见后续读回记录），仍未完成：用户当前 luminousblue 真机视觉、移动键盘、多palette实际显示、完整 LuCI loader/RPC 交互、SDK/IPK。jsdom无真实布局，DOM/CSS契约不替代视觉验收。请用户Ctrl+F5强制刷新，特别核验原footer JS v1是否拿到新内容及CSS v3；未修改主题启动版本，因此自动JS缓存升级不在本次成果中。
