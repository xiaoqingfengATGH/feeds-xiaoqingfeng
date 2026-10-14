# Scoped RPC / LuCI 本地切片完成检查点

## 最新收尾（以下旧blocked段仅保留历史，已被本节取代）

父真实browser与本轮正式 `make browser` 均exit0：实际LuCI loader、DOM Save `家庭 NAS 😀`、saved_revision=1、pending=true、无active revision、DOM Stop latch=true、Start disabled。实际官方rpcd/ubus/uhttpd业务，不是HTTP fake；静态frontend loader外壳仅fixture支持，非完整目标BusyBox/procd证明。uhttpd注入的 `ubus_rpc_session` 已在canonical前剔除。runner有ready/browser/退出deadline及finally清理读回，最后cleanup PASS，owned_processes/mounts/listeners=[]、directory_absent=true。SIGTERM触发KeyboardInterrupt诊断traceback但runner exit0，未扩修。

正式 `rpc` target保持、新增 `browser` target。普通用户 `make rpc controller product` 完整exit0，真实两backend Apply及60秒原expiry/stream关闭通过。一次误用root跑controller得到start errno=5、cleanup confirmed、make exit2，不算通过；随后普通用户完整复跑exit0。既有Lua tmpnam linker warning保留。

先前官方下载已获准且成功，仅私有OpenWrt24.10.5 x86_64 overlay，非生产安装。本轮读取实际 `/home/eric/homestun-sdk-check/homepublish-official-24.10.5/manifest.json`，逐包版本/hash来自该manifest：

- uhttpd 2025.07.06~7e64e8ba-r5 SHA256 782fef79789861a423427e1a17e701f54bfa2c1000dac66570f926fa45d30440
- uhttpd-mod-ubus 同版本 SHA256 e049a397598b31bac7e65c2f457c6268a6daa7dcbc8df26c162a90bd51d63aad
- libubus20250102 2025.10.17~60e04048-r1 SHA256 d4adddbd3bea025e38026e187f96ac156cea68e6279a49fb03a504f4beddce22
- libubox20240329 2025.07.23~49056d17-r1 SHA256 2129f92e30b38ae6d74618fbf5fddd0ea910d4c5b9d38f07004765dcd8019162
- libblobmsg-json20240329 同版本 SHA256 14831ca29c68970819aad29165bcf669d3ef10824f0c9eb58f2d840f6311bdd6
- libjson-script20240329 同版本 SHA256 0f92abb5f7a9f1f8f9e311922eecb3568f2347e6e70eeea31df808de7914e986
- libjson-c5 0.18-r1 SHA256 f2d69c8ddc3d86c87b640d40dc3f8180a826c58c347e04c8c68204f9df5685f3

官方base https://downloads.openwrt.org/releases/24.10.5/；targets/x86/64/packages/Packages index SHA256 9807e385bcd72d00a0966ad8e2838c0005df80ea97b9f127b36e76c265f8a4e9；packages/x86_64/base/Packages index SHA256 3ceb2749b477b9d0cd5255b70bf23b258de579310d9dcdac091bdf52dc70cef7。脚本校验包字节对index，不冒称签名验证或生产authority闭合。

### 正式复跑命令与host前提

RPC/controller/product用Ubuntu-24.04普通用户、cached Lua/compiler/Nginx：

```sh
wsl -d Ubuntu-24.04 -e env TMPDIR=/home/eric/homestun-sdk-check timeout 180 make -C /mnt/d/DevPortal/homelede/homepublish-product/homepublish/tests rpc controller product
```

browser用WSL root（chroot/bind mount）、cached matching SDK/LuCI资源/官方overlay、可从WSL调用Windows node.exe、Windows Chrome与Windows Node可resolve Playwright；18993/18994空闲。HP_BROWSER_DEPS可覆写Linux overlay。HP_PLAYWRIGHT可指定Windows Playwright模块目录，默认require('playwright')，不硬编码用户依赖路径；target不下载/生产安装。

以下在Windows Git Bash层执行，先设置自己的HP_PLAYWRIGHT或省略使用Node默认resolve；必须WSLENV forward，Linux env不会自动传给Windows node.exe，保留已有WSLENV：

```sh
# export HP_PLAYWRIGHT='C:/your/cache/node_modules/playwright'
WSLENV="${WSLENV:+$WSLENV:}HP_PLAYWRIGHT" wsl -d Ubuntu-24.04 -u root -e make -C /mnt/d/DevPortal/homelede/homepublish-product/homepublish/tests browser
```

本地commit收尾；最终hash与提交后rpc/browser exit由handoff读回。接入向导、服务增删、多服务controller及其余四页完整交互仍待；production Start/Apply unsupported、ENOTSUP/helper78、activation_ready=false保持，功能后统一安全复评。测试机127.0.0.1:222已授权内网安装但SSH connection refused，未重试/绕过，未安装。无生产、公网、防火墙/UPnP、push/merge/PR。__pycache__不提交。

## 历史接管记录（当时未完成）

- Worktree `D:/DevPortal/homelede/homepublish-product`, branch `feature/homepublish-product`, HEAD `af779ad`；保留前worker所有dirty修改，无reset，无新commit。
- 本轮无生产安装、公网、防火墙/UPnP变更、下载、push/merge/PR；生产Start/Apply unsupported、ENOTSUP/helper78与activation_ready=false保持。

## 真实browser阻断：不是业务验证器错误

复跑 `node luci-app-homepublish/tests/product-browser.cjs` exit1：两个真实LuCI `/ubus?1791949401869`、`/ubus?1791949407947` 请求获得 `{"error":"<urlopen error timed out>"}`，loader随后报 `No related RPC reply`。chroot `uhttpd.log` 是 `chroot: failed to run command ‘/usr/sbin/uhttpd’: No such file or directory`，uhttpd子进程586为defunct；真实ubusd/rpcd已注册插件且status成功，但HTTP ubus服务从未启动。SDK root-x86没有uhttpd可执行文件；扫描 `/home/eric` 未找到缓存uhttpd binary/source tar，只找到OpenWrt recipe与LuCI资源。未用模拟JSON-RPC替换真实uhttpd，未盲改业务验证器。fixture现在在首次资源获取前明确assert缺失uhttpd/ubus模块（exit1），避免再启动假ready fixture。

下一步须提供匹配缓存uhttpd+ubus module，或另行准许下载并构建匹配目标依赖。恢复后再定位真实HTTP请求/response ID、session/路由；当前不能声称loader、DOM Save/Stop或整个切片完成。SDK缺BusyBox仍使用host dash，仅fixture前提，非真target shell验收。product-browser.cjs的Playwright依赖目前为前worker绝对scratch路径，正式browser target和自有启动/退出guard仍待完成。

## 新真实功能证据

- `wsl -- python3 .../homepublish/tests/test-rpc.py` exit0：真实插件→固定stdin CLI→native canonical store，validate/save/status/revision conflict/pending/stop latch。新中文+emoji JSON转义Save曾RED KeyError(saved_revision)，根因拒合法surrogate pair；product-json.lua仅补合法pair→UTF8，孤立surrogate仍拒；重跑GREEN。
- test-controller.py将实际运行第二代的cross-process Stop改为真实复制plugin `call stop`（仅fixture替换固定安装路径，非client/provider选项）。证明应答先持久manual_stop_latch/cleanup_required，再由真实controller关闭TLS listener并清理runtime；不是假running fixture。
- 最终明确exit0：`wsl -- env TMPDIR=/home/eric/homestun-sdk-check timeout 160 make -C /mnt/d/DevPortal/homelede/homepublish-product/homepublish/tests controller product`；真实两backend Apply、60秒原expiry/stream断流、失败状态、canonical/review/recipe/package全部过。host Lua recipe的既有tmpnam linker warning保持。
- 较早包装命令虽make全部绿，但Windows/bash变量展开导致`exit: : numeric argument required`、wrapper exit2；未把该wrapper称为成功，随后以上无shell变量命令完整复跑exit0。
- Makefile新增正式 `rpc` target；真实browser尚不能注册为通过的正式验收target。

## 清理与收尾状态

先只读检查旧 `rpc-luci-gnmat24h`：无owned `/proc root/exe/cwd`、无mount、无18993/18994 listener，仅删除该已确定fixture目录。新fixture `/home/eric/homestun-sdk-check/rpc-luci-rqz2z1xj` 的wrapper PID556经cmdline核对后SIGTERM，执行自身finally停止owned daemons/卸bind/删目录。最终独立readback：rpc-luci目录[]、owned进程[]、mount[]、18993/18994 absent，主机DNS监听保留。controller fixture退出清理成功。工作树的 `homepublish/tests/__pycache__` 是前worker及当前Python测试产生，未纳入提交。

未localcommit：用户要求真实browser成功后完整切片提交，不能把缺依赖/loader失败冒充完成。下一功能段仍是接入向导、service增删/多服务controller、其余四页交互；当前UI仅概览/服务与接入JSON编辑。完整功能后再统一安全复评，不扩底座。
