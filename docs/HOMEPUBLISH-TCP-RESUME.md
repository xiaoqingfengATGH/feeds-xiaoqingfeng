# HomePublish P5 临时关机续跑入口

## 用户指令
用户要求保存进度、临时关机。立即暂停新实现、部署、构建和测试。恢复必须先检查实际状态，不自动重复构建或恢复历史配置。

## 仓库与阶段
- 工作区：D:/DevPortal/homelede/homepublish-product
- 上次核验分支 feature/homepublish-product；HEAD 7ac1fe8（P3），P4/P5有未提交修改，尚未commit/push/merge。
- P4限定设备/私有控制通道验收通过；不是production/public完成。
- P5进行中，禁止宣称最终产品/IPK已完成。
- 用户允许测试机实际Start；允许保留测试配置/非秘密数据。默认测试后停止发布并清理临时私钥/快照，不清空服务数据。
- 未授权改全局防火墙、路由、DNS、认证、UPnP、开放公网或安装升级IPK。

## 已完成与证据
1. P4最新精确绑定Start/renew校验、真实UI生命周期、增量poll和modal null修复通过。见 docs/HOMEPUBLISH-TCP-P4-PROGRESS.md 与 UI-PROGRESS。父独立task27与verify-final exit0。
2. P5独立审查报告 docs/HOMEPUBLISH-TCP-P5-REVIEW.md：B1生产适配器原不可用、四协议需补；真实RPC权限与组件安全/打包门禁。
3. HTTPS生产provider最小切片与真实HTTP /ubus scoped ACL测试通过。脚本 homepublish/tests/run-device-tcp-p5-production.py。细节/边界 docs/HOMEPUBLISH-TCP-P5-INTEGRATION.md。成功生命周期使用private native journal；普通live成功变更链、完整用户登录映射尚未验。
4. Nginx1.30.6和sslh2.3.1组件交叉构建完成，官方归档签名/来源及许可见 docs/HOMEPUBLISH-TCP-P5-PACKAGING.md。配方 homepublish-engines/，runtime补依赖。最终产品IPK尚未构建。

## 组件产物（恢复必须实查）
WSL /home/eric/homestun-sdk-check/tcp-ingress-p5/build/out/
- nginx SHA256 941b54d84fc4fd40b0257e42195899f0bd77895ec0486e3e263344c2fa8dc08a
- sslh-select SHA256 1b9746f96d31624eb2cfa4076ca7eb0b636979321dbec92947171f780ee38db7
- materials /home/eric/homestun-sdk-check/tcp-ingress-p5/component-materials.tar.gz SHA256 5a83c5936634b495a1c4093a6f5fa7c86009a7aba45a11ffaa6fe96cae02034e
- 产品固定路径 /usr/libexec/homepublish/nginx 与 sslh-select；不替换系统管理nginx。

## 关机时在途工作 / 未确认
- 活动worker sa-0-5a8b6f12 / deleg_78ab63c8，负责新引擎部署与四协议production provider。
- 已发送暂停steer：禁止新操作、优先落盘 docs/HOMEPUBLISH-TCP-P5-PAUSE.md，保留测试数据，记录已部署字节/残留/实际状态。
- 此入口写入时worker尚未回确认，不能假称已停或清理完成。当前目标发布/监听/源码传输/后台进程状态未知，恢复先读worker检查点并核验。
- worker trace C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/delegation/live/deleg_78ab63c8/task-0.log（仅恢复读取，不依赖其进程能跨关机存活）。
- 历史live是revision1/intent7/disabled/manual_stop_latch/stopped，不得恢复旧revision0。是否被本轮修改须实际查，保留用户当前配置与备份。

## 恢复顺序
1. 加载homedirect-development与homelede-development；读本入口、P5-PAUSE、INTEGRATION、PACKAGING、REVIEW及REFACTOR checkpoint。
2. git status/branch/log/diff确认实际修改；不清dirty、不重复commit、不覆盖用户数据。
3. 检查WSL SDK make/timeout进程、cwd、共享build.lock；旧build存在不可重复启动。
4. SSH只读检查设备管理连通、homepublish controller、发布group/listener、私有runtime/证书快照、已装引擎SHA与动态库；先确认owned再做有界停止/清理。
5. 根据worker实际checkpoint恢复四协议production切片，不把P4测试profile、固定fixture端口或SSHbridge当正式发布。源码部署后实机RED→GREEN、最终manifest与清理核验。
6. 完成ordinary RPC/browser成功链、相关最终回归和S2证据；修复审查缺陷后freeze明确dirty snapshot或另征commit授权，再构建IPK。不得标dirty为HEAD来源。
7. P5最终文档与独立复核；外网/物理reboot/代理reload等未验逐条说明，IPK安装另授权。

## SSH
root@127.0.0.1:222，key D:/DevPortal/CloudHosts/HomePri.key；ProxyCommand=none ProxyJump=none IdentitiesOnly=yes BatchMode=yes，scp -O。业务证书/私钥保持服务器侧，不导出。认证失败请用户协助，禁止重置密码。
