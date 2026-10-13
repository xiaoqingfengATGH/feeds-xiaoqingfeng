#!/bin/bash
# Invoke as WSL root: unshare -nm --propagation private bash this-file
set -euo pipefail
cd "$(dirname "$0")/../.."
ip link set lo up
# NATMap upstream checkout for the socket-boundary test (WSL host fact)
export NATMAP_SOURCE="${NATMAP_SOURCE:-/home/eric/natmap-20260214}"
hosts=$(mktemp -d /tmp/homepublish-hosts-XXXXXX)
cleanup() { umount /etc/hosts; rm -rf "$hosts"; }
trap cleanup EXIT
printf '127.0.0.1 localhost stun-test.innonext.win\n' > "$hosts/hosts"
mount --bind "$hosts/hosts" /etc/hosts
exec_tests() {
 python3 -B homepublish/tests/test-token-validation.py -v || return $?
 python3 -B homepublish/tests/test-publication-security.py -v || return $?
 for test in publication socket-boundary lifecycle recipe package source-cleanup; do
  python3 -B "homepublish/tests/test-$test.py" -v || return $?
 done
}
exec_tests 2>&1 | tee docs/homepublish-publication-security-final.txt
