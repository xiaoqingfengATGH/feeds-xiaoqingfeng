#!/bin/sh
# Build private target binaries only; NEVER execute target tests locally.
set -eu
SDK=/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64
WORK=/home/eric/homestun-sdk-check/tcp-ingress-p0
TC="$SDK/staging_dir/toolchain-x86_64_gcc-13.3.0_musl"
TARGET="$SDK/staging_dir/target-x86_64_musl"
export STAGING_DIR="$SDK/staging_dir"
export PATH="$TC/bin:$PATH"
CC="$TC/bin/x86_64-openwrt-linux-musl-gcc"
AR="$TC/bin/x86_64-openwrt-linux-musl-ar"
mkdir -p "$WORK/out"
exec 9>/home/eric/homestun-sdk-check/build.lock
flock -n 9 || exit 73
cd "$WORK"
if [ ! -f libconfig-1.7.3.tar.gz ]; then
    curl -fL --connect-timeout 15 --max-time 120 https://github.com/hyperrealm/libconfig/releases/download/v1.7.3/libconfig-1.7.3.tar.gz -o libconfig-1.7.3.tar.gz
fi
sha256sum libconfig-1.7.3.tar.gz sslh-e831b732.tar.gz "$SDK/dl/nginx-1.26.1.tar.gz" > out/source-sha256.txt
[ -d libconfig-1.7.3 ] || tar xf libconfig-1.7.3.tar.gz
cd libconfig-1.7.3
CC="$CC" AR="$AR" ./configure --host=x86_64-openwrt-linux-musl --prefix="$WORK/libconfig" --disable-shared --enable-static --disable-cxx --disable-examples
make -j2
make install
cd "$WORK/sslh-e831b732dbd239d7805ec8ec113a926f0a9271b6"
CC="$CC" ./configure --host=x86_64-openwrt-linux-musl
make -j2 sslh-select CC="$CC" AR="$AR" USELIBEV= USELIBCAP= USESYSTEMD= CPPFLAGS="-I$WORK/libconfig/include -I$TARGET/usr/include -DLIBCONFIG -DENABLE_REGEX" LDFLAGS="-static -L$WORK/libconfig/lib -L$TARGET/usr/lib"
cp sslh-select "$WORK/out/sslh-select"
cd "$WORK"
[ -d nginx-1.26.1 ] || tar xf "$SDK/dl/nginx-1.26.1.tar.gz"
cd nginx-1.26.1
if [ ! -f .homepublish-cross-patched ]; then
    for name in 101-feature_test_fix.patch 102-sizeof_test_fix.patch 104-endianness_fix.patch; do
        patch -p1 < "$SDK/feeds/packages/net/nginx/patches/nginx/$name"
    done
    touch .homepublish-cross-patched
fi
export CONFIG_BIG_ENDIAN=
./configure --crossbuild=Linux::x86_64 --with-cc="$CC" --with-ld-opt=-static --prefix=/tmp/homepublish-tcp-p0 --without-http --with-stream --without-stream_limit_conn_module --without-stream_access_module --without-stream_geo_module --without-stream_map_module --without-stream_split_clients_module --without-stream_return_module --without-stream_set_module --without-stream_upstream_hash_module --without-stream_upstream_least_conn_module --without-stream_upstream_random_module --without-stream_upstream_zone_module
make -j2
cp objs/nginx "$WORK/out/nginx-stream"
cd "$WORK/out"
sha256sum sslh-select nginx-stream > binary-sha256.txt
file sslh-select nginx-stream
printf '%s\n' BUILD_ONLY_COMPLETE_NO_LOCAL_TESTS
