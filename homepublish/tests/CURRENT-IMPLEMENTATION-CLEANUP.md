# 按当前实现清理（本文件覆盖早期审查的保留决定）

## 决策标准

- 已退出的实现不因历史覆盖价值而留在测试目录；直接删除，不要求先复活旧实现或补齐等价断言。
- 路径或宿主运行时过时，不等于测试点过时。先比对当前源码；有价值的迁移执行，无价值的删除。
- 本轮未改生产程序、未安装包、未重启生产服务。私有目标测试会生成并删除独立测试文件。

## 本轮删除 43 个文件

### 旧 native store 与依赖链（10）

`test-controller.py`, `test-controller-multi.py`, `test-controller-recovery.py`, `test-rpc.py`, `rpc-luci-fixture.py`, `test-browser-lifecycle.py`, `run-device-tcp-p5-production.py`, `controller-host.lua`, `controller-adapter.c`, `product-store-fault.c`。

依据：仍编译 product-store.c 为 homepublish_store.so，或依赖其 fixture/host adapter。当前 store 为 product-store-core.lua/product-store.lua。删除旧实现测试，不声称所有独立断言已经迁入新测试。

### 已退出构建/安装链的原生租约、guard、publisher（22）

`test-lifecycle.py`, `test-source-cleanup.py`, `test-socket-boundary.py`, `test-token-validation.py`, `test-publication.py`, `test-publication-security.py`, `test-renewable-guard.py`, `test-owned-runtime.py`, `test-startup-owned.py`, `test-trusted-provider.py`, `test-openssl-engine.py`, `test-guardian-nginx.py`, `test-audit-regressions.py`, `owned-runtime-probe.c`, `guardian-nginx-fixture.c`, `renewable-guard-fixture.c`, `renewable-start-faults.c`, `renewable-tree-fixture.c`, `startup-owned-contract.c`, `startup-owned-faults.c`, `token-io-injection.c`, `private-pair-probe.c`。

依据：homepublish/Makefile 的 Build/Compile 为空，当前包不再构建或安装这些旧 C helper；生产 Lua 文件无对应 native runtime 引用。旧 C 源码仍在 src 中，不代表当前发布实现仍使用它们。此处只删除测试与测试夹具，不越界删除产品源码。

### 旧 init / UCI 发布模型及驱动（4）

`test-service.sh`, `test-publication-service.sh`, `run-publication-security.sh`, `router-publication-uci.sh`。

依据：断言旧 homepublish_plan、exposure_approved、router_token_file 和 native publish/lease 注册路径，非当前 product-daemon/procd/Lua journal 生命周期。调用脚本同步删除。

### 固定历史产物构建、验收及孤立浏览器 overlay 下载（7）

`build-r8.sh`, `build-r9.sh`, `verify-r8-package.py`, `build-tcp-private-components.sh`, `build-tcp-identity-components.sh`, `build-tcp-p3-nginx.sh`, `fetch-browser-deps.py`。

依据：固定历史 R8/R9 commit/version 或 P0/P3 nginx 1.26.1、旧 sslh 试验产物，不是当前 homepublish-engines 包构建。overlay 下载器唯一原生 RPC fixture 调用链已删除。当前三个实际包由 check-current-ipk.py/check-companion-ipk.py 验证。

Makefile 仅保留 current/current-target，删除旧目标，而非保留失效配方再附加拒绝前置目标。

## 已迁移并实际执行

### 七组本机 Lua 契约

`test-canonical.lua`, `test-direct.lua`, `test-certificate-model.lua`, `test-certificate-san.lua`, `test-config.lua`, `test-core.lua`, `test-publication-config.lua`。

这些模块及契约仍存在于当前源码；不因旧环境路径删除。增加 test-current-lua-contracts.py，使用 Lupa Lua 5.1、仓库相对路径，保持断言并纳入 current suite。注意 canonical v1/config/core 是仍保留的兼容模块，执行不代表生产新服务使用旧 schema。

### 两组目标证书契约

`test-certificate-metadata.py`：保留真实 OpenSSL SAN、有效期、禁止 CN fallback、无密钥/路径泄漏测试；去除 /home/eric 依赖，迁入 1.2 私有目录。

`test-certificate-inventory.lua`：旧测试断言 UCI section 引用和调用 HomeVPN resolver，已不符合实现。保留仍有价值的证书身份、SAN、算法、隐私测试点，改为真实 acme.sh 目录身份 `acme:*.example.test`，真实生成证书与 key、公钥配对、RSA/ECC 拒绝和真实清单扫描，不再用假的 resolver 返回绕过实际读取。

run-device-retained-contracts.py 将仓库 Lua 拷贝到唯一 /tmp/homepublish-cert-contract-*，仅将副本中固定清单目录改为私有目录；不修改生产文件。openssl 与 nixio 均使用设备实际工具/库。最终删除私有目录并确认不存在。两组测试纳入 --target。

## 验证

完整 current suite --target --ipk-dir：86 tests、54 subtests、本机 Worker 8 项、目标证书两组、restart 三组、Lua store 八组、三个实际 IPK 全部通过。

仍未迁移的 Linux 真流量入口（test-direct.py、test-direct-boundary.py、test-shared-runtime.py）涉及现有 renderer/provider 的实际 Host/SNI、后端切换、连接清理测试点，不因旧 SDK 路径直接删除；本轮真实业务流量/浏览器验收按既定范围排除，不将它们计为通过。其旧运行环境仍需在恢复该验收范围时迁移，不能据此宣布 SDK 损坏。完整目录中其他专项用例的 current 标记只代表已纳入明确入口，不代表所有保留文件执行过。
