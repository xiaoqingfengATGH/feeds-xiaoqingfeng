# HomePublish 已恢复：当前续跑入口

当前多服务controller本地功能切片通过（接续56bc5fa）：canonical保存的两服务进入同一专用guarded Nginx实例，独立SAN/证书/key、IPv4/IPv6入口到IPv4/IPv6 backend四组合真实TLS marker通过；逐服务readiness绑定整体generation，全部成功才提交active/running。Save修改单服务仍pending旧流量，Apply先stop/reap旧整代再启动新整代（有短暂停机，非零停机reload）；删除服务后旧SNI不再提供业务。第二服务readiness失败关闭全实例，历史active仅记录、attempted/candidate独立、active_verified=false。Stop断两服务已建立stream并关闭双栈listener/native runtime。temporary首次deadline经Save/Apply保持；原单服务60秒自然到期回归本轮一次通过。详见[多服务checkpoint](HOMEPUBLISH-CONTROLLER-MULTI-CHECKPOINT.md)。production Start/Apply unsupported与activation_ready=false不变；内部固定test-only adapter不等生产支持。安全深化暂停，下一步bounded recovery/可信时钟/boot接口、向导/生产provider/目标验收；SSH127.0.0.1:222仍未恢复未重试，未安装/公网/fw/UPnP/push/merge/PR。

当前功能主线：D2 controlled Apply/temporary/readiness 本地切片完成，源码 `926311e`。内部明确approval与固定scope核验后stop/reap旧代、启动新generation，真实TLS+HTTP readiness成功才提交active/running；失败保留历史active、attempted/candidate并标active_verified=false、stage/error/cleanup，不假保旧仍运行。两backend marker/counter证明Save仍旧流量、Apply真实切换。真实60秒temporary首次绝对截止经Save/Apply不延，持续stream与新listener到原截止关闭、desired撤销；修复长会话双guard心跳队列累积导致约9秒误关。committed源码 `make controller product direct guardian-nginx` exit0（64条PASS输出，非64独立用例），证据 `/home/eric/homestun-sdk-check/controller-apply-committed.log` 及 `.exit`。下一功能方向scoped RPC/UI状态/Save/Stop与内部受控入口；双栈多服务controller、bounded recovery/时钟可信/重启仍未完成。安全深化暂停，最终统一复评清单保持未完成；production CLI Start/Apply unsupported、ENOTSUP/helper78、activation_ready=false不变，非产品完成。

本轮已按用户恢复指令续跑，不再处于关机暂停状态。独占 worktree `D:/DevPortal/homelede/homepublish-product`，branch `feature/homepublish-product`，恢复基线 `7c9e8d2907b90ad013dae2750eb484e983e6e50e`。当前修复提交可由 `git log -1` 读取；父任务应先独立复跑并审查，再进入下一slice。

## 本轮完成与真实结果

- 保留关机前修改并将正式 `homepublish/tests/test-openssl-engine.py` / `openssl-engine` target收尾，使用matching cached SDK gcc constructor模块及真实Nginx固定provider，不依赖scratch脚本、外部git worktree或host ENGINE注册ABI。
- RED只改复制fixture为旧exec环境：actual ambient open、module open/maps、constructor marker均真。GREEN用当前原样provider：读取owned固定empty config，无ambient/module/marker访问。
- ptrace只观察/重定向owned tracee的ambient open到scratch恶意config，不改系统/etc；bind执行前SIGKILL，status9是设计，无实际监听。保存actual-open/raw.maps/exec前env及兜底前inode metadata；observer清理不冒充native guardian清理。
- Ubuntu-24.04 uid1000完整执行：`TMPDIR=/home/eric/homestun-sdk-check timeout 560 make -C homepublish/tests owned-runtime guardian direct product startup-owned guardian-nginx trusted-provider openssl-engine`，**exit0**。
- 完整日志：`/home/eric/homestun-sdk-check/resume-openssl-final-full.log`。正式探针证据：`/home/eric/homestun-sdk-check/openssl-engine-regression/run-7rbelw4a/attack-summary.json`，同目录red/green各有observation.json、actual-open.json、raw.maps。输出RED True/True、GREEN False/False，均bind intercepted；访问数117/115。
- 完整guardian-nginx继续验证TLS双栈/renew/respawn/temporary/各单guardian故障、native清理及foreign保全，证据 `/home/eric/homestun-sdk-check/d2b2-nginx-evidence`。
- 最终提交后必须再以committed源码执行 `make -C homepublish/tests openssl-engine guardian-nginx`；确切commit、exit与日志由最终handoff读回，不能拿旧日志当提交后结果。

## 已排除的失败路线 / 历史证据

host `openssl engine -t dynamic` 曾因SDK module/host ABI错配失败 `eng_dyn.c:481`，不是有效RED。现在仅用host openssl req生成临时fixture证书，不进行host ENGINE注册。此前独立scratch探针与`/home/eric/homestun-sdk-check/independent-7c9e8d2`仍在，但不是正式target依赖。

## 下一入口与不变门槛

父独立复跑审查当前提交和正式target，确认所有owned进程/运行时清理后继续下一slice。安装manifest/signature权威、不可变库路径及musl缺库fallback、TLS source/SAN/health/scope controller、typed durable residual/crash recovery、partial prepare accounting、matching SDK/aarch64/BusyBox/procd/fw4仍gate。`ENOTSUP`、helper exit78、Start/Apply unsupported、`activation_ready=false`保持；本地subset不代表产品可激活或生产完成。

本轮仅本地非root WSL loopback和localcommit；未生产安装、下载、公网、fw、UPnP、push、merge、PR。详细证据见 [D2d2 checkpoint](HOMEPUBLISH-D2D2-CHECKPOINT.md) 与 [PROGRESS](HOMEPUBLISH-PROGRESS.md)。
