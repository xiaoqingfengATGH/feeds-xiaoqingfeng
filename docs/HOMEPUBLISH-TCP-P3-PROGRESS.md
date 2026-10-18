# P3 数据面进度与续跑入口

范围：冻结计划 tasks 16–21。仅设备 root@127.0.0.1:222，私有目录与 loopback 高端口；不动 live journal、不撤 v2 activation guard，不修改系统 nginx/sslh、管理服务、防火墙、路由或认证。P4 生命周期/UI不在本轮范围。

## 当前验收结论（Checkpoint7优先于下文历史时点）

P3 tasks16–21 的授权设备隔离/installed固定profile数据面门槛已复验GREEN；HTTPS四族实流缺口已补齐。仅申请父任务阶段验收，不等于production release：production system provider仍不可用，nginx/sslh仍为pinned私有fixture依赖。P4未开始，未commit。

| Task | 当前证据 / 精确边界 |
|---|---|
|16|`task20-through16-stage-final.log`最终task16：业务systemCA+hostname、HTTP正例、HTTPS upstream正例/错名502/不可信502、源证书保护/清理GREEN。|
|17|同一日志task17：HTTPS+精确SNI TLS/mTLS、身份/指纹保持、无证书与未知/后缀/无SNI/垃圾/PROXY/超时拒绝GREEN。|
|18|同一日志task18：共享原生SSH实际KEX+一次性key认证/forced command，管理PID/配置/监听保持GREEN。|
|19|同一日志task19：独立TCP双向8192二进制、客户端/服务端先发、双向半关闭、held8sGREEN。|
|20|同一日志task20 TLS/SSH/TCP四族、受控libc答案变更/范围拒绝、POST不重放GREEN；最终task16新增HTTPS ingressv4/v6×backendv4/v6，HTTP及verified HTTPS upstream共8实际流GREEN。|
|21|`task21-installed-stage-final.log`四协议installed固定profile/procd/readiness/Stop/失败与unknown GREEN；`task21-stale-stage-final.log`过期generation拒绝、`task21-private-stage-final.log`完整固定adapter回归GREEN。父独立installed `task21-installed-parent.log`由父任务提供exit0。|


## 阶段边界
隔离 runtime 实流不等于 installed provider / procd 完整验收，也不证明公网 IPv6 可达。现有 installed v2 activation guard 保留。业务证书/私钥不输出不下载，仅服务器端快照。

## Checkpoint 0
- 分支 feature/homepublish-product，基线 19a6ec677b05c6b02786bed48564bb77240212c0；已有 untracked 证据/sketch/pycache 保留。
- 只读确认设备无 P3 高端口监听；管理 dropbear 34089/36655、uhttpd 4308、xray 16371。live rev0 / intent7 / disabled / stopped / cleanup confirmed。
- P0 nginx 1.26.1 是 stream-only，不能直接冒称 HTTP SSL 交付；需从缓存 SDK 私有交叉构建 HTTP SSL/realip/stream variant，不本地运行目标程序。
- 续跑入口待添加 harness 与命令；每轮证据写 docs/evidence/tcp-p3/。不得使用历史 router-business-tls.sh（会修改 live state）。

## Checkpoint 1 — task16 独立验证落盘 / task17 最终实机 GREEN

- 父任务已独立上传并运行 task16 最终四文件 exit0；本轮又用包含混合路由支持的最终 Lua 重跑 task16，完整结果在 `docs/evidence/tcp-p3/task17-final-and-task16-regression.log`（exit0）。原 `/tmp/homepublish-tcp-p3/evidence` 的非秘密 `.log/.txt` 已下载至 `task16-device-final/`；没有下载业务或fixture私钥。
- task17 RED：`task17-red.log`，设备上明确失败 `P3 route type not implemented: tls_passthrough`，再实现最小混合编译链。最终 `task17-final.log` exit0；首次 GREEN 和完整回归结果分别保留，不覆盖失败证据。
- 新增 `sslh-renderer.lua`，`tcp-route-plan.lua` 降低 enabled HTTPS/TLS 混合图；`direct-renderer.lua` 仅对 passthrough 图转入该分支，HTTPS-only 保持专用 Nginx 直听。新增设备脚本 `device-tcp-p3-mixed-render.lua`、`device-tcp-p3-mixed.sh`、`device-tcp-p3-reject.lua`。
- 实机链：固定 harness 将一个 canonical ULA 精确缩窄至 `[::1]:49543` → 私有 sslh 2.3.1 → HTTPS only `127.0.0.1:49544`（PROXY v1）或 exact `tls.fixture.home` → `127.0.0.1:49546`（无PROXY）。应用自有 Nginx stream `127.0.0.1:49549` 主动接受并立即关闭未知/超时连接，不借不存在端口拒绝。生产 canonical loopback 禁止未改。
- HTTPS 分支实际 systemCA/hostname 验证 `home.iwonderful.top/acme:home_rsa`，后端记录 `HP_P3_MIXED_WEB|::1|::1`，伪造 X-Real-IP/XFF 被重建。仅 sslh 的精确 loopback peer 被 realip 信任，本机进程不构成密码学隔离边界。
- 透传实际 fixtureCA/hostname 验证及客户端mTLS，响应 `HP_P3_END_TO_END_MTLS|CN=P3_FIXTURE_CLIENT|SUCCESS`；后端直连/透传恰好两条 SHA256 指纹且唯一值相同；缺客户端证书400无业务标记。fixtureCA/客户端身份明确仅fixture，不宣称业务CA信任。
- 未知SNI、suffix攻击SNI、无SNI、垃圾、客户端PROXY及无输入探测超时均拒绝；后三种 real socket 在4秒内 EOF/连接拒绝，未获得任何业务字节。源证书/私钥hash与uid/gid/mode仅服务端比对，快照0600/runtime0700；退出所有私有进程后快照与fixture keys清理。
- `task17-device-final/` 保存最终非秘密日志、响应、fingerprint、listeners与source SHA256。前后 live journal、防火墙/管理/Passwall2配置、系统nginx hash一致；runtime与mixed-runtime均不存在。未改 live Save/migrate/Start 或 installed UI；未装系统包、未改DNS/路由/认证/防火墙；无commit/push/merge。
- 受影响 legacy `direct-boundary-fixture.lua` 在设备上以IPv4和IPv6后端各执行一次：两个hostname、双监听输出均渲染，检查第二后端 exact proxy_pass；此为旧模型纯渲染回归，非 legacy 实流重验。证据为完整回归日志最后一行。`git diff --check` exit0（既有autocrlf warning保留）。

### 精确续跑命令（仅真实设备）

仓库根目录运行，SSH/scp通用参数不可遗漏：

```sh
ssh -o ProxyCommand=none -o ProxyJump=none -o IdentitiesOnly=yes -o BatchMode=yes -i D:/DevPortal/CloudHosts/HomePri.key -p 222 root@127.0.0.1 'sh /tmp/homepublish-tcp-p3/device-tcp-p3-mixed.sh && sh /tmp/homepublish-tcp-p3/device-tcp-p3.sh'
```

更新后用 `scp -O` 同参数、端口 `-P 222` 上传到 `/tmp/homepublish-tcp-p3/`：三个renderer/route Lua及以上设备脚本；task16四文件原样保留。sslh私有可执行文件为设备 `/tmp/homepublish-tcp-p3/sslh-select.private`，缓存来源 `/home/eric/homestun-sdk-check/tcp-ingress-p0/out-identity/sslh-select`；不必重建。编译来源与固定commit见 `build-tcp-identity-components.sh`。Nginx继续设备已有 `nginx-private`；二者都不覆盖系统文件。

### 明确未完成

- 这里只完成 task17 要求的混合图（至少一个 HTTPS + TLS）；仅透传无HTTPS图目前显式拒绝，不能假称已全矩阵支持。
- tasks18–19 的隔离实机切片现已GREEN（见Checkpoint2/3）；tasks20–21未关闭，需族矩阵与DNS安全 / 标准procd整组ownership/readiness。内部端点分配、占用预检和拒绝端点生命周期必须接入固定provider后才是task21完成。
- `activation_ready=false`、installed v2 activation guard仍保留。没有把可信fixture ports/provider选择暴露为客户端配置；本轮非installed provider、非P4生命周期/UI、非公网IPv6验收。父任务仍须独立重跑最终版本。


## Checkpoint 2 — task18 shared native SSH

- 父任务在本子任务开始前独立执行 `sh /tmp/homepublish-tcp-p3/device-tcp-p3-mixed.sh && sh /tmp/homepublish-tcp-p3/device-tcp-p3.sh`，exit0，task17+16最终实流全GREEN；本项为父任务提供的独立验证记录。
- 新测试 `device-tcp-p3-ssh-render.lua` / `device-tcp-p3-ssh.sh` 先实机RED（`task18-red.log`：route type not implemented: ssh），再扩展 lowering 与ssl h的原生ssh探针（无PROXY）。
- `task18-green.log` exit0：同一个 `[::1]:49543` 同时通过HTTPS业务CA、TLS/mTLS指纹、拒绝矩阵和SSH。SSH到独立 `127.0.0.1:49547` dropbear，使用一次性私钥、公钥授权目录、forced marker command完成真实KEX/认证/会话，不连接管理SSH后端。
- fixture修正：dropbear正确拒绝world-writable `/tmp` 下authorized_keys（保留task18-attempt1.log）；仅授权fixture目录改为 `/root/homepublish-p3-ssh-auth` mode0700，退出删除，不改系统authorized_keys、密码或认证配置。host/client keys仍在私有runtime，退出删除。管理dropbear 34089/36655、uhttpd4308、xray16371 PID+监听逐行一致；immutable配置/journal和源证书服务器端校验一致。
- 复跑：同SSH参数执行 `sh /tmp/homepublish-tcp-p3/device-tcp-p3-ssh.sh`；该脚本沿用mixed-runtime/mixed-evidence，禁止并发运行task17/18。后续最终独立复跑仍由父任务执行。

## Checkpoint 3 — task19 independent TCP / final task16–19 regression

- 实机RED `task19-red.log`：`P3 route type not implemented: tcp_forward`。新增 `tcp-stream-renderer.lua` 并接入canonical lowering/direct-renderer，独立端口直接由private Nginx stream监听，不经过sslh探针、不注入PROXY、不申请证书；`proxy_half_close on; proxy_next_upstream off; proxy_timeout 1h;`。纯TCP配置不监听未使用的共享入口49543。
- 三个精确harness IPv6 listener `[::1]:49550/49552/49554` 分别到IPv4 `127.0.0.1:49551/49553/49555`。客户端/服务端先发各传8192字节（含全部0..255二进制值），反向精确倒序、PING/PONG交错、同socket空闲保持8秒后继续HELD8/AFTER；客户端FIN后仍读到完整TAIL；第三流由服务端先write-half-close，客户端观察EOF后仍发送完整8192字节且后端验证成功。8秒是本轮有界长连接观察，不冒称数小时soak。
- Fixture首次GREEN前修正 nixio:setopt reuseaddr 需integer1而非boolean（保留task19-attempt1.log）；不改产品逻辑掩盖失败。`task19-attempt2.log`、`task19-final.log` exit0。
- 最终全套 `task18-19-final-and-regression.log` exit0，顺序task18 SSH → task19 TCP → task17 mixed → task16 HTTPS/upstream。最终额外重跑task18和task19各exit0后保存 `task18-device-final/`、`task19-device-final/` 非秘密日志；未下载runtime或私钥。`task18-19-upload-hashes.json` 验证9个最终source/harness文件本地与设备SHA256相同。
- `task18-19-cleanup-final.log`确认runtime、mixed-runtime、tcp-runtime和/root/homepublish-p3-ssh-auth均不存在，无任何task16–19高端口listener。每个harness前后live journal/防火墙/管理/Passwall2/system nginx hash一致；task18/19管理SSH/Web/proxy PID与监听一致。源业务证书/私钥不变，仅服务端比对；所有fixture keys已删除。git diff --check exit0（既有autocrlf warning）。
- 本轮新增文件：device-tcp-p3-ssh-render.lua、device-tcp-p3-ssh.sh、device-tcp-p3-tcp-render.lua、device-tcp-p3-tcp-sockets.lua、device-tcp-p3-tcp.sh、tcp-stream-renderer.lua；扩展 tcp-route-plan.lua、sslh-renderer.lua、direct-renderer.lua。全部私有上传，不安装/覆盖系统组件。

### 父任务独立最终复跑（必做）

同上述固定SSH参数：
```sh
ssh -o ProxyCommand=none -o ProxyJump=none -o IdentitiesOnly=yes -o BatchMode=yes -i D:/DevPortal/CloudHosts/HomePri.key -p 222 root@127.0.0.1 'sh /tmp/homepublish-tcp-p3/device-tcp-p3-ssh.sh && sh /tmp/homepublish-tcp-p3/device-tcp-p3-tcp.sh && sh /tmp/homepublish-tcp-p3/device-tcp-p3-mixed.sh && sh /tmp/homepublish-tcp-p3/device-tcp-p3.sh'
```

未完成（Checkpoint3历史时点）：task20双栈/其余族组合与DNS受限变更/非幂等noReplay；task21标准procd/controller整组readiness与ownership/cleanup_unknown；纯TLS/SSH无HTTPS共享图仍显式拒绝。mixed+独立TCP共一个nginx配置的合成分支有实现但本轮未额外实流验证，不以本轮三个独立TCP例代替该组合验收。installed activation guard不变，未进入P4，未改最新safeUI/保存live配置/开放公网，无commit/push/merge。

## Checkpoint 4 — task20 final isolated GREEN / task21 still open

- 父任务已在本次开始前独立复跑task18 SSH → task19 TCP → task17 mixed → task16 HTTPS全exit0；本次收到的父验证作为独立Checkpoint3确认，不冒称本子任务独立验证。
- 冻结计划 `.hermes/plans/2026-10-15_143056-homepublish-tcp-ingress-luci.md` tasks16–21边界保持。新行为先实机RED：`task20-red.log`为`shared SSH/TLS without HTTPS not implemented`。最小产品变更仅`tcp-route-plan.lua`允许非空无HTTPS共享图，`sslh-renderer.lua`仅有HTTPS才要求https内部端口/调用HTTP renderer与证书provider；否则仅生成拒绝stream。未改canonical、direct-backend、device-integrations及installed guard。
- 新增`device-tcp-p3-matrix-render.lua`、`device-tcp-p3-matrix.sh`、`device-tcp-p3-post-render.lua`。无HTTPS图由TLS透传+原生SSH+独立TCP组成，同一运行图同时监听IPv4/IPv6的49543/49550，分别到IPv4及IPv6真实loopback后端；四种族组合每项并发启动TLS共享请求、独立TCP TLS请求及真实Dropbear KEX/一次性key认证/forced command，均获得精确marker。无入口证书快照/解析调用；后端fixtureTLS证书不等于入口证书。TLS-only及SSH-only无证书额外纯render断言通过，未将它们冒称独立runtime矩阵。
- 生产绑定不放宽：固定harness仅将canonical `192.168.1.2`及精确两个ULA映射至相应loopback；IPv6 backend采用canonical ULA，不能以`::1`绕过canonical。`task20-matrix-attempt1.log`保留初次`unsafe IPv6`fixture失败及成功cleanup；随后修正仅fixture，不改生产IPv6规则。
- 受控解析：在非installed harness的`nixio.getaddrinfo`返回边界馈入答案，执行原样`device-integrations.resolve`和`direct-backend.select`。TLS backend域名从IPv4答案换到IPv6答案后重新render/restart私有图，并获得各族不同实流marker。额外验证双答案去重/确定性IPv4偏好、仅IPv6变更、混入一个范围外私网答案及公网答案均拒绝；renderer整链对范围外答案拒绝。明确是**controlled libc answer-feed**，不是实际DNS记录变更，未修改hosts/resolv/DDNS；不宣称已验installed周期renew/controller恢复。
- POST为既有noReplay行为追加回归，不假称新的RED：受控双IPv4答案按现有selector只选一个后端；POST `/ok`实际200、`/drop`后端主动444关闭而入口502。后端access log精确`POST /ok=1`、`POST /drop=1`、备选地址请求=0。两个非幂等请求均无重放；配置仍`proxy_next_upstream off`。
- `task20-final-and-regression.log`完整最终版本顺序task20 → task18 → task19 → task17 → task16 exit0；不仅沿用`task20-matrix-attempt2.log`历史GREEN。受影响HTTPS业务CA/hostname、上游TLS校验正反例、mTLS身份/指纹/无证书拒绝、所有未知协议/SNI拒绝、TCP8192二进制/半关闭/held8s及管理基线全通过。新task20的四族矩阵针对TLS/SSH/独立TCP；HTTPS反代本轮仍仅task16的IPv6→IPv4，未新增HTTPS四族实流。所有公网族可达性仍未验。
- `task20-device-final/`只下载matrix-evidence非秘密证据；无runtime/私钥下载。`task20-final-readback.log`记录最终5个新增/变更源码SHA256和`FINAL_CLEANUP_READBACK_GREEN`；已程序化比对本地/远端5项一致。sslh=`635f8462494ebf2a16f5b466cbe10390c742425d483f42b5c7395ce77ca3bfa8`，route-plan=`46aa480ed4376e99a78a7a9a2897a1d33cbbaecec6c0d9c6dceaaad325e63213`，matrix-render=`af47dd2d11167b17e91b4b42177ac246e125af3c70a57ad6ccbff7d05c8a0b88`，matrix-shell=`406fefe8890ce7d6325d15b90f5e01c46eadbec2f3ccbb4c5fc08b3f0dc789d1`，post-render=`8768708c4559f8df226b196e1205dd7353f299143968af98984616e481afff88`。
- 最终readback：runtime/mixed-runtime/tcp-runtime/matrix-runtime、两个root-private SSH auth目录均不存在，49443–49557所有明确测试端口无监听。各harness前后live journal/管理/防火墙/Passwall2/system nginx一致，task20另比对hosts/resolv配置，管理SSH/Web/proxy PID/监听一致。业务源证书原样、快照/fixture keys清理。git diff --check exit0，仅既有autocrlf warnings。

### 下一步与精确复跑

同前述SSH/scp固定参数，仅私有上传：`sslh-renderer.lua tcp-route-plan.lua device-tcp-p3-matrix-render.lua device-tcp-p3-matrix.sh device-tcp-p3-post-render.lua`。父任务独立复跑命令：

```sh
ssh -o ProxyCommand=none -o ProxyJump=none -o IdentitiesOnly=yes -o BatchMode=yes -i D:/DevPortal/CloudHosts/HomePri.key -p 222 root@127.0.0.1 'sh /tmp/homepublish-tcp-p3/device-tcp-p3-matrix.sh && sh /tmp/homepublish-tcp-p3/device-tcp-p3-ssh.sh && sh /tmp/homepublish-tcp-p3/device-tcp-p3-tcp.sh && sh /tmp/homepublish-tcp-p3/device-tcp-p3-mixed.sh && sh /tmp/homepublish-tcp-p3/device-tcp-p3.sh'
```

Task21仍必须实现/验收标准procd/controller整组ownership/readiness及cleanup_unknown；隔离套接字GREEN不是installed provider。HTTPS完整四族实流、installed DNS周期renew不在本次已有证据内，后续若要求完整跨协议矩阵须补。P4未开始；无commit/push/merge，无live Save/migrate/Start、管理认证、fw/routes/DNS/UPnP变更。

## Checkpoint 5 — task21 parent independent fixed adapter confirmation

- 父任务独立运行 `python homepublish/tests/run-device-tcp-p3-controller.py --stale` 和不带参数版本，均exit0。原始父日志 `C:/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/terminal-output/out-1792065526-4328-dcd0.log`。覆盖真实procd TLS+TCP整组、第二组件bind失败、第二服务readiness失败、stale generation拒绝、foreign identity cleanup_unknown拒删/拒重启后owner解决、held连接关闭和baseline不变。这是父任务提供的独立结果，不冒称本轮新独立验证。

## Checkpoint 6 — installed device v2 capability / four protocols GREEN

- RED：`task21-installed-red.log`，实际 `/usr/share/homepublish/product-device-provider.lua` 缺runtime_plan capability；执行私有JSON CLI失败exit1。实现后首次 `task21-installed-attempt1.log` 仍拒绝（旧device-test enabled文件不存在），不以创建全局开关绕开。改成固定私有fixture内authorized marker，仅fixture存在期间可用；marker退出删除，installed canonical/public guard没有全局放宽。
- 新增共享产品模块 `product-v2-runtime.lua`，负责canonical-v2重验、enabled/authentication审核、所有后端受限选择、证书resolver身份、render、procd整组、逐服务generation readiness和30秒证书/DNS身份renew。`product-procd-group.lua`新增应用自有root内0600证书/key快照。`product-device-provider.lua`接入v2分支并保留legacy；新的固定server-owned `product-device-v2-profile.lua`只允许本轮授权hostname/业务RSA引用/端口/精确ULA→loopback缩窄，没有客户端provider/path/exec选择；并非克隆旧测试adapter。`product-system-provider.lua`仍production unavailable，canonical通用guard保持。
- 9个匹配模块已直接部署 `/usr/share/homepublish/` 并逐文件SHA256核验，旧已存在文件备份于 `/root/homepublish-p3-installed-backup`；不恢复旧UI，不重载/启动live controller，不替换系统nginx/sslh。最终installed来源清单 `task21-installed-source-sha256.json`。现用nginx1.26.1/sslh2.3.1仍是 `/tmp/homepublish-tcp-p3/` 私有fixture依赖，**生产组件选择与系统provider未完成**。
- 私有 `device-tcp-p3-installed-cli.lua`仅选私有native journal；package.path首项为真实 `/usr/share/homepublish/`，原样require installed provider/controller/renderer/group，无package.loaded替换、无语义fakeprovider。固定profile只有端点授权/缩窄与fixture后端TLS trust；业务HTTPS使用real `home.iwonderful.top/acme:home_rsa` resolver、systemCA+hostname，源证书/key SHA256+uid/gid/mode在服务器内前后比较，不下载秘密。
- `task21-installed-final.log` exit0：同generation四项HTTPS/SSH/TLS/TCP readiness均ready后才active；实流HTTPS业务CA/hostname marker、TLS透传和独立TCP exact marker、原生SSH真实KEX/一次性key认证+forced marker。SSH不需要/不创建入口证书；仅HTTPS创建cert1.pem/key1.pem，uid0/runtime0700/key0600实读。四协议held客户端均在Stop前running，Stop后全部退出、新连接拒绝、procd整组/runtime/快照消失、duplicate Stop confirmed。
- 同一次installed验收覆盖第二组件sslh bind失败（unrelated sentinel保留）、raw第二服务不可达（其他服务ready仍不能active、全代clean confirmed）、foreign command identity Stop拒删+cleanup_unknown、Start拒绝，随后仅test owner移除foreign再provider读回confirmed。无全局init reset。
- 最终版本连续执行installed全套 → private stale → private full → task20 → task18 → task19 → task17 → task16，完整命令exit0。日志分别 `task21-installed-final.log`、`task21-stale-final.log`、`task21-private-final.log`、`task21-all-affected-final.log`。不沿用最后测试修改前的attempt2 GREEN。生产模块与harness上传hash在每套结束校验。
- 最终独立只读结果 `task21-installed-final-readback.log`：live rev0/intent7/disabled/latch/stopped；四个owned procd names不存在，runtime/fixture/SSH auth/key不存在，私有marker消失后installed capability再次拒绝。各套baseline管理PID/监听、live journal、firewall/dropbear/uhttpd/passwall2/DNS hosts/resolv/system nginx保持；业务源证书原样。`git diff --check` exit0，仅既有autocrlf warning。无live Save/Start/migrate、fw/routes/DNS/UPnP/auth变更，无commit/push/merge。

### 父任务必须独立复跑（不带deploy，禁止并发）

```sh
python homepublish/tests/run-device-tcp-p3-controller.py --installed
python homepublish/tests/run-device-tcp-p3-controller.py --stale
python homepublish/tests/run-device-tcp-p3-controller.py
```

随后沿Checkpoint4的SSH命令重跑task20/18/19/17/16。需要重新部署本轮源码时才加 `--installed --deploy-supported`，该参数只部署已列9模块，不启动live，不覆盖管理或UI。

### 当前边界 / 剩余

- installed device v2 adapter四协议/标准procd切片已GREEN，**P3暂不宣告关闭，待父任务独立final验收**。
- 系统production provider及正式依赖组件选择/安装仍未完成；本轮不是public production activation支持，live UI仍safe installed。
- task20 HTTPS四族实流仍缺（本轮HTTPS为IPv6入口→IPv4 backend）；已验TLS/SSH/TCP四族不得替代HTTPS矩阵。v2 installed周期DNS/cert变更恢复、P4 Apply/policy/UI概览没有扩展或验收，公网可达性未验。

## Checkpoint 7 — HTTPS完整四族 / 最终安装态与受影响全套复验

- 已记录父任务独立 `python homepublish/tests/run-device-tcp-p3-controller.py --installed`：`task21-installed-parent.log` exit0（父任务提供）；本轮再次串行复验最终installed四协议 → stale → private full → task20 → task18 → task19 → task17 → task16，四个主日志全部exit0。当前源码仍基线19a6ec6上的未提交P3，不commit/push/merge。
- 新增测试 `device-tcp-p3-https-matrix-render.lua`，扩展 `device-tcp-p3.sh`；**无产品功能改动**。新矩阵首次真正匹配上传版本运行即GREEN，是已有功能补覆盖，不伪称功能RED→GREEN。`task20-https-all4-first.log`实际上误跑远端旧脚本（scp相对路径问题），不算矩阵证据；改用绝对路径并上传SHA256比对后 `task20-https-all4-attempt2.log` exit0，最终完整重跑也exit0。
- 新renderer测试明确优先require真实 `/usr/share/homepublish/` 模块；双入口v4/v6分别向HTTP和verified HTTPS的v4/v6后端发起真实curl，总计8条精确marker、systemCA+hostname验证；业务身份固定 `home.iwonderful.top / acme:home_rsa`。IPv6 backend用canonical精确ULA后在harness内缩窄至`::1`，v4入口也只精确fixture缩窄；生产loopback ingress仍拒绝，没有放宽canonical/生产授权。HTTPS upstream错名/不可信链502负例同时复验。
- 最终证据：`task21-installed-stage-final.log`、`task21-stale-stage-final.log`、`task21-private-stage-final.log`、`task20-through16-stage-final.log`。HTTPS非秘密设备日志/8条响应及最终监听表保存 `task20-https-device-final/`。矩阵精确集合用Python检查8项无重复/遗漏；`verify-stage-final.py`真实执行exit0，未运行本机业务替身。
- `p3-stage-final-source-sha256.json`对9个installed产品模块+2个新增/改动私有harness逐文件读回匹配；`p3-stage-final-readback.log`确认所有owned procd对象/runtime/SSH auth/fixture keys/高端口listener不存在，authorized marker删除后installed能力再次拒绝；live rev0/intent7/disabled/latch/stopped。各全套前后live journal、管理PID/配置/监听/firewall/Passwall2/system nginx保持；源业务cert/key hash+uid/gid/mode仅服务器内比较不变，快照0700/0600且退出删除。
- 最终只读collector初版按JSON原始文本比较空ubus对象失败（格式空白），随后尝试把native journal envelope当纯JSON失败；二者均是只读验收工具问题，不是产品失败。最终collector使用JSON解码ubus与正式只读provider status，保留严格状态断言并实际通过。

### 有界源码审查候选事实（非中立审查结论）

本轮读取 `product-procd-group`、`product-v2-runtime`、`product-device-v2-profile`、controller/device-provider/direct-renderer增量及route/sslh/tcp renderers，对照tasks16–21与最终证据；因本轮作者身份，仅提供父任务审查候选，不宣称独立P5通过：

1. profile只允许1个精确ULA入口/固定v4后端端口、私有authorized marker和固定可执行路径；因此四族新增验证是installed renderer实流，**不是installed profile双栈支持**。通用production provider、组件打包/安装与实际用户网络入口仍是后续集成/发布门槛，不能用该profile冒称全局生产就绪。
2. controller要求v2逐service generation一致才ready；group无respawn，失败/foreign identity走cleanup_unknown不误删；真实负向与Stop held四协议证据已过。本轮未发现已复现且阻塞P3授权切片的缺陷。
3. runtime renew的证书身份复核/每服务backend重新选择有代码，但本轮未验周期DNS/cert替换与恢复；进程内active状态、provider模式切换与P4恢复链需后续独立验收，不能从当前静态或启动GREEN推断已通过。
4. group当前ownership是可信procd name/command和进程身份检查，不能声称抵抗root主动篡改、目录置换或任意崩溃窗口；parent可在P5评估进一步故障覆盖，勿为本轮引入新guardian架构。
5. SSH readiness只证明协议banner，raw readiness只证明后端+入口连接；真实SSH认证/四协议marker是测试另行证明，不能把readiness字段等同完整应用鉴权。

### 精确复跑 / 阶段停止

```sh
python homepublish/tests/run-device-tcp-p3-controller.py --installed
python homepublish/tests/run-device-tcp-p3-controller.py --stale
python homepublish/tests/run-device-tcp-p3-controller.py
# 同Checkpoint4 SSH选项，串行执行 matrix.sh -> ssh.sh -> tcp.sh -> mixed.sh -> device-tcp-p3.sh
python docs/evidence/tcp-p3/verify-stage-final.py
```

P3授权的数据面测试门槛已齐，交父任务决定阶段验收；**停在P3，不执行P4**。P4 overview/Apply/policy/周期恢复，P5独立审查/IPK依赖归档/生产provider与公网另行授权验收；未启live、未改管理认证/fw/routes/DNS/UPnP，未提交。历史Checkpoint6的“HTTPS四族缺口”已由Checkpoint7覆盖，不删除历史证据。


