# HomePublish 真实目标部署预检 — 2026-10-14

## 结果：已安装，真实 RPC Save/Stop/default-disabled 通过（最新）

用户追加授权安装 natmap 后完成安装与限定功能验收。以下“缺依赖、未安装”章节为之前预检历史，本节优先。

- 安装前 HEAD `f4039225411abab59edc60c215dd942ad6e7c9d0`，branch `feature/homepublish-product`；没有产品代码修改/SDK 重构建。
- 实际官方 feed natmap `20250924-r1` 的 SHA256 与压缩 feed 索引精确相符：`2bd73426316806c953c0600393fc3904d0a64ec4766ac0b74d691ca5092eb703`。已读 control、data、默认 config、init 及系统 default_postinst。natmap 并非只有 CLI：带 procd init，默认 enable=0；default_postinst 会 enable/start，因此安装使用 `IPKG_NO_SCRIPT=1 opkg install` 避免所有自动脚本。随后两个 init 明确 disable，只 reload rpcd，不启动映射。无 force-depends/update/upgrade，已有 duplicate provider 警告未新增依赖阻断。
- 实际 readback：natmap `20250924-r1`、homepublish `0.1.0-r1`、luci-app-homepublish `0.1.0-r1`，均 list-installed。native binaries/rpcd plugin 0755，ubus 注册 status/validate/save/stop。natmap bin SHA256 `94d7707af3f637501d4a822f8fbe4f67641f0107e5eb56d44e9f67cfd243986a`，rpcd plugin SHA256 `234a205177f367acdc369aad7e39b6358b540ed4e91e6cb123724645dfc2eaa9`。
- 真实目标没有 stat，未注入 GNU stat；合成 noSecrets config validate=true，Save saved_revision=1/pending=true/desired disabled/no active，独立 status 确认持久化；Stop manual_stop_latch=true、intent_revision=1、active_verified=false、phase=unsupported，独立 status 相符。本地读取目标证据 JSON 并执行实际断言全通过，因此无兼容修复必要。
- 测试前 `/etc/config/homepublish` 备份到 `acceptance/default-homepublish`，新装前所有应用路径不存在。测试 Stop journal 备份至 `acceptance/test-product-stopped/` 后，只删除自有 `/etc/homepublish/product/state` 恢复新 app 默认；readback revision0/intent0/disabled/latch=false/no saved或active config，目录仅空 lock，UCI 字节与默认备份一致。没有证书、backend、测试 listener 或 natmap/homepublish executable 进程残留。
- 两个 init S95/S99链接不存在；procd `service list` 对 natmap/homepublish 均空对象。生产 Start/Apply unsupported 与 UI activation_ready=false 不变，没有运行或伪造 active。
- 四个 JS overview/product/schema/settings 从现有管理 `http://192.168.1.2/luci-static/resources/view/homepublish/` 获取并与安装文件 cmp 一致；管理首页 HTTP200。目标 browser 登录/完整 LuCI loader 尚未验，不猜凭据。应用留装供用户体验。
- 独立 SSH 重连成功，完整 TCP监听前后 cmp一致，IPv4/IPv6路由 cmp一致，uhttpd PID4308:80、dropbear PID63780:443/PID34089:LAN22及 xray PID16371保留。firewall hash `52a2755e9a380e1e6d526204ec443dcdd85639f07d2903f64839d073edd55795` 不变。未改 fw/UPnP/代理/管理，未运行 STUN，未曝光公网，未 push/merge/PR。

### 实际证据与回滚边界

目标私有证据：`/tmp/homepublish-install-20261014-1508b70/acceptance/`（0700）；`acceptance-evidence.tar.gz` 已 scp 回 `C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch/homepublish-deploy-20261014/`。包含 initial/validate/save/status-saved/stop/status-stopped/status-restored 七份实际 JSON、完整 TCP/route/firewall 前后读回、默认 UCI 与合成 stopped journal。恢复时不要把 `test-product-stopped/state` 当默认配置装回。应用当前数据目录 `/etc/homepublish/product/`，只有零字节 lock；原系统无旧应用需恢复。若另行授权卸载，先只 remove luci-app-homepublish/homepublish，保留 natmap 作为用户已授权安装依赖，不 autoremove；删除任何 conffile/数据前先核对后续用户改动。当前没有执行卸载。

## 历史结果：已上传，缺依赖阻止安装

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
