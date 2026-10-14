# HomePublish 真实目标部署预检 — 2026-10-14

## 结果：已上传，缺依赖阻止安装

用户授权目标 `root@127.0.0.1:222` 安装 HomePublish/LuCI 两个 IPK；禁止 firewall/UPnP/公网曝光及影响已有管理通道。本轮仅上传、只读检查、`opkg --noaction install`，未实际安装任何包、未重载 rpcd、未改网络或服务。缺依赖时按本轮部署约束停止，不能将此记录称为安装成功。

源 worktree `D:/DevPortal/homelede/homepublish-product`，branch `feature/homepublish-product`，部署预检源码 HEAD `1508b70e3d9e1597bc8cb0b93eae8ce9cbf84589`。既有 untracked `homepublish/tests/__pycache__/` 未处理。

## 实际包与传输核验

官方 SDK `24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64` 的 `bin/packages/x86_64/homestunlocal` 产物；WSL 和目标 `sha256sum` 完全一致：

- `homepublish_0.1.0-r1_x86_64.ipk`: `d24fe623b166be515d89a841d68fb873a2b9110ab8c6e2ec9bfc05cb8334c412`
- `luci-app-homepublish_0.1.0-r1_all.ipk`: `f0176aee51a1df7d7ac19f9ed7c4ffbdfb68d10172ec8437ac6029669b5a6462`

真实 control/data 解包列出 native/Lua/config/init、rpcd plugin、menu/ACL、四个 LuCI JS。control 两包版本都是 `0.1.0-r1`。HomePublish Depends: `libc, libgcc1, liblua5.1.5, lua, libuci-lua, nginx-ssl, natmap, curl, ca-bundle`；LuCI Depends: `libc, homepublish, luci-base`。

目标路径 `/tmp/homepublish-install-20261014-1508b70/`，目录权限 0700。Windows 副本在当前 ta profile scratch `homepublish-deploy-20261014/`。用 `scp -O`，未读取私钥内容。

## 阻断证据

目标 OpenWrt 24.10.5 x86/64，HomeLede revision `v2026.10.01 based on OpenWrt 24.10.5`。lua/libuci-lua/nginx-ssl/curl/ca-bundle/luci-base 已装，`natmap` 未装。

`opkg --noaction install <homepublish.ipk> <luci.ipk>` exit 0，但计划除两包外安装 `natmap (20250924-r1)`，从 `https://mirrors.tencent.com/lede/releases/24.10.5/packages/x86_64/packages/natmap_20250924-r1_x86_64.ipk` 下载。exit 0 仅代表 dry-run 成功，不是包安装。同时输出已有 libgcc1/libpthread/libstdcpp6 duplicate provider HOLD/PREFER 警告；未 force，未 opkg update/upgrade。

安装前所列 HomePublish config/init/native/Lua/rpcd/menu/ACL/LuCI 目录全部无碰撞。独立 SSH 重连后的 `opkg status`/`list-installed` 再证实 `homepublish`、`luci-app-homepublish`、`natmap` 均未装，`ubus list homepublish` Not found，路径仍不存在。

下一步需用户/父任务确认是否授权安装确切缺失 natmap 依赖（并先检查该依赖实际包及安装脚本，不允许启动映射）；或者另行批准通过源码修正不必要依赖并本地 TDD/SDK 重构建。不能通过 force-depends 绕过。

## 管理与网络读回

独立 SSH 重连成功；原 uhttpd PID4308 监听 IPv4/IPv6 80、dropbear PID63780 监听443、PID34089监听LAN IPv4/IPv6 22，原 xray PID16371及 DNS/代理监听保持。TCP完整列表前后相同。目标自身 `curl http://192.168.1.2/` 返回200；`http://127.0.0.1/cgi-bin/luci/` 返回403（目标策略，不证明浏览器登录成功）。未猜密码或使用浏览器凭据。

firewall config SHA256 前后相同：`52a2755e9a380e1e6d526204ec443dcdd85639f07d2903f64839d073edd55795`。IPv4/IPv6 route show 前后一致。未执行 firewall/UPnP 写命令，无新应用 listener/进程；ps 查询命中的是验收 shell 自身命令文本，不是应用运行。

目标无 `stat` 命令；真实 Save/Stop/native store 对此兼容性尚未执行，不假称通过。未安装故没有 rpcd reload/session 中断，也没有测试配置/证书/active 状态。

## 待验与恢复

真实包安装、rpcd executable/ubus status、Save/validate revision与Stop latch、init default-disabled及完整 LuCI loader/browser均待验。production Start/Apply unsupported、activation_ready=false 的既有门槛不变，未执行生产 controller 或任何曝光。

目标留存两包和私有 `packages.sha256`、`result.txt`、`listeners-after.txt`、`routes4-after.txt`、`routes6-after.txt`、`firewall-after.sha256`、`installed-after.txt`。未覆盖现存文件，故无应用回滚操作需执行。若只清理此次上传，精确删除 `/tmp/homepublish-install-20261014-1508b70/` 即可，不触碰其它 /tmp 内容；当前保留供后续部署。实际安装前必须新增相关状态/配置备份和完整原始基线，依赖不能盲目 autoremove。

未 push/merge/PR。
