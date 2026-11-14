# HomePublish 当前测试集

> 最新决定以 CURRENT-IMPLEMENTATION-CLEANUP.md 为准：本轮另删除 43 个已退出实现的测试/夹具/驱动；不是继续禁用保留。当前本机为 86 tests、54 subtests，另有 8 项 Worker 与目标证书两组；已纳入 current suite。下文旧数量和保留说明为此前记录，不再作为当前状态。

从仓库根目录运行（Windows/Git Bash，需 uv、Python 3.13 和 Node.js）：

```sh
uv run --no-project --python 3.13 --with lupa --with pytest python homepublish/tests/run-current-suite.py
uv run --no-project --python 3.13 --with lupa --with pytest python homepublish/tests/run-current-suite.py --target
```

安装了 GNU make 时，也可在 `homepublish/tests` 执行 `make current` / `make current-target`；当前 Windows 未提供 make，已验证的是上面的 Python 入口。旧 Makefile 目标拒绝执行已在 VM250 用相同 Makefile 验证。第二条连接 192.168.1.2 root，使用 `D:/DevPortal/CloudHosts/HomePri.key`，在目标 `/root/homepublish-lua-store/` 和独立 `/tmp/homepublish-restart-*` 运行夹具，并创建独立 procd 实例；不部署包、不修改生产配置或主动重启生产服务。它会写私有文件及测试证据，请确保主机、密钥和空间适用。重启夹具对生产 journal、防火墙配置和 nginx 配置做前后比较；store 夹具使用独立根，不应与同一源目录的并发测试同时运行。测试证据写入仓库 `docs/evidence/lua-store/` 和 `BH_AGENT_WORKSPACE`（Windows 默认 Hermes scratch，其他环境默认用户目录）的 `homepublish-current-suite/`。失败即停止并返回非零。

## 覆盖

- 本地：明确选择 18 个 pytest 文件（当前 79 项与 54 个子测试，包含历史生产入口拒绝执行测试），覆盖防火墙计划、故障分类、重启语义、探测、打包、后端范围、渲染和监听器约束等。以及 Node Worker 8 项；pytest 输出分别报告 tests 和 subtests，不将模块导入时的附加断言计入测试数量。
- 目标：实际 OpenWrt Lua/nixio、私有真实 journal；存储契约、错误分类、写入故障、候选清理、锁及资源、迁移、路径安全、验证；独立的控制器重启、单次交接、procd 启动；包含 retry 预算、清理失败恢复、启动策略、过期和待应用配置边界。

## 非本套覆盖

本套不是完整发布验收：不运行真实 nft 私有命名空间故障链、sysupgrade、设备重启、网络协议实际流量、UI、安装/失败/回滚、不同设备与架构；这些需另行按隔离和授权条件执行。也不保证 `pytest homepublish/tests` 可用：历史目录包含在模块导入时运行的脚本、WSL 旧 SDK 固定路径和早期架构测试，不能全量当 pytest 测试收集。

## 实际包检查

```sh
python homepublish/tests/check-current-ipk.py <homepublish.ipk>
python homepublish/tests/check-companion-ipk.py --complete <luci-app-homepublish.ipk> <homepublish-engines.ipk>
python homepublish/tests/build-test-inventory.py

# 一次运行本机、1.2 与三个实际包检查（目录中每种包必须恰好一个）
uv run --no-project --python 3.13 --with lupa --with pytest python homepublish/tests/run-current-suite.py --target --ipk-dir C:/Users/xiaoq/AppData/Local/hermes/cache/scratch/hp-r13
```

已用 VM250 的 core 0.1.0-13、LuCI 0.1.0-r9、engines 1.30.6-1 实际产物执行通过。核心 Lua 与 LuCI root/htdocs 文件逐字节核对（只规范 CRLF）；校验配置权限/默认禁用、依赖、持久化 keep 文件存在、菜单/ACL JSON、RPC 可执行且不可全局写、nginx/sslh-select ELF 及 x86_64 ELF 头。归档检查不是安装或完整 ABI 证明。

## 历史用例处理

完整清点与最终决定见 `TEST-INVENTORY.csv` 和 `TEST-AUDIT-DECISIONS.md`；初步审查报告不是执行授权。除下面三个旧测试外，两个会恢复旧生产配置的 R8/R9 驱动也已删除；18 个历史 Python 生产写入入口及 R7 shell setup 无条件拒绝执行，旧 Makefile 目标也拒绝执行。保留的专项夹具不是“通过”或“待删除”，而是明确保留未被等价替代的覆盖。

- 已删除 `test-product-lifecycle.py`（旧 C store/init）、`test-recipe.py`（旧 C store 安装假设）及 `test-ipk.py`（固定旧 SDK、旧架构）。当前生命周期关键边界由 `device-restart.lua` 覆盖；真实包检查可使用 `python homepublish/tests/check-current-ipk.py <ipk路径>`。新检查不声称逐断言等价于旧测试，也不能替代目标安装测试。
- `test-guardian-nginx.py`、`test-certificate-metadata.py`、`test-trusted-provider.py` 等固定旧 SDK 路径的脚本，以及旧 milestone/部署脚本，不因现环境缺少 SDK 就断言逻辑完全无价值。历史 Makefile 目标仅供参考；需逐项审查其架构、依赖和安全后迁入当前套件。
- `test-product.py`、`test-product-review.py` 是设备脚本入口，包含测试目标和基线假设，不能作为通配 pytest 导入；不得通过绕过保护来强行运行。

实际覆盖范围由 `run-current-suite.py` 中的显式清单定义；更新测试时先确认其隔离边界和当前构建架构，再加入清单。
