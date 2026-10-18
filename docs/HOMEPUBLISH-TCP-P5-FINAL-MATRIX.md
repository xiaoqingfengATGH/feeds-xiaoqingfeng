# P5 final production matrix checkpoint

Scope: unchanged installed production provider with private native journal; preserve ordinary UI retained svc_1 and live state SHA256 `6995a844e18ac2c9182b3e4f8035138ebe561aee168530d43c550d5ee14be7d1`. Never restore historical revision1.

Discovery: actual target IPv4 LAN 192.168.1.2 and IPv6 ULA fd89:878e:a47f::1 available; ::1 available for backend-only local fixtures. Publication procd group absent before work. Existing final four-protocol evidence covers IPv4 ingress to IPv4 backend; earlier P3 family fixture is not final production-provider evidence. Ordinary real HTTP ubus/native UI HTTPS Save/Start/Apply/Stop already passed and is not repeated here.

S2 inventory blocker: read-only installed certificate inventory contains RSA and ECC certificates, each SAN exactly `home.iwonderful.top`. There is no second supported Web hostname or wildcard/multi-SAN certificate. Two distinct exact Web domains with verified certificate identities cannot be honestly demonstrated using this inventory. No new certificate issuance, ACME mutation, fabricated SAN or disabled hostname checks authorized. S2 remains explicitly blocked on authorization/provision of certificate(s) covering a second hostname. Existing single-host inherit/override and UI evidence do not close S2.

## Final bounded result

`python homepublish/tests/run-device-tcp-p5-matrix.py > docs/evidence/tcp-p5/final-matrix-final.log 2>&1` exited **0** on final exact harness. Parsed `final-matrix-results.json` has exactly **7** successful cases:

| Case | Actual ingress | Actual backend | Protocol traffic |
|---|---|---|---|
| v4→v4 | 192.168.1.2 | 127.0.0.1 | HTTPS, opaque TLS, native SSH auth, independent TCP |
| v6→v4 | fd89:878e:a47f::1 | 127.0.0.1 | all four |
| v4→v6 | 192.168.1.2 | fd89:878e:a47f::1 | all four |
| v6→v6 | fd89:878e:a47f::1 | fd89:878e:a47f::1 | all four |
| no HTTPS | IPv6 ULA | IPv6 ULA | TLS-only + independent TCP |
| no HTTPS | IPv6 ULA | IPv6 ULA | SSH-only + independent TCP |
| no HTTPS | IPv6 ULA | IPv6 ULA | TLS+SSH + independent TCP |

All cases used unchanged installed `/usr/share/homepublish/product-system-provider.lua`, actual procd engines, and the existing private native journal only. No replacement provider, address narrowing, authorization marker or custom HTTPS trust. HTTPS used system CA + hostname and exact Web marker; opaque TLS reversed a non-HTTP payload; SSH completed real fixture public-key auth and forced harmless marker; independent TCP echoed exact bytes. No-HTTPS configurations omit default_certificate_ref entirely. Every case required all-service ready, actual traffic, Stop cleanup confirmed, runtime absence and unchanged live journal SHA. Device-local clients target actual LAN/ULA sockets; these are not independent external/LAN client or public reachability results. IPv4 fixture backend is loopback; IPv6 fixture backend is the actual ULA, not ::1.

Earlier attempts retained: attempt1 correctly observed TLS payload but driver rejected intended timeout124 of an open opaque stream; attempt2 rejected ::1 at canonical Save (`unsafe IPv6`) and switched the fixture to existing permitted ULA without modifying production validation; attempt3 passed all traffic but duplicate final backend-delete Not found aborted credential teardown; next attempted repeat reused old keys and failed auth. Final corrected driver ran from confirmed absent fixture auth, generated fresh keys, passed all seven and cleaned them. `final-matrix-green.log` is a failed attempt despite its filename; only `final-matrix-final.log` exit0 is the final result. No production source fixes were needed.

Readback `final-matrix-readback.log`: publication and backend groups empty, `/tmp/homepublish-runtime` and matrix-auth absent; final log netstat has no matrix ports. Live ordinary UI journal remains exact SHA `6995a844e18ac2c9182b3e4f8035138ebe561aee168530d43c550d5ee14be7d1`; retained svc_1 saved/active revision3 data not overwritten. Private matrix config/backend config retained nonsecret and stopped. Business private keys never exported; generated fixture SSH keys removed. System authentication unchanged.

## Frozen candidate / remaining gates

`final-matrix-source-sha256.json` binds **30/30 installed Lua files** to current local bytes plus both new matrix drivers. Installed engine hashes remain nginx `941b54d84fc4fd40b0257e42195899f0bd77895ec0486e3e263344c2fa8dc08a`, sslh `1b9746f96d31624eb2cfa4076ca7eb0b636979321dbec92947171f780ee38db7`. This batch changes tests/docs only. IPK candidate should use these Lua files together with ordinary UI's 36-file source manifest, current init/Makefiles, engine package/provenance and dependency ledger; this is not an IPK build, package-byte freeze, or an unqualified release approval.

S2 remains blocked by single-host SAN inventory as above: a second hostname covered by authorized existing/new certificate(s) is required. No claim of dual-Web inheritance/override final acceptance. Ordinary UI lifecycle previously proves HTTPS only; four-protocol UI control success is not established by this private-journal matrix. External IPv6, final package build/content/install verification and remaining review release gates stay separate. No firewall/routes/DNS/auth/UPnP/public/IPK/install/commit/push/merge changes.
