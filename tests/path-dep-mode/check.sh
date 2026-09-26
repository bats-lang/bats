#!/bin/sh
# A path dependency's files keep their permission bits when copied into
# bats_modules/, as Rust's fs::copy does; they used to be 0644.
# usage: tests/path-dep-mode/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/app/src/bin" "$TMP/dep/src"
printf '[package]\nname = "app"\nkind = "bin"\n\n[dependencies]\ndep = { path = "../dep" }\n' > "$TMP/app/bats.toml"
printf '#use dep as D\nimplement main0 () = ()\n' > "$TMP/app/src/bin/app.bats"
printf '[package]\nname = "dep"\nkind = "lib"\n' > "$TMP/dep/bats.toml"
printf 'fn d (): int = 1\n' > "$TMP/dep/src/lib.bats"
printf '#!/bin/sh\n' > "$TMP/dep/tool.sh"
chmod 751 "$TMP/dep/tool.sh"
chmod 600 "$TMP/dep/src/lib.bats"
cd "$TMP/app"
"$BATS" check > log 2>&1 || { echo "FAIL: check"; cat log; exit 1; }
mode() { ls -l "$1" | cut -c1-10; }
[ "$(mode bats_modules/dep/tool.sh)" = "-rwxr-x--x" ] || { echo "FAIL: tool.sh $(mode bats_modules/dep/tool.sh)"; exit 1; }
[ "$(mode bats_modules/dep/src/lib.bats)" = "-rw-------" ] || { echo "FAIL: lib.bats $(mode bats_modules/dep/src/lib.bats)"; exit 1; }
echo "path-dep-mode: ok"
