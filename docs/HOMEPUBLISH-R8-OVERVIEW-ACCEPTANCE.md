# r8 实际 overview 路由验收（纠正此前遗漏）

源码包基线：`9b7b93e`，分支 `feature/homepublish-product`。后续测试/记录提交不改变已构建运行源码。

此前 settings 内“概览”tab 不能代表 menu 的 `admin/services/homepublish/overview` 已交付；旧 overview.js 确实只有 15 行英文内部状态文本。已替换为独立中文概览，非 redirect、非复制配置编辑器：已保存/本机/TLS/公网/期限状态卡、只读服务表、入口/证书摘要、pending 提示、能力门控开启/应用/停止、刷新重试、默认折叠内部诊断。product.js 共用差异与操作确认；settings 使用同一动作确认。

## 真浏览器 / RPC / 运行链

- RED：真实已安装 r7 资源、Chrome、官方 LuCI `View.__init__` 单节点；等待 `#hp-overview-services` 超时，证明真实路由缺图形概览。
- 本地源码 GREEN：官方已安装 loader + 真实设备 scoped RPC，只换源码资源，无伪造状态。
- `make product rpc browser` 最终 exit0；settings 原有增删改、SAN 错误、共享/独立证书、保存版本、375px、轮询草稿/焦点保留回归通过。修正本地 fixture bootstrap 同样避免二次手工 load/render。
- 安装后 `overview-browser.cjs` exit0：按实际 overview route 加载真实已安装 `view.homepublish.overview`，官方 lifecycle 仅初始化一次；`#hp-start` count=1；中文卡/表/摘要；默认 public capabilities Start/Apply 禁用且原因可见；details 开合保留、375px 无整页溢出；真实 RPC 请求中断显示“状态未知（不是已停止）”、禁操作，恢复请求后重试恢复。pageerrors=[]。
- `run-r8-overview.py` 最终 exit0：固定 root-only fixture 开启真实 capability，概览按钮 Start 两服务共享 RSA → settings 保存独立 ECC/后端变更仍旧流量 → 回到真实 overview 按钮 Apply，显示名称/后端/继承→独立证书差异及原截止 → Stop 两个已建立 hostname/fixture-CA 验证 TLS 连接关闭、新连接拒绝、私有 runtime 消失。实际 procd/Nginx/HTTP marker A→B，无 fake active。最终 deadline `1791983883` 经 Save/Apply 不延长；pageerrors=[]。
- 使用 scoped 300 秒 session，不授予 uci.commit；finally 销毁 session。测试 Web bootstrap 是受限 session 外壳，模块/loader/RPC 来自实际已安装设备，并非以 settings 页面代替 overview。未登录直接访问管理 route HTTP403 是认证边界，未声称匿名全 LuCI shell 成功。

## SDK / 安装绑定

实际 OpenWrt24.10.5 x86/64 SDK、共享 flock、无并发 make；Windows `git -c core.autocrlf=false archive` 固定 commit，ext4 `device-r8-source`；实际 package/feeds/homestunlocal 两包 link 指向此目录；defconfig 后两项 CONFIG_PACKAGE=m；SDK 真 compile/两只 IPK control Version `0.1.0-r8`。

产物：`D:/DevPortal/homelede/artifacts/homepublish-r8/`

| 包 | SHA256 |
|---|---|
| homepublish_0.1.0-r8_x86_64.ipk | f89d729d1448ad0ea2b842cb0bfae143013a4e21bff580ef67682804be991b24 |
| luci-app-homepublish_0.1.0-r8_all.ipk | af9c3807298f993f7a53182f618ef6c6776359ed87fa9bf843466ccdcc97ee96 |

解包32文件；30源文件逐字节匹配归档与 Git blob，另2为配置与 SDK生成 ELF；目标安装后32文件 SHA256全部 OK（含两包版本与 overview/product/settings）。helper tests、node_modules 没有入包。安装后通过受限浏览器读取实际页面资源。

## 清理与边界

最终 cleanup exit0 / CLEANUP_PASS：state.backup 与当前 journal 文件 cmp 一致、revision0/disabled/manual_stop_latch=true/stopped/cleanup confirmed；ACME配置恢复 cmp 一致；源fixture RSA/ECC目录、device-test 开关、私有运行目录/socket不存在；两个后端及 controller 停止、两个 init disabled；firewall哈希、全部 TCP listener、IPv4/IPv6 route 前后相等，管理80/443/22保留。root-private evidence/backup 保留在设备 `/tmp/homepublish-r8-final-evidence`；实际设备管理 SSH 正常。

遇到并已修复的验收工具问题：WSL distro 名应 Ubuntu-24.04；SDK root-owned 文件使用 root 构建；Windows stdin text 模式转 CRLF，改 bytes；目标没有 diff，改逐文件 cmp；RPC URL 有尾部/查询，故障拦截改 `**/ubus**`。首次 cleanup 在 state/ACME已恢复后因 diff 缺失退出，立即独立补验，再完整最终 rerun cleanup exit0；不隐瞒失败。

最终证据：artifact `overview-final.log`、`lifecycle-final.log`、`installed-manifest.json`、`installed.sha256`；WSL `r8-final-local.log`、`r8-feeds.log`、`r8-defconfig.log`、`r8-build.log`。

仍未交付/未验证：public production activation（明确unsupported）、独立LAN/IPv4/IPv6公网可达性、fw4/UPnP/DDNS adapter、代理 reload；本轮没有更改防火墙、UPnP、公网 DNS/ACME申请、proxy/HomeVPN配置，没有 push/merge/PR。概览 GUI 这一切片已验，不代表整个产品完成。
