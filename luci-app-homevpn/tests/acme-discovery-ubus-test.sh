#!/bin/sh
# Exercise real ubus dispatch with isolated fixtures, never production ACME files.
set -eu
T=$(mktemp -d /tmp/homevpn-ubus.XXXXXX)
PLUGIN=/usr/libexec/rpcd/homevpn-discovery-test
[ ! -e "$PLUGIN" ] || { rmdir "$T"; echo 'test plugin already exists'; exit 1; }
cleanup() { rm -f "$PLUGIN"; rm -rf "$T"; /etc/init.d/rpcd reload; }
trap cleanup EXIT
mkdir -p "$T/acme/test.example" "$T/acme/test.example_ecc" "$T/links"
# The test object exposes ONLY the read-only production discovery method.
cat > "$PLUGIN" <<EOF
#!/bin/sh
export HV_ACME_STATE_DIR='$T/acme' HV_ACME_LINK_DIR='$T/links'
case "\$1:\$2" in
list:) echo '{"discover_acme":{"domain":""}}';;
call:discover_acme) exec /usr/libexec/rpcd/homevpn call discover_acme;;
*) exit 1;;
esac
EOF
chmod 755 "$PLUGIN"
/etc/init.d/rpcd reload
n=0
until ubus list homevpn-discovery-test >/dev/null 2>&1; do
 n=$((n+1)); [ "$n" -lt 20 ] || exit 1; sleep 1
done
check() {
 result=$(ubus call homevpn-discovery-test discover_acme '{"domain":"test.example"}')
 [ "$(printf '%s' "$result" | jsonfilter -e '@.ok')" = true ]
 types=$(printf '%s' "$result" | jsonfilter -e '@.types[*]' | tr '\n' ' ')
 [ "$types" = "$1" ] || { echo "FAIL: expected [$1] got [$types]"; exit 1; }
 echo "PASS: ubus discovery [$types]"
}
check ''
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/acme/test.example/test.example.key" -out "$T/acme/test.example/fullchain.cer" -days 1 -subj /CN=test.example >/dev/null 2>&1
check 'rsa '
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$T/acme/test.example_ecc/test.example.key" -out "$T/acme/test.example_ecc/fullchain.cer" -days 1 -subj /CN=test.example >/dev/null 2>&1
check 'rsa ecc '
rm -rf "$T/acme/test.example"
check 'ecc '
