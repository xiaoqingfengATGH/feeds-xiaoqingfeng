#!/bin/sh
# Execute the real set_settings branch with isolated UCI and a harmless regen.
set -e
. /usr/share/libubox/jshn.sh
src="${1:?RPC source required}"
t=$(mktemp -d /tmp/homevpn-cidr-test.XXXXXX)
trap 'rm -rf "$t"' EXIT INT TERM
mkdir "$t/config" "$t/save" "$t/bin"
printf 'config homevpn config\n\toption vpn_name original\n\toption ip_mode subnet\n\toption pool_subnet 10.100.1.0/24\n' > "$t/config/homevpn"
cat > "$t/bin/uci" <<EOF
#!/bin/sh
exec /sbin/uci -c '$t/config' -P '$t/save' "\$@"
EOF
chmod +x "$t/bin/uci"
export PATH="$t/bin:$PATH"
# No production init command can execute from this branch fixture.
{
 printf '. /usr/share/libubox/jshn.sh\nCFG=homevpn\ncfg() { uci -q get "homevpn.config.$1"; }\nerr() { json_init; json_add_boolean ok 0; json_add_string error "$1"; json_dump; exit 0; }\nok() { json_add_boolean ok 1; }\njson_load "$1"\ncase set_settings in\n'
 sed -n '/^[[:space:]]*set_settings)/,/^[[:space:]]*provision)/p' "$src" | sed '$d' | sed 's@/etc/init.d/homevpn regen@true@g; s@/tmp/homevpn.state@/dev/null@g'
 printf 'esac\n'
} > "$t/branch"
before=$(sha256sum "$t/config/homevpn")
for cidr in '' '   ' garbage 999.1.0.0/24 10.1.0.0/33; do
 json_init; json_add_string cert_mode selfsigned; json_add_string ip_mode subnet; json_add_string pool_subnet "$cidr"; json_add_string vpn_name MUST_NOT_SAVE
 out=$(sh "$t/branch" "$(json_dump)")
 json_load "$out"; json_get_var result ok
 [ "$result" = 0 ] || { printf 'FAIL: accepted invalid CIDR [%s]\n' "$cidr"; exit 1; }
 case "$cidr" in ''|'   ') json_get_var message error; case "$message" in *'is required'*) ;; *) printf 'FAIL: whitespace needs required-field error\n'; exit 1;; esac;; esac
 [ "$before" = "$(sha256sum "$t/config/homevpn")" ]
 [ -z "$(uci changes)" ]
done
json_init; json_add_string cert_mode selfsigned; json_add_string ip_mode subnet; json_add_string pool_subnet 10.100.1.0/24
out=$(sh "$t/branch" "$(json_dump)"); json_load "$out"; json_get_var result ok; [ "$result" = 1 ]
printf 'PASS: real RPC branch rejects empty/whitespace/invalid before any UCI write; valid CIDR accepted in isolated config, no production regen\n'
