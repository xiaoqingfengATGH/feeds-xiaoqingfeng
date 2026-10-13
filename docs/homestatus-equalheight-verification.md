# HomeStatus 同排自然等高热更新

- 用户授权：仅应用静态 CSS/JS 热更，不构建/安装 IPK，不改主题或配置。
- 最小实现：`.ngov-cols` 的 `align-items: start` 改为 `stretch`；同一网格行按较高卡片自然等高，移动单列各行保持内容高度。没有固定 height、概览内部滚动或新增设备行；body 级详情 portal 不变。
- JS 仅提升 CSS 缓存键 `v=3` → `v=4`，源包 release 保持 r4。
- RED：真实 Edge layout smoke 在 upstream/1600/16 测得左349.34375、右280.375，等高断言失败。GREEN：27项布局（upstream/wan/multi-wan ×1600/1200/390 ×16/20/24）及6项独立详情尺寸通过；桌面等高、移动独立高度、无概览滚动/水平溢出。
- CSS 缓存迁移测试也先 RED（实际v3、预期v4）再 GREEN。最终 Node 24/24 PASS；JS语法、palette generator --check、git diff --check通过。
- 真机部署前：SSH 127.0.0.1:222 可用；已安装包 1.0.0-r3。homestatus 配置 SHA256 `f0b9f55405e300bf4412ac4a491de24a93a03a967e76d9a7d78a420192ff0a6c`，主题配置 `ffc3cac919b1885e449d0d21c9bd1d580f98f230ddd04a7aee1df8a5e6ef8d64`。
- 部署要求：备份旧 overview.css/js 至独立 `/root/homestatus-hotpatch-equalheight-*`；上传后 chmod 644，核对源/目标/HTTP SHA256，确认配置与 opkg 版本未变。JS主题预载缓存键未变，已登录真机浏览器需强制重取 JS 后刷新，由父任务完成最终主题视觉复验。
- 实际部署完成：备份 `/root/homestatus-hotpatch-equalheight-20261014-001455`；两个静态文件权限读回为644。源文件/远端文件/HTTP v4 响应三方 SHA256一致：CSS `1af8793fae69b7b8c4509a7f577f8bdfd02193459bea5699f75deced28f036af`，JS `153d2faad4010751989d2b064002a91b079de65c4483340f158276edf4e8a943`。两配置哈希不变，opkg仍为1.0.0-r3。
