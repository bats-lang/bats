#!/bin/sh
# bats lock writes "<package> <version> <sha256 of the archive>" per line,
# as the Rust bats does (lock::resolve_all). It used to write 0 for the
# hash.
# usage: tests/lock-hash/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$(cd "$2" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if command -v sha256sum >/dev/null 2>&1; then SUM="sha256sum"; else SUM="shasum -a 256"; fi
mkdir -p "$TMP/app/src"
printf '[package]\nname = "lockhash"\nkind = "lib"\n\n[dependencies]\n"toml" = ""\n' > "$TMP/app/bats.toml"
printf '#use toml as T\n\n#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/app/src/lib.bats"
cd "$TMP/app"
"$BATS" lock --repository "$REPO" > "$TMP/lock.log" 2>&1 || { echo "FAIL: lock"; cat "$TMP/lock.log"; exit 1; }
[ -s bats.lock ] || { echo "FAIL: empty bats.lock"; exit 1; }
while read -r pkg ver hash; do
  arc="$REPO/$pkg/$(echo "$pkg" | tr / _)_$ver.bats"
  want=$($SUM < "$arc" | cut -d' ' -f1)
  [ "$hash" = "$want" ] || { echo "FAIL: $pkg $ver: hash $hash, archive $want"; exit 1; }
done < bats.lock
echo "lock-hash: ok"
