#!/bin/bash
set -euo pipefail
repo=/mnt/d/DevPortal/homelede/homepublish-product
sdk=/home/eric/homestun-sdk-check/openwrt-sdk-24.10.5-x86-64_gcc-13.3.0_musl.Linux-x86_64
source=/home/eric/homestun-sdk-check/device-r8-source
mkdir -p "$source"
tar -xf /mnt/d/DevPortal/homelede/artifacts/homepublish-r8/r8-source.tar -C "$source"
cd "$sdk"
exec 9>/home/eric/homestun-sdk-check/build.lock
flock -n 9
for pkg in homepublish luci-app-homepublish; do
 ln -sfn "$source/$pkg" "package/feeds/homestunlocal/$pkg"
 test "$(readlink -f package/feeds/homestunlocal/$pkg)" = "$source/$pkg"
done
./scripts/feeds update homestunlocal > /home/eric/homestun-sdk-check/r8-feeds.log 2>&1
# Final source links bound explicitly after feed refresh.
for pkg in homepublish luci-app-homepublish; do ln -sfn "$source/$pkg" "package/feeds/homestunlocal/$pkg";done
make defconfig >/home/eric/homestun-sdk-check/r8-defconfig.log 2>&1
grep '^CONFIG_PACKAGE_homepublish=m$' .config
grep '^CONFIG_PACKAGE_luci-app-homepublish=m$' .config
timeout 480 make package/homepublish/clean package/luci-app-homepublish/clean package/homepublish/compile package/luci-app-homepublish/compile -j2 V=s CONFIG_PACKAGE_homepublish=m CONFIG_PACKAGE_luci-app-homepublish=m > /home/eric/homestun-sdk-check/r8-build.log 2>&1
mkdir -p /mnt/d/DevPortal/homelede/artifacts/homepublish-r8
cp bin/packages/x86_64/homestunlocal/*_0.1.0-r8_*.ipk /mnt/d/DevPortal/homelede/artifacts/homepublish-r8/
sha256sum /mnt/d/DevPortal/homelede/artifacts/homepublish-r8/*.ipk
