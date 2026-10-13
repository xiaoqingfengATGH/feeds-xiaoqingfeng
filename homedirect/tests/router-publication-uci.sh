#!/bin/sh
set -eu
base=/tmp/homedirect-test/uci
root=$base/root
mkdir -p "$root"/bin "$root"/usr/bin "$root"/usr/lib/lua "$root"/lib/functions "$root"/usr/share/libubox "$root"/etc/config "$root"/etc/init.d "$root"/etc/homedirect "$root"/tmp "$root"/dev "$root"/usr/libexec
cp /bin/busybox "$root/bin/"
for app in sh rm chmod chown ln mv printf readlink basename; do ln -sf busybox "$root/bin/$app"; done
for app in lua uci jshn jsonfilter; do cp "$(command -v "$app")" "$root/usr/bin/$app"; done
cp /lib/ld-musl-x86_64.so.1 /lib/libgcc_s.so.1 "$root/lib/"
ln -sf ld-musl-x86_64.so.1 "$root/lib/libc.so"
cp /usr/lib/liblua.so* /usr/lib/libjson-c.so* "$root/usr/lib/"
cp /lib/libuci.so* /lib/libubox.so* /lib/libblobmsg_json.so* "$root/lib/"
cp /usr/lib/lua/uci.so "$root/usr/lib/lua/"
cp /lib/functions/procd.sh "$root/lib/functions/"
cp /usr/share/libubox/jshn.sh "$root/usr/share/libubox/"
printf '' > "$root/dev/null"
chmod 700 "$root/etc/homedirect"
printf original-cert > "$root/etc/homedirect/cert.pem"
printf original-key > "$root/etc/homedirect/key.pem"
chmod 600 "$root/etc/homedirect/"*.pem
# Executable no-network sentinels; registration must never execute these.
printf '#!/bin/sh\ntouch /tmp/engine-ran\nexit 99\n' > "$root/usr/bin/natmap"
cp "$root/usr/bin/natmap" "$root/usr/libexec/homedirect-publish"
chmod 755 "$root/usr/bin/natmap" "$root/usr/libexec/homedirect-publish" "$root/usr/libexec/homedirect-lease"
cp "$root/usr/bin/natmap" "$root/usr/bin/curl"
mkdir -p "$root/etc/ssl/certs"
printf fixture-ca-not-for-network > "$root/etc/ssl/certs/ca-certificates.crt"
chroot "$root" /usr/bin/uci set homedirect.fixture=host
chroot "$root" /usr/bin/uci set homedirect.fixture.name=nas-stun-test.innonext.win
chroot "$root" /usr/bin/uci set homedirect.fixture.upstream=http://127.0.0.1:18081
chroot "$root" /usr/bin/uci commit homedirect
chroot "$root" /bin/sh /test-publication-service.sh
