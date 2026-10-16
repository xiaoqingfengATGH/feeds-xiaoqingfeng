#!/bin/sh
# Target cross-compilation only; never execute target binaries on the build host.
# Caller owns the SDK flock. All input archives must pass pinned hashes first.
set -eu
SDK=$1
WORK=$2
SOURCES=$3
TC="$SDK/staging_dir/toolchain-x86_64_gcc-13.3.0_musl"
TARGET="$SDK/staging_dir/target-x86_64_musl"
export STAGING_DIR="$SDK/staging_dir" PATH="$TC/bin:$PATH" CONFIG_BIG_ENDIAN=
CC="$TC/bin/x86_64-openwrt-linux-musl-gcc"
AR="$TC/bin/x86_64-openwrt-linux-musl-ar"
mkdir -p "$WORK/out" "$WORK/relink"
cd "$SOURCES"
printf '%s\n' '3cf46f5ed7504d460125866b7bea99fb357f31d887e2e63b35503310e9b8b6c8  nginx-1.30.6.tar.gz' '4822815217ba8c19d8a7469d19e686a5a3f6a0388e772636996f9cae1cdbc056  sslh-d39388d1.tar.gz' 'ecfaa002f2f36a87c7e52f515a6caaec492fb69ed5f0f74295934ed3b8475882  libproxyprotocol-3e133b96.tar.gz' '545166d6cac037744381d1e9cc5a5405094e7bfad16a411699bcff40bbb31ee7  libconfig-1.7.3.tar.gz' | sha256sum -c -
for f in nginx-1.30.6.tar.gz sslh-d39388d1.tar.gz libproxyprotocol-3e133b96.tar.gz libconfig-1.7.3.tar.gz; do tar xf "$f" -C "$WORK"; done
cd "$WORK/libconfig-1.7.3"
CC="$CC" AR="$AR" ./configure --build="$(./aux-build/config.guess)" --host=x86_64-openwrt-linux-musl --prefix="$WORK/libconfig" --disable-shared --enable-static --disable-cxx --disable-examples
make -j2
make install
P="$WORK/libproxyprotocol-3e133b9602e59f47ceceef74fbd52a3b147e5874"
mkdir -p "$WORK/proxy/include" "$WORK/proxy/lib"
"$CC" -O2 -fshort-enums -fPIC -c "$P/src/proxy_protocol.c" -o "$WORK/relink/proxy_protocol.o"
"$AR" rcs "$WORK/proxy/lib/libproxyprotocol.a" "$WORK/relink/proxy_protocol.o"
cp "$P/src/proxy_protocol.h" "$WORK/proxy/include/"
cd "$WORK/sslh-d39388d1edcc9fe7a35449fc5c23d222d20d6f81"
# Explicit --build different from --host forces autoconf cross mode, even on x86_64.
CC="$CC" CPPFLAGS="-I$WORK/proxy/include -I$TARGET/usr/include" LDFLAGS="-L$WORK/proxy/lib -L$TARGET/usr/lib" ./configure --build=x86_64-pc-linux-gnu --host=x86_64-openwrt-linux-musl
# Fail closed: PROXY must be a compiled capability, not a guessed runtime option.
grep -qx '#define HAVE_PROXYPROTOCOL 1' config.h
make -j2 sslh-select CC="$CC" AR="$AR" USELIBEV= USESYSTEMD= CFLAGS='-Wall -O2 -fshort-enums' CPPFLAGS="-I$WORK/proxy/include -I$WORK/libconfig/include -I$TARGET/usr/include -DLIBCONFIG -DENABLE_REGEX" LDFLAGS="-L$WORK/proxy/lib -L$WORK/libconfig/lib -L$TARGET/usr/lib -Wl,-Map,$WORK/relink/sslh.map"
cp sslh-select "$WORK/out/sslh-select"
cp *.o *.a config.h Makefile "$WORK/relink/"
cd "$WORK/nginx-1.30.6"
for name in 101-feature_test_fix.patch 102-sizeof_test_fix.patch 104-endianness_fix.patch; do patch -p1 < "$SDK/feeds/packages/net/nginx/patches/nginx/$name"; done
./configure --crossbuild=Linux::x86_64 --with-cc="$CC" --with-cc-opt="-I$TARGET/usr/include" --with-ld-opt="-L$TARGET/usr/lib -Wl,-Map,$WORK/relink/nginx.map" --prefix=/var/run/homepublish --sbin-path=/usr/libexec/homepublish/nginx --with-http_ssl_module --with-http_realip_module --with-stream --with-stream_ssl_module --with-stream_ssl_preread_module --without-http_ssi_module --without-http_scgi_module --without-http_uwsgi_module --without-http_grpc_module --without-http_memcached_module --without-http_fastcgi_module
make -j2
cp objs/nginx "$WORK/out/nginx"
cp objs/ngx_modules.c objs/ngx_auto_config.h "$WORK/out/"
cd "$WORK/out"
file nginx sslh-select
"$TC/bin/x86_64-openwrt-linux-musl-readelf" -d nginx sslh-select > needed.txt
sha256sum nginx sslh-select > SHA256SUMS
printf '%s\n' P5_COMPONENT_CROSS_BUILD_COMPLETE_NO_HOST_EXECUTION
