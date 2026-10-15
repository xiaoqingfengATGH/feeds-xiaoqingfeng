# REQ-007 P1 progress

P0 committed: ef24a28 (feature/homepublish-product), no push/merge.

## Boundaries
- Only P1 canonical v2, explicit migration, semantic conflict validation, read-only inventory/RPC, revision persistence.
- No P2 controls, no P3 listener activation, no firewall/routing/system package mutations.
- v1 preserved; v2 runtime must explicitly refuse until P3.
- Device only RED→GREEN; private /tmp fixtures, no local target execution.

## In flight
- canonical-v2.lua + minimal canonical dispatcher + device-tcp-p1-model.lua: delegated isolated file ownership; migration preview pure, all conflicts include disabled items per contract.
- network-inventory.lua + device-tcp-p1-network.lua: delegated isolated file ownership; fixed ubus/UCI reads, exact binding resolution, ambiguity preserved.

## Parent review of network slice
- Read actual module/tests/evidence; fixed ubus/UCI adapter is read-only, no shell or client-controlled path.
- Worker reports device RED→GREEN and fixture absence; parent rerun still required before integrated acceptance.
- Integration risk found: inventory preserves IPv6 spelling and resolve uses string equality, while canonical normalization may change spelling. Parent must add equivalent-IPv6 integration regression and normalize address identity on both sides; exact binding means same address, not same text spelling.
- This module-only result does not prove RPC/ACL/preflight/save integration.

## Backup slice parent inspection
- Read product-store.c, actual device test and final/fault/cleanup evidence. Third callback bool preserves response-only API; exact locked old journal bytes back fixed migration-v1 before state rename; capability migration_backup=true.
- Metadata checks include O_NOFOLLOW, regular file, uid, 0600 including special bits, single link, same bytes for reuse; partial backup failure cleanup uses dev/inode ownership, existing backup never overwritten.
- Worker device evidence includes partial/zero write, fsync/close/dirsync fault cases, metadata/symlink/FIFO/hardlink/absent-source rejection. Parent integrated execution still pending provider build.
- Provider worker notified capability is available and must exercise real v1→v2 backup + stale revision + active v1 preservation before claiming acceptance.
- Crash-created partial backup intentionally blocks retry; documented fail-closed limitation, no automatic overwrite.

## Parent integrated device acceptance (pending independent review)
- Reuploaded latest combined Lua sources to existing private provider fixture; parent personally executed provider, 16-group v2 model, and network suites: exit0, evidence tcp-p1-parent-integration.txt.
- Added explicit malformed save expected_revision transport tests (string, negative, fractional, absent); latest provider transport rerun passed. Existing v1 canonical and certificate-model suites rerun on device passed; tcp-p1-parent-final.txt.
- Exact original-journal backup, active v1 preservation, unsafe-backup state preservation and equal-backup retry were exercised through actual provider + latest compiled C module, not just isolated storage test.
- Fixture removed after successful parent run; PARENT_FIXTURE_ABSENT exit0. No installed code/services/config mutations. Source ACL exists but installed rpcd authorization was NOT exercised.
- Full certificate/backend/port execution preflight deliberately unavailable and reports ready=false dependency blocker; reserved P3, no v2 Start capability advertised.
- Independent read-only review dispatched; P1 not declared complete until findings resolved. No P1 commit/push/merge.

## Independent review and repair
- Review found three credible public-boundary defects: durability-unknown mapped INVALID_CONFIG, structured inventory error table crashing CLI, empty RPC arrays encoded as objects. All must be fixed before P1 acceptance.
- Parent device RED→GREEN fixed JSON response schema for services/endpoints/warnings/networks/addresses/zones and other declared arrays, preserving runtime.services as an object. Numeric arrays now count keys/check dense indexes, reject sparse/mixed rather than truncate with ipairs. Actual JSON parsed with Python json.loads (not Lua length assertions): tcp-p1-json-red.txt / tcp-p1-json-green.txt; JSON_FIXTURE_ABSENT readback exit0.
- CLI fixes returned; parent inspected actual product-cli.lua and persistent runnable fault harness, independently recreated private fixture and ran full actual JSON→RPC→CLI→RPC faults: exit0, tcp-p1-errors-parent.txt. ubus/firewall/malformed failures retain NETWORK_UNAVAILABLE with zero stderr; actual post-rename dir-fsync EIO returns STATE_UNKNOWN with status revision 0→1; unsafe migration backup preserves v1. Exact store vocabulary replaces substring heuristic. Fixture removed/readback verified; network/firewall/homepublish hashes unchanged. Three independent-review defects now repaired and device verified.
- Installed rpcd ACL session enforcement still unverified; no claim of runtime authorization acceptance.

## P1 closure and P2 authorization
用户已要求“提交代码，进入P2”。P1配置/control源码与私有实机链路验收通过，独立审查三项缺陷已修复并由父代理复跑。依据 tcp-p1-parent-integration.txt、tcp-p1-parent-final.txt、tcp-p1-json-green.txt、tcp-p1-errors-parent.txt。历史 in-flight/next 为过程记录，不再是待办。实际安装 rpcd 会话 ACL 尚未验证，移交 P2 安装浏览器链路验收；P3 数据面仍明确拒绝启动，非产品整体完成。仅本地提交，不 push/merge；进入 P2 原生四类型表单、真实地址选择与共享保存/重置/迁移确认。无公网/防火墙/路由/认证变更授权。

## Parent integration next (historical, completed except installed ACL)
1. Verify both delegated implementations and read actual real-device evidence.
2. Add scoped network_inventory RPC/ACL; preflight revision returns blockers, no activation.
3. Test current scoped C store using PRODUCT_ROOT fixed private fixture; compile only using SDK, execute device only.
4. Save v1→v2 must retain original in application-owned private backup, fail closed on backup failure; preserve state_version format and active v1 snapshot.
5. Exercise stale revisions, readback, Save-not-Start, schema capability truthfulness, migration preservation and malformed transport.
6. Independent review, repair findings, device regressions, cleanup readback; record exact P1 completion/gaps. No commit/push/merge implied for new P1 work.

Current legacy store converts callback assertion errors into generic 'invalid stored state or request'; structured revision errors should be returned as read-only callback responses without breaking legacy nil/string API expectations. Model validation and transport need stable public error mapping, no stack/path leakage.
