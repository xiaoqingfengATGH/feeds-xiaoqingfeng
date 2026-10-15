#!/bin/sh
# HomePublish P0: device-only dependency gate; no service/config mutation.
set -u
missing=0
printf '%s\n' 'HP_TCP_P0_BEGIN'
printf '%s\n' '--- Immutable baseline ---'
sha256sum /etc/config/firewall /etc/config/network /etc/config/homepublish
printf '%s\n' '--- Runtime ---'
uname -a
ip -brief address
netstat -lntp
printf '%s\n' '--- sslh ---'
sslh_bin=''
for name in sslh-select sslh; do
    if command -v "$name" >/dev/null 2>&1; then
        sslh_bin="$(command -v "$name")"
        break
    fi
done
if [ -n "$sslh_bin" ]; then
    "$sslh_bin" -V 2>&1
    printf '%s\n' 'SSLH_PRESENT (features and reject behavior NOT yet verified)'
else
    printf '%s\n' 'BLOCKER SSLH_MISSING'
    missing=1
fi
printf '%s\n' '--- Nginx ---'
if command -v nginx >/dev/null 2>&1; then
    version="$(nginx -V 2>&1)"
    printf '%s\n' "$version"
    case "$version" in
        *--with-stream*) printf '%s\n' 'STREAM_BUILD_OPTION_PRESENT (load/runtime NOT yet verified)' ;;
        *) printf '%s\n' 'BLOCKER NGINX_STREAM_BUILD_OPTION_MISSING'; missing=1 ;;
    esac
    printf '%s\n' '--- Module file candidates ---'
    for file in /usr/lib/nginx/modules/* /usr/lib/nginx/*.so /usr/lib/nginx/modules/*.so; do
        [ -f "$file" ] && printf '%s\n' "$file"
    done
else
    printf '%s\n' 'BLOCKER NGINX_MISSING'
    missing=1
fi
printf '%s\n' '--- Controller registration (read only) ---'
ubus call service list '{"name":"homepublish"}'
printf '%s\n' '--- Immutable baseline after inspection ---'
sha256sum /etc/config/firewall /etc/config/network /etc/config/homepublish
if [ "$missing" -ne 0 ]; then
    printf '%s\n' 'HP_TCP_P0_BLOCKED: dependency prerequisite; no transport acceptance claimed'
    exit 2
fi
printf '%s\n' 'HP_TCP_P0_INVENTORY_OK: transport verification still required'
