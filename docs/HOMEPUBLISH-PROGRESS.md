# HomePublish 当前检查点

## 关机恢复：正式 actual-Nginx OpenSSL engine 回归接入（local，未激活）

接续 `7c9e8d2907b90ad013dae2750eb484e983e6e50e`，正式 `openssl-engine` target 不再依赖scratch脚本或host ENGINE ABI：matching SDK gcc constructor模块、真实Nginx固定provider、ptrace实际open/raw maps/exec前env。旧exec环境仅复制fixture mutant作RED：ambient config→manifest外module open/maps/marker均真；HEAD固定空config作GREEN：无ambient/module/marker访问。bind前observer SIGKILL/status9是设计，非product failure，不修改系统/etc。完整 `make owned-runtime guardian direct product startup-owned guardian-nginx trusted-provider openssl-engine` exit0；日志 `/home/eric/homestun-sdk-check/resume-openssl-final-full.log`，探针证据 `openssl-engine-regression/run-7rbelw4a`。详见[D2d2](HOMEPUBLISH-D2D2-CHECKPOINT.md)及[恢复入口](HOMEPUBLISH-RESUME-CHECKPOINT.md)。仅自检，父独立复跑/审查后继续下一slice；生产manifest/签名、immutable library paths/musl fallback、TLS/SAN/health/scope controller、typed durable residual/crash recovery、partial prepare accounting、matching target SDK仍gate。ENOTSUP/helper78/Start-Apply unsupported/activation_ready=false保持。

## 最新 D2d2 fixed OpenSSL/provider authority subset（local，未激活）

接续 `cdfa83503216bc0840932a29afcca86261d9e95d`：新增 native-owned 固定空 `openssl.cnf`、固定 `OPENSSL_CONF`/`OPENSSL_MODULES`/`OPENSSL_ENGINES` 环境及非秘密 `provider-init.trace`；同步13文件槽、FD allowlist、prepare/cleanup。真实 TLS/renew/respawn/temporary/controller-guardian-watchdog STOP/KILL 回归通过；所有master/worker及respawn worker逐进程精确ELF映射集合（五私有依赖+sealed loader/Nginx memfd）及FD/NNP/seccomp元数据通过，非SDK路径/unknown不接受。新增断言先RED后GREEN；`test-guardian-nginx.py`、`test-trusted-provider.py`、`test-owned-runtime.py`均exit0。详见 [D2d2 checkpoint](HOMEPUBLISH-D2D2-CHECKPOINT.md)。**仍是真实vertical subset，不是完整依赖/目标authority闭合：target安装manifest/签名、不可变路径/mount gate、各支持OpenSSL版本provider布局、aarch64/BusyBox/procd及Nginx配置语义来源仍未验；不把trace/ptrace/maps当sameUID边界，不宣称通用load_module/include解析闭合。** production `ENOTSUP`、Start/Apply unsupported、`activation_ready=false`、helper78保持。


新增 server-owned host-test manifest + FD exact-byte digest copy + sealed loader/Nginx memfd + 五实际依赖私有readonly native-owned snapshot，真实 maps 验闭包、恶意LD/OPENSSL环境清除。14拒绝回归（exec替换正式RED→GREEN，其余补充覆盖）、完整make七targets exit0、8真实Nginx lifecycle native cleanup通过。详见 [D2d1 checkpoint](HOMEPUBLISH-D2D1-CHECKPOINT.md)。**库snapshot仍经private path，未对sameUID/root或runtime-parent替换建立kernel immutable authority；target安装manifest/namespace能力尚未验，production API ENOTSUP。不是production trust closed。** Start/Apply unsupported/activation_ready=false/helper78保持；parent验证与独立review待做。

## 最新 D2c2 errno/residual LOW 收尾（local gate，未激活）

接续 a794446：invalidargs/binding独立review已通过；早期启动errno覆盖及residual优先级正式RED→GREEN，新增controller pidfd EMFILE保留。early random/probe/pair/mmap/fork统一错误tail；remote handshake仍明确EIO，cleanup residual优先ENOTRECOVERABLE，EINVAL/EBUSY不混foreign PID。79 startup runs+两ownership contracts与全套真实本地make exit0；foreign内容/inode保全。详见 [errno checkpoint](HOMEPUBLISH-D2C2-CHECKPOINT.md#early-startup-errnoresidual-low-closure-after-a794446)，本轮仅自检，非新独立review。Start/Apply unsupported、activation_ready=false、helper exit78不变；production authority/controller/target仍未完成。

## 历史 D2c2 LOW 收尾（local gate，未激活）

原秘密残留修复独立复审通过；LOW 无效启动参数遗留 empty runtime 已正式五项 RED→GREEN关闭，nullguard不再崩溃。绑定仅转交本次prepared empty清理责任并在返回时消费；active重入/claimed ledger拒绝且不误删，不从无效g取得PID信号权限，foreign replacement保留并报residual。11新增故障纳入正式regression，25 delayed ACK重复保留；65 startup runs + 两ownership contracts，不冒称每项都有RED。全套/最终committed-source复验及清理责任详见 [D2c2 LOW checkpoint](HOMEPUBLISH-D2C2-CHECKPOINT.md#independent-re-review-low-closure-after-f311c114)。新修复仍须独立复审；生产authority另切片，Start/Apply unsupported、activation_ready=false、helper exit78不变。

## 历史 D2c2：启动秘密残留 review 修复（local gate，未激活）

独立 watchdog pidfd EMFILE 注入重现 start_rc=-1/key size21 残留；正式项目 regression 先 RED，再加入 server-owned preprovision barrier、全部必需 pidfd 锚定和统一 startup/runtime cleanup-before-peer-kill。24 startup ownership faults（含真实写入后/短 READY/各 pidfd/单 STOP-KILL）与 committed-source 全套/三连续真实 Nginx 矩阵本地通过；原有 residual/foreign 保全不改。详见 [D2c2 checkpoint](HOMEPUBLISH-D2C2-CHECKPOINT.md)，最终 hash/复验由完成报告读回。固定 exec/loader libs/source/SAN/health/controller/typed durable crash manifest/target SDK 仍未有，产品继续禁激活。

## 最新 D2c1：FD-pinned native cleanup 竞态关闭（本地 gate，未激活）

接续 `ed646fc03a8ba5b1e7af5a1e7acd23747d158b92`，父复验 controller-stop 真失败，本轮独立重复第三轮同样 exit2：所有 owned 文件/目录残留而 PID 已消失。根因是双guard在cleanup前互杀，可同时杀死两个cleaner；改为kill provider group→pidfd观察真实退出→native cleanup→kill reciprocal guard→bounded reap。所有文件/目录在fork前FD-pinned，减少inode reuse；不加断言延迟、不拿harness删除当native通过。14 native cases+100 Stop压力、5连续真实Nginx全fault矩阵以及完整 `make owned-runtime guardian direct product guardian-nginx` exit0；每矩阵12 records/8 native runtime absent，foreign inode/source TLS保全。失败/成功均保留兜底前metadata证据。最终committed-source复验命令与root cause/evidence详见 [D2c1 checkpoint](HOMEPUBLISH-D2C1-CHECKPOINT.md)。固定exec authority、生产SAN/health/controller/typed residual/crash recovery仍gate；Start/Apply unsupported、activation_ready=false、helper exit78不改。

## 历史 D2b3：私有 STREAM socketpair 本地兼容 GREEN（未激活）

真实 `make guardian direct product guardian-nginx` exit0；2worker双栈TLS、动态SCM_RIGHTS/FD复用、worker重建/同master续展、temporary及三监管角色单STOP/KILL、兜底前owned PID/listener清理通过；12 integration records，channel_EPERM0/internal_errors0。generic仍全局拒recvmsg；新private profile仅HP_GUARD_TEST内部fixture可选，禁止socket(AF_UNIX)/其它非INET域及DGRAM/SEQPACKET pair，仅私有STREAM pair。pathname/abstract外来sender旧profile真实入队，新profile创建连接拒绝，三角色foreign inode保全。详见 [D2b3 checkpoint](HOMEPUBLISH-D2B3-CHECKPOINT.md)。生产固定exec/inode authority、native TLS文件cleanup、scope/DNS/health/controller和目标aarch64仍未完成；Start/Apply unsupported、activation_ready=false、helper exit78保持。仅可信固定非root provider契约，不是hostile filesystem sandbox，不包含外部sameUID/root干预隔离。

## 历史 D2b2：真实 guardian + Nginx RED gate（当时BLOCKED，未激活）

接续 `408d963896a33aac076b48cbe4c31896586df05d`；test-first local checkpoint `ba57e816c16efd853de64f0b572e655717246216`。新增固定cached Nginx内部host fixture与 `make -C homepublish/tests guardian-nginx`：真实2worker、worker KILL重建、同master跨600ms多窗口renew、1200ms固定temporary、IPv4/IPv6 loopback TLS、controller/guardian/watchdog各KILL/STOP断流；已读回owned PID/监听在兜底前消失。外来UNIX真实SCM_RIGHTS已入队而guarded recvmsg EPERM，旧三角色foreign inode回归保留。**内部channel仍EPERM，新增target真实RED，不是兼容完成。** TLS/config/pid/temp文件仍靠harness删除，非native guardian清理完成。

生产guard未改，seccomp是默认ALLOW的syscall denylist，recvmsg全局禁令保留；没有用静态FD例外或可信callback标志绕过。cached Nginx源码确认每次spawn/respawn动态socketpair、SCM_RIGHTS OPEN_CHANNEL与close/reuse。当前WSL非rootuserns/mountns、Landlock ABI7及ancestor pidfd_getfd探测成功，**未证明内核不可实现**；block是provider-specific kernel对象边界/broker尚未实现。设计、实跑命令/hash与剩余门槛见[最新D2b2](HOMEPUBLISH-D2B2-CHECKPOINT.md)。Start/Apply unsupported、activation_ready=false、helper exit78保持，无生产/安装/网络安装/fw/UPnP/push/merge/PR。

## 最新 D2b1 F2 受控worker边界（local gate）

核心checkpoint commit `4628cfcfa6d5a1101e70f6510badc404093cdea6`，基线 `20eb7cf90422dc098c2461667010fbd9e5474ad7`。真实项目 setsid RED escape=1/listener开放；继承seccomp+NNP GREEN。watchdog KILL descendants RED、startup stop1/stop3残留RED分别以guardian subreaper/owned group kill与bootstrap注册/清理关闭。最终WSL `TMPDIR=/home/eric/homestun-sdk-check make -C homepublish/tests guardian direct product` exit0：19进程树、10启动故障、18原生命周期；FD三角色逐foreign dev/inode核验通过，controller对象保留。详见[最新D2b1](HOMEPUBLISH-D2B1-CHECKPOINT.md)。

只支持可信固定非root、同UID/GID、daemon-off前台worker树，允许fork/普通exec，不许setsid/setpgid/namespace/credential/FD导入；非通用hostile sandbox/cgroup。x86_64 WSL验证，aarch64源码分支未实测，其余arch fail closed。双guardian同时停调度/双故障、内核D-state不保证。exec原leader PDEATHSIG=9，fork及fork-exec worker=0实际观察；关子孙靠整组。**D2b1当时未做真实Nginx guard integrated master/worker验收；D2b2已新增真实集成RED，内部通道仍未通过**；direct真实Nginx测试是独立数据面gate，不能替代集成。产品Start/Apply unsupported、activation_ready=false、helper exit78保留。typed ERROR packet、生产provider/health/TLS/journal/fw/SDK/procd及目标预算仍待实现，无生产/公网/安装/push/merge/PR。旧fixed-TTL源码不变。


## 范围与结论

worktree `D:/DevPortal/homelede/homepublish-product`，分支 `feature/homepublish-product`，接续基线 `2f508fcca89150f1425b8a8555e240e731260500`。
用户授权仅本地源码、隔离测试、local commit；无生产、安装、映射、防火墙、公网、push/merge/PR操作。
源码命名迁移已完成；**产品未完成**。本次完成 canonical → fixed stdin CLI → 原生私有journal纵向切片，未接入旧fixed-TTL engine，不改其语义。

## 已验证交付

- `canonical.lua`：strict typed schema、continuous默认/temporary边界、boot_restore默认false、服务与listener/地址scope/证书ref校验，返回detached plan。hostname仅保存语法与scope，实际DNS/归属/管理角色/TLS须未来Start核验。
- `product-wire.lua`：HP1非执行编码，大小/深度/节点限制、重复key/尾随数据拒绝；无loadstring/eval。
- `product-provider.lua` + `product-store.c`：固定编译路径 `/etc/homepublish/product`；0700目录、0600单链接文件、owner/type/O_NOFOLLOW核验，flock非阻塞事务，candidate→file fsync→checked close（失败不重试fd）→rename→目录fsync。revision由后端递增、compare-and-save，客户端不能写desired/approval/active。
- `product-cli.lua`：仅stdin HP1，拒绝argv与未知字段。真实跨进程Save/status/Stop，Save不Apply、不Start；Stop latch后Save不复活。Start/Apply明确unsupported。
- active/pending隔离测试的active来自特权fixture，**不是运行中的数据面**；Stop仅撤意图，已有active fixture标cleanup_required，未声称清理成功。
- Makefile以TARGET_CC编译PIC Lua 5.1模块，-llua、+liblua，安装到 `/usr/lib/lua/homepublish_store.so`；recipe smoke逐字节比对编译/安装产物并真实require。未做matching SDK/IPK/真目标验收。

## 实际测试证据 / 复验

所有命令在本机WSL执行，仓库cwd `/mnt/d/DevPortal/homelede/homepublish-product`。
Lua: `/home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1`；headers默认 `/home/eric/homestun-sdk-check/canonical-lua-dev/usr/include`。

```sh
export TMPDIR=/home/eric/homestun-sdk-check
python3 homepublish/tests/test-product.py
python3 homepublish/tests/test-recipe.py
python3 homepublish/tests/test-package.py
# 以下用 wsl.exe -u root 执行，仅隔离chroot，无网络
python3 homepublish/tests/test-lifecycle.py
python3 homepublish/tests/test-source-cleanup.py
python3 homepublish/tests/test-token-validation.py
```

结果：product 8组PASS（每次独立temp编译，不依赖canonical-current）；recipe 1 test OK；package 1 test OK；lifecycle 1 test OK；source-cleanup 30 tests OK；token-validation 2 tests OK。上述最终版命令均exit 0。
CLI覆盖真实跨进程Save/status/Stop/compare-save/不越scope/拒绝server字段/Start及Apply unsupported/argv/injection/坏wire/文件symlink与mode/flock busy。

legacy Lua另在临时复制的share目录执行，防止test-core写nginx.conf污染源码：
```sh
lua=/home/eric/homestun-sdk-check/local-tools/usr/bin/lua5.1
fixture=$(mktemp -d "$TMPDIR/legacy-lua.XXXXXX")
cp homepublish/files/usr/share/homepublish/*.lua "$fixture/"
for f in test-core.lua test-config.lua test-publication-config.lua; do
  "$lua" "homepublish/tests/$f" "$fixture" || exit 1
done
rm -rf "$fixture"
```
结果：core 16项ok；config与publication-config均PASS，exit 0。

RED证据：初次test-product.py在真实provider测试通过后以 `fixed configuration CLI missing`失败；recipe新增模块断言以 `canonical native store missing from package`失败。补CLI/接线后GREEN。

## 遇到与修复

- legacy首次回归发现Windows checkout CRLF使shell `set: Illegal option -\r`，source-cleanup 30中15失败；仅规范两个执行脚本的LF，新增精确.gitattributes，不改旧模块逻辑。Windows写文件工具仍会产生CRLF，最终按字节规范后30/30通过。
- WSL没有host shared liblua；dev archive非PIC无法链接shared module。recipe fixture改用已缓存Lua 5.1.5源码临时编译host PIC库，未安装/联网。仅宏桩recipe smoke，不当作SDK证据。fixture Lua上游tmpnam链接警告仍存在，产品store本身-Werror编译通过。
- 曾错误不传share路径执行legacy Lua，报core.lua缺失；改为真实临时share目录后通过。

## 3013d16 独立审查关闭（本地源码 gate）

审查基线 `3013d16510e75f7128c3701196ced1095a0447f3`；本节修复提交为该基线后的 local commit，可由本文件 git log 定位。没有修改 scratch 独立review脚本；项目新增 `test-product-review.py` / `test-product-review.lua` / `product-store-fault.c`。

- F1/P2：array先计数，再逐个 `rawget(1..n)` 证明连续，不依赖Lua未定义的稀疏 `#`。services/listeners/methods_allowed/allowed_ranges的1,2,4,100键全部拒绝，不能用ipairs截断隐藏内容。saved/active journal config以 `model.validate` 返回的detached canonical替换后才公开；稀疏哨兵和dense未知secret字段都拒绝，合法但未归一化journal也只输出canonical。CLI真实跨进程export验证不泄露 `SENTINEL_ONLY`，坏journal不写盘。
- F2/P2：candidate写入→fsync→checked close（先clear fd、不retry）→rename→目录fsync。LD_PRELOAD close真实释放fd后返回EIO，Save非零、旧state字节/revision不变、owned candidate被清理。write/filefsync/close/rename均在发布前失败并保旧版；dirfsync在rename后失败，返回 `commit durability unknown; read status`，读回已发布的新revision，不声称回滚或持久化成功。各阶段下一次Save可恢复；owned crash candidate恢复，foreign symlink candidate保留。
- P3 policy：仅nil缺省，false/string/number拒绝，nil仍continuous。
- P3 revision：保持既有合法域 `<9007199254740991`，save/stop递增前要求 `<9007199254740990`。两种revision均验证max-1→max成功、max拒绝写盘且status仍可读、max+1坏journal拒绝。

### TDD与最终结果

逐个行为在修改对应产品代码之前实跑RED：`accepted sparse services`；数组修复后journal仍以 `raw journal exported instead of canonical plan`失败；`accepted nonobject policy false`；`overflow committed saved_revision`；真实close EIO以 `close: incorrectly reported successful save`失败。各步GREEN后再完整回归。
最终项目测试还复制到固定旧基线git archive独立复跑：sparse/journal/policy/revision/fault退出码 **[1,1,1,1,1]**，都为上述真实缺陷断言失败（journal为 `corrupt journal accepted saved_config`），不是语法/环境错误。第一次WSL `git -C`因Windows worktree .git路径失败，改显式主仓库 `--git-dir` 后复跑成功。

最终版复验（WSL、仅隔离临时目录，无安装到系统/目标）：

```sh
cd /mnt/d/DevPortal/homelede/homepublish-product
export TMPDIR=/home/eric/homestun-sdk-check
python3 homepublish/tests/test-product-review.py
python3 homepublish/tests/test-product.py
python3 homepublish/tests/test-recipe.py
python3 homepublish/tests/test-package.py
```

全部exit 0。review输出4个Lua行为PASS、CLI export PASS、5阶段fault PASS、crash/foreign candidate PASS；product原8组PASS；recipe `Ran 1 test ... OK`；package `Ran 1 test ... OK`。native模块与注入器均 `-Wall -Wextra -Werror` 编译通过。recipe上游Lua `tmpnam` linker warning仍存在，非本次新增；recipe仍仅宏桩smoke，不是matching SDK/IPK或真实部署。

独立证明旧基线RED（从当前worktree执行，成功标准是5个case全部非零）：

```sh
export TMPDIR=/home/eric/homestun-sdk-check
baseline=$(mktemp -d "$TMPDIR/review-baseline.XXXXXX")
trap 'rm -rf "$baseline"' EXIT
git --git-dir=/mnt/d/DevPortal/homelede/feeds-xiaoqingfeng/.git archive 3013d16510e75f7128c3701196ced1095a0447f3 | tar -x -C "$baseline"
cp homepublish/tests/test-product-review.py homepublish/tests/test-product-review.lua homepublish/tests/product-store-fault.c "$baseline/homepublish/tests/"
for case in sparse journal policy revision fault; do
  if python3 "$baseline/homepublish/tests/test-product-review.py" "$case"; then
    printf 'UNEXPECTED GREEN %s\n' "$case"; exit 1
  fi
done
```

## D2a 本地renderer/backend切片（产品仍未完成）

- `direct-address.lua` / `direct-backend.lua` / `direct-renderer.lua`：独立于legacy core的纯内部模块，接受typed plan与可信provider；精确literal listener、IPv6 socket `ipv6only=on`、拒wildcard/重复socket/未批准或管理冲突。backend受限hostname或literal，全量安全/scope/ownership-role核验后稳定IPv4优先并要求health；IPv6按16-bit完整解析，拒zone/linklocal/multicast/unspecified/mapped/坏压缩；proxy_pass冻结为literal IP，无runtime resolver，`proxy_next_upstream off`。
- renderer返回configuration/backend evidence，**activation_ready始终false**。可信内部provider是缺省拒绝的代码依赖，不能由CLI/client注入。fixture的ownership/管理角色/health/resolve为隔离断言，不是实际系统权威发现。生产须先canonical.validate并接入真实审核provider；fixture直接构造相同typed结构并仅用loopback，未放宽canonical生产listener限制。
- certificate_ref仅acme/import标识；路径来自可信snapshot provider并拒Nginx注入。**真实证书SAN/chain/有效期/key匹配/owner权限与secret snapshot guardian未实现**。测试客户端真实CA/SAN校验只证明本地TLS反代，不冒称产品证书readiness。
- DNS snapshot含resolver/TTL/observed_at，TTL限定1..86400；无可信TTL拒绝。真实受限resolver、TTL refresh/rebinding受控替换与deadline关闭尚未接入，禁止无限缓存或激活。backup/runtime failover尚未接入。
- 中途local checkpoint commit `97fb603`；TDD实跑RED：`direct typed backend selection missing` → GREEN；安全下一轮 `accepted unsafe resolver result ::` → GREEN；renderer `direct renderer missing` →真实nginx RED `duplicate listen options` → GREEN（ipv6only只设置一次）。初次fixture用fd00::/8不满足canonical范围最小/16，收紧fixture范围后通过。
- 最终命令（WSL，无联网/安装）：`cd /mnt/d/DevPortal/homelede/homepublish-product && export TMPDIR=/home/eric/homestun-sdk-check && make -C homepublish/tests direct product`，exit 0。新增test Makefile注册可复验入口；包Makefile已有*.lua通配，无需改安装规则。
- Cached SDK nginx 1.26.1经musl loader运行，3次真实nginx -t和启动通过；v4→v4、v6→v4、v4→v6、v6→v6全部真实TLS反代PASS。附加controlled hostname fixture（AAAA先给出、选择A）两种ingress真实通过，config无backend hostname。六次POST各接受一次副作用后后端断连接，客户端502、计数仅+1，零重放；unknown Host空响应/unknown SNI握手拒绝。全部loopback隔离，无公网结果。
- 子进程wait/readback、测试listener连接失败、owned PID不存在、临时目录/CA/key/cert移除均断言PASS。product-review/product/recipe/package完整复跑PASS；recipe既有上游Lua tmpnam warning仍在，仅recipe smoke非SDK/IPK。

## D2a 独立review修复（2ef5be5之后 local commit）

两项真实问题已按行为逐个RED→GREEN关闭：absolute-form使`$host`跳过原始未知Host；大写合法SNI被大小写敏感比较拒绝。现策略只允许origin-form，严格匹配原始Host/实际socket port与SNI，同域大小写合法；不允许absolute-form forward proxy或不同Host port（未来external translated port需权威controller明确支持）。端口额外RED证明`service.home:0`旧实现到达backend，修复后拒绝。

项目新增`test-direct-boundary.py`/`direct-boundary-fixture.lua`并注册Makefile direct：两个独立SAN证书、两个独立GET计数backend，真实双栈四组合；所有未知/跨服务/absolute请求两backend零副作用，大小写/Host:实际port合法。最终WSL `export TMPDIR=/home/eric/homestun-sdk-check && make -C homepublish/tests direct product` exit 0；原direct/POST不replay、边界矩阵、product-review/product/recipe/package全部PASS，Start/Apply unsupported与activation_ready=false保持。owned process/listener/临时证书清理断言PASS；既有Lua tmpnam linker warning不变。具体RED断言、命令和端口策略见[详细checkpoint](HOMEPUBLISH-D2A-CHECKPOINT.md)。本段引入的local commit由文件git log定位；无生产/安装/公网/映射/fw/push/merge/PR。

**产品仍未完成；下一阶段独立有限能力guardian/controller**，不能从本地TLS修复跳到activation。

## D2b1 独立原生有限可续授权内核（仅process-control gate）

新增 renewable-guard.c/.h、固定loopback C fixture及13场景Python回归，tests guardian target与TARGET_CC recipe helper。首次expiry及renew实跑RED→GREEN，中途checkpoint commit acffea1；最终 `export TMPDIR=/home/eric/homestun-sdk-check && make -C homepublish/tests guardian direct product` exit 0。有限600ms guard、独立200ms watchdog、monotonic固定temporary截止、gen/epoch/exact sequence/token/有限严格帧、Stop不可续活；真实同PID八次renew、controller/guardian KILL/STOP、stale/replay/auth/短帧断流，foreign进程/文件不动，owned PID/监听/既有流/临时目录清理读回通过。helper无provider，任意argv也仅exit78。完整协议/预算/证据/未验watchdog STOP与FD/descendant边界见[checkpoint](HOMEPUBLISH-D2B1-CHECKPOINT.md)。无secret-copy/owner journal/renderer/controller/fw整合；activation_ready=false、Start/Apply unsupported不变，旧fixed-TTL未改；macro recipe不是SDK/IPK/真目标。产品仍未完成。

## 剩余门槛

D1尚缺真实rpcd scoped权限/角色及迁移工具；D2a仅renderer/静态backend完成本地切片，D2-D7 controller/guardian生产整合、权威DNS/TLS/归属管理核验与TTL刷新、精确INPUT/UPnP受控续租恢复、真实四页LuCI/RPC、ACME/DNS维护/Passwall2、matching SDK/IPK/真BusyBox-procd-fw4及另授权实网均未完成。Start/Apply继续unsupported，provider不宣称running。禁止以本切片或legacy PASS称产品可发布。
