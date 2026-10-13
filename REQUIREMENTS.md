# Feed 需求登记

登记前核查：本隔离 Feed worktree 在基线 `8953489` 无已跟踪 REQUIREMENTS 文件，已跟踪 Markdown 未发现 `REQ` 数字编号或“需求编号”登记。采用组件前缀 `REQ-HS-001`，不推断其他仓库的全局编号。

## REQ-HS-001 — HomeStatus 驾驶舱第一阶段代码归属迁移

- 状态：源码迁移与本地回归完成；待 SDK/IPK 与生产浏览器验收。
- 基线：Feed `8953489`；主题 `d0bddb3`。
- 分支：两个独立 worktree 均为 `refactor/homestatus-phase1`。
- 需求：将驾驶舱主体 JS/CSS 归属迁入 `luci-app-homestatus`，主题删除旧副本并引用应用资源。保留现有布局、数据判断和交互，LAN 交互不改。
- 允许保留：主题 footer 启动、`ng-page-rendered`、经典状态 include DOM 搬移依赖及 palette 视觉适配；不要求完全跨主题。
- 构建要求：主题依赖应用，应用依赖经典状态包；通过 package feed 链接发现 CSS，不猜 feed 名，允许显式覆盖；独立生成器无默认本机路径。
- 本地验收：三份 Node 测试 10/10；Build/Prepare GNU make 宏桩 fixture 3/3；JS 语法、palette 一致性和两边 diff 空白检查通过；可复现 package.json/pnpm-lock.yaml，不提交 node_modules。
- 部署验收：未执行。SSH 已恢复且只读核查旧安装版本；不得据此标记新版本真机验收成功。
- 文档：`luci-app-homestatus/README.md`；`docs/homestatus-phase1-verification.md`；主题包 `README-homestatus-phase1.md`。
- 回滚：成对恢复旧主题/应用，先旧主题后旧应用；保留配置，清缓存，再检查经典入口与 RPC。
- 范围外：部署、改远程配置、合并、推送、PR、LAN/WOL 交互重设计。

## REQ-HS-002 — LAN 四设备概览与宽幅完整查询面板

- 状态：阶段2源码与本地自动化验收完成；待独立审查、真实浏览器/设备验收。
- 基线：应用阶段1提交 `c108e8f`；独立分支 `feature/homestatus-lan-detail`。
- 已确认结构：WAN/LAN 保持半宽；LAN 最多四设备、不等高限高、不内部滚动。完整设备列表放在独立宽幅 modal；手机全屏。
- 完整查询：设备名、IPv4、MAC 和真实 IPv6 地址搜索；按实际接口网络筛选、保留空网络与其他/未分类、上游与未划入网络端口事实。
- 刷新：原5秒轮询；保持面板、搜索与筛选控件身份、输入、焦点和列表滚动；选中网络暂时消失不重置筛选，恢复后自动显示。
- 访问性：对话框语义、Tab/Shift-Tab 焦点圈、Esc/关闭按钮/遮罩关闭、背景 inert/aria-hidden 与锁滚动，关闭恢复原值、焦点及页面位置；文档监听器随面板清理。
- 数据边界：normalize/在线判定/数量口径保持基线；IPv6 只在详情读取已采集 hints；保留 conntrack 当前/上限、条件式 WiFi、DHCP 深链和无租约说明。
- 资源：应用 r3，CSS `v=2`；应用原位升级主题已预载 `v=1` link，不重复插入；body portal 复用 `.ngov` 组件/palette 并覆盖根布局副作用，不修改主题。
- 本地验收：Node 三份共20/20、JS/测试语法、WSL资源打包 fixture 1/1、现有四配色生成器只读 `--check`、`git diff --check`。
- 文档：`luci-app-homestatus/README.md` 与 `docs/homestatus-phase2-verification.md`。
- 未执行：浏览器布局/视觉、真实 LuCI/RPC/设备、SDK/IPK、部署、合并、推送、PR。CSS契约/jsdom不是视觉验收。
