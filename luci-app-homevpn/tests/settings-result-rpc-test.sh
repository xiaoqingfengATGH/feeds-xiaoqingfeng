#!/bin/sh
# Real set_settings branch, real jshn and UCI; init boundary isolated.
set -e
src="${1:?RPC source required}"
t=$(mktemp -d /tmp/homevpn-settings-test.XXXXXX)
trap 'rm -rf "$t"' EXIT INT TERM
mkdir "$t/config" "$t/save" "$t/bin"
printf 'config homevpn config\n option cert_mode selfsigned\n option ip_mode subnet\n' > "$t/config/homevpn"
cat > "$t/bin/uci" <<EOF
#!/bin/sh
exec /sbin/uci -c '$t/config' -P '$t/save' "\$@"
EOF
cat > "$t/regen" <<'EOF'
#!/bin/sh
printf '%s\n' "$TEST_OUTPUT"
exit "$TEST_RC"
EOF
chmod +x "$t/bin/uci" "$t/regen"
export PATH="$t/bin:$PATH"
{
 printf '. /usr/share/libubox/jshn.sh\nCFG=homevpn\ncfg() { uci -q get "homevpn.config.$1"; }\nerr() { json_init; json_add_boolean ok 0; json_add_string error "$1"; json_dump; exit 0; }\nok() { json_add_boolean ok 1; }\nhv_pki_valid_remote() { return 0; }\njson_load "$1"\ncase set_settings in\n'
 sed -n '/^[[:space:]]*set_settings)/,/^[[:space:]]*provision)/p' "$src" | sed '$d' | sed "s@/etc/init.d/homevpn provision@$t/regen@g; s@/tmp/homevpn.state@$t/state@g"
 printf 'esac\n'
} > "$t/branch"
. /usr/share/libubox/jshn.sh
failed=0
for scenario in success precheck runtime; do
 TEST_RC=0; TEST_OUTPUT=applied; expected=1
 [ "$scenario" != precheck ] || { TEST_RC=1; TEST_OUTPUT='precheck refused fixture'; expected=0; }
 [ "$scenario" != runtime ] || { TEST_RC=1; TEST_OUTPUT='runtime failed fixture'; expected=0; }
 export TEST_RC TEST_OUTPUT
 printf 'reason=%s\n' "$TEST_OUTPUT" > "$t/state"
 out=$(sh "$t/branch" '{"remote":"vpn.example.com","cert_mode":"selfsigned","ip_mode":"subnet","pool_subnet":"10.100.1.0/24","vpn_name":"fixture"}')
 json_load "$out"; json_get_var result ok; json_get_var applied precheck_ok
 if [ "$result" != "$expected" ] || [ "$applied" != "$expected" ]; then printf 'FAIL %s: %s\n' "$scenario" "$out"; failed=1; fi
 if [ "$expected" = 0 ]; then
  json_get_var saved saved || :; json_get_var error error || :; json_get_var output output
  [ "$saved" = 1 ] && [ -n "$error" ] && [ "$output" = "$TEST_OUTPUT" ] || { printf 'FAIL saved/error/output %s: %s\n' "$scenario" "$out"; failed=1; }
 fi
 [ "$(uci -q get homevpn.config.vpn_name)" = fixture ]
 printf '%s %s\n' "$scenario" "$out"
done
exit "$failed"
