#!/bin/sh
# Cross-build only, no target execution. Private P0 fixture, not a release package.
set -eu
SDK=/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64
WORK=/home/eric/homestun-sdk-check/tcp-ingress-p0
TC="$SDK/staging_dir/toolchain-x86_64_gcc-13.3.0_musl"
TARGET="$SDK/staging_dir/target-x86_64_musl"
export STAGING_DIR="$SDK/staging_dir" PATH="$TC/bin:$PATH"
CC="$TC/bin/x86_64-openwrt-linux-musl-gcc"
AR="$TC/bin/x86_64-openwrt-linux-musl-ar"
exec 9>/home/eric/homestun-sdk-check/build.lock
flock -n 9 || exit 73
cd "$WORK"
fetch() {
 [ -f "$2" ] || curl -fL --connect-timeout 15 --max-time 120 "$1" -o "$2"
 printf '%s  %s\n' "$3" "$2" | sha256sum -c -
}
fetch https://codeload.github.com/yrutschle/sslh/tar.gz/d39388d1edcc9fe7a35449fc5c23d222d20d6f81 sslh-d39388d1.tar.gz 4822815217ba8c19d8a7469d19e686a5a3f6a0388e772636996f9cae1cdbc056
fetch https://codeload.github.com/kosmas-valianos/libproxyprotocol/tar.gz/3e133b9602e59f47ceceef74fbd52a3b147e5874 libproxyprotocol-3e133b96.tar.gz ecfaa002f2f36a87c7e52f515a6caaec492fb69ed5f0f74295934ed3b8475882
[ -d sslh-d39388d1edcc9fe7a35449fc5c23d222d20d6f81 ] || tar xf sslh-d39388d1.tar.gz
[ -d libproxyprotocol-3e133b9602e59f47ceceef74fbd52a3b147e5874 ] || tar xf libproxyprotocol-3e133b96.tar.gz
mkdir -p "$WORK/out-identity/lib" "$WORK/out-identity/include"
PP="$WORK/libproxyprotocol-3e133b9602e59f47ceceef74fbd52a3b147e5874"
# Match library's fshort-enums ABI also in consumer. Retain LGPL source/object for relinking.
"$CC" -O2 -fshort-enums -c "$PP/src/proxy_protocol.c" -o "$WORK/out-identity/proxy_protocol.o"
"$AR" rcs "$WORK/out-identity/lib/libproxyprotocol.a" "$WORK/out-identity/proxy_protocol.o"
cp "$PP/src/proxy_protocol.h" "$WORK/out-identity/include/"
cd "$WORK/sslh-d39388d1edcc9fe7a35449fc5c23d222d20d6f81"
[ ! -f Makefile ] || make clean
export CPPFLAGS="-I$WORK/out-identity/include -I$WORK/libconfig/include -I$TARGET/usr/include"
export LDFLAGS="-static -L$WORK/out-identity/lib -L$WORK/libconfig/lib -L$TARGET/usr/lib"
CC="$CC" ./configure --host=x86_64-openwrt-linux-musl
make -j2 sslh-select CC="$CC" AR="$AR" USELIBEV= CPPFLAGS="$CPPFLAGS -DLIBCONFIG -DENABLE_REGEX" CFLAGS="-Wall -O2 -fshort-enums"
cp sslh-select "$WORK/out-identity/sslh-select"
cp "$WORK/out/nginx-stream" "$WORK/out-identity/nginx-stream"
cd "$WORK"
sha256sum sslh-d39388d1.tar.gz libproxyprotocol-3e133b96.tar.gz > out-identity/source-sha256.txt
cd out-identity
sha256sum sslh-select nginx-stream > binary-sha256.txt
file sslh-select nginx-stream
printf '%s\n' IDENTITY_BUILD_ONLY_COMPLETE
