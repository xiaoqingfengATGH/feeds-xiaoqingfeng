# HomeTunnel 1.0.0-r3 源码发布

本次获授权将全部已验收的 HomeTunnel UI 修复以 squash 提交发布到 Feed master，不创建 PR、tag 或 GitHub Release，不进行 SDK 构建或设备安装。

## 包与变更边界

- `luci-app-hometunnel`：`PKG_VERSION=1.0.0`，`PKG_RELEASE=3`（r2→r3）。
- 合并共享实时主题角色桥、说明横幅、设置/domain select 配对及焦点、六步向导状态配色、已有 alert/button/label/pre 配对。
- 删除向导内容区重复 h2；保留主题外壳标题、说明、六步与控件。
- 保留 `LUCI_MINIFY_JS:=0`；LuCI 包不再重复登记 runtime 所有的 `/etc/config/hometunnel` conffile。
- runtime `hometunnel` 的源码与版本不变；不改主题、HomeStatus、业务配置或服务状态。
- 从最新 origin/master 独立 worktree squash，保留主线并发变更，不覆盖整个仓库。

## 验证与证据边界

发布候选重跑 wizard 10 项、diagram 30 项、真实 Edge 五配色 915 项与无主题 fallback 183 项；具体结果及最终 SHA 记录于仓库外 `artifacts/hometunnel-theme-unified/PUBLICATION-R3.md` 和 `.json`。

此前测试机已验收 r2 加 wizard 热修复：六步、说明和控件正常，内容 h2=0。这不是 r3 安装证据。r2 IPK 不包含后续标题移除；本轮 r3 尚未打包、未安装，不声明旧 IPK 与 r3 源码字节一致。

LuCI 模块缓存键来自全局 `resource_version`，不是应用 PKG_RELEASE。本轮不修改全站键，不声称升至 r3 自动失效浏览器缓存。将来获授权打包安装后，仍须核对安装字节、正常缓存加载及实际主题菜单切换；原生 OS option 弹层视觉不在本轮认证范围。

`docs/hometunnel-theme-unified.md` 为初始修复阶段历史证据，其中未部署/未升版表述仅属于当时阶段；本文件及发布记录定义本次范围。
