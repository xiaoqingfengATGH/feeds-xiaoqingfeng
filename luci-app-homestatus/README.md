# HomeStatus 驾驶舱：LAN 概览与完整面板

## 阶段2（REQ-HS-002，当前分支）

应用版本为 `1.0.0-r3`，基于阶段1 `c108e8f`。WAN/LAN 仍各半宽，LAN 概览最多四设备，无高度测量/内部滚动。保留网络数、DHCP 租约、conntrack 当前/上限、存在无线电时的 WiFi 客户端统计与 DHCP 深链。

“查看全部设备”打开 body 级宽幅 modal（桌面最多1120px，≤700px手机全屏）。标题、关闭和搜索/筛选工具栏在独立滚动列表之外，列表有 sticky 表头，窄屏可横向查询完整四列。详情保留 MAC、实际 IPv6、网络子网/网桥成员/端口在线、空网络、其他/未分类（含上游）、未划入网络端口及无 DHCP 租约说明；不改变在线判定和原有数量口径。

搜索支持名称、IPv4、MAC、真实 host hints IPv6，忽略大小写；网络筛选来自实际接口。5秒刷新只替换列表内容，不重建搜索、筛选或列表容器，保留输入/筛选/焦点/滚动。网络暂时消失保留选项并标注，恢复后继续选中。关闭面板后重新打开以全部设备开始，不承诺跨关闭持久化筛选。

面板有 dialog/aria-modal、焦点圈及背景 inert；Esc、关闭按钮和遮罩关闭。恢复已有 inert/aria-hidden、body 样式、滚动位置和最新概览按钮焦点，移除本次 document 键盘/焦点监听器。body portal 使用 `.ngov` 以复用主题组件/palette，并复制驾驶舱解析后的 `--ngov-*`；专用选择器消除根容器 gap/margin/列布局副作用，不新增固定配色。

CSS 缓存由应用升级至 `v=2`：找到主题原 `v=1` link 就原位更新 href，未预载才创建。主题源码与 JS footer 缓存标记不修改；首次升级仍须强制刷新/清缓存，确保浏览器取得新应用 JS，再由它升级 CSS。不是声称已解决设备端 JS 缓存。

本地测试为 migration 5 + regression 4 + DOM 11 = **20项**；回归只允许 LAN 展示区域、详情地址旁路和 render LAN 更新/旧等高逻辑变化，其余 normalize、动作、轮询与经典 drawer 保留全文精确基线保护；非新增 LAN CSS 保留精确保护。WSL资源打包 fixture 1/1、JS及三份测试语法、现有四配色 `--check`、diff检查通过。证据/命令见 `../docs/homestatus-phase2-verification.md`。

未部署、未构建 SDK/IPK、未做真实浏览器/设备/RPC/视觉验收；DOM和响应式CSS契约通过不代表已验证移动端实际排版。下文是阶段1历史说明，r2/v1和10项等数字仅指阶段1。

## 第一阶段归属迁移（历史记录）

## 范围和边界

本阶段把驾驶舱主体从主题迁入 `luci-app-homestatus`，不是完全跨主题独立运行。
应用拥有 `htdocs/luci-static/resources/view/homestatus/overview.js` 和 `overview.css`，包括 RPC、状态判断、卡片渲染、轮询、弹层、应用操作与经典状态视图 DOM 搬移。主体逻辑及 CSS 选择器/声明与主题基线 `d0bddb3` 保持一致；只变更资源归属和加载地址。LAN、网络设置、WOL 等交互没有另行改造。

主题仍负责外壳、overview 路由 footer 启动、`ng-page-rendered` 事件以及 palette 视觉覆盖。应用仍依赖既有经典状态 include 的 DOM 包装；保留观察器/搬移行为，不声称兼容任意主题。主题旧 `ngOverview.js/css` 已删除，不能再作为第二份源文件维护。

应用显式设置 `LUCI_MINIFY_JS:=0` / `LUCI_MINIFY_CSS:=0`，保持迁移前不再压缩资源的契约。主题 `LUCI_DEPENDS` 选择应用参与构建，`LUCI_EXTRA_DEPENDS:=luci-app-homestatus (>=1.0.0-r2)` 声明运行时版本下限；CONTROL 中同名包出现两次分别来自这两个通道，不代表两个安装实例。本轮宏验证未发现实际冲突，无需仅为去重重写；真实 SDK/opkg 行为仍待验。

依赖方向：`luci-theme-infinityfreedom-ng → luci-app-homestatus → luci-mod-status/luci-base`；应用不反向依赖主题。应用版本 `1.0.0-r2`，主题版本 `2.0-ucode-r10`。新路径资源缓存标记 `v=1`，主题 palette 两个 header 均为 `v=21`。

## 构建与安装顺序（操作说明，未在本轮执行）

1. 在固件/SDK 中分别接入这两个隔离分支的源码，执行对应 feeds update/install；必须先安装 `luci-app-homestatus` 的 package feed 链接，再编译主题。
2. 主题 `Hooks/Prepare/Pre` 中的 `Build/PreparePalettes` 在 LuCI 复制资源前通过 `package/feeds/*/luci-app-homestatus` 链接解析 CSS 真路径，不假定 feed 名称。自定义源码布局可用 `make ... HOMESTATUS_OVERVIEW_CSS=/absolute/path/to/overview.css` 显式覆盖；找不到源文件时明确失败。
3. 正式安装应先满足 `luci-base`、`luci-mod-status` 和 rpcd/ucode 依赖，再安装应用 r2，最后安装主题 r10；不要仅升级主题使新资源变成 404。
4. 独立运行 palette 生成器必须设置 `HOMESTATUS_OVERVIEW_CSS`。没有本机路径 fallback。生成后同步提交四份 palette；生成器 `--check` 可校验是否漂移。
5. 安装后重新加载 LuCI/浏览器缓存，检查新 JS/CSS 请求、经典 include、RPC 权限和卡片交互。此步骤是待执行验收，不是本轮成果。

## 可复现本地测试

需要 Node >=22.12、pnpm 12.5.1、Python 3（命令 `python`）、git；GNU make fixture 在 Linux/WSL 执行。主题 git 历史须含固定基线 `d0bddb3`（回归测试读取旧 JS/CSS），浅克隆需先补齐该历史。测试没有默认本机主题目录，须显式指定。

在应用包目录执行（POSIX shell；Windows Git Bash 环境路径使用 `D:/...`）：

```sh
pnpm install --frozen-lockfile --ignore-scripts
export HOMESTATUS_THEME=/absolute/path/to/theme-repo/luci-theme-infinityfreedom-ng
pnpm test
node --check htdocs/luci-static/resources/view/homestatus/overview.js
export HOMESTATUS_OVERVIEW_CSS="$PWD/htdocs/luci-static/resources/view/homestatus/overview.css"
python "$HOMESTATUS_THEME/scripts/gen-palettes.py" --check
```

`package.json` 和 `pnpm-lock.yaml` 固定 jsdom 27.0.1；`node_modules` 不提交。三份测试必须一起运行：migration 5 项、regression 4 项、DOM 1 项，合计 10 项。DOM 使用 jsdom 和模拟 RPC，不是设备浏览器验收。

真实 OpenWrt/LuCI 24.10 宏 fixture（需要 Linux/WSL 的 GNU make、/bin/sh、cp、find 和 Python 3；Windows 原生 Python 缺 make 的 WinError 2 是环境前提，不是产品失败）：

```sh
# Linux/WSL；本环境 TMPDIR 指向 Hermes 可写 scratch
python3 tests/test_resource_packaging.py
python3 /absolute/path/to/theme-repo/luci-theme-infinityfreedom-ng/tests/test_dependency_control.py
python3 /absolute/path/to/theme-repo/luci-theme-infinityfreedom-ng/tests/test_prepare_paths.py
```

旧版空 luci.mk 桩仅证明路径 recipe，不能证明 LuCI 宏覆盖和执行顺序；该证据已被真实 24.10 宏 fixture 取代。最终 prepare 3 项使用原版 luci.mk，并从 package.mk 提取 Prepare/Pre→Build/Prepare 顺序；生成器替身证明生成结果先于 LuCI 复制，且 ucode/root 被复制。dependency control 1 项使用 package-pack.mk 的 CONTROL 宏证明版本下限进入 Depends。resource packaging 1 项在全局启用 minifier 的条件下证明应用禁用 JS/CSS minify、安装资源字节不变。rules.mk/package.mk 周边仍是最小桩，生成器及 minifier 使用替身，不是 SDK/IPK 或 opkg 实装验收。fixture URL、SHA-256、许可证见 `tests/fixtures/README.md` 和 Feed 根目录 `docs/homestatus-phase1-verification.md`。

## 本轮测试证据与未验项

- 新增 release 和生成器缺环境变量测试先观察 2 项 RED，再修复后 GREEN；Build/Prepare 三个 fixture 先全部 RED，修复后全部 GREEN。
- 固定 lockfile 安装成功；三份 Node 测试 10/10，WSL resource packaging 1/1、dependency control 1/1、prepare 3/3（父任务完整复跑确认）；应用 JS 及三份测试 `node --check`、四份 palette `--check`、两个 worktree `git diff --check` 均通过（最终命令见 `docs/homestatus-phase1-verification.md`）。
- SSH 早前出现握手前 reset，后来使用显式禁用 ProxyCommand/ProxyJump 的连接恢复；只读检查返回 Linux 6.18.55、ucode 存在、经典 status/include 目录存在。设备仍安装应用 `1.0.0-r1`、主题 `2.0-ucode-r4`；这些不是本轮源码版本。
- 未部署，未构建 SDK/IPK，未做真实 LuCI loader、ucode 新模板编译、设备 RPC/浏览器、LAN/WOL 或视觉验收。SSH 可达不等于新版本功能已验收。

## 回滚（操作说明，未执行）

部署前备份配置和匹配的旧应用/主题包。需要回滚时先恢复旧主题（其 footer 重新使用内置 ngOverview 资源），再恢复旧应用；旧主题源文件对应基线 `d0bddb3`，旧应用对应 feed 基线 `8953489`。两个仓库的迁移提交应成对撤销，不能只回滚应用而保留新主题的资源引用。保留 `/etc/config/homestatus` 与 `/etc/config/infinityfreedom-ng`，不要用删除配置代替回滚；刷新缓存后重新检查入口与 RPC。不要把降级命令默认直接执行在生产设备。

需求登记：Feed 根目录 `REQUIREMENTS.md`，编号 `REQ-HS-001`。
