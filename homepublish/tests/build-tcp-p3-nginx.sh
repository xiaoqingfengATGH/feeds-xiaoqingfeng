#!/bin/sh
# Cross-build only. Reuse pinned P0 source for task16 private device acceptance.
# NOT the production version/security/supply-chain selection (P5 gate).
set -eu
SDK=/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64
WORK=/home/eric/homestun-sdk-check/tcp-ingress-p3
TC="$SDK/staging_dir/toolchain-x86_64_gcc-13.3.0_musl"
TARGET="$SDK/staging_dir/target-x86_64_musl"
export STAGING_DIR="$SDK/staging_dir" PATH="$TC/bin:$PATH" CONFIG_BIG_ENDIAN=
exec 9>/home/eric/homestun-sdk-check/build.lock
flock -n 9 || exit 73
mkdir -p "$WORK"; cd "$WORK"
sha256sum "$SDK/dl/nginx-1.26.1.tar.gz" > source-sha256.txt
[ -d nginx-1.26.1 ] || tar xf "$SDK/dl/nginx-1.26.1.tar.gz"
cd nginx-1.26.1
if [ ! -f .homepublish-cross-patched ]; then
 for name in 101-feature_test_fix.patch 102-sizeof_test_fix.patch 104-endianness_fix.patch; do
  patch -p1 < "$SDK/feeds/packages/net/nginx/patches/nginx/$name"
 done
 touch .homepublish-cross-patched
fi
./configure --crossbuild=Linux::x86_64 --with-cc="$TC/bin/x86_64-openwrt-linux-musl-gcc" --with-cc-opt="-I$TARGET/usr/include" --with-ld-opt="-static -L$TARGET/usr/lib -lpthread" --prefix=/tmp/homepublish-tcp-p3/runtime --with-http_ssl_module --with-http_realip_module --with-stream --with-stream_ssl_module --with-stream_ssl_preread_module
make -j2
cp objs/nginx "$WORK/nginx-private"
cd "$WORK"; sha256sum nginx-private > binary-sha256.txt
file nginx-private
printf '%s\n' P3_CROSS_BUILD_ONLY_COMPLETE
