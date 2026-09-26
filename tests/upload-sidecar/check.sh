#!/bin/sh
# bats upload writes "<sha256 of the archive>  <archive filename>" next
# to the archive, as the Rust bats did (and as sha256sum prints it). It
# used to hash a zero-padded 512 KiB buffer with a broken SHA-256 and
# write the whole path.
# usage: tests/upload-sidecar/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if command -v sha256sum >/dev/null 2>&1; then SUM="sha256sum"; else SUM="shasum -a 256"; fi
mkdir -p "$TMP/repo" "$TMP/lib/src"
printf '[package]\nname = "sidecar"\nkind = "lib"\n' > "$TMP/lib/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/lib/src/lib.bats"
printf 'build/\ndist/\ndocs/\n' > "$TMP/lib/.gitignore"
cd "$TMP/lib"
git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm t
"$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1 || { echo "FAIL: upload"; cat "$TMP/up.log"; exit 1; }
cd "$TMP/repo/sidecar"
arc=$(ls *.bats)
want=$($SUM "$arc")
got=$(cat "$arc.sha256")
[ "$got" = "$want" ] || { echo "FAIL: sidecar is '$got', want '$want'"; exit 1; }
echo "upload-sidecar: ok"
