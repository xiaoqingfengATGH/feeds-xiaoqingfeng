# HOMEPUBLISH r9 重构执行计划（两轮已验证侦察固化）

> 本文件由 TA 固化两轮只读侦察结论。执行者**先读本文件，再动手**，不要重复侦察。
> 仓库：`D:/DevPortal/homelede/homepublish-product`，分支 `feature/homepublish-product`，基线 HEAD `71643ac`（r8 已装设备、已完全清理：revision0/disabled/stopped/cleanup confirmed）。
> untracked 必须保持不入 commit：`homepublish/tests/__pycache__/`、`sketches/001-guided-setup/`、`sketches/001-native-list/`。

## 用户需求（原话归纳）
1. 传统 LuCI form.Map 风格大范围重构（现手写 DOM 不符用户习惯）。
2. 入口设置单独 TAB：Nginx 入口端口、默认证书（从 ACME 读）、发布策略等。
3. 接入服务参考 HomeTunnel 接入配置风格（GridSection）。
4. 证书选择从 ACME 读取证书列表。
5. 可配置参数放单独 TAB。
6. 移除假能力门控（用户已授权 127.0.0.1:222 实机开启配置、实机测试）。

## 已验证事实（不要再花预算重查）

### 假门控位置
- `homepublish/files/usr/share/homepublish/product-provider.lua` L59：`public()` 内 `out.capabilities={start=false,apply=false,stop=true,reason="installed public provider unsupported"}`；同文件 `M.handle` 对 start/apply 返回 `'unsupported: runtime not implemented'`。
- `homepublish/files/usr/share/homepublish/product-cli.lua` L20：仅当 `/etc/homepublish/device-test/enabled` 存在且经 `product-channel`（controller unix socket `/var/run/homepublish/control.sock`）成功时改写 capabilities={start=true,apply=true,stop=true,scope=...}。
- UI 侧：`settings.js` `refresh()` 与 `overview.js` `refresh()` 均以 `cap.start`/`cap.apply` 禁用按钮。

### 现有视图
- `luci-app-homepublish/htdocs/luci-static/resources/view/homepublish/`：`settings.js`（53 行手写 DOM 四 tab）、`product.js`（56 行 RPC+actionDialog+diff+defaults，两视图共用）、`overview.js`（32 行中文概览路由）、`schema.js`（旧 homestun 校验，仅 ui.test.cjs 引用）。
- `menu.d`：overview(order10, view homepublish/overview) + services(order20, view homepublish/settings)，firstchild。
- 参照风格：`D:/DevPortal/homelede/feeds-xiaoqingfeng/luci-app-hometunnel/htdocs/luci-static/resources/view/hometunnel/` 的 `settings.js`（form.Map+NamedSection）、`ingress.js`（GridSection addremove+anonymous+sortable、Flag/Value+datatype/ListValue/DummyValue）。

### canonical 模型（schema_version=1）
- `services[]{service_id,name,hostname,backend{addressFamily ipv4|ipv6|hostname,host,port,allowed_ranges[]},certificate_mode inherit|override,certificate_ref(acme:|import:),enabled,authentication_review{authentication confirmed|unconfirmed,management}}`
- `default_certificate_ref`、`access_profile{methods_allowed[manual_ipv4|upnp_ipv4|direct_ipv6|stun_experimental],listeners[]{family,address,interface,zone,protocol tcp,internal_port 1024-65535,external_port}}`
- `publication_policy{mode continuous|temporary,temporary_duration 60-86400,boot_restore}`
- 注意：**无独立入口 port 字段**，Nginx 端口=listener internal_port；canonical 禁 IPv4 loopback 入站（device provider 服务端把 192.168.1.2 收窄为 127.0.0.1）。

### device-test provider 约束（fixture 验收范围，不得放宽）
- `product-device-provider.plan()`：≤2 服务；service_id 仅 `fixture`/`fixture2`；hostname 仅 `a.fixture.home`/`b.fixture.home` 配 `acme:fixture_rsa`|`acme:fixture_ecc`（或业务 `home.iwonderful.top`+`acme:home_rsa`）；backend 仅 `127.0.0.1:49285`|`127.0.0.1:49286`；authentication=confirmed 且 management=false；恰 1 个 ipv4 listener `192.168.1.2/br-lan/lan/49284/49284`；methods_allowed=['manual_ipv4']。

### form.js API（LuCI 24.10.5，SDK feeds/luci/modules/luci-base/htdocs/.../form.js 已读）
- GridSection.handleAdd→data.add→renderMoreOptionsModal（子 CBIMap+NamedSection+cloneOptions+addModalOptions→m.render() 模态）；handleModalSave→activeMap.save(null,true)→父 map load/reset。
- `CBIJSONMap(data)` 支持 `{type:[...]}`、add/remove/set/sections、save() 为 no-op——**服务 GridSection 可用 JSONMap 承载 RPC saved_config 而非 UCI**。
- Map.save(cb,silent)=parse→cb→data.save→load→renderContents（datatype 违规即 reject）。
- ui.js apply 确认后 dispatch `'uci-applied'`。
- 主题补丁参照 hometunnel `ui.js` 的 `htui.apply`，homepublish 需自带等价物（若现有 product.js 无此需求可先不做，以浏览器实测为准）。

### 工具链
- 构建：WSL SDK `/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64`；复用 `homepublish/tests/build-r8.sh` 模式（`flock /home/eric/homestun-sdk-check/build.lock`、`git -c core.autocrlf=false archive` 到 device-r9-source、`ln -sfn package/feeds/homestunlocal/{homepublish,luci-app-homepublish}`、defconfig 后 `grep CONFIG_PACKAGE_*=m`、`make compile -j2`、产物 `/mnt/d/DevPortal/homelede/artifacts/homepublish-r9/`）。
- 部署/实机：`ssh -o ProxyCommand=none -o ProxyJump=none -o IdentitiesOnly=yes -o BatchMode=yes -i D:/DevPortal/CloudHosts/HomePri.key -p 222 root@127.0.0.1`。
- fixture：`homepublish/tests/router-r7-browser-setup.sh`（/etc/acme/*.fixture.home RSA + *.fixture.home_ecc、uhttpd 后端 49285/49286 markers HP_R7_A/HP_R7_B、/etc/homepublish/device-test/enabled、listener 49284）。
- 浏览器生命周期：`luci-app-homepublish/tests/overview-lifecycle.cjs`（Chrome+官方 LuCI loader+本地 18995 bootstrap，/ubus 与静态资源代理到 127.0.0.1:1081；**1081 隧道来源未查明，下轮先 `grep -rn "1081" homepublish/tests/` 找隧道建立方式**）；驱动脚本 `homepublish/tests/run-r8-overview.py`（备份 state/acme/firewall/listeners/routes→setup→node overview-lifecycle.cjs→finally 完整清理 CLEANUP_PASS）。
- Lua 测试：`homepublish/tests/Makefile`（WSL `LUA_TEST=/home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1`）；`test-product-provider.lua` 未断言 capabilities（grep 证实 tests 无 'capabilities'），provider 改真实能力不破坏现有 Lua 测试。
- Node 测试：`node --test luci-app-homepublish/tests/*.test.cjs`（ui/validation/save/row-lifecycle）；**ui.test.cjs 断言的是旧 settings DOM 与旧 ACL（uci read/write）——与当前 ACL（ubus-only read status/validate/certificates + write save/stop/start/apply）已不符，基线疑似已红，先跑基线再重写为 r9 RED**。

## 执行步骤（1-10）

1. **RED**：重写 `ui.test.cjs` 等为 node:test 断言：settings/服务视图源码含 `form.Map`+`form.GridSection`+`NamedSection`、证书 TAB 只读表、无 `'installed public provider unsupported'` 与 cap.start/cap.apply 禁用逻辑。先跑确认 RED（若 ui.test.cjs 基线已红，先记录再重写）。
2. **GREEN 视图**：新结构：
   - menu.d 四 tab：overview 保留；**services**=GridSection（JSONMap 承载 RPC saved_config：Flag enabled / Value name / Value hostname datatype=hostname / Value backend_url / ListValue 证书=继承默认+ACME 库存；modalizable 增删改）；**entry**=NamedSection（listener internal_port/external_port datatype=port、family、interface/zone、default_certificate_ref ListValue、publication_policy mode/temporary_duration/boot_restore Flag）；**certificates**=certificates RPC 只读表（身份/SAN/有效期/被哪些服务用）。
   - 语义：Save=RPC save（pending 不启动）；`handleSaveApply`=save 后弹确认对话框展示 `api.diff` 具体差异与整组影响→确认才 `api.apply(approved=true)`；Start/Stop 沿用 product.js actionDialog；**按钮使能只由 saved_revision/running/pending/cleanup 真实状态驱动**。
3. **provider**：`product-provider.lua` `public()` 改 capabilities={start=true,apply=true,stop=true}（已安装即真实能力）；保留 M.handle 后端权威校验路径（CLI→device-test channel→controller 权威拒绝）；`product-cli.lua` 的 device-test capabilities 改写随之冗余可删。
4. **版本**：两 Makefile `PKG_RELEASE:=9`。
5. **回归**：`node --test` + WSL make（homepublish/tests）+ `make product rpc browser`。
6. **build**：`build-r9.sh`（照 build-r8.sh，flock 复用）双 IPK → `artifacts/homepublish-r9/`。
7. **部署**：scp 双 IPK 到 127.0.0.1:222 安装，LF manifest 逐文件比对 Git blob。
8. **实机全链路**：按 run-r8-overview.py 模式：入口端口+默认证书→GridSection modal 新增服务→Save pending→Start 真 TLS marker→修改→Save&Apply 确认对话框差异→整组切换→Stop 已建立连接关闭/快照删除；overview-lifecycle.cjs 按新 form.Map UI 重写选择器。
9. **清理**：run-r8-overview.py finally 块原样（revision0/ACME cmp/fixture 删除/firewall hash/监听路由不变 CLEANUP_PASS）。
10. **docs+commit**：REQUIREMENTS.md / docs/HOMEPUBLISH-R9-*.md 记录 + local commit 不 push。

## 安全合同（保留，不许放松）
- Save 永不启动；Start/Apply 需明确确认（approved=true）；手动 Stop latch；临时截止不因 Save/Apply/恢复延长。
- 后端权威校验路径保留（UI 只是门控移除，后端拒绝路径不动）。
- 禁止：fw/UPnP/公网暴露、DNS/代理/现网 ACME 配置修改、push/merge/PR、私钥导出或打印。

## Worker 分工
- **Worker A（源码）**：只做步骤 1-5 + 步骤 10 的 docs/commit。不碰设备、不跑 SDK。
- **Worker B（构建+实机）**：读 Worker A 的 commit 与本文件，做步骤 6-9 + 最终 docs/commit。

## 进度快照（2026-10-15 收工，commit e40a679）
- 步骤 1-6 已完成：r9 源码全量落地 + SDK 双 IPK 构建并安装实机（127.0.0.1:222，capabilities 全 true，四 tab 正常）。
- **用户新指令（覆盖上文本地测试流程）**：
  1. 禁止一切本地测试（WSL Lua/chroot fixture/node 全套）——脚本直接上实机跑。
  2. 日常迭代不编 IPK：改完源码 scp 直传实机安装路径（如 /usr/share/homepublish/*.lua、/www/luci-static/resources/view/homepublish/*.js），重启 daemon（rpcd reload 等）后实机验证。IPK 仅里程碑版本用。
  3. 每阶段完成即停，无用户指令不进下一步。
- **步骤 7/8 中断点**：实机 lifecycle 跑到「入口页 Save」被 `保存失败：array size` 拒。
  - 根因：canonical `array(c.services,1,16)` 与 r9「先存入口后加服务」拆页流程冲突。
  - 修复（已 commit e40a679，**未上机**）：canonical.lua L101 → `array(c.services,0,16)`（Start 空配置仍被 runtime_plan `no enabled services` 拒，test-canonical.lua 已锁语义）；r9-device-lifecycle.cjs 会话 ACL 补 `uci get`。
  - 本地曾跑过 canonical/product/rpc 回归全绿（controller 基线失败为 pre-existing 环境问题，非本次引入）。
- **明天续接（等用户指令后）**：scp canonical.lua + r9-device-lifecycle.cjs 相关改动到实机 → rpcd reload → 跑 run-r9-device.py（或直接 node r9-device-lifecycle.cjs）继续步骤 8 全链路。
- 实机脚本：`homepublish/tests/run-r9-device.py`（pre/setup/node lifecycle/finally cleanup 还原）+ `luci-app-homepublish/tests/r9-device-lifecycle.cjs`（选择器已按 r9 form.Map UI 适配：modal `.cbi-button-add`/`[data-field$=".xxx"]`、`.cbi-button-positive`、行编辑 `.cbi-button-edit`、双 input 用 .first()）。
