#!/bin/sh
# Isolated probe contract tests; no router, ubus, UCI or services required.
set -eu
PACKAGE="${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
PROBE="$PACKAGE/root/etc/homestatus-probes/homevpn"
SH="${TEST_SHELL:-/bin/sh}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir "$T/bin"
check() {
	name="$1" expected="$2"
	set +e
	PATH="$T/bin" "$SH" "$PROBE" >"$T/stdout" 2>"$T/stderr"
	actual=$?
	set -e
	[ "$actual" = "$expected" ] || { printf 'FAIL %s: expected %s, got %s\n' "$name" "$expected" "$actual"; exit 1; }
	[ ! -s "$T/stdout" ] && [ ! -s "$T/stderr" ] || { printf 'FAIL %s: noisy probe\n' "$name"; exit 1; }
	printf 'PASS %s\n' "$name"
}
# A shell-only PATH ensures no accidental fallback to host tools.
cat >"$T/bin/pidof" <<EOF
#!$SH
[ "\$#" = 1 ] && [ "\$1" = charon ] || exit 99
printf '123 456\n'
exit 0
EOF
chmod +x "$T/bin/pidof"
check running 0
for code in 1 2 3 126 127; do
	cat >"$T/bin/pidof" <<EOF
#!$SH
[ "\$#" = 1 ] && [ "\$1" = charon ] || exit 99
printf 'diagnostic noise\n' >&2
exit $code
EOF
	chmod +x "$T/bin/pidof"
	expected=2; [ "$code" != 1 ] || expected=1
	check "pidof-exit-$code" "$expected"
done
rm "$T/bin/pidof"
check missing-pidof 2
# Global file modes also affect translation IPKs, which do not contain probes.
if grep -Eq '^[[:space:]]*PKG_FILE_MODES[[:space:]:+?]*=' "$PACKAGE/Makefile"; then
	printf 'FAIL global file modes affect translation packages\n'; exit 1
fi
# Exercise the actual package hook with a Windows-style non-executable source.
mkdir -p "$T/package/root/etc/homestatus-probes" "$T/build/root/etc/homestatus-probes" "$T/app" "$T/translation"
cp "$PROBE" "$T/package/root/etc/homestatus-probes/homevpn"
chmod 0644 "$T/package/root/etc/homestatus-probes/homevpn"
cp -pR "$T/package/root/." "$T/build/root/"
{
	printf 'INSTALL_BIN := install -m0755\nPKG_BUILD_DIR := %s/build\n' "$T"
	sed -n '/^define Build\/Prepare\/luci-app-homevpn$/,/^endef$/p' "$PACKAGE/Makefile"
	printf 'all:\n	$(call Build/Prepare/luci-app-homevpn)\n'
} >"$T/hook.mk"
make --no-print-directory -s -C "$T/package" -f "$T/hook.mk"
cp -pR "$T/build/root/." "$T/app/"
[ -x "$T/app/etc/homestatus-probes/homevpn" ] || { printf 'FAIL installed probe not executable\n'; exit 1; }
[ "$(stat -c %a "$T/app/etc/homestatus-probes/homevpn")" = 755 ] || exit 1
[ ! -x "$T/package/root/etc/homestatus-probes/homevpn" ] || { printf 'FAIL source mode changed\n'; exit 1; }
[ ! -e "$T/translation/etc/homestatus-probes/homevpn" ] || exit 1
printf 'PASS package prepare hook: 0644 source -> 0755 app probe, no global translation modes\n'
