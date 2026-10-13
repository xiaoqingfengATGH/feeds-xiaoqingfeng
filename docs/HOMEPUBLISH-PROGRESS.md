# HomePublish 当前检查点

## 范围与结论

worktree `D:/DevPortal/homelede/homepublish-product`，分支 `feature/homepublish-product`，接续基线 `2f508fcca89150f1425b8a8555e240e731260500`。
用户授权仅本地源码、隔离测试、local commit；无生产、安装、映射、防火墙、公网、push/merge/PR操作。
源码命名迁移已完成；**产品未完成**。本次完成 canonical → fixed stdin CLI → 原生私有journal纵向切片，未接入旧fixed-TTL engine，不改其语义。

## 已验证交付

- `canonical.lua`：strict typed schema、continuous默认/temporary边界、boot_restore默认false、服务与listener/地址scope/证书ref校验，返回detached plan。hostname仅保存语法与scope，实际DNS/归属/管理角色/TLS须未来Start核验。
- `product-wire.lua`：HP1非执行编码，大小/深度/节点限制、重复key/尾随数据拒绝；无loadstring/eval。
- `product-provider.lua` + `product-store.c`：固定编译路径 `/etc/homepublish/product`；0700目录、0600单链接文件、owner/type/O_NOFOLLOW核验，flock非阻塞事务，candidate→fsync→rename→目录fsync。revision由后端递增、compare-and-save，客户端不能写desired/approval/active。
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

## 剩余门槛

D1尚缺真实rpcd scoped权限/角色及迁移工具；D2-D7 controller/独立有限续授权guardian、双栈直接Nginx/确定DNS backend、精确INPUT/UPnP受控续租恢复、真实四页LuCI/RPC、ACME/DNS维护/Passwall2、matching SDK/IPK/真BusyBox-procd-fw4及另授权实网均未完成。禁止以本切片或legacy PASS称产品可发布。下一步在独立review后继续runtime纵向TDD，不把旧120秒engine冒充continuous。
