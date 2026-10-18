#!/bin/sh
# Standalone host validation only: no make, deployment, production config or DNS.
set -eu
pkg=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
archive=${1:?usage: verify.sh /absolute/path/ddns-go-6.17.7.tar.gz}
expected=f7001004e092d9641aad5a94158e0b4cae4a53a7f5c7d96d5c6af3d246c56fcc
actual=$(sha256sum "$archive"); actual=${actual%% *}
[ "$actual" = "$expected" ] || { printf 'Source hash mismatch\n' >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-$HOME}/ddns-go-local-api.XXXXXX")
printf 'Private validation workspace: %s\n' "$work"
# Retain workspace/binary and test output for inspection.
tar xzf "$archive" -C "$work"
cd "$work/ddns-go-6.17.7"
for p in "$pkg"/patches/*.patch; do patch -p1 --fuzz=0 < "$p"; done
go test -race ./localapi ./dns
go test ./...
go vet ./...
go build -trimpath -ldflags '-X main.version=6.17.7-localapi1' -o "$work/ddns-go" .
"$work/ddns-go" -v
sh "$pkg/tests/test-init.sh"
printf 'PASS fresh pinned archive, patches, race tests, full unit suite, vet, standalone build; binary: %s/ddns-go\n' "$work"
