# HomePublish：用 Lua 替换自有 C 存储模块实施计划

> **For Hermes:** 按本计划逐项实施并独立复核；当前仅计划，不执行实现。实施加载 homedirect-development、homelede-development、test-driven-development。未经用户指令不 commit/push/merge，不新建 PR。

**Goal:** 移除自有 `homepublish_store.so` 和其 C 编译链，改为使用 OpenWrt 已有 Lua/nixio 文件接口的简单状态存储，保留现有配置与发布行为。

**Architecture:** 首批保留现有 journal 格式和 provider 的 transaction 回调契约，以 Lua 模块替换原生模块。保留一把进程间短锁和临时文件原子替换，不新增数据库、锁服务或自研守护器。持久状态与运行状态拆分作为后续独立优化，不与本次替换捆绑。

**Tech Stack:** Lua、OpenWrt 已有 nixio/nixio.fs、现有 wire 编解码、rpcd、procd、Nginx/sslh。无 Node.js，无新自有 C 代码。

---

## 1. 已核对的现状与范围

工作区 `D:/DevPortal/homelede/homepublish-product`，现有 P4/P5 未提交工作必须保留。

已核对代码：
- `homepublish/src/product-store.c`：C Lua 扩展，唯一核心接口 transaction，固定 PRODUCT_ROOT，migration_backup 能力。
- `homepublish/files/usr/share/homepublish/product-provider.lua`：handle 和 controller_transaction 两条调用路径，共用同一状态文件。不只是用户低频 Save，控制器也写状态。
- `homepublish/Makefile`：Build/Prepare 复制 C，Build/Compile 生成 .so，安装到 /usr/lib/lua。
- 历史实机测试以 PRODUCT_ROOT 宏编译隔离 .so；替换后测试也必须去掉此依赖。

本次不改变：canonical schema、state_version、saved/active/pending、临时截止、有界恢复、手动停止、RPC/ACL、LuCI 表单、配置生成和组件进程架构。

现有测试数据保留；最近确认普通 live 为 saved_revision=3，保留 svc_1 测试服务。实施前必须读回当前状态，不能以历史数字硬编码或恢复更早 revision。

## 2. 明确取舍

### 保留
- 写前校验、临时文件替换正式文件、失败不截断旧状态。
- revision 冲突检查和一把短的跨进程锁，覆盖读→回调→替换；锁只保护状态，不包住启动/网络握手等长操作。
- 目录0700/文件0600、拒绝常见不安全路径/符号链接；只使用固定应用目录。
- 原字节迁移备份和原格式可读性。
- 读失败/损坏返回错误，不能退回空配置后覆盖。

### 移除
- 自有 C 模块、编译宏、Lua ABI 二进制适配和对应包构建步骤。
- 对 inode/硬链接身份等逐项复刻原生实现的工程目标。
- 自有动态链接故障注入库作为新存储验收前提。
- 数据库式强断电持久性承诺。

使用 Lua 不代表操作系统完全无依赖：已有 nixio 库本身是系统原生能力。目标是“不维护自有 C”，而非“禁止所有系统 C 库”。Nginx/sslh 引擎依然按目标架构构建。

### 为什么暂留一把锁

当前 RPC Save 和 daemon 状态更新可来自不同进程。低频降低冲突概率但不能让丢更新变正确。复用系统已有 fd 锁是小成本保护，不新增并发框架。若 nixio 的目标版本不支持可用文件锁，先停在发现阶段报告；优先评估现有系统 lock 工具或统一写入口，不引入新的自有 C/复杂陈旧锁回收。

## 3. 模块布局和接口

新增：
- `homepublish/files/usr/share/homepublish/product-store.lua`：固定生产实例，导入实现，root=/etc/homepublish/product。
- `homepublish/files/usr/share/homepublish/product-store-core.lua`：仅内部 factory `new(root)`，便于目标机隔离测试；不得将 root/provider 参数暴露给 RPC 请求或环境自由覆盖。

修改 product-provider.lua 为从固定 source 路径加载 product-store.lua，不再 require homepublish_store。这样不受 Lua .lua/.so 加载顺序及历史残留 .so 影响。

保留契约：
```
store.transaction(function(old_bytes)
    -- 返回 new_bytes 或 nil、业务响应、是否迁移备份
    return new_bytes_or_nil, response, migration_backup_requested
end)
-- 成功只返回 response；失败返回 nil, error
store.migration_backup == true
```

响应 false 必须原样返回，不能误当失败。callback 抛错要确保关 fd/释放锁并返回可分类错误。nil old_bytes 只表示文件确实不存在，不能表示权限/读取/JSON错误。

保留现有大小限制，通过具名常量明确，不另算/扩大。status 只读不得重写或更新 mtime。内部实例 root 不允许调用后动态改变。

## 4. 顺序任务与退出门槛

### Task 1：冻结基线和存储调用清单

**Files:** REQUIREMENTS.md、现有 P5 账本（实施授权后更新），新增 `docs/HOMEPUBLISH-LUA-STORE-MIGRATION.md`。

1. 只读 git status/diff，确认已有改动归属；在项目需求表按现有编号规则登记，不猜编号。
2. 搜索 homepublish_store、PRODUCT_ROOT、controller_transaction、所有 .so 构建/上传脚本。
3. 将 active store、legacy fixtures、历史证据分开列出；历史证据不重写。
4. 在目标机服务器内备份当前 state、迁移备份及已安装模块，记录 SHA/权限；备份不复制业务私钥到本机。
5. 保存 ordinary 测试服务、实际发布状态和基线摘要。

**Gate:** 精确调用清单、数据备份可读，未启动/停止用户发布；无代码变更。

### Task 2：验证目标机现有 Lua 文件能力

**Create:** `homepublish/tests/device-lua-store-capabilities.lua`。

在应用自有隔离目录测试，禁止访问 live store：
1. 实际查询 nixio/nixio.fs 可用接口和行为，确认 open/create/chmod、lstat、rename、fd 锁、关闭语义；不凭 API 名猜用法。
2. 两个真实 Lua 进程验证锁互斥、持锁进程退出后释放。
3. 同目录 rename 覆盖成功；目标读者只能读到完整旧/新内容。
4. 确认错误返回形式并记录 BusyBox/OpenWrt/Lua/nixio 版本。

**Gate:** 确认可用原语后冻结实现，不增加依赖二进制。此探针是实机测试，不在 Windows/WSL 模拟 nixio。

### Task 3：先建立 Lua 存储契约 RED

**Create:** `homepublish/tests/device-lua-store.lua`、`homepublish/tests/run-device-lua-store.py`。

Python 只上传/驱动目标 Lua 和读取证据，不执行本地被测存储。

测试：首次不存在、已有字节读回、只读不写、callback 返回新字节/响应 false/抛错、长度和类型错误、锁忙、写入失败、rename失败、坏目录和读错误。RED 应是新 Lua 实现缺失，不运行破坏性 live 测试。

**Planned command（实现脚本后才可执行）:**
`python homepublish/tests/run-device-lua-store.py`

**Gate:** 保存真实 RED；不存在脚本不得报已执行。

### Task 4：实现最小 Lua store GREEN

**Create:** product-store-core.lua、product-store.lua（上述固定路径）。

transaction 顺序：
1. 校验/创建应用私有目录，检查固定文件路径的基本类型/权限。
2. 获取持有 fd 的短排他锁；忙返回明确可重试错误。
3. 读取完整旧字节，交给现有 Lua callback；回调期间维持锁。
4. new_bytes=nil 时不写，仅返回业务响应。
5. 新字节先完成类型/大小检查，写同目录独占临时文件；使用现有 fd 接口写完、检查关闭结果。临时文件0600；不得使用 shell 拼接 JSON 或路径。
6. 如果本次请求迁移备份，先按 Task5 完成备份。
7. rename 临时文件到 state；失败保留旧 state。
8. 所有正常/错误分支释放 fd/锁，最多清理本次自己创建的临时文件。

不承诺独立于硬件的强断电持久性；若已验证接口可便捷文件同步，可以使用，但不为了复制目录fsync能力引入新 C。rename 已成功后的附加步骤失败必须区分“可能已经提交”，不能报告明确未写入导致调用者盲重试。

**Gate:** Task3 全 GREEN，实机重复调用无 fd/锁泄漏，不生成额外后台服务。

### Task 5：迁移备份兼容

**Test:** 扩展 device-lua-store.lua，新 Lua 迁移断言。

1. 迁移备份必须取锁内读到的原始 state，不重新编码或接受客户端备份字节。
2. 既有 migration-v1 内容一致时复用，不同/不可读时拒绝，不覆盖旧备份。
3. 写备份失败时不替换 state；重跑迁移不破坏首次备份。
4. 备份权限0600；备份失败不删除预先存在文件。
5. provider 的 migration_backup=true 能力继续成立，既有 migration_preview→confirmed Save 行为不变。

**Gate:** 原v1/当前v2都可读；原始字节比较通过。无格式迁移，无 revision 重置。

### Task 6：切换 provider，确认模块身份

**Modify:** `homepublish/files/usr/share/homepublish/product-provider.lua`。

1. 新实现先在隔离 native Lua store 实例上运行 provider/controller 用例。
2. 将 provider 改为固定 Lua 模块加载，仅换存储依赖，不改业务状态机。
3. 目标 Lua 新进程中保持旧 .so 暂时存在，也能确认只加载新的 Lua 实现；通过模块来源和实际加载检查证明，不只看 require 成功。
4. 受控暂停 idle daemon，完整备份，部署匹配 Lua 文件，重启对应 controller；不自动启动发布。
5. 原 state SHA 保持、status可读、已有服务和当前revision保持。

**Gate:** C模块不再参与普通读写，仍可原字节回退；未把架构重构混入本步骤。

### Task 7：移除编译/安装链和兼容升级

**Modify:** `homepublish/Makefile`。
**Remove after verification:** `homepublish/src/product-store.c`。

1. runtime包 Build/Compile 不再执行 TARGET_CC，不再复制C源码或安装 .so；不要误删 engines 包构建。
2. 仅在确认没有直接链接/调用后去掉不必要的直接依赖；Lua/nixio/ubus等正常依赖保留，不能因 nixio 内部是C就移除。
3. 当前存储目录/state的升级保留策略显式核验：conffiles或保留钩子遵循当前OpenWrt包行为，不只保护 /etc/config/homepublish 却丢 /etc/homepublish/product/state。
4. 开发机上不手工删除旧已安装 .so作为“成功证明”；先确认旧包归属和新包升级语义。目标最终无自有 .so。
5. 定点清理自有候选临时文件，不批量删目录或用户备份。

**Gate:** 最终 IPK data 无 homepublish_store.so、自有store ELF；Lua文件包含正确、权限正确、state升级保留有证据。安装/升级IPK仍需另行授权。

### Task 8：更新现行测试驱动

**Modify after exact inventory:**
- `homepublish/tests/device-tcp-p1-backup.lua`
- `homepublish/tests/device-tcp-p1-provider.lua`
- `homepublish/tests/device-tcp-p1-errors.lua`
- P4/P5 runner 中编译/上传隔离 homepublish_store.so 的相关脚本；实际路径以Task1清单为准。

统一用内部 Lua store factory 和固定测试启动脚本选择私有root；不得经RPC接受任意root。删当前测试的编译先决条件，不删历史 .log/manifest 或伪造历史证据。

原依赖 LD_PRELOAD/fault.so 注入的纯 C 系统调用故障用例标为历史；新实现使用仅测试实例可注入的文件操作边界验证失败，不添加生产RPC故障开关。最终系统链仍必须用未替换的生产Lua模块实跑。

**Gate:** 私有根相互隔离；测试不会写live state；当前测试不再要求编译自有 C store 或故障注入库。

### Task 9：最终设备回归（串行）

先运行新store与provider定向测试，再受影响生命周期，避免重复跑所有历史guardian实验：
- 已存服务/证书/入口普通LuCI读取，原state字节与基线一致。
- Save无启动，revision正常；错误revision拒绝不改state。
- 实际页面Start A→Save仍A→Apply B→Stop既有连接关闭，使用真实HTTP /ubus，不用SSH成功桥。
- Save与controller状态更新的两进程最小交错测试，无丢配置/Stop意图；不做高并发压测。
- 后台临时到期、manual Stop不复活、恢复不偷pending/不延长截止。
- 四协议生产流量和Stop回归，概览增量poll及服务modal不倒退。

现有回归入口（实施前读实际参数/造数清理逻辑，改造后才运行）：
```
python homepublish/tests/run-device-tcp-p5-production.py
python homepublish/tests/run-device-tcp-p5-complete.py
python homepublish/tests/run-device-tcp-p5-matrix.py
```
普通页面 driver `luci-app-homepublish/tests/p5-ordinary-browser.cjs` 需按其实际 harness 入口执行，不臆造CLI参数。旧P4runner如硬编码store编译先完成Task8。

**Gate:** 最后修改后的代码全部上传实跑、SHA对应；用户保留测试服务仍在、默认停发布、密钥快照清理。报告具体失败不选择有利历史PASS。

### Task 10：独立审查与归档交付

1. 审查无残留 require homepublish_store、.so安装规则、PRODUCT_ROOT编译、错误默认覆盖、持锁网络请求。
2. 更新需求、P5集成/打包账本、REFACTOR checkpoint和操作说明：撤销C存储前提但保留历史证据。
3. 冻结最终来源清单；用户未授权commit时使用明确标注dirty snapshot的SHA manifest，不冒充HEAD。
4. SDK里程碑构建，解包确认只有engines/必要平台组件需原生构建，homepublish主包无自有原生store。
5. 安装/升级另获授权；未安装只能交付“包构建/字节已核验”，不称升级验收通过。

## 5. 部署与回退

- 首次切换必须停止正在进行的保存/启停操作，暂停控制器，不在两个store实现同时写时切换。
- 原 `.so`、Lua provider、state均在服务器私有备份；回退先停写、恢复匹配模块，再启动controller，不能仅恢复state而保留不匹配代码。
- 因格式不变，Lua期间合法新配置原则上可供旧实现读取；实际回退前验证，不默认用旧备份覆盖用户新保存服务。
- 部署不自动恢复发布，保留手动停止状态；测试允许明确Start，不允许改全局网络/认证。

## 6. 不纳入本次的后续优化

将 saved_config/必要intent 与 pid/readiness/error等临时状态拆分、所有写操作统一进入controller，是合理方向，但不作为“删C”的前置门槛。本次先降低二进制维护成本并保持行为；只有实际写频率/闪存或维护问题确实需要时再另立小任务。不引入数据库、WAL、Node、自定义锁服务或新guardian。

## 7. 完成定义

- [ ] 产品和当前验收不依赖自有C存储模块。
- [ ] 原配置原格式保留，用户测试数据不丢失，revision不重置。
- [ ] 基本原子替换/互斥及错误处理通过；不承诺数据库级断电持久性。
- [ ] 真实普通LuCI与四协议生产生命周期回归通过。
- [ ] 包内无store.so，升级配置保留策略已核。
- [ ] 平台依赖/安全取舍/未验证边界说明完整；未擅自commit/安装/公网变更。
