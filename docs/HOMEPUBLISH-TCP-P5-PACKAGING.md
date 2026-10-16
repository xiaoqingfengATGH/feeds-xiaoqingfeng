# HomePublish TCP P5：IPK 前置审计与冻结构建交接

## P5 组件 owner checkpoint（组件交叉构建通过；最终产品门禁尚未关闭）

### 固定接口与实际交付

- 固定产品私有路径：`/usr/libexec/homepublish/nginx`、`/usr/libexec/homepublish/sslh-select`。新增 `homepublish-engines` 配方，不安装 init/UCI，不替换管理 Nginx/系统 sslh，不启动监听。backend owner 应在 production adapter 使用这两个路径；本 owner 没有编辑 runtime/controller/RPC/frontend 或 backend integration 文档。
- `homepublish/Makefile` 已补 `+libubus-lua +homepublish-engines`，移除不能保证 stream 的 `+nginx-ssl`。最终来源仍为 dirty 工作树，未 commit。旧 init/system-provider 的系统 Nginx 引用由 backend owner 衔接，不应把依赖修正当作 provider 已完成。
- 新建 `homepublish-engines/{Makefile,build-components.sh}`；当前显式仅支持匹配 SDK 的 x86_64，其他架构尚未实现。真实 SDK package.mk 的 DUMP 已读取并确认依赖，**不是最终 IPK 构建通过**。
- RED→GREEN：`homepublish/tests/test_p5_packaging.py`，日志 `docs/P5-PACKAGING-{RED,GREEN}.log`。仅为配方/依赖契约测试，不冒称设备运行测试。

### 版本与来源安全

1. 选择 **Nginx 1.30.6 stable maintenance**。official download 页曾仍显示 1.30.5，但 https://nginx.org/en/CHANGES-1.30 已列 2026-10-14 的 1.30.6 安全修复；直接下载的 tarball nginx.h/CHANGES 确认 1.30.6。URL `https://nginx.org/download/nginx-1.30.6.tar.gz`，SHA256 `3cf46f5ed7504d460125866b7bea99fb357f31d887e2e63b35503310e9b8b6c8`。
2. tag `release-1.30.6` 对应 commit `fb0e979c6dd63c018958b41eeb844947c5c21264`，tag object `4b7a1a2ed58d97e385cbf5c7bb0a7ece05fe16fd`。tar.asc 实际 GPG GOODSIG/VALIDSIG，key 来自官方 `https://nginx.org/keys/pluknet.key`，fingerprint `D6786CE303D9A9022998DC6CC8464D549AF75C0A`。GPG trust=undefined，不声称独立线下身份认证。签名显示日期早于 release/tag 日期；额外下载该 exact commit 源归档，程序核对 **498 个共同文件、0 差异**（`source-compare.json`），包括源码/auto脚本。release-only 是 CHANGES、configure、html/man 生成物，未冒称整个 tar 与 git archive 相同。
3. sslh **2.3.1** commit `d39388d1edcc9fe7a35449fc5c23d222d20d6f81`，codeload URL `https://codeload.github.com/yrutschle/sslh/tar.gz/d39388d1edcc9fe7a35449fc5c23d222d20d6f81`，实下载 SHA256 `4822815217ba8c19d8a7469d19e686a5a3f6a0388e772636996f9cae1cdbc056`，与既有缓存一致。上游 release/tag 为来源依据，未做 sslh 离线信任签名验收。SUSE https://security.opensuse.org/2025/06/13/sslh-denial-of-service-vulnerabilities.html 明确 CVE-2025-46806/46807 已在 2.2.4 修；2.3.1 不倒退，仍不承诺任意负载抗 DoS。
4. libproxyprotocol commit `3e133b9602e59f47ceceef74fbd52a3b147e5874`，真实仓库 **kosmas-valianos/libproxyprotocol**；codeload 实下载 SHA256 `ecfaa002f2f36a87c7e52f515a6caaec492fb69ed5f0f74295934ed3b8475882`。曾尝试错误 rofl0r 仓库返回404，已纠正并实下载验证，不使用伪造替代。libconfig 1.7.3 SHA256 `545166d6cac037744381d1e9cc5a5405094e7bfad16a411699bcff40bbb31ee7`，匹配 SDK 上游配方。

### 公告适用性与模块/ABI

- 官方安全总表：https://nginx.org/en/security_advisories.html 。map/regex CVE-2026-42533 与当前 renderer 相关，1.30.4+ 修；HTTPS upstream CVE-2026-1642 相关，1.28.2+ 修。采用 1.30.6，而不是以 verify=true 或“无用户 regex”排除。
- CHANGES 新列 CVE-2026-93479 含变量字符串表达式、http/stream root/log；当前生成器使用变量/map，不能忽略。CVE-2026-97629 涉及 ticket rotation，选择修复版而不假定永远不启用。alias/rewrite CVE-2026-15176 无当前 alias 文件映射；HTTP/3 CVE-2026-95101/90439 无编译模块；SSI/AIO CVE-2026-97205/56434 无 SSI、无 file-aio；slice/MP4/DAV/mail 不编译；scgi/uwsgi/grpc 明确禁用。1.30.6 也覆盖此前 rewrite/charset 等修复。没有声称逐个漏洞利用复现。
- **静态编入 Nginx 模块**：HTTP SSL、realip、proxy/map/rewrite；stream、stream SSL、SSL preread。`ngx_modules.c` 与 `ngx_auto_config.h` 已留存，无需外部 load_module/任意 nginx-ssl stream ABI。这里“静态模块”不表示整个 ELF 静态链接。
- 两个 ELF 均 dynamic musl x86_64，未在 WSL 本地执行。Nginx NEEDED：libpcre2-8.so.0、libssl.so.3、libcrypto.so.3、libz.so.1、libgcc_s.so.1、libc.so；sslh NEEDED：libpcre2-8.so.0、libcap.so.2、libgcc_s.so.1、libc.so。配方明确依赖 libc/libgcc/libopenssl/libpcre2/zlib/libcap。
- sslh config.h 明确 HAVE_PROXYPROTOCOL/HAVE_LIBCAP/HAVE_LANDLOCK=1；configure 显式 build/host 进入 cross mode，没像旧相同架构 auto-detect 那样执行目标程序。仅宣称编译能力，不宣称实际运行降权/Landlock 已启用。
- 动态链接避免把旧 SDK OpenSSL 3.0.18 等库静态封入产品；但它们仍是部署运行依赖，**目标共享库安全维护状态须在最终部署门禁单独复核**，本轮未声称关闭全部传递依赖公告。

### 实际构建与许可材料

- 构建前再次读取 Linux ps、取得共享 `/home/eric/homestun-sdk-check/build.lock` flock；独占运行 source-pinned component script。退出0，最后标记 `P5_COMPONENT_CROSS_BUILD_COMPLETE_NO_HOST_EXECUTION`。结束后读取进程无旧构建，flock 再取成功 LOCK_RELEASED。没有改 SDK 原产品包链接/.config，也没有运行最终 dirty 产品包 make。
- 产物根 `/home/eric/homestun-sdk-check/tcp-ingress-p5/build/out/`：
  - `nginx` SHA256 `941b54d84fc4fd40b0257e42195899f0bd77895ec0486e3e263344c2fa8dc08a`。
  - `sslh-select` SHA256 `1b9746f96d31624eb2cfa4076ca7eb0b636979321dbec92947171f780ee38db7`。
- 源/对象/静态库/完整 link map/生成 Makefile/config/三项 SDK cross 补丁/SDK config/构建脚本/log/签名/key 均归档：`/home/eric/homestun-sdk-check/tcp-ingress-p5/component-materials.tar.gz`，SHA256 `5a83c5936634b495a1c4093a6f5fa7c86009a7aba45a11ffaa6fe96cae02034e`。此为**组件构建材料快照**，不是最终产品 git archive；晚于该归档生成的 source-compare/recipe-dump 另存 docs evidence，不属于此 hash。
- Nginx BSD-2-Clause；sslh 上游 GPL-2.0-or-later（SDK配方也确认），与 LGPL-3.0-or-later libproxyprotocol 静态组合采用 **GPL-3.0-or-later** 分发口径；libconfig LGPL-2.1-or-later 静态链接。保留完整源码、库源码/对象、应用对象、link map、构建命令，供重建/替换库/重链接；不能只发 ELF 和网络来源链接。其他嵌入源码许可证见完整上游源树（例如 argtable）。配方安装各上游 COPYRIGHT/COPYING/LICENSE 文本；最终分发必须同时提供对应完整材料和 notices，材料不能仅留构建机。
- 仓库证据 `docs/evidence/tcp-p5-packaging/`：build.log、signature.log、SHA256SUMS、needed.txt、ngx_modules.c、ngx_auto_config.h、compare-source.py/source-compare.json、recipe-dump.log。

### 未关闭的最终门禁

**组件选版、固定来源交叉构建、模块/依赖声明已交付；不等于 P5 总体关闭。** 无 IPK 安装、无设备二进制部署/能力运行复验，未启动共享 fixture，没有 firewall/routes/auth/DNS/UPnP/public 变化或清理测试服务数据。父任务 freeze 后仍需：正式 SDK 组件包+产品包构建/strip后的 control/data 字节清单；backend 使用固定路径的最终 target `-V/-t` 与 HTTPS upstream/map/PROXY/四协议/Stop 复跑；目标动态库维护评审；最终 dirty snapshot 或授权 commit 来源 manifest/release号；许可材料随发布可获取性。没有未经授权 commit/push/merge。


## 结论与范围

本文件为 **前置审计，不是构建/安装成功报告**。审计时 HEAD 为 `7ac1fe88f4817a24bc9abe69364c4324040d2d41`，业务工作树仍有 P4 未提交修改。不得将这些 dirty 文件打包后标为该 HEAD 的 Git 来源。等待任务28独立审查、任务29修复及最终实机回归完成，由父任务冻结确切来源后再分派构建。本轮未运行 make、未安装包、未启动共享 fixture、未连接/改动目标设备、未改 fw/routes/auth/DNS；没有 commit/push/merge/PR。

冻结计划：`.hermes/plans/2026-10-15_143056-homepublish-tcp-ingress-luci.md` 任务28–32：审查/最终回归、里程碑 IPK 与字节核验、文档、另行授权安装和外网验证。本文只覆盖打包前置，不替代安全公告、上游签名和功能审查。

## 1. 已实际读取的 SDK 环境

- WSL distro：`Ubuntu-24.04`；内核 `6.18.54.1-microsoft-standard-WSL2`，x86_64。
- SDK 存在且 realpath 确认：`/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64`。
- `include/version.mk`：24.10.5，`r29087-d9c5716d1d`；交叉编译器 `-dumpfullversion`：13.3.0；`.config`：x86/64、x86_64、musl。
- SDK 所在 ext4：251G 总计、43G 已用、196G 可用、19%；inode 2% 使用。只是当前资源快照，不保证后续容量。
- 共享锁 `/home/eric/homestun-sdk-check/build.lock` 是空普通文件；`flock -n ... -c ...` 实际返回 `LOCK_AVAILABLE`。空文件本身不能证明无持锁者。
- `ps` 与 `/proc/*/{comm,cwd,cmdline}` 对 make/gmake/flock/timeout/cc1/ld 的读取，未观察到旧构建进程。此结论仅对审计时刻成立，真正开工必须重查并持锁。
- `.config` 当前 `homepublish=m`、`luci-app-homepublish=m`、`nginx-ssl=m`，`nginx-mod-stream` 未选择；procd/rpcd 为 y。当前读取没有 `CONFIG_PACKAGE_libubus-lua=` 或 `CONFIG_PACKAGE_luci-lib-nixio=` 的匹配，须在最终 defconfig 后复核。
- **高风险旧来源链接**：SDK 当前包链接解析为 `/home/eric/homestun-sdk-check/device-r9-source/{homepublish,luci-app-homepublish}`，不是本轮最终源码。feeds.conf 的 homestunlocal 仍指 source-feed。仅更新 feed/index 不足，最终必须同时验证直接包链接及 package/feeds 链接。
- local feed pins：base OpenWrt v24.10.5；packages `953b6d47b4e9f0ad3c39547c6d3f9a828f10e206`；LuCI `d88390be4ec9722cb427fee03368fc8c8582627d`。

WSL 从 Windows Python 传 shell 时必须使用 `subprocess.run(..., input=script.encode(), ...)` 的二进制 stdin。首次字符串经 Windows text 模式产生 CRLF 导致探针失败；已用 LF bytes 重跑成功。原先 shell 嵌套变量被提前展开的探针同样无效，不作为 SDK 不存在的证据。

## 2. 包依赖与二进制归属：当前明确缺口

### 当前配方

`homepublish/Makefile`：版本 `0.1.0-9`；仅编译 `src/product-store.c` 到 `/usr/lib/lua/homepublish_store.so`，没有 Nginx/sslh 编译或安装规则。依赖：libgcc、liblua、lua、libuci-lua、nginx-ssl、luci-lib-nixio、curl、ca-bundle。

`luci-app-homepublish/Makefile`：`0.1.0-9`，依赖 homepublish/luci-base，JS/CSS 禁压缩；具备 feed scan BuildPackage signature。未声明额外 conffiles，避免重复拥有 runtime 配置。

### 阻断/待确认

1. **私有数据面不在任何本项目 IPK 中**：`product-device-v2-profile.lua` 明确调用 `/tmp/homepublish-tcp-p3/nginx-private` 与 `/tmp/homepublish-tcp-p3/sslh-select.private`，且要求 `controller-fixture/authorized`。配方不携带它们，依赖也不提供这些路径。装上两个当前 IPK 不会获得 P3/P4 四协议能力；缺 marker 按设计关闭。不能为让包运行而删除授权门控。
2. 该 profile 只授权一个固定 ULA/lan 入口、固定 loopback 后端端口/域名/证书引用；它是已安装私有验收适配器，不是通用 production provider。须由父任务决定本里程碑是“带明确能力限制的候选包”，还是先补正式可安装 provider/私有引擎包。这不是构建脚本可擅自解决的问题。
3. `network-inventory.lua:134` 直接 `require('ubus')`。SDK 的 `libubus-lua` 包明确安装 `/usr/lib/lua/ubus.so`，依赖 libubus/liblua，但当前 runtime Makefile 未声明它。应由实现 owner 确认补 `+libubus-lua`；目标历史已存在该模块不等于新装依赖正确。
4. `nginx-ssl` 不保证 stream：SDK recipe 只有选择 nginx-mod-stream 才加 `--with-stream=dynamic --with-stream_ssl_module --with-stream_ssl_preread_module`。当前 stream 未选择。即使补模块依赖，仍需明确 load_module/ABI/专用实例与管理 Nginx 共存，不能用包名冒称私有静态 Nginx 等价。
5. homepublish init 使用 `/etc/rc.common`、procd shell、Lua/nixio、控制 socket；rpcd 插件归 LuCI 包，LuCI runtime 安装路径/执行权限与 rpcd 依赖闭包需要实际 control/data 确认。procd/rpcd 本 SDK 已有，但“SDK 已有”不替代目标依赖审查。
6. 版本仍为历史 `0.1.0-9`，最终 freeze 必须决定新的 release，避免旧 IPK 同名和升级来源混淆。本轮不改版本。
7. 本轮未联网复核 Nginx/sslh 安全公告、最新 stable、上游签名或 GPL/static-link 重链接材料；属于任务28/发布门禁，不能标已通过。

### 已核实缓存组件，仅可用于来源定位

| 对象 | SHA256 |
|---|---|
| P3 nginx-private（static x86-64 ELF，有 debug_info） | `69206fd1ecef606da8e92141089787847c44d67380edc409d904f880b3048d73` |
| P0 out/sslh-select（static x86-64 ELF，有 debug_info） | `1d4ba7aa4931cae148d36ec24f3d85ee0bb527c0029c3ee3984f4144bf8826e9` |
| SDK dl/nginx-1.26.1.tar.gz | `f9187468ff2eb159260bfd53867c25ff8e334726237acf227b9e870e53d3e36b` |
| tcp-ingress-p0/sslh-e831b732.tar.gz | `8a100fe98fd1a98c3e16830667ee4e344cb95cda7bc2195cd41820d015b9419c` |
| tcp-ingress-p0/libconfig-1.7.3.tar.gz | `545166d6cac037744381d1e9cc5a5405094e7bfad16a411699bcff40bbb31ee7` |

sslh 构建脚本固定目录 commit `e831b732dbd239d7805ec8ec113a926f0a9271b6`；Nginx 1.26.1、libconfig 1.7.3。哈希匹配既有 build source-sha256 文件只证明缓存一致性，不证明上游真实性、可重现构建或安全性。

## 3. 最终归档方案

**首选 committed freeze**：任务29最终版本回归通过后，由有权限的父任务冻结完整 commit（本轮禁止提交），记录 full SHA、测试最终 source manifest 与审查结论。Windows 原生执行 `git -c core.autocrlf=false archive --format=tar -o <scratch>/source.tar <FULL_SHA> homepublish luci-app-homepublish`。同时对归档每个文件与该 commit 的 Git blob 逐字节比较；输出 path/mode/size/SHA256 来源清单。复制到 ext4 独占目录并核 tar SHA256 后解压，不直接在 DrvFS dirty worktree 构建，避免 ignored node_modules 被 SDK 递归 hash。

**无提交 freeze 仅作显式替代**：父任务如明确批准，生成不可变 source snapshot、完整 SHA256/path/mode 清单、base HEAD、binary diff 与受控 untracked 白名单；保存 archive SHA256 与最终测试所用 source manifest。来源必须标 `dirty snapshot`，不得标为 base HEAD 对应 commit，也不得用工作树复制后假称 git archive。当前未批准/生成该替代归档。

归档不纳入 docs/evidence 下 fixture 二进制、私钥、node_modules、__pycache__ 或测试运行数据。不要删除用户原目录实现排除；只从冻结白名单构造归档。引擎如改成独立包，须追加其 recipe、来源/patch/hash/许可与安装清单到同一 freeze。

## 4. 后续 build owner 命令（本轮未执行）

以下为 **冻结归档已解压且内容审查完成后** 可执行的 SDK 命令。参数 FREEZE_DIR 必须是 ext4 上含两个包目录的确切归档根；不得指 dirty checkout。改包链接、defconfig/clean/compile 都是后续 owner 在持锁后执行的 SDK 写操作。

```sh
set -eu
ROOT=/home/eric/homestun-sdk-check
SDK=$ROOT/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64
: "${FREEZE_DIR:?set exact verified ext4 archive root}"
: "${OUT_DIR:?set new exclusive output/evidence directory}"
test -d "$FREEZE_DIR/homepublish"
test -d "$FREEZE_DIR/luci-app-homepublish"
mkdir -p "$OUT_DIR"
exec 9>"$ROOT/build.lock"
flock -n 9 || exit 73
# Before mutating links, inspect /proc make/gmake cwd and stop on any old SDK build.
cd "$SDK"
# Preserve old config/links/feed metadata in OUT_DIR before changing these SDK-only links.
cp .config "$OUT_DIR/config-before"
for p in homepublish luci-app-homepublish; do
  test -L "package/$p" || { echo "inspect non-symlink package/$p" >&2; exit 74; }
  readlink -f "package/$p" >> "$OUT_DIR/links-before"
  ln -sfn "$FREEZE_DIR/$p" "package/$p"
  test "$(readlink -f "package/$p")" = "$FREEZE_DIR/$p"
done
# Inspect any package/feeds/*/{homepublish,luci-app-homepublish} links as well;
# stop if scan resolves a second/older recipe. Never delete unrelated feed/package dirs.
export PATH="$ROOT/local-tools/usr/bin:$PATH"
unset CPATH LIBRARY_PATH LD_LIBRARY_PATH PKG_CONFIG_PATH PKG_CONFIG_SYSROOT_DIR
make defconfig CONFIG_PACKAGE_homepublish=m CONFIG_PACKAGE_luci-app-homepublish=m
# Assert actual resulting selection, not just make exit status.
grep -qx 'CONFIG_PACKAGE_homepublish=m' .config
grep -qx 'CONFIG_PACKAGE_luci-app-homepublish=m' .config
cp .config "$OUT_DIR/config-final"
timeout --signal=TERM --kill-after=30s 180s make package/homepublish/clean package/luci-app-homepublish/clean V=s > "$OUT_DIR/clean.log" 2>&1
timeout --signal=TERM --kill-after=30s 1200s make -j2 package/homepublish/compile package/luci-app-homepublish/compile V=s CONFIG_PACKAGE_homepublish=m CONFIG_PACKAGE_luci-app-homepublish=m > "$OUT_DIR/build.log" 2>&1
```

先补妥第2节依赖/引擎归属和 release 决策，才允许将上述输出称为最终里程碑。命令只构建，不执行目标二进制/测试、不 opkg install。若依赖缺缓存需下载，先报告并按父任务范围处理，不 apt install 或执行历史 bootstrap。若工具超时，必须读取 Linux 侧 make/timeout/cwd/锁；不重启同 SDK 构建。不因 wrapper 退出推断 make 结束。

既有 `docs/homestun-sdk-build.sh` 会下载 apt 包、写 feeds.conf/.config 并指旧 homestun 路径；`docs/homestun-luci-build.py` 仍复制旧包且删除 source-feed 子目录，不得原样运行。`build-tcp-private-components.sh` 和 `build-tcp-p3-nginx.sh` 是私有交叉构建，非 BuildPackage；后者复用三项 SDK patch、静态链接 staging libs，但缺完整静态库来源/重链接材料。不能复制缓存 ELF 到最终包后跳过 provenance。

## 5. 安装字节与权限验收清单

这是 **待最终 IPK 解包生成的验收表**，不是已生成的安装 SHA256。没有最终归档/IPK，所以不能虚构最终 native `.so` 或安装字节哈希。

| 包/路径 | 来源与必核要求 |
|---|---|
| homepublish `/usr/lib/lua/homepublish_store.so` | TARGET_CC 编译 src/product-store.c；TARGET ELF/ABI、NEEDED、strip 后 hash；不能与源 C hash 混比 |
| homepublish `/usr/share/homepublish/*.lua` | 归档所有顶层 Lua，逐文件与 Git blob/冻结快照 SHA256 比较，常规 0644；包含 P4 最终 controller/runtime/profile |
| homepublish `/etc/config/homepublish` | 唯一 conffile，INSTALL_CONF；记录默认字节/模式及 control/conffiles；升级前保留已有配置 |
| homepublish `/etc/init.d/homepublish`、`homepublish-nginx` | INSTALL_BIN，0755，LF；核 procd 无 respawn/自动 exposure；nginx 实例仍指系统 nginx，不等价四协议 profile |
| homepublish `/etc/homepublish` | 0700；不打包 live journal、certificate/key、fixture marker |
| LuCI `/www/luci-static/resources/view/homepublish/{certificates,entry,overview,product,schema,services}.js` | 六份原始 JS，LUCI_MINIFY_JS=0，逐文件 hash 与归档/Git blob 相等 |
| LuCI `/usr/share/luci/menu.d/luci-app-homepublish.json` | 菜单 ACL/路由与来源字节一致 |
| LuCI `/usr/share/rpcd/acl.d/luci-app-homepublish.json` | scoped read status/validate/certificates/network_inventory/preflight/migration_preview；write save/stop/start/apply；无通配 ubus/file/UCI 授权 |
| LuCI `/usr/libexec/rpcd/homepublish` | 固定 shell→Lua管线，0755、LF，实际包数据拥有可执行位 |

当前 homepublish 配方不安装 files 内 `lease-run.sh`、`nginx.conf`、`worker/worker.mjs`；不应误列为实际入包。测试、docs/evidence、私有 nginx/sslh、host 二进制和 keys 均不得混入 data。空 `/usr/libexec` 目录不意味着拥有额外 native helper。

后续必须：独占输出目录收集新版本 IPK，程序核计包数/名称/Version/Architecture/Depends；用 `tar -tf` 先识别 OpenWrt IPK 容器（不盲假设 ar），再安全解 control/data 到独立目录；生成每个 data 文件 path/type/mode/size/SHA256 清单，与冻结源对应静态资源及构建 `.so` 比较。保留完整 control、conffiles、postinst/prerm 和原始 IPK SHA256。若另行授权安装，先备份真实配置/journal/版本和服务基线，再对 **实际安装路径** 逐个 hash/权限读回，保留 opkg conffile 分歧与配置变更，不能只验上传包 SHA256。

## 6. 用户数据保留与清理边界

本轮上下文的新约定：**保留测试数据/服务配置；清理只限自有私钥及明确残留，不默认删服务配置**。项目检索未发现独立的新约定文档，因此在这里显式记录该约束，不把历史 harness 的 finally 整目录清理当作当前用户许可。

- 保留用户服务、监听草稿、saved/active journal、应用 UCI、测试说明/非秘密证据；不做 factory-reset，不恢复过期 revision0 覆盖用户 revision1。
- 生命周期 Stop 应移除自有进程、listener、TLS 运行快照/自有授权标记；后续 cleanup 只处理精确 ownership 可证的私钥/短期认证材料及残留，不删除源业务证书/密钥或其他实例。
- 真实目标清理或测试执行需父任务范围授权。本轮只读本地/WSL，未运行任何清理或服务操作；不宣称目标无残留。
- 现存 P4 lifecycle harness 有删除 `/root/homepublish-p3-controller-auth` 等 fixture 清理规则；下一位执行前应按此约定复核 finally，分开“必须删除的秘密/运行残留”与“应保留的服务配置/测试数据”。

## 7. 可行与阻断交接

- **可行**：已存在匹配的 x86_64 SDK、compiler 和充足 ext4 空间；当前无观察到的构建并发，锁可取得；无需安装新包即可继续冻结后基础 runtime/LuCI 交叉编译准备。
- **最终可追溯 build 阻断**：P4 dirty/最终来源未冻结；SDK 链接仍指旧 device-r9-source；私有 Nginx/sslh 无正式包所有权/路径依赖；libubus-lua 未声明；stream 能力不在现有 nginx 依赖保证内；release/组件安全与许可来源未关闭。
- **未完成且不冒称**：最终归档、最终 IPK、最终安装字节 manifest、安装/升级、外网 IPv6 验收。本轮未启动构建，因此没有 build PASS 或失败结果可报告。
