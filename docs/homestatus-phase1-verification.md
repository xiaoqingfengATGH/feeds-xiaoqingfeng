# HomeStatus phase1 最终本地验证

范围：隔离 Feed `wt-homestatus-app`（基线 8953489）及主题 `wt-homestatus-theme`（基线 d0bddb3），分支 `refactor/homestatus-phase1`。未修改原仓库工作目录，未部署/merge/push/PR。

## 实际命令与结果

在应用包目录，Node v26.7.0、pnpm 12.5.1、Python 3.14.7：

```sh
pnpm install --frozen-lockfile --ignore-scripts
HOMESTATUS_THEME=D:/DevPortal/homelede/wt-homestatus-theme/luci-theme-infinityfreedom-ng node --test tests/migration.test.cjs tests/regression.test.cjs tests/dom.test.cjs
node --check htdocs/luci-static/resources/view/homestatus/overview.js
node --check tests/migration.test.cjs
node --check tests/regression.test.cjs
node --check tests/dom.test.cjs
HOMESTATUS_OVERVIEW_CSS=D:/DevPortal/homelede/wt-homestatus-app/luci-app-homestatus/htdocs/luci-static/resources/view/homestatus/overview.css python D:/DevPortal/homelede/wt-homestatus-theme/luci-theme-infinityfreedom-ng/scripts/gen-palettes.py --check
# WSL/Linux prerequisites: python3, GNU make, /bin/sh, cp, find; writable TMPDIR
wsl -e sh -c 'export TMPDIR=/mnt/c/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch; python3 /mnt/d/DevPortal/homelede/wt-homestatus-app/luci-app-homestatus/tests/test_resource_packaging.py && python3 /mnt/d/DevPortal/homelede/wt-homestatus-theme/luci-theme-infinityfreedom-ng/tests/test_dependency_control.py && python3 /mnt/d/DevPortal/homelede/wt-homestatus-theme/luci-theme-infinityfreedom-ng/tests/test_prepare_paths.py'
git -C D:/DevPortal/homelede/wt-homestatus-app diff --check
git -C D:/DevPortal/homelede/wt-homestatus-app diff --cached --check
git -C D:/DevPortal/homelede/wt-homestatus-theme diff --check
git -C D:/DevPortal/homelede/wt-homestatus-theme diff --cached --check
```

实际结果：lockfile up to date；Node `tests 10 / pass 10 / fail 0`；最终审查修复由父任务完整复跑：WSL resource packaging `Ran 1 test / OK`、dependency control `Ran 1 test / OK`、prepare `Ran 3 tests / OK`，Node 三份 10/10 与 palette --check 再次通过；4 次 node --check、palette --check 及两边工作区/暂存区 diff --check 均 exit 0，最终输出 `FINAL_LOCAL_CHECKS_OK`。Git 提示生成 CSS 的 LF 将自动转换 CRLF，未产生 whitespace 错误。首次安装提示间接依赖 whatwg-encoding@3.1.1 deprecated，不影响本次执行；未据此声明依赖安全审计完成。

## RED→GREEN

1. release=2 与 standalone generator 必须显式环境变量两个测试先运行：`tests 2 / pass 0 / fail 2`；修复版本 4→2、去掉本机 fallback 并补清晰报错后 `pass 2 / fail 0`。
2. 原主题 Makefile 运行路径 fixture：任意 feed、显式 override、缺源报错三项全部失败；改为 wildcard package feed 链接+realpath、允许变量 override 和前置文件校验后 3/3。
3. 最终三份 Node 测试全量 10/10，主体逻辑与 CSS 均对比固定主题基线，DOM 验证经典节点身份、启动幂等、卡片/轮询/弹层。

## 真实设备只读观察

SSH 连接显式 `ProxyCommand=none`、`ProxyJump=none`、`IdentitiesOnly=yes` 后已恢复。只读输出：

```text
Linux 6.18.55
/usr/bin/ucode
luci-app-homestatus - 1.0.0-r1
luci-base - 26.268.60624~3e89467
luci-mod-status - 26.280.31797~eac442a
luci-theme-infinityfreedom-ng - 2.0-ucode-r4
STATUS_INCLUDE_PRESENT
```

组合命令最后检查 `/usr/share/ucode/luci/template.ut` 不存在，导致总体 exit 1；该路径探测不证明模板引擎缺失。本轮没有继续猜测安装路径、上传模板或覆盖生产文件。先前 reset 不应解释为不监听或密钥错误。

## 证据限制

旧空 luci.mk fixture 仅证明自定义 recipe 路径，不能证明真实 LuCI 的宏覆盖和执行顺序；上面的早期路径 RED→GREEN 不应读成 LuCI buildroot 成功。最终 fixture 已改为真实 24.10 luci.mk：prepare 从 package.mk 提取 Prepare/Pre→Build/Prepare 顺序，确认 palette 先生成后复制，ucode/root 同时复制；control 从 package-pack.mk 提取真实 CONTROL 宏；应用 packaging 执行真实 prepare/install，开启全局 minifier 并证明包级禁用生效、安装 JS/CSS 字节不变。

周边 rules.mk/package.mk 仍使用最小桩，生成器和压缩器使用替身；不执行完整 BuildPackage/toolchain，未生成或安装 IPK。宏 fixture 不是 SDK/IPK、包管理器安装或目标依赖验收。Node 使用 jsdom/模拟 RPC，不是目标 loader/browser。没有新版本部署、设备模板编译、真实 RPC/浏览器、LAN/WOL 或视觉验收。设备只读版本仍为旧版；不得称已真机验收。

Windows 原生 Python 首次运行 packaging 报 WinError 2（缺 GNU make），属于环境前提而非产品失败；父任务随后在 WSL 完整重跑上述三份 Python 测试通过。本次收尾只修改文档、补溯源及提交，不重复长探索或目标浏览器验证。

## 审查修复与真实 CONTROL 证据

- 主题不覆盖随后被 luci.mk 重定义的 Build/Prepare，改为 `Hooks/Prepare/Pre += Build/PreparePalettes`，在 LuCI 复制资源之前生成 palette。
- 主题保留 `LUCI_DEPENDS` 的构建选择，新增 `LUCI_EXTRA_DEPENDS:=luci-app-homestatus (>=1.0.0-r2)` 运行时版本下限。实际 CONTROL 宏输出：

```text
Depends: luci-app-homestatus (>=1.0.0-r2), luci-base, luci-app-homestatus
```

同名包重复分别来自 EXTRA floor 与 LuCI build-selection 的依赖展开，不代表两个安装实例。宏测试未发现冲突，无需仅为去重重写；只有真实 SDK/opkg 发现问题才需进一步处理。

- 应用设置 `LUCI_MINIFY_JS:=0`、`LUCI_MINIFY_CSS:=0`，保持旧主题不再压缩的迁移契约。

## fixture 来源、SHA-256 与许可证

本次用 Python hashlib 对本地原始字节计算，应用 luci-24.10.mk 与主题 luci.mk 相同：

| fixture | 来源 URL | SHA-256 | 保留的许可证头 |
|---|---|---|---|
| luci.mk / luci-24.10.mk | https://raw.githubusercontent.com/openwrt/luci/openwrt-24.10/luci.mk | bc1a97fb6c3b4fef065227c6d1530ee580f0af3966d36a967fbca2da1c7000ac | Apache-2.0，The LuCI Team 2008–2015 |
| package.mk | https://raw.githubusercontent.com/openwrt/openwrt/openwrt-24.10/include/package.mk | 1e658561abd13b1ddb4a5a2e9ac78032b584477e9a764767621c0e4dae02782d | GPL-2.0-only，OpenWrt.org 2006–2020 |
| package-pack.mk | https://raw.githubusercontent.com/openwrt/openwrt/openwrt-24.10/include/package-pack.mk | 3c51015e5df1d568b1e6bfc474e986538ff6cc7270d338909fee68911ebb41d2 | GPL-2.0-only，OpenWrt.org 2006–2022 |

完整快照未经源码修改、保留第三方版权/许可证头；许可证正文及各包测试边界另见应用 `tests/fixtures/README.md` 和主题 `tests/fixtures/openwrt-24.10/README.md`。URL 指向可变分支，未记录上游 commit，复现以已提交快照及本地 SHA-256 为准。收尾访问 raw GitHub 连接 reset（urllib/curl 均失败），没有声称当前远端字节已重新比对。
