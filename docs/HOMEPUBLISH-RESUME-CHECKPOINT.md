# HomePublish 已恢复：当前续跑入口

最新独立审查修复：9af952f 的 P1 prefix-filtered maps 假exact-set与 P2 pre-trace编译失败 owned 泄漏已正式 RED→GREEN；完整inventory/shared parser及compiler/trace异常/timeout回归见 docs/HOMEPUBLISH-D2D2-CHECKPOINT.md（docs内链接同名文件）。旧exact-set声明不充分已撤回；observer仅single tracee/bind前，非native guardian清理。八target完整retry exit0，首轮既有Stop重复91 readiness失败日志保留、不算PASS、不在本轮扩修。最终source guardian-nginx/openssl-engine与localcommit以交接实测为准。禁激活、ENOTSUP/helper78/Start Apply unsupported/activation_ready=false以及manifest/immutablepaths/muslfallback/controllerTLS/residual/target gates保持；新两修独立review待。

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
