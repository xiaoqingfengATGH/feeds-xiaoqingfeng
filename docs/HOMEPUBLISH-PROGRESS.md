# HomePublish 当前检查点

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

## 剩余门槛

D1尚缺真实rpcd scoped权限/角色及迁移工具；D2-D7 controller/独立有限续授权guardian、双栈直接Nginx/确定DNS backend、精确INPUT/UPnP受控续租恢复、真实四页LuCI/RPC、ACME/DNS维护/Passwall2、matching SDK/IPK/真BusyBox-procd-fw4及另授权实网均未完成。禁止以本切片或legacy PASS称产品可发布。下一步在独立review后继续runtime纵向TDD，不把旧120秒engine冒充continuous。
