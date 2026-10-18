# P4 生命周期验收账本

## 当前最终验收（优先于下文历史checkpoint）

HEAD `7ac1fe88f4817a24bc9abe69364c4324040d2d41`，既有dirty worktree保留。**P4 tasks22–27限定设备/私有控制通道功能验收完成；不是production/public发布验收。** 不进入P5，无commit/push/merge。下文旧“未开始/尚未验收/rev0”仅历史快照，不是当前结果。

|任务|当前结果与精确证据（docs/evidence/tcp-p4/）|
|---|---|
|22 概览|`ui-overview-final-after27.log` GREEN：正式独立route、原生Map/Grid，saved/active/pending及四协议同generation，旧/缺代拒绝，轮询保留Map/row/cell/focus/诊断及非零滚动，读取失败/重试、窄屏内部滚动。mutationCalls=0，errors=[]。复杂状态矩阵为明确labelled status fixtures，不冒充真实runtime。|
|23 按钮/确认|`ui-lifecycle-final-after27.log` GREEN：实际LuCI Start→services原生编辑Save→Apply→Stop；取消Start零mutation、取消Apply保留generation。`services-modal-final-after27.log` GREEN：空默认值/证书继承覆盖/四协议条件字段/中文必填/Cancel无残行、零mutation。生命周期rpc.declare请求由固定SSH测试bridge送到设备private Unix RPC/真实installed controller，**不是public rpcd/session ACL验收**。|
|24 Save/Apply/Stop|`task24-final-after27.log` GREEN：四协议同代ready；Save rev2保留active1/generation/四held client PID与HTTPS A；Apply整组短暂停机后新代active2/HTTPS B；Stop四既有连接关闭、新连接拒绝、runtime/cert/procd无残留、重复Stop confirmed。不宣称无损reload。|
|25 到期/恢复|`task25-final-after27.log` GREEN：真实后台/clock temporary60秒原截止，恢复active1不偷用pending2、Apply不延期、stale事件忽略；无浏览器轮询自然到期四held clients关闭（最后等待44.3秒）；连续策略3次恢复后budget exhausted；Stop latch阻止迟到事件；boot_restore=false经C.restore。不是物理reboot/冻结controller硬截止；不是每项独立RED。|
|26 共存/清理|每runner前后live journal、firewall/dropbear/uhttpd/passwall2、hosts/resolv/system nginx、管理PID/监听一致；业务certificate/key hash/uid/mode仅服务器比对不变。`verify-final-after27.log`读回5个owned procd对象不存在、所有明确高端口无listener、runtime/fixture/SSH auth/授权marker不存在。**独立LAN回程/代理reload/公网未验**。|
|27 负向|`task27-final.log` GREEN：地址消失/zone缺失/inventory失败均阻断preflight与真实Start且journal不变；第二监听竞争整组失败cleanup confirmed且foreign PID保持；运行后地址消失在31秒tick整组停/cleanup confirmed/retry_wait且active_verified=false，不wildcard、不改saved/active配置。24 partial TLS EOF、unknown plaintext/SNI拒绝，负载下业务HTTPS成功且procd PID保持。24仅bounded observation，非全局硬连接上限。|

### 本轮运行中绑定RED→GREEN

`task27-running-binding-red.log` exit1：真实Start后仅当前Lua进程只读inventory快照移除lan IPv6地址，等31秒C.tick，仍running/active_verified=true；finally清理且live基线未变。最小修复 `product-v2-runtime.lua` V.renew在既有30秒周期调用既有`verify_bindings(active.listeners)`，失败走既有controller整组Stop/有界恢复。`task27-running-binding-green.log`：加`--deploy-supported --negative`实机部署SHA匹配并exit0；随后无deploy最终串行完整回归。未改真实interfaces/fw/routes/DNS/auth/UPnP，未放宽精确绑定。

### 最终精确串行命令（仓库根目录）

```sh
python homepublish/tests/run-device-tcp-p4-lifecycle.py --negative > docs/evidence/tcp-p4/task27-final.log 2>&1
python homepublish/tests/run-device-tcp-p4-lifecycle.py > docs/evidence/tcp-p4/task24-final-after27.log 2>&1
python homepublish/tests/run-device-tcp-p4-policy.py > docs/evidence/tcp-p4/task25-final-after27.log 2>&1
python homepublish/tests/run-device-tcp-p4-ui.py > docs/evidence/tcp-p4/ui-lifecycle-final-after27.log 2>&1
node luci-app-homepublish/tests/p4-overview-browser.cjs > docs/evidence/tcp-p4/ui-overview-final-after27.log 2>&1
node luci-app-homepublish/tests/p4-services-modal-browser.cjs > docs/evidence/tcp-p4/services-modal-final-after27.log 2>&1
python docs/evidence/tcp-p4/verify-final.py > docs/evidence/tcp-p4/verify-final-after27.log 2>&1
```

前五项由串行`&&`继续执行证明exit0；长terminal在420秒工具上限超时，前五与modal GREEN已落盘，未将timeout当成功。随后modal→verify完整单独串行重跑，工具exit0。无并发占用private P3端口。所有最终业务/测试源码为实际运行版本，无尾改。

最终verify exit0，**15项** installed Lua/private helper/UI SHA逐项相同，manifest `p4-stage-final-source-sha256.json`。runtime `2e1182f2d555a43dbe8e73cd064afaed2c8aa767580e39ac9e6430ffa551aaba`；controller `967d8c4e23607799ccd893e2b91dd4f8628ae02be34a530dfff1943760294d07`。ordinary live **revision1 / intent7 / disabled / manual_stop_latch / stopped**，journal SHA等于当前before/after基线，禁止恢复历史rev0。marker删除后installed capability再次拒绝。证书仅`home.iwonderful.top` / `acme:home_rsa`服务器使用，源保持。

**未关闭门槛**：public rpcd注册/session ACL完整生命周期、非fixture production能力、独立LAN回程/Passwall2 reload、公网各协议/地址族与物理reboot未验。私有bridge/status fixtures不替代这些。正常controller deadline不承诺SIGSTOP独立硬fail-close。P4限定功能验收不等于产品可公开发布；停在P4。

---

## 历史过程（以下Checkpoint 1至最终复验是旧快照）

## 范围与当前结论（Checkpoint 1）

基线真实提交 `7ac1fe8` / `feature/homepublish-product`；P3 tasks16–21 已由父任务提交。本轮仅 P4 后端 task24 的 installed 纵向切片，不把 P3 的四协议启动/停止证据直接当作 P4 Apply 验收。不执行 P5；无 commit/push/merge。

|任务|当前结果 / 边界|
|---|---|
|22 概览|未开始；后续前端 owner 统一维护 product.js/overview.js。|
|23 按钮与确认|未开始。不得把 isolated capability 等同 production capability；需后续接入真实隔离 provider 通道，不以永久假禁用关闭任务。|
|24 Save/Apply/Stop|真实安装模块、private journal CLI、标准 procd 实流首次 GREEN。Save rev2 后 active rev1/原 generation，四协议 held client PID/running 保持、业务 HTTPS 仍 A；Apply 整组替换，新 generation 四服务 readiness 绑定后 active rev2，业务 systemCA+hostname HTTPS 返回 B；重新建立四协议 held sessions 后 Stop 全部退出、新连接拒绝，group/runtime/cert snapshots 不存在，重复 Stop confirmed。短暂停机为明确合同，不宣称无损 reload。|
|25 到期/恢复|尚未在 P4 验收；旧 controller 能力不等于本轮 installed 四协议已验证。下一切片临时截止、手动Stop latch、pending不偷用、有界恢复、boot默认关。|
|26 共存/清理|task24 每次前后 live journal、管理 PID/监听、firewall/dropbear/uhttpd/passwall2、hosts/resolv/system nginx 完全一致；业务证书/key源 hash/uid/gid/mode仅服务器内比对不变。未证明独立 LAN 回程/代理 reload。|
|27 负向|P4 尚未开始；P3已有失败/unknown证据仍仅归P3，不作全套P4关闭。|

## RED → GREEN

- `docs/evidence/tcp-p4/task24-red.log`：真实 target 上 Save 保留旧四流通过；原 P3 私有 CLI 不转发 Apply，拒绝并清理。初次 harness 曾误把 subprocess result 当 status，随后修正重跑；该工具错误不算产品 RED。
- 新增 P4 CLI 只负责把 `apply` 转入 unchanged installed controller，仍优先 `/usr/share/homepublish/?.lua`，只选固定 private native journal；不注入 package.loaded provider，不从 staging 目录优先加载产品模块。
- `task24-profile-red.log`：Apply 真实返回 `installed v2 scope denied`，证明固定 server-owned profile 不允许 B 端口。
- 最小产品变更：`product-device-v2-profile.lua` 仅新增固定 loopback backend `127.0.0.1:49556`，仅固定业务 HTTPS hostname/ref 可选 A49545/B49556；没有任意 exec/path/provider 或客户端授权开关。其他协议白名单保持。
- `task24-green.log`：`python homepublish/tests/run-device-tcp-p4-lifecycle.py --deploy-supported` exit0。仅9个既有受支持模块按原清单部署（其他8项字节未改），不重启 live。最终 source manifest 为 `task24-installed-source-sha256.json` / `task24-source-sha256.json`。

## 精确复跑（禁止并发）

```sh
python homepublish/tests/run-device-tcp-p4-lifecycle.py
python homepublish/tests/run-device-tcp-p3-controller.py --installed
```

Python仅 SSH/scp/assertion transport，本机不运行目标业务逻辑。固定 SSH root@127.0.0.1:222，`ProxyCommand=none ProxyJump=none IdentitiesOnly=yes BatchMode=yes`，key `D:/DevPortal/CloudHosts/HomePri.key`；scp `-O`、绝对本地路径。运行期间固定授权 marker；退出删除 fixture/marker/SSH auth/private keys。Nginx1.26.1与sslh2.3.1仍为 `/tmp/homepublish-tcp-p3/` 私有固定依赖，不替换系统包。

## 后续 UI 接口冻结（不是 UI 完成）

- status: `saved_revision` / `active_revision`、`saved_config` / `active_config`；`pending_config.saved_revision` 与 `apply_required`。
- runtime: `phase` / `generation` / `active_verified` / `cleanup`；`services` 是 service_id-keyed **map**，每项 `{hostname?, ready, generation}`，不是 services 配置数组。仅当前 generation 所有 enabled 服务 ready 才 running/active。
- 命令：`start(revision, approved)`、`apply(revision, approved)`、`stop()`；Save不启动不reload。Apply必须 running/enabled/无latch；Stop失败/残留也可调用。Apply是旧整组清理后重建，有短暂停机。
- 当前公共 `product-provider` 对 schema2 的 `capabilities.start/apply=false`、`product-system-provider` production unavailable **未解决**。本次测试调用真实 installed device provider，但不能把通道测试当正式 RPC/LuCI 按钮能力完成；前端整合前需由 backend owner 提供隔离且真实的能力通道。禁止为点亮按钮把 live 全局授权打开。
- ordinary live 保持 rev0 / intent7 / disabled / manual_stop_latch / stopped，未 Save/migrate/Start；不改 fw/routes/DNS/UPnP/auth，不开放公网。

## Task25 backend handoff (final tested source)

- 新增真实后台 private Unix RPC server/client `homepublish/tests/device-tcp-p4-policy-rpc.lua` 与远程 transport/assertion runner `run-device-tcp-p4-policy.py`。固定 installed module first + private native journal；不注入 provider、不执行host目标逻辑、不修改生产RPC授权。
- RED `task25-red.log`：默认 untrusted clock 导致可恢复 sslh SIGKILL 后误 Stop；最小修复 controller 默认读 kernel boot_id + os.time。真实临时策略到期/恢复均未使用人工clock。
- Capabilities 两轮 RED：status与command response原来对真实schema2 provider仍返回 false。现在 controller 用 endpoint provider.runtime_plan 验证后修饰status及transaction response，未改变全局 product-provider 生产gate。Save是store-only响应，必须再读controller status。固定接口见 `docs/HOMEPUBLISH-TCP-P4-API.md`。
- `task25-final.log`: `python homepublish/tests/run-device-tcp-p4-policy.py --deploy-supported` exit0；真实60秒deadline，恢复active1而非pending2，Apply不延期，stale generation忽略；无browser/无RPC等待自然到期，最后等待45.17秒后四个此前存活协议client均退出、procd/runtime不存在。连续策略四轮真实SIGKILL：前三次恢复且attempt_count 1/2/3，无expires_at，第四轮blocked budget exhausted/no next_retry，之后不自启。Stop latch和延迟事件不复活。boot_restore=false通过真实C.restore路径（不是物理重启）。
- 每项新增行为非全部独立RED：clock与capability有真实RED→GREEN，其余扩展是既有controller能力实际installed回归。单次自然到期不宣称控制器SIGSTOP独立硬截止。
- `task24-after25-regression.log` task24最终回归 exit0。`python docs/evidence/tcp-p4/verify-final.py` exit0：installed SHA、授权marker移除后拒绝、live rev0/intent7/disabled/latch/stopped，owned资源与所有fixture监听清理。Task25 runner另逐项核验最终private RPC源码SHA，manifest保留 `task25-source-sha256.json` 和 `task25-installed-source-sha256.json`。
- 业务cert/key源hash/uid/mode只在服务器比较不变；firewall/dropbear/uhttpd/passwall2/hosts/resolv/systemnginx/管理PID/监听基线一致。无fallback cleanup未报告的unknown；runner finally中的Stop为幂等收尾，不掩盖expiry/recovery事前断言。未运行真实物理reboot、未验public RPC ACL、公网、独立LAN回程/代理reload；task27仍待后续owner。P3历史证据未覆写，无commit/push/merge。
- 后端最终产品修改仅 controller clock+endpoint capability；task24既有profile B端口仍保留。frontend文件完全未触及。当前无持久测试fixture在跑，frontend集成须先协调固定fixture server所有权。
- 精确重跑（禁止并发）：`python homepublish/tests/run-device-tcp-p4-policy.py`；`python homepublish/tests/run-device-tcp-p4-lifecycle.py`。首次部署controller可加 `--deploy-supported`。`--contract-only` 仅能力短测，不能作为task25生命周期验收。

## 最终复验

- `task24-final.log`：最终源码不带 deploy 再运行 `python homepublish/tests/run-device-tcp-p4-lifecycle.py`，exit0，`P4_TASK24_INSTALLED_LIFECYCLE_GREEN`。
- `p3-installed-regression.log`：最终 profile 上重新运行 P3 `--installed`，exit0；第二组件 bind失败、第二服务 readiness失败、foreign identity cleanup_unknown/拒删/拒重启和owner解决全通过。回归生成的新 manifests/procd PID evidence 移至本P4目录 `p3-regression-task21-*`；P3已提交历史文件恢复原字节，避免覆写历史验收。
- `python docs/evidence/tcp-p4/verify-final.py` exit0：10项 installed/private source SHA256逐项相同；四个owned procd对象不存在，所有P3/P4明确高端口无listener，runtime/fixture/SSH auth不存在，authorized marker删除后 installed capability再次拒绝。
- `p4-stage-final-readback.log`：ordinary live rev0 / intent7 / disabled / latch / stopped。`p4-stage-final-source-sha256.json`为最终10项读回清单。
- `git diff --check` exit0；仅既有 autocrlf warning。没有最后执行后未运行的业务源码修改。当前交接仅 task24 后端实流切片，task25/27尚未验收，22/23仍需前端整合与真实隔离RPC能力通道，不能宣称P4完成。

