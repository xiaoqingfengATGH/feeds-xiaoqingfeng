#!/bin/bash
set -euo pipefail
ROOT=/home/eric/homestun-sdk-check
SDK=$ROOT/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64
cd "$ROOT"
apt-get download libncurses6 >>ncurses-download.log 2>&1
for p in libncurses6_*.deb; do dpkg-deb -x "$p" local-tools; done
export PATH="$ROOT/local-tools/usr/bin:$PATH"
export CPATH="$ROOT/local-tools/usr/include"
export LIBRARY_PATH="$ROOT/local-tools/usr/lib/x86_64-linux-gnu"
export LD_LIBRARY_PATH="$ROOT/local-tools/usr/lib/x86_64-linux-gnu"
export PKG_CONFIG_PATH="$ROOT/local-tools/usr/lib/x86_64-linux-gnu/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$ROOT/local-tools"
mkdir -p source-feed
cp -a /mnt/d/DevPortal/homelede/feeds-xiaoqingfeng-homestun/homestun source-feed/
# Official release snapshots: retain immutable feed commits from SDK manifest.
mkdir -p upstream
curl -fL --retry 2 --connect-timeout 20 --max-time 240 -o upstream/base.tar.gz https://codeload.github.com/openwrt/openwrt/tar.gz/refs/tags/v24.10.5
curl -fL --retry 2 --connect-timeout 20 --max-time 240 -o upstream/packages.tar.gz https://codeload.github.com/openwrt/packages/tar.gz/953b6d47b4e9f0ad3c39547c6d3f9a828f10e206
tar -xf upstream/base.tar.gz -C upstream
tar -xf upstream/packages.tar.gz -C upstream
cd "$SDK"
printf 'src-link base %s/upstream/openwrt-24.10.5\nsrc-link packages %s/upstream/packages-953b6d47b4e9f0ad3c39547c6d3f9a828f10e206\nsrc-link homestunlocal %s/source-feed\n' "$ROOT" "$ROOT" "$ROOT" >feeds.conf
printf 'CONFIG_HAVE_DOT_CONFIG=y\nCONFIG_ALL_NONSHARED=n\nCONFIG_ALL_KMODS=n\nCONFIG_ALL=n\n' >.config
make prereq V=s
./scripts/feeds update base packages homestunlocal
./scripts/feeds install homestun
./scripts/feeds install lua libuci-lua nginx-ssl natmap curl ca-bundle
printf 'CONFIG_ALL_NONSHARED=n\nCONFIG_ALL_KMODS=n\nCONFIG_ALL=n\nCONFIG_PACKAGE_homestun=m\n' >.config
make defconfig
# Never leak host ncurses include/library search paths into TARGET_CC.
unset CPATH LIBRARY_PATH LD_LIBRARY_PATH PKG_CONFIG_PATH PKG_CONFIG_SYSROOT_DIR
make -j2 package/feeds/homestunlocal/homestun/compile V=s
find bin -name '*homestun*.ipk' -print
