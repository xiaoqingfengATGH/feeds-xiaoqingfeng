#!/bin/sh
set -eu
root="$1"
configs="$2"
[ -f "$root/homepublish.init" ] || { echo 'FAIL missing procd service'; exit 1; }
. "$root/homepublish.init"
homepublish_plan() { lua "$root/config-cli.lua" plan "$configs"; }
procd_open_instance() { echo 'FAIL disabled service called procd'; exit 9; }
start_service
status=$(lua "$root/config-cli.lua" status "$configs")
[ "$status" = '{"state":"disabled","publication":"disabled","mapped":"unknown","reachable":"unverified"}' ]
echo 'PASS real UCI disabled start has zero procd commands; status never claims reachable'
# All UCI writes are exclusively to the isolated test directory.
uci -c "$configs" set homepublish.main.enabled=1
uci -c "$configs" commit homepublish
if start_service; then echo 'FAIL unapproved start accepted'; exit 1; fi
[ "$(lua "$root/config-cli.lua" status "$configs")" = '{"state":"invalid","publication":"invalid","mapped":"unknown","reachable":"unverified"}' ]
uci -c "$configs" set homepublish.main.exposure_approved=1
uci -c "$configs" set homepublish.fixture=host
uci -c "$configs" set homepublish.fixture.name=nas-stun-test.innonext.win
uci -c "$configs" set homepublish.fixture.upstream=http://127.0.0.1:18081
uci -c "$configs" commit homepublish
lua "$root/config-cli.lua" render "$configs" /tmp/homepublish-service-Test123 > "$root/rendered.conf"
[ "$(lua "$root/config-cli.lua" status "$configs")" = '{"state":"configured","publication":"disabled","mapped":"unknown","reachable":"unverified"}' ]
echo 'PASS unapproved start rejected; real UCI host routes render; configured is not mapped/reachable'
