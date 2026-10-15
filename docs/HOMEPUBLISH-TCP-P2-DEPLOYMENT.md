# HomePublish TCP P1/P2 已安装部署记录

## 结果与边界
- 基线 `feature/homepublish-product` / `a74c65b`，部署当前工作树；未 commit/push，未修改产品源码。
- 已永久安装并逐文件 SHA256 回读 **39 个文件**：24 Lua、6 LuCI 静态资源、1 SDK native、其余 init/RPC/ACL/menu 及应用自带 worker 资源。不是临时四 JS 替换，成功后不恢复旧版本。worker 文件仅复制未执行/部署外部服务。
- 安装前本机 18997 connect_ex=10061，无 probe；父代理确认另一 browser child 未启动 probe/写入/finally。
- 未保存、迁移或启动 live 配置。保存版本 0、intent_revision 7、desired disabled、manual_stop_latch=true、phase stopped、cleanup confirmed 均保持。
- `/etc/homepublish/device-test/enabled` 与 `/var/run/homepublish/control.sock` 均不存在，无常驻 HomePublish controller，无运行数据面；因此无需重载旧 Lua controller。只重启 rpcd 完成新方法注册；uhttpd/SSH 不重启。
- `/etc/config/homepublish`、network、firewall 与整个 `/etc/homepublish` 私有 journal 文件 hash 回读未变。未改凭据、路由、全局配置、证书源文件、管理服务、防火墙或映射。

## 可直接查看
- 现有映射 Web： http://127.0.0.1:1081/cgi-bin/luci/admin/services/homepublish/entry
- 概览： http://127.0.0.1:1081/cgi-bin/luci/admin/services/homepublish/overview
- 使用现有认证登录，不是新建代理/隧道。实际浏览器通过已保存 vault login 登录后在正式菜单路径读取 DOM。
- 初始无配置：entry 原生 NamedSection 表单可见，保存/重置各一组；无需先 Save/migrate 才能显示。services 提示先在入口页保存监听，未伪造已保存状态。
- overview 正确显示版本 0 / 已停止；certificates 实际显示 RSA/ECC 两行和六列；四路由均未显示 load-error。这里只验只读渲染，不替代父代理完整扩展交互矩阵。

## Native 来源
- 从当前 `homepublish/src/product-store.c` 用已缓存 matching x86_64 OpenWrt SDK GCC 13.3.0 musl 新编译，不使用任何 fixture `.so`。
- C SHA256：`441ab3b8bcf5a8eca705f64b6a75926e1686e559ae01da322ebd0415b7d8ef5d`。
- native SHA256：`529e359ae4cecb04a59cea18eabb4ccea0f261a330543f61332985430a558418`。
- 编译无 `-DPRODUCT_ROOT` override；strings 仅确认生产根 `/etc/homepublish/product`，无 `/tmp/homepublish` fixture 根。目标真实 Lua require 返回 `migration_backup=true`。
```sh
sdk=/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64
export STAGING_DIR="$sdk/staging_dir"
flock -w 10 /home/eric/homestun-sdk-check/build.lock "$sdk/staging_dir/toolchain-x86_64_gcc-13.3.0_musl/bin/x86_64-openwrt-linux-musl-gcc" -std=c99 -Wall -Wextra -Werror -fPIC -shared -I"$sdk/staging_dir/target-x86_64_musl/usr/include" /mnt/d/DevPortal/homelede/homepublish-product/homepublish/src/product-store.c -L"$sdk/staging_dir/target-x86_64_musl/usr/lib" -llua -o "$out/homepublish_store.so"
```

## 备份与传输
- 私有 root-only 备份目录：`/root/homepublish-backups/20261015-165134`，目录 0700，所有备份文件 0600。
- `installed-and-private.tar.gz` 包含部署前存在的全部目标文件，以及整个 `/etc/homepublish` 和 `/etc/config/homepublish`，不输出秘密内容。
- archive SHA256：`c5486723e844697aa0f62fb6b5f11e960cb773167a889ddb472500fd1fd0f603`。
- `existing-paths`、`before.sha256`、`private.sha256`、`config.sha256`、`status-before.json` 与部署 `deployment-manifest.json` 都保存在该目录。manifest 已读回 hash 确认。
- 固定命令：`ssh -o ProxyCommand=none -o ProxyJump=none -o IdentitiesOnly=yes -o BatchMode=yes -i D:/DevPortal/CloudHosts/HomePri.key -p 222 root@127.0.0.1`；直接 `scp -O` 上传实际路径，无 IPK 重打包。
- 具体可复核脚本/manifest/readback：`docs/evidence/tcp-p2-deployment/`。脚本不可无意重复执行：deploy.py 会重新部署当前树并再次重启 rpcd。

## 真实注册、只读 RPC 与 ACL
- `/etc/init.d/rpcd restart` 后 `ubus -v list homepublish` 实际注册 migration_preview、network_inventory、preflight 和原有 status/validate/save/start/apply/stop/certificates。
- `network_inventory {}` 返回真实 lan/br-lan/up/lan zone，IPv4 192.168.1.2/24 与 IPv6 fd89:878e:a47f::1/60。
- `migration_preview {expected_revision:99}` 与 `preflight {revision:99}` 均返回结构化 REVISION_CONFLICT/retryable=true。
- revision 0 的 migration_preview 返回 INVALID_CONFIG（无 saved v1），preflight 返回 INVALID_CONFIG（无 saved config），符合初始状态且 journal hash 不变。
- 浏览器以 vault 提供的真实 root 登录会话调用 `session.access`：status/network_inventory/preflight/migration_preview/save/start/apply/stop 全为 true；没有手工 grant。未执行写方法。
- **ACL 限权验收仍有缺口**：当前唯一合法登录 root 的 rpcd read/write 是 `*`；其访问成功不能证明 application ACL 的只读/写分离。已安装 ACL read 列表含六只读方法、write 含 save/stop/start/apply，字节已比对，但无合法受限只读/写账号，未改认证配置创建测试账户。

## 恢复步骤（仅需要回退时，默认保持新版本）
1. SSH 上先 `cd /; sha256sum /root/homepublish-backups/20261015-165134/installed-and-private.tar.gz; tar -tzf /root/homepublish-backups/20261015-165134/installed-and-private.tar.gz >/dev/null`，确认 archive hash。
2. 确认没有新 Save/启动且仍 disabled/stopped；如果用户之后已使用新配置，先另备份当下 journal，不能盲目恢复旧私有状态。
3. 只恢复原已存在的代码文件：按 `existing-paths` 中 `/usr/`、`/www/`、`/etc/init.d/` 目标从 tar 提取到 `/`；manifest 中原不存在的新代码目标先逐个核对再删除。不要直接整包解压覆盖用户后续配置。
4. journal/config 仅在另行确认需要回退状态时，从 archive 精确恢复对应 `/etc/homepublish` 或 `/etc/config/homepublish`；保留目录 0700、私有文件 0600。不触碰 network/firewall。
5. 回读 `before.sha256` 对应原文件；仅 `/etc/init.d/rpcd restart`，再次核对注册、status、Web 静态字节和 SSH/Web 管理可用。若存在运行 controller，应先取得停止/重启授权，而非恢复脚本擅自启动。

## P2 扩展回归后续补丁（当前部署）
- 双栈 ui.Select 更新 API 已修复；services/certificates 原生表格增加可横向滚动容器，修复 375px 整页横溢。三 JS 直接永久上传，不恢复旧 static-backup。
- `HP_CASE=extended node luci-app-homepublish/tests/tcp-ingress-device-probe.cjs` 最终 exit0，16 条 PASS，完整 `docs/HOMEPUBLISH-TCP-P2-EXTENDED-GREEN.log`；原始 RED/中间失败另保留。
- `python docs/evidence/tcp-p2-deployment/verify-extended.py` exit0：39 文件匹配当前源码，6 静态 JS 的 HTTP served bytes 匹配；private/config SHA 与上述 backup 一致，live rev0/intent7/disabled/latch=true/stopped 不变。当前逐文件 SHA 以 `docs/evidence/tcp-p2-deployment/extended-final-readback.json` 为准，下方表格仍是首次部署历史 SHA，不覆盖初次备份 manifest。
- 当前补丁 SHA256：entry `163876d5d8e9a9c0d5eee7367a10300025c40c211d0d72fc8d2705e1081227ef`；services `0e6e674ef205ff3d2d558569fa568a8d408ec9fc0d7fd5a0dd6e742089241a66`；certificates `9d9d9ae2dc9da0719330a583dc15a06e6524cf7d05e7bc4e34e48163cf6923be`。

## 未完成事项
- 扩展浏览器矩阵已通过，保留上述私有 native journal 隔离方式；未在 live 配置执行 Save/迁移。动态系统地址消失未注入（已验证选择真实 down/addressless 网络的拒绝/保留/reset）。
- P3 protocol-aware production provider 未实现/未验收；v2 runtime 不支持不能称生产发布成功。本次只交付可查看的当前 P1/P2 控制面/UI，未批准或执行对外发布。
- 不宣称公网 IPv4/IPv6 可达，不宣称当前 root 会话证明受限 ACL 分离。

## 逐文件部署 SHA256
| installed target | SHA256 |
|---|---|
| `/usr/share/homepublish/canonical-v2.lua` | `0c677d4a05875929639ec519c268170742afcfd9e6efc52a19349969e9528ed7` |
| `/usr/share/homepublish/canonical.lua` | `9801b5c822ddc40e31bea2aea5a460baf5038f5efefeac6e262cb7db025262f8` |
| `/usr/share/homepublish/certificate-metadata.lua` | `b751d71892f91ef5366a6a2007a3fa2d3ff6ee4713e07d8a246a56fdf343499a` |
| `/usr/share/homepublish/config-cli.lua` | `94e1261ce0ef8a12474864d775bbf0f6b5ca4f7ac1c0f649e9bcb306aec07069` |
| `/usr/share/homepublish/config.lua` | `9f69c6dd2b2c16cb8a31c896010fc8f48188b3ea0f3c1b4c846f57b5ef5e8152` |
| `/usr/share/homepublish/core.lua` | `fb5863d9c0da02c034bb2a0634d4e4649ceb7f89b45b23e939d7c3054a9602c8` |
| `/usr/share/homepublish/device-integrations.lua` | `06da2f95e5cd7fba61331c2b5f45b4758dd0559256147e5a5cac9a2ca15eeb6e` |
| `/usr/share/homepublish/direct-address.lua` | `6b56bb6971d9c87da9f93c9c510ceaaf6958f41fed016427e1cf2997385b4d34` |
| `/usr/share/homepublish/direct-backend.lua` | `f00fbd26b7795abb7c6702f826ee4b6898db0435ed5496ed16b247f4ea5fd539` |
| `/usr/share/homepublish/direct-renderer.lua` | `186a54cd82142966d1a14e766fbd5d57ff146fbf9fbaa02d8ae05d60c09e3ef7` |
| `/usr/share/homepublish/lease-run.sh` | `54b95697c8a7bab6c03515fb9cdf941925e6a66e0bf254d655c6c37f4d209d69` |
| `/usr/share/homepublish/network-inventory.lua` | `2606bb1e742e440c8a2d88a91823798bb6d05b158ec23c289b65d7ddae78c8b8` |
| `/usr/share/homepublish/nginx.conf` | `b7ac6b426a847a30befa59a295c14113d7ea83eefe4483eafa739f306bd2a843` |
| `/usr/share/homepublish/preflight.lua` | `dd0e4b03ce8481e7b7a262b9b71ff098d0f6ed3c99afc40d37da561b9d3d28e5` |
| `/usr/share/homepublish/product-channel.lua` | `e90a511ce26d95332495fbd2cccb0663534a86e7f74d4f8a8c42f57e18c99e63` |
| `/usr/share/homepublish/product-cli.lua` | `5c25f5d639735efcc760cc9675d91b08aba2fa8c23ea5c590ed755ccbd2efbda` |
| `/usr/share/homepublish/product-controller.lua` | `e00706c2f5dc617b659cbf7a93968bc8109dcf0b6bbbd37060cf4bb4cfea2b09` |
| `/usr/share/homepublish/product-daemon.lua` | `146778856bc33c0da1536bcf5509f41580107114f905c9a3c3238021ae7cc71c` |
| `/usr/share/homepublish/product-device-cli.lua` | `af24209f6c75cd1739e41e668a4ab356c8797f94d5019158f75f9191bac031dc` |
| `/usr/share/homepublish/product-device-provider.lua` | `37e134da07f47a3763253c982003c613b48df9ae593191fc0496cd180431596a` |
| `/usr/share/homepublish/product-json.lua` | `679f95e8f30fdc37ec406944b608bbbf9d60336dfabe3db194ffbbc3955b4632` |
| `/usr/share/homepublish/product-lifecycle.lua` | `9770a8e2c747d76185ae7f865138d7449946b8b20122311ea0138b9f5f046faa` |
| `/usr/share/homepublish/product-provider.lua` | `5e12a7fcc5e69a20c02b0fa66c6591e44237da3b04d569aaa133308b59740dee` |
| `/usr/share/homepublish/product-rpc.lua` | `44adc4619f8c516e0b2d4f702bcb6d9a933694a439d785e592cf924a1110b035` |
| `/usr/share/homepublish/product-system-provider.lua` | `5edb145efc242d74a39052974ba07fc477533e5831b0425382a6fb1819ecbd37` |
| `/usr/share/homepublish/product-wire.lua` | `7bf869bfc3f4771b553fc44a8d72801466c25bdb1a434b823a054726c42aca5b` |
| `/usr/share/homepublish/worker/worker.mjs` | `ad6b2751fe1153ae8b6196d129366b87877f6ea21f26ee76359b6d9a469122c5` |
| `/etc/init.d/homepublish` | `98d8f8bcba5f61a19fdef703da8895f29c185a8d86efb5a37613cb0688ae91fb` |
| `/etc/init.d/homepublish-nginx` | `ff1859e128900b909342259ef8a34dbcdb07c28ec20fbcdc3fece75aeab4f7f6` |
| `/www/luci-static/resources/view/homepublish/certificates.js` | `e2008be801d04207dde1fd9224229adb412c72a4fc9c70c402f56553d79e32d6` |
| `/www/luci-static/resources/view/homepublish/entry.js` | `7999d24360f21e7d772df85af72ad1fe2a6b7c0c9f54b3794441afe629912efd` |
| `/www/luci-static/resources/view/homepublish/overview.js` | `9d750830af8f528310481509bbc6a01f13d5c75219f34f7fb0f015a0a754dd47` |
| `/www/luci-static/resources/view/homepublish/product.js` | `e68785444fccc98caed21c6ac0be5de4969a1c0b2bcd63cd18f6cd40f1b2079f` |
| `/www/luci-static/resources/view/homepublish/schema.js` | `07b65e7330fb753500fb23746daadb9c68ec81894b0bb162f3d8c336596dd2f0` |
| `/www/luci-static/resources/view/homepublish/services.js` | `494a827148963e8165353c55c475c9747fcf1b0cd85a0e0e80170e7e11d6c3ee` |
| `/usr/libexec/rpcd/homepublish` | `00920ffa6e4a8b5ca0080afb8770f49d86fc8c989ef601917d8c3c3a57459221` |
| `/usr/share/luci/menu.d/luci-app-homepublish.json` | `005ee119d4052411c75991ec12b5c41c77f6d4867644bfa2f8504c15c8f246de` |
| `/usr/share/rpcd/acl.d/luci-app-homepublish.json` | `e31468f783d063ae7d0314c00369c413bad226f86fddc162ff6e26f44b59cd05` |
| `/usr/lib/lua/homepublish_store.so` | `529e359ae4cecb04a59cea18eabb4ccea0f261a330543f61332985430a558418` |
