# 测试清理最终决定

> 最新决定以 CURRENT-IMPLEMENTATION-CLEANUP.md 为准：本轮另删除 43 个已退出实现的测试/夹具/驱动；不是继续禁用保留。当前本机为 86 tests、54 subtests，另有 8 项 Worker 与目标证书两组；已纳入 current suite。下文旧数量和保留说明为此前记录，不再作为当前状态。

本文件为本轮最终决定，优先于 NON-PYTHON-AUDIT.md 与 PYTHON-RUNNERS-AUDIT.md 的早期“全部暂留”描述。完整逐文件索引由 `python homepublish/tests/build-test-inventory.py` 生成 `TEST-INVENTORY.csv`，枚举 Git 管理及未忽略的新文件，排除缓存和 CSV 自身。索引仅证明清点完整，不证明每项已执行或断言等价。

## 删除

| 文件 | 确认过时的依赖/行为 | 替代或保留覆盖 |
|---|---|---|
| test-product-lifecycle.py | 旧 C store / 旧 init 文本契约 | device-restart.lua 的当前私有 Lua journal、controller/marker/procd 生命周期；旧实现断言不保留 |
| test-recipe.py | 旧宿主 Lua C 编译及安装 homepublish_store.so | 当前实际 core IPK 检查 Lua 文件、权限/默认禁用；引擎包单独检查 ELF。不是重建旧宏编译环境 |
| test-ipk.py | 固定 homestunlocal SDK 目录、旧 helper ELF 和 native store | check-current-ipk.py + check-companion-ipk.py：当前三个实际包、源码一致性、配置/执行权限、依赖、menu/ACL、引擎 ELF；不是安装或 ABI 测试 |
| run-r8-overview.py | 固定旧隧道/页面基线；finally 删除生产 product 并恢复旧备份 | 删除危险驱动，不声称 UI 全覆盖已替代；overview-lifecycle.cjs 和相关夹具仍保留，浏览器验收不在当前用户要求范围 |
| run-r9-device.py | 同类生产配置回退风险与旧 R9 UI 基线 | 删除危险驱动，r9-device-lifecycle.cjs 保留专项断言，不再恢复旧生产状态 |

上述删除的历史来源可由 Git 查看；历史验收文档不是当前操作指南。

## 禁用而不删除

18 个 deploy/finalize/resume、rpc-luci-fixture 和 P5 production Python 入口在任何 import、SSH 或其他副作用之前无条件 SystemExit；router-r7-browser-setup.sh 在操作之前 exit 2。无环境变量旁路。保留源码是因为部分 verify/receipt 会动态读取/exec 它们，而专项断言与历史凭证仍有价值。其调用链也可能因此明确失败，这是有意隔离，不是当前有效套件。不要解除保护来使旧工具跑通。

`test-retired-entrypoints.py` 验证早退的 AST 位置，并实际运行每个受保护 Python 入口及 shell 入口验证拒绝；同时验证两个危险驱动不存在。它已纳入当前回归集。

Makefile 的旧 SDK 集成目标统一拒绝执行；有效默认入口只有 current/current-target。若将来迁移专项测试，先将其改造成私有根、无生产回退的夹具，再恢复专用入口，不恢复原危险脚本。

## 其余文件：保留专项覆盖，不冒充当前回归

- 原生 lease-supervisor / renewable-guard / publisher / owned-runtime / trusted-provider 等：对应 C 源码仍在树中，包含进程身份、子进程清理、socket 与路径竞态专项边界；Lua store 测试不能等价替代。这一轮决定保留，不再以“待删除”悬置。运行要求隔离 Linux、root/chroot 或 SDK，不属于当前固件回归通过记录。
- certificate metadata / inventory / SAN 与 openssl-engine：实际 OpenSSL 和证书语义仍有价值，旧工具链路径需按专项测试部署环境解析；不能因缺 SDK 删除。
- controller/multi/recovery/direct/shared-runtime：保留旧 provider 集成覆盖，不作为当前已安装 Lua/procd 架构验收；旧 Makefile 快捷目标已禁用。
- P1/P3/P4/P5 私有设备 runner 与 helper：存在相互引用、隔离保护和故障矩阵，保留；只有当前清单中重跑过的入口算本轮通过。安全测试对旧入口的引用仍保留，不通过删除这些测试来掩盖安全条件。
- 浏览器、协议真实流量、固定历史证据的设备脚本：用户已排除本轮业务流量/浏览器验收，保留专项代码，不运行旧生产写入链。
- C/Lua/shell/JS 夹具：详细线索见 NON-PYTHON-AUDIT.md；没有证明重复的独立专项断言保留。当前 Worker 两个测试文件确实运行，不能将其他夹具也算通过。

## 可执行结果与未覆盖边界

以 TEST-SUITE.md 命令及真实执行输出为准。core / LuCI / engine 三个归档均已检查；ELF 头、架构和权限不等于目标 libc ABI。当前隔离目标机用例可在 1.2 执行，不需停生产服务。真实失败安装/包回滚、sysupgrade、boot_restore=true 整机重启仍是独立维护窗口场景；本轮测试目录整理没有执行这些破坏性操作，也没有把它们标为通过。
