#!/bin/sh
# Host-only procd harness; all filesystem-changing commands are mocked.
set -eu
pkg=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$pkg/files/ddns-go.init"
config_load() { :; }
config_get() {
 case "$3" in enabled) value=1;; noweb) value=1;; local_api) value=$API;; *) value=${4:-};; esac
 eval "$1=\$value"
}
config_get_bool() { config_get "$@"; }
mkdir() { printf 'mkdir %s\n' "$*"; }
chown() { printf 'chown %s\n' "$*"; }
chmod() { printf 'chmod %s\n' "$*"; }
touch() { :; }
procd_open_instance() { :; }
procd_close_instance() { :; }
procd_set_param() { printf 'set %s\n' "$*"; }
procd_append_param() { printf 'append %s\n' "$*"; }
API=0; disabled=$(start_service)
case "$disabled" in *-local-api*) printf 'FAIL: API enabled by default\n'; exit 1;; esac
API=1; enabled=$(start_service)
for expected in 'chmod 0700 /var/run/ddns-go' 'chown ddns-go:ddns-go /var/run/ddns-go' 'append command -local-api /var/run/ddns-go/local-api.sock' 'append command -noweb' 'set user ddns-go'; do
 case "$enabled" in *"$expected"*) :;; *) printf 'FAIL missing %s\n' "$expected"; exit 1;; esac
done
printf 'PASS init opt-in, private runtime, unprivileged daemon, noweb coexistence (mocked filesystem/procd)\n'
