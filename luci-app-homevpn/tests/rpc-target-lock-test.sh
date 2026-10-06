#!/bin/sh
# Actual concurrent RPC processes on target ash; no production mutation paths.
set -e
src="${1:?RPC source required}"
t=$(mktemp -d /tmp/homevpn-rpc-lock.XXXXXX)
trap '[ -z "${holder:-}" ] || kill "$holder" 2>/dev/null || :; rm -rf "$t"' EXIT INT TERM
mkdir "$t/bin"
sed "s@/var/lock/homevpn-service.lock@$t/lock@g" "$(dirname "$src")/service-lock.sh" > "$t/lock-lib"
sed "s@/usr/share/homevpn/service-lock.sh@$t/lock-lib@g; s@/etc/init.d/homevpn@$t/init@g" "$src" > "$t/rpc"
printf '#!/bin/sh\necho boundary >> %s/boundaries\nexit 1\n' "$t" > "$t/init"
cp "$t/init" "$t/bin/uci"; chmod +x "$t/init" "$t/bin/uci"
export PATH="$t/bin:$PATH"
cat > "$t/holder" <<EOF
. '$t/lock-lib'
hold() { touch '$t/ready'; while [ ! -f '$t/release' ]; do sleep 1; done; }
hv_with_lock hold
EOF
sh "$t/holder" & holder=$!
n=0; while [ ! -f "$t/ready" ]; do n=$((n+1)); [ "$n" -lt 100 ]; sleep 1; done
. /usr/share/libubox/jshn.sh
for method in set_enabled set_settings add_user del_user set_user_ip provision upload_certs; do
 out=$(printf '{}\n' | HOMEVPN_SERVICE_LOCK_HELD=1 sh "$t/rpc" call "$method")
 json_load "$out"; json_get_var result ok; json_get_var error error
 [ "$result" = 0 ]; case "$error" in *busy*) ;; *) exit 1;; esac
 [ ! -e "$t/boundaries" ]
 printf 'PASS locked %s before boundary\n' "$method"
done
touch "$t/release"; wait "$holder"; holder=''
[ ! -d "$t/lock" ]
printf '. "%s/lock-lib"\nhv_with_lock true\n' "$t" > "$t/child"
printf '. "%s/lock-lib"\nhv_with_lock sh "%s/child"\n' "$t" "$t" > "$t/parent"
sh "$t/parent"; [ ! -d "$t/lock" ]
printf 'PASS authenticated nested child and lock release\n'
