# HomePublish 跨主机 Hermes 接续入口

这是当前接续权威入口。先读本文，再读具体阶段账本；旧 RESUME/PAUSE 是历史快照，不可覆盖当前状态。新主机不需要原会话或 Hermes 私有 memory/skills 才能理解任务。

## 1. 获取工作区

仓库 `git@github.com:xiaoqingfengATGH/feeds-xiaoqingfeng.git`，分支 `feature/homepublish-product`，不是 main。克隆后 checkout 该分支，读取本文。不要合并、创建PR或推main。提交中记录的是开发检查点，不是P5发布完成。

## 2. 当前准确进度 / 下一件事

- P0–P3已提交；本次检查点补齐P4/P5源码、测试、证据及组件配方。
- P4限定设备生命周期验收完成。
- P5正式生产provider已支持HTTPS/TLS透传/原生SSH/独立TCP；新Nginx1.30.6、sslh2.3.1已在产品私有路径部署。最终完整产品IPK尚未构建/安装，P5不能宣称结束。
- 最新用户方向：不希望维护自有C存储。**下一工作是按 `.hermes/plans/2026-10-16_152409-homepublish-lua-store-replacement.md` 审阅后实施Lua替换；目前仅计划，C尚未删除。** 不要把C方案继续强化，也不要假称替换已完成。当前迁移交接请求没有额外授权自动实施该计划。
- 先读 `homepublish/src/product-store.c`、`product-provider.lua` 和 Makefile，理解现有 transaction 契约。计划保留格式和最小短锁/原子替换，使用系统Lua/nixio，不引Node/数据库/guardian。

## 3. 必读文档顺序

1. 本文。
2. 上述Lua替换计划。
3. 冻结范围 `.hermes/plans/2026-10-15_143056-homepublish-tcp-ingress-luci.md`。
4. `docs/HOMEPUBLISH-TCP-P5-INTEGRATION.md`、`HOMEPUBLISH-TCP-P5-BACKEND-COMPLETE.md`。
5. `docs/HOMEPUBLISH-TCP-P5-ORDINARY-UI.md`、`HOMEPUBLISH-TCP-P5-FINAL-MATRIX.md`。
6. `docs/HOMEPUBLISH-TCP-P5-PACKAGING.md`、`HOMEPUBLISH-TCP-P5-REVIEW.md`（审查是发现时快照，部分缺陷后来修复，以最终证据逐条核）。
7. REQUIREMENTS.md、产品设计、review checklist及 REFACTOR 文档；其中阶段性历史记录不可当最新结论。

## 4. 必须延续的用户约定

- 目标代码只在授权真实OpenWrt测试机验收。本机Python/Playwright仅驱动远程，不用本地Lua/Node替身冒充目标测试。
- 源码直接上传安装路径，匹配部署后实机验证，迭代不编IPK；里程碑才SDK打包。测试部署/启动已授权，IPK安装升级另授权。
- 用户允许测试机Start，允许保留服务配置/测试数据。结束默认停止发布，清理自有进程、临时认证私钥/证书快照；不要清空测试服务或恢复旧revision。
- 禁止擅改全局防火墙、路由、DNS、认证、UPnP或公网开放；不改Passwall2/管理服务。不重置密码。
- 原生LuCI JSONMap/NamedSection/GridSection，四独立菜单；不造自定义表单或向导。overview增量poll，不能重新render整个Map。列表摘要DummyValue设modalonly=false且optional，避免弹窗null。
- TDD：新行为目标机RED→GREEN，最后字节上传再回归，独立核验子任务。不能只信子代理GREEN，不能用历史PASS覆盖当前失败。
- 不创建PR；合并/主分支push须用户指示。当前跨机同步仅功能分支检查点。

## 5. 设备与迁移前提（机器相关，不能直接照搬 localhost）

旧主机访问 SSH `root@127.0.0.1:222`，LuCI `http://127.0.0.1:1081/cgi-bin/luci/admin/services/homepublish/overview`。**这些是旧主机映射，新主机127.0.0.1不是同一设备**。请用户提供/恢复等价可达映射，确认目标身份后才操作，禁止对新机器本地未知端口盲部署。

旧密钥路径 `D:/DevPortal/CloudHosts/HomePri.key`，不在Git内。通过安全方式由用户配置新主机访问，不能从日志/仓库猜凭据。旧SSH需禁全局代理：
`ssh -o ProxyCommand=none -o ProxyJump=none -o IdentitiesOnly=yes -o BatchMode=yes -i <USER_KEY> -p <PORT> root@<HOST>`；scp旧系统需要 `-O`。

最近设备状态（恢复需重新查）：普通保留服务 `svc_1 / P5 ordinary retained HTTPS`，saved_revision3，active_revision3，disabled/manual_stop_latch/stopped/active_verified=false。state SHA256 `6995a844e18ac2c9182b3e4f8035138ebe561aee168530d43c550d5ee14be7d1`，备份 `/root/homepublish-p5/ordinary-before/homepublish.tar`。不要恢复旧rev0/rev1。默认入口8443，原地址/默认证书/策略保留。业务证书引用 `acme:home_rsa` / home.iwonderful.top（原入口有ECC默认引用），私钥留服务器，禁止入Git。

## 6. 工具链与可重建资源

- 旧主机Windows11 git-bash，原工作区D:/DevPortal/homelede/homepublish-product；新主机按实际目录调整。脚本有硬编码路径，要先审查，不要用全局替换破坏历史证据。
- Python驱动无必要pip假定；旧机python/pip版本不一致，使用明确解释器。浏览器使用Playwright与用户已有认证session；认证/session文件不在Git。不能复制旧会话令牌入Git。
- SDK旧机WSL Ubuntu-24.04路径 `/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64`；x86_64 musl GCC13.3.0。新机自行安装匹配SDK，不把旧绝对路径当可用。
- 共享锁旧路径 `/home/eric/homestun-sdk-check/build.lock`，先查make/timeout进程再持锁，不能timeout就重复启动。
- 组件重建规则在 `homepublish-engines/Makefile`、`build-components.sh`，下载URL/hash与依赖见PACKAGING。补丁依赖SDK packages feed，固定feed版本见该文档。从源码重建，不依赖旧WSL二进制目录。当前recipe仅x86_64，其他架构需要额外适配。
- 已部署Nginx SHA256 `941b54d84fc4fd40b0257e42195899f0bd77895ec0486e3e263344c2fa8dc08a`，sslh `1b9746f96d31624eb2cfa4076ca7eb0b636979321dbec92947171f780ee38db7`，路径/usr/libexec/homepublish/；不替换系统管理Nginx。
- 旧WSL对应材料包 `/home/eric/homestun-sdk-check/tcp-ingress-p5/component-materials.tar.gz`（含重链接材料）不在Git；源码/构建方法与hash已入库，未来分发IPK必须重新生成并同时提供许可材料。迁移开发无需取得旧产物；若要求逐字节旧产物/原许可包，需另安全传输，该目录不是克隆能带来的。

## 7. 实测证据与明确剩余

父级已独立运行成功：run-device-tcp-p5-four.py、run-device-tcp-p5-complete.py、run-device-tcp-p5-matrix.py；日志见docs/evidence/tcp-p5/*parent.log。
普通正式LuCI HTTPS Start→Save保持A→ApplyB→Stop通过：ordinary-ui-run5.log/ordinary-ui.json，无SSH RPC桥/响应模拟。四协议普通页面完整操作覆盖仍不是已通过项。
最终矩阵精确7case：四种v4/v6入口×后端组合各四协议；另TLS-only、SSH-only、TLS+SSH无HTTPS/默认证书并与TCP共存。设备本机访问真实LAN/ULA非外网。`final-matrix-green.log`是失败尝试！最终为final-matrix-final.log与parent.log。
S2第二Web域名/证书覆盖实测缺第二域名证书：现有RSA/ECC只覆盖home.iwonderful.top，不得擅申请/修改ACME或冒称完成。
公网、独立外部IPv6、物理reboot、代理reload完整共存等未验。方法级HTTP /ubus ACL拒绝已验，不等于完整用户名→LuCI角色映射。

## 8. 新主机恢复步骤

1. checkout feature/homepublish-product，确认HEAD和clean status，读本文/计划/账本。
2. 用户配置正确目标和SSH密钥、浏览器认证；失败先询问，不清密码。
3. 只读核设备身份、journal哈希/revision、已安装模块/引擎SHA、发布procd/监听、管理服务；差异先分析，勿自动覆盖。
4. 阅读runner中的SSH/路径/端口/证书/cleanup常量，按新主机环境做最小配置后才执行。所有runtime测试串行，先备份，保留数据。
5. 实施Lua替换前建立目标机baseline；按计划推进，最后真实页面/四协议回归并更新账本。
6. P5里程碑打包与S2缺口另闭环；不把当前迁移checkpoint当release。

凭据/浏览器session/原WSL缓存不入Git是刻意安全边界，不是遗忘。本文及源码/测试/证据是可移植接续依据；平台实际访问仍须用户在新主机配置。
