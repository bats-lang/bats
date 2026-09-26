#!/bin/sh
# bats upload hashes the whole archive for its sidecar, whatever its size,
# as the Rust bats does. It used to hash only the first 512 KiB, so an
# archive larger than that got a wrong sidecar.
# usage: tests/upload-large-archive/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if command -v sha256sum >/dev/null 2>&1; then SUM="sha256sum"; else SUM="shasum -a 256"; fi
mkdir -p "$TMP/repo" "$TMP/lib/src"
printf '[package]\nname = "large"\nversion = "1.0.0"\nkind = "lib"\n' > "$TMP/lib/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/lib/src/lib.bats"
# About 3 MB of hex from random bytes: it compresses to well over 512 KiB
head -c 1500000 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$TMP/lib/src/data.txt"
cd "$TMP/lib"
"$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1 || { echo "FAIL: upload"; cat "$TMP/up.log"; exit 1; }
cd "$TMP/repo/large"
size=$(wc -c < large_1.0.0.bats)
[ "$size" -gt 1048576 ] || { echo "FAIL: the archive is only $size bytes"; exit 1; }
$SUM -c large_1.0.0.bats.sha256 > /dev/null || { echo "FAIL: the sidecar does not match the archive"; exit 1; }
echo "upload-large-archive: ok"
