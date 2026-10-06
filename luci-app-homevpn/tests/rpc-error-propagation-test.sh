#!/bin/sh
# Full actual RPC, real UCI/jshn; fail only the isolated init boundary.
set -e
src="${1:?RPC source required}"
t=$(mktemp -d /tmp/homevpn-rpc-errors.XXXXXX)
trap 'rm -rf "$t"' EXIT INT TERM
mkdir "$t/config" "$t/save" "$t/bin"
printf 'config homevpn config\n option cert_mode selfsigned\n' > "$t/config/homevpn"
cat > "$t/bin/uci" <<EOF
#!/bin/sh
exec /sbin/uci -c '$t/config' -P '$t/save' "\$@"
EOF
cat > "$t/init" <<'EOF'
#!/bin/sh
echo 'fixture leaf failure'
exit 1
EOF
chmod +x "$t/bin/uci" "$t/init"
export PATH="$t/bin:$PATH"
sed "s@/var/lock/homevpn-service.lock@$t/lock@g" "$(dirname "$src")/service-lock.sh" > "$t/lock-lib"
sed "s@/usr/share/homevpn/service-lock.sh@$t/lock-lib@g; s@/etc/init.d/homevpn@$t/init@g; s@/tmp/homevpn-regen.log@$t/regen.log@g" "$src" > "$t/rpc"
. /usr/share/libubox/jshn.sh
failed=0
for method in add_user del_user provision; do
 case "$method" in add_user) request='{"name":"fixture","password":"Fixture12345"}';; del_user) request='{"name":"fixture"}';; provision) request='{}';; esac
 out=$(printf '%s\n' "$request" | sh "$t/rpc" call "$method")
 json_load "$out"; json_get_var result ok
 [ "$result" = 0 ] || { printf 'FAIL %s: %s\n' "$method" "$out"; failed=1; }
 json_get_var error error || :
 [ -n "$error" ] || { printf 'FAIL missing error %s\n' "$method"; failed=1; }
 printf '%s %s\n' "$method" "$out"
done
exit "$failed"
