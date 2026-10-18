# Isolated listener acceptance

Run from any directory:

```
python D:/DevPortal/Openwrt/feeds-xiaoqingfeng/homepublish/tests/check-listener-isolated.py --enforce --evidence D:/DevPortal/Openwrt/feeds-xiaoqingfeng/homepublish/tests/evidence/listener-acceptance-recovery.json
```

## Scope and verified outcome

Latest evidence `evidence/listener-acceptance-recovery.json`: all six cases passed; all six cleanup checks passed; production `homepublish-runtime` procd snapshot unchanged. Device 192.168.1.2, SSH root/key specified in runner, direct connection/no proxy. No production configuration, firewall changes/reloads, production deployment, commits or explicit SIGKILL.

The runner copies current repository Lua modules to one random private `/tmp/homepublish-portcheck-*` directory. Each case uses a distinct private `homepublish-portcheck-*` procd service and high loopback ports. Actual installed `/usr/libexec/homepublish/nginx`, real procd, nixio/fs, kernel socket inode rows and nginx child processes are exercised. Foreign socket fixtures are Python socket listeners, not simulated `/proc` rows.

Cases:

1. Correct own socket is ready, including reconstructed-group manifest loading.
2. Own nginx listens on wrong port: real `L.verify()` and reconstructed `G.healthy()` reject intended endpoint as not listening.
3. Foreign process listens on intended port while own nginx listens elsewhere: rejects foreign inode.
4. Occupied shared port: `G.start()` rejects with address-in-use before launching.
5. Occupied dedicated port: same rejection with service label.
6. Same numeric port, wrong owned local address (127.0.0.2 vs intended 127.0.0.1), plus foreign correct address: rejects foreign inode rather than accepting numeric-port ownership.

Every case verifies private service absence, private LISTEN socket disappearance, and unchanged foreign socket inode. Cleanup allows a bounded five-second settling interval and ignores TIME_WAIT.

## Exact production APIs used

- `require('product-procd-group').new({name,root,nginx,sslh})`, `.start(plan,generation)`, `.healthy()`, `.stop()`.
- `require('product-listeners').family({nginx=procd_pid})` -> socket-inode owner sets and process identities.
- `.rows()` -> real TCP LISTEN rows; `.verify(expected,rows,owners)` -> bool/reason.
- `expected` entry: `{component='nginx',address='127.0.0.1',family='ipv4',port=N,label='...'}`.
- `.expected(plan)` is derived from actual rendered `configuration`/`sslh_configuration`, NOT `plan.listeners`. Metadata/render disagreement alone is therefore not a valid readiness-negative fixture.

For negative socket cases the rendered fixture intentionally differs from the intended endpoint. Initial `G.healthy()` is correctly true for the actual render. The runner then writes **only its own private** `listeners.json` with the intended endpoint and constructs a fresh group object to exercise the real manifest-loading `G.healthy()` path. `recovered_healthy=false` and the explicit missing/foreign diagnostic are required for acceptance. This is not a claim that production accepts metadata/render mismatch.

## Ownership edge-case review / remaining coverage

- Real nginx child ownership is covered by normal master/worker fixture startup and stop, but arbitrary deep grandchildren/reparenting and PID-reuse races are not independently forced.
- Shared case currently uses nginx's shared HTTP listener, not an actual sslh multiplexing listener. Both occupied checks execute the production rendered-listener preflight path.
- IPv6 wildcard/v6only, dual-stack cross-family collisions, compressed IPv6 addresses, IPv4-mapped IPv6 addresses and a bound-but-not-LISTEN socket need additional device fixtures; not covered by this six-case acceptance.
- Review concern: `L.preflight()` only probes the kernel in ambiguous cross-family LISTEN cases. A socket bound but not yet listening is absent from `/proc/net/tcp*` LISTEN inventory; startup readiness should still fail, but plan-only preflight may not detect it.
- Review concern: `L.same_address()` custom IPv6 word parser handles canonical hex forms, not embedded dotted IPv4. Ensure rendering never emits mapped dotted addresses or test/reject that representation explicitly.
- Manifest reload test only uses trusted private fixture data. Malformed manifest validation/fail-closed behavior remains a separate negative test.
- Earlier evidence files named `listener-baseline*` and `listener-acceptance.json` include exploratory failures (fixture access-log path and Lua concatenation mistakes, and mixed implementation snapshots). Do not use those as current acceptance. `listener-acceptance-final.json` passed direct inode checks; `listener-acceptance-recovery.json` additionally passed real group health integration.
