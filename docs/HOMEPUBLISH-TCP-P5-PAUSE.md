# P5 pause checkpoint — immediate shutdown request

## Saved before bounded readback

- Repo: D:/DevPortal/homelede/homepublish-product; branch feature/homepublish-product; HEAD 7ac1fe88f4817a24bc9abe69364c4324040d2d41. Existing dirty P4/P5 work preserved. This continuation changed only docs/HOMEPUBLISH-TCP-P5-INTEGRATION.md (discovery note); no runtime/test implementation edits, no deployment/build/test started.
- Current step: read-only discovery of engine files/ELF dependencies and installed provider. Four-protocol implementation has NOT started; installed production provider still rejects non-HTTPS with `production stream/multiplex capability unavailable`.
- Target last read: OpenWrt 24.10.5 x86/64, Linux 6.18.55. `/usr/libexec/homepublish` absent; no P5 private engines deployed. Last publication `ubus call service list` returned empty object. Live journal read revision1/intent7 disabled/manual-stop latch/stopped/cleanup confirmed. Fresh pause readback pending below; do not infer shutdown-time state from this earlier read.
- Built but NOT deployed: WSL `/home/eric/homestun-sdk-check/tcp-ingress-p5/build/out/nginx`, nginx 1.30.6 supplied owner SHA256 941b54d84fc4fd40b0257e42195899f0bd77895ec0486e3e263344c2fa8dc08a; sslh-select 2.3.1 supplied owner SHA256 1b9746f96d31624eb2cfa4076ca7eb0b636979321dbec92947171f780ee38db7. Existence and x86-64 musl ELF independently read; fresh artifact hash/version not independently rerun this continuation. Target private deployed version/SHA: not installed at last read.
- Prior completed evidence, NOT rerun this continuation: docs/evidence/tcp-p5/production-and-rpcd-final.log, production-final-source-sha256.json. Prior HTTPS-only production private-journal Start/Save/Apply/Stop and real HTTP rpcd scoped authorization GREEN. No new RED/GREEN lifecycle evidence generated.
- No self-owned background process launched by this continuation. No temporary key/certificate snapshot created. Existing nonsecret test data/config preserved. Residual processes/cleanup at pause: unknown until bounded readback; never delete unknown resources.
- Business certificate source examined server-side only: RSA reference acme:home_rsa SAN home.iwonderful.top only. No private key export.

## Resume (only after user reauthorizes continuation)

First command: `git -C D:/DevPortal/homelede/homepublish-product status --short` then read this file and docs/HOMEPUBLISH-TCP-P5-INTEGRATION.md. Recheck target before any write:

`ssh -o ProxyCommand=none -o ProxyJump=none -o IdentitiesOnly=yes -o BatchMode=yes -i D:/DevPortal/CloudHosts/HomePri.key -p 222 root@127.0.0.1 'ubus call service list; sha256sum /etc/homepublish/product/state; ls -ld /usr/libexec/homepublish /tmp/homepublish-runtime 2>/dev/null'`

No automatic Start. Next authorized implementation step: backup current live/private journals and exact installed destinations; verify real artifact hashes/ELF/target libs; deploy only fixed private engine paths with scp -O; target -V/config capability readback; add four-protocol production RED test before runtime implementation. Allocate internal ports server-owned, retain legacy P3/P4 regression, use unchanged installed production provider/private native journal first. No fixture marker/fixed495xx/profile masquerading. No firewall/routes/auth/global DNS/UPnP/IPK/install/commit/push/merge. TLS passthrough readiness currently assumes HTTP+hostname CA and needs a bounded transport-correct design/test; do not silently weaken HTTPS verification.

## Bounded pause readback

Completed read-only readback at target `2026-10-16T00:30:56+08:00`, SSH exit0 bounded15s; exact output retained in `docs/evidence/tcp-p5/pause-readback.log`.

- Live journal SHA256 `64fdd7f00450e683e460215f2fda4054f27152d1d1d2bbe24ed1945e06178dba` still exact prior baseline; revision1/intent7 disabled/manual latch/stopped/cleanup confirmed. No Stop mutation needed or issued.
- `homepublish-runtime`, `homepublish-p5-backend`, `homepublish-p3-controller`, `homepublish-p3-backend`, `homepublish-p3-clients`: each exact procd lookup returned empty object.
- Standard idle `homepublish` controller remains running PID13500 by prior requested design; it is NOT publication and was not killed.
- Full netstat/ps readback has no P5/P3 publication Nginx/sslh/backend/held-client processes or 50881–50884/495xx test listeners. Existing management/Passwall2 services were not touched.
- Listed paths `/usr/libexec/homepublish`, `/tmp/homepublish-runtime`, `/tmp/homepublish-tcp-p3/controller-runtime`, `/root/homepublish-p3-controller-auth` produced no entries (absent); no runtime certificate snapshots or temporary P3 auth directory observed. No secret created by this continuation, so no destructive cleanup performed. Other historical private fixture locations not comprehensively scanned: unknown; do not claim global secret cleanup.
- No self-owned bounded operations remain; no background job was started. No deployment/test/build resumed. Test state and nonsecret backend files retained.
- This continuation's final artifacts: this pause file, discovery addition to `docs/HOMEPUBLISH-TCP-P5-INTEGRATION.md`, and pause-readback.log only. Four-protocol production acceptance remains incomplete; no new runtime GREEN claimed.
