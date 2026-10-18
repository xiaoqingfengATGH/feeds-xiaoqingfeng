# /hold fixture: local RED → GREEN

## Outcome and scope

WSL loopback through the existing SDK nginx **1.26.1** passed raw HTTP and hostname/certificate-verified TLS. Each received nine numbered application ticks over 16 seconds, with approximately two-second spacing and immediate HTTP headers. No router commands, UPnP requests, WAN listeners, installs, firewall, DNS, production changes or commits were performed. This does **not** upgrade `homestun-upnp-lease-final.json`'s public hard-cutoff result: that remains NOT PROVEN.

## Root cause and source evidence

Read the scratch `homestun-upnp-lease-final-run.py` and original `homestun-upnp-lease-test.py`:

- Both lines 56–60 generate the actual nginx configuration. Line 58 defines `/hold` as `limit_rate 1; return 200 '<marker repeated 12 times>';`. This is a static body, not an application streaming backend. There is no `nc` backend in these runs.
- Lines 57/60 already set 240-second proxy/send timeouts and `proxy_buffering off`. Repeating those settings alone does not repair a source that rate-limits even delivery of its HTTP response headers.
- Lines 81–84 launch the chroot native lease controller; nginx itself serves the source on loopback 18081 and proxies TLS on loopback 18443.
- The scratch `homestun-upnp-forwarder.c` lines 13–14 mark sockets and relay opaque TCP bytes using poll/read/write. It does not produce HTTP, tick framing or buffering. It was read but not run or modified.

The local legacy replay received **zero bytes / no headers**, then hit its explicit three-second socket timeout. Removing **only** `limit_rate 1` from the same legacy configuration immediately yielded HTTP 200 headers and its entire static body (312 bytes) in 0.0035 seconds, but zero application ticks. Thus the local zero-byte symptom is attributable to the one-byte-per-second source response throttling, not absent proxy-buffering directives. The complete upstream headers cannot reach the downstream proxy promptly. This is experimentally reproduced on SDK nginx 1.26.1, not a retrospective target trace of the earlier router nginx 1.21.3.

## Corrected reusable files

- `homestun-upnp-stream-fixture.py`: real Python HTTP/1.1 source, loopback only; explicit chunked headers, `X-Accel-Buffering: no`, `Cache-Control: no-store`, flush after headers and every numbered tick, monotonic source timestamps, two-second cadence, three-second write timeout. Continues until its owner stops it, not a short finite response. Standalone TTL must be 1..120 seconds; default 60. No mapping capability.
- `homestun-upnp-stream-regression.py`: isolated SDK nginx config reproduces source → reverse proxy and default-rejecting TLS vhost. No `limit_rate`; explicit `proxy_buffering off`, HTTP/1.1 upstream and 240-second idle timeouts. Raw socket/TLS consumer records complete application tick lines rather than counting recv calls. Tests sequence, cadence, monotonicity, ≥10-second tick span, immediate HTTP headers, and sustained 16-second observation. Finally stops its nginx process group and backend, joins server threads, checks every test port closed and deletes the temporary certificate/key/config directory.

Evidence:

- `homestun-upnp-stream-red.json`: legacy zero-byte failure; cleanup PASS.
- `homestun-upnp-stream-no-rate.json`: single-variable control; immediate static response, expected no-tick failure; cleanup PASS.
- `homestun-upnp-stream-duration-red.json`: initial seven-tick/12-second source correctly rejected as ending before the observation window. Fixed to keep streaming until stopped.
- `homestun-upnp-stream-green.json`: final code PASS; raw HTTP headers at 0.0054s, TLS headers at 0.0132s; nine ticks per path, each across 16 seconds; 419 received bytes per path; all owned ports closed, nginx exited, fixture directory removed. Keys and certificates were temporary scratch artifacts, never saved in the repository.

## Re-run locally (WSL; existing SDK, no installation)

```sh
SDK=/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64
DOCS=/mnt/d/DevPortal/homelede/feeds-xiaoqingfeng-homestun/docs
python3 "$DOCS/homestun-upnp-stream-regression.py" \
  --sdk-root "$SDK/staging_dir/target-x86_64_musl/root-x86" \
  --loader "$SDK/staging_dir/toolchain-x86_64_gcc-13.3.0_musl/lib/ld-musl-x86_64.so.1" \
  --scratch /mnt/c/Users/xiaoq/AppData/Local/hermes/profiles/ta/cache/scratch \
  --output "$DOCS/homestun-upnp-stream-green.json"
```

Add `--legacy` and a different output path to observe the original RED. Source standalone: `python3 homestun-upnp-stream-fixture.py --port 18081 --ttl 120` (binds only 127.0.0.1).

## Handoff gate for a separately authorized external reuse

No external retest was run. Parent must adapt its source delivery to the actual target environment; WSL Python is not assumed installed on the router. Reuse the backend and the nginx location from the regression, not the old static `/hold`. Reuse `probe(address, port, cafile=..., seconds=...)` and the tick assertions for preflight; none creates mappings. Keep source owner TTL later than native cutoff, e.g. source 120s and native 60s with enough setup margin; equal independently-started deadlines would reintroduce attribution ambiguity. The native deadline still must not exceed 120s.

Before a public mapping, require local verified-TLS headers and ≥5 numbered ticks across ≥10s. For the public cutoff, record numbered application ticks up to the native deadline, exact EOF/error time, last-tick-to-EOF gap, supervisor exit and new-connection refusal while the accepted gateway lease still exists. An EOF after a source TTL or an idle timeout is not native-cutoff proof. Stop on preflight failure; do not retry Add or implicitly expose another port. Preserve existing 22/80/443 managers. The parent's existing authorization boundary remains unchanged.
