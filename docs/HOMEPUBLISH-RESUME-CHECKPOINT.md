# HomePublish 已恢复：当前续跑入口

当前结构化LuCI功能切片通过：服务新增/删除/编辑、IPv4/IPv6/hostname后端及备用表单、CIDR逐行输入、鉴权/证书引用、接入方式与listener地址/接口/区域/内外端口已替换JSON编辑；continuous默认/temporary可选。真实Chrome→LuCI loader→官方rpcd→CLI→native保存两服务并刷新读回，编辑删除后revision3/中文emoji保持，重复id/hostname及空服务列表由原canonical拒绝（当前至少1服务），Stop仍独立、Start禁用。Save仅本应用/pending，不启动、不global commit、不改fw/UPnP。普通用户make rpc product controller及root make browser exit0，清理读回无owned进程/挂载/18993/18994/fixture目录。多服务仅配置保存，runtime未宣称支持；下一步多服务controller、bounded recovery/可信时钟/boot、访问向导及目标部署（SSH127.0.0.1:222 refused未恢复，未重试安装）。安全深化暂停、最终风险复评清单保留不扩大；production Start/Apply unsupported、activation_ready=false保持，完整产品未完成。

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
