# HomeSTUN NATMap 安全边界暂停/续跑交接

用户要求临时关机：立即暂停新实现和新测试；未 commit/push/merge/PR，未做远程写入、安装、Firewall/Cloudflare 修改或公网监听。

## 工作树与改动协调范围

- 仓库：`D:/DevPortal/homelede/feeds-xiaoqingfeng-homestun`，分支 `feature/homestun`。这些 HomeSTUN 文件当前属于原任务已有未提交/未跟踪工作树；不要重置或删除其他 agent 的成果。
- 本安全子任务修改：
  - `homestun/src/lease-supervisor.c`：新增 `confine_natmap()` 原生 seccomp-BPF；审计 ABI 检查；拒绝 `pidfd_getfd`（EPERM）；`PR_SET_NO_NEW_PRIVS`；NATMap exec 前安装；私有 pipe 就绪确认后才启动 nginx。安装失败不执行两个引擎，原 guardian 清理/期限路径继续生效。
  - `homestun/tests/test-socket-boundary.py`：新增四项真实原生/内核边界测试。强制 root 且拒绝 host network namespace。两个真实 socket 测试直接编译固定上游原始 `set_reuse_port()`，验证占用端口与预检成功后被抢占的 startup race。
  - `homestun/README.md`：说明边界、OpenWrt 内核前提、测试命令和限制。
  - 本文 `docs/homestun-resume-natmap.md`。
- 未修改 `lease-run.sh`、init、Lua/config、Makefile；这些由另一个 cleanup agent 管理，禁止覆盖其改动。已阅读 package recipe，raw BPF 不新增用户态库依赖；实际目标 SDK/内核仍待验证。
- 另更新了当前 ta profile 的 `homelede-development` skill 专题参考，记录 NATMap root 导入 foreign socket 的风险和隔离测试方法；没有修改其他 profile。

## 已确认上游风险与方案

本地上游：`/home/eric/homestun-natmap-20260214`，revision `f8d7996710677c9885c148dda80a42d626f0a17b`。

`src/hev-sock.c:216-219` 在 bind 失败后调用 `hev_reuse_port`；`src/hev-misc.c:193-206` 中 `pidfd_getfd` 导入占用者的 socket，随后设置其 `SO_REUSEPORT=1`。端口配置分离或预检存在 race，不能构成安全边界。

采用 raw Linux seccomp-BPF 而非猜测 OpenWrt 包依赖/额外库或全系统替换 NATMap。目标头文件提供 syscall number，未知 ABI/缺少定义编译失败；内核不支持 filter 时运行失败关闭。审计 arch 检查并拒绝 x86-64 的 x32 syscall namespace。支持代码包含 x86-64、i386、ARM、AArch64、RV64、MIPS o32/n64/n32，**实际只在 WSL x86-64 编译执行，其他 ABI 尚未 SDK 验证**。

这只防止已检查上游的 descriptor-import/socket mutation，不是恶意 root 沙箱；其他进程已经主动开启 REUSEPORT 的端口仍可能允许共享。需要真专属端口。配置默认禁用/approval off 保持。未证明真实 NATMap 完整发现、映射 readiness 或公网可达性。

## RED → GREEN 实际结果

1. 首个 seccomp syscall 测试在原 native helper 上 RED：期待 `-1 1` (EPERM)，实际 `-1 9` (EBADF)。实现 exec 前安装边界后 GREEN。
2. 模拟 kernel filter 安装失败并延迟 100ms 的测试 RED：nginx 已启动 marker 存在，证明仅 child 安装不足以阻止监听器先启动。新增 private pipe acknowledgement 后 GREEN：未执行 NATMap/nginx，helper 非零退出，snapshot 清理。
3. 两个 socket 回归使用 scratch 临时源副本移除 boundary 的负对照均 RED：原始 unrelated listener 的 `SO_REUSEPORT` 从 0 被修改为 1。复用了未修改固定上游危险函数，不是 mock syscall。生产源码没有为负对照被删除/回滚。
4. 最终正常版本四项 socket-boundary 测试均 GREEN，均在 `unshare -n` namespace，仅 loopback 测试 socket：
   - occupied-port 保持外国 socket REUSEPORT=0，原双向 TCP 流量正常，helper 非零退出；
   - pidfd_getfd 在 engine exec 后返回 EPERM；
   - startup race（成功 bind/release 预检，gate 等待父进程抢占）同样保持选项/流量；
   - seccomp 安装失败不执行任何 engine，清理 snapshot。
   上游日志 `[E] set_reuse_port ...:201` 与注入失败日志 `NATMap seccomp boundary: Invalid argument` 是预期的拒绝证据。

最后一次完整本地回归命令 exit=0：

```bash
wsl.exe -d Ubuntu-24.04 -u root -- unshare -n sh -c 'ip link set lo up; cd /mnt/d/DevPortal/homelede/feeds-xiaoqingfeng-homestun; python3 homestun/tests/test-socket-boundary.py -v && python3 homestun/tests/test-lifecycle.py -v && python3 homestun/tests/test-recipe.py -v && python3 homestun/tests/test-package.py -v && python3 homestun/tests/test-source-cleanup.py -v'
```

实际结果分别为：boundary 4 tests / OK（11.343s）；lifecycle 1 / OK（3.740s）；recipe 1 / OK（1.026s）；package 1 / OK（0.013s）；source-cleanup 15 / OK（45.613s）。recipe 使用 `gcc -Os -static -Wall -Wextra -Werror` 执行真实 Makefile 宏桩 compile/install，**不是 SDK/ipk**。source-cleanup 最终运行已包含其他 agent 的15项测试；不要把早期9项记录当作最终版。

## 执行中进程与清理

- 本子任务没有任何后台/PTY/持久化进程；所有 terminal 调用都是前台，最后回归已退出。
- socket tests 的 helper/engine 在 guardian 生命周期内结束，测试有 timeout，temporary directory 上下文回收 chroot/fixture/source/binary。
- namespace 由 `unshare -n` 前台命令拥有，命令退出后销毁；仅该 namespace 的 loopback 被启用。没有 host 网络/公网监听，也没有 mount/规则/远程修改。
- 不新增测试来核验关机状态；最后执行结果为所有测试完成并 exit=0。其他 agent 的任务/进程由父 agent 独立协调，不能声称替其清理。

## 未完成项（关机前停止，不继续实施）

1. README 新增链接 `../docs/homestun-socket-boundary.md` 尚未创建；续跑时建立正式证据说明，或把链接改为本暂停文档。这是已知文档欠项，未隐瞒。
2. 尚未保存完整 stdout 到单独正式 regression artifact；上述结果来自真实工具执行。可按下面命令复现并保存。
3. 父 agent 独立审查 final helper、pipe handshake/ABI filter 和 cleanup agent 合并后的实际源码；确认其他 agent 没有覆盖安全改动。
4. 可补充 no_new_privs 安装失败、filter 继承到 grandchildren 和 ABI-bypass 回归；当前拒绝非法 pidfd syscall、busy socket、startup race 和 filter-install failure 已通过。
5. 真实 OpenWrt SDK build、目标 libc/ABI/kernel CONFIG_SECCOMP/CONFIG_SECCOMP_FILTER acceptance 未验证；不能当成可发布/可启用包。未经另行批准不安装/不外网实验。Lua、Worker 和 router 全矩阵未在本安全子任务内重跑；父 agent 需统一最终版本验证（没有访问路由器）。

## 精确续跑命令

从 Windows 的 Git Bash（`C:/Users/xiaoq`）执行；不自动启用/部署：

```bash
git -C D:/DevPortal/homelede/feeds-xiaoqingfeng-homestun status --short
git -C D:/DevPortal/homelede/feeds-xiaoqingfeng-homestun branch --show-current
wsl.exe -d Ubuntu-24.04 -u root -- unshare -n sh -c 'ip link set lo up; cd /mnt/d/DevPortal/homelede/feeds-xiaoqingfeng-homestun; python3 homestun/tests/test-socket-boundary.py -v && python3 homestun/tests/test-lifecycle.py -v && python3 homestun/tests/test-recipe.py -v && python3 homestun/tests/test-package.py -v && python3 homestun/tests/test-source-cleanup.py -v'
```

复现负对照（**预期两项失败，证明抓到漏洞；只能在隔离 namespace**）：

```bash
wsl.exe -d Ubuntu-24.04 -u root -- unshare -n sh -c 'ip link set lo up; cd /mnt/d/DevPortal/homelede/feeds-xiaoqingfeng-homestun; HOMESTUN_SECURITY_NEGATIVE_CONTROL=1 python3 homestun/tests/test-socket-boundary.py Boundary.test_occupied_port_preserves_foreign_socket_and_traffic Boundary.test_startup_race_preserves_foreign_socket_and_traffic'
```

自定义 checkout 设置 `NATMAP_SOURCE=/absolute/path`，必须保持上面精确 revision 和递归 task-system headers；测试对 revision 不符直接失败。不要猜密码、不要配置 git 全局 safe.directory；测试只在单次 git 命令使用 `-c safe.directory=<checkout>`。
