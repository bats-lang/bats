#!/bin/sh
# --only narrows the build matrix (profiles debug, release; targets
# native, wasm); an axis no --only names keeps all its values. --only
# wasm used to build debug only, and --only native was ignored.
# usage: tests/build-only/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "bo"\nkind = "bin"\n' > "$TMP/p/bats.toml"
printf '#target native\n\nimplement main0 () = ()\n' > "$TMP/p/src/bin/cli.bats"
printf '(* the web client *)\n#target wasm\n\nimplement main0 () = ()\n' > "$TMP/p/src/bin/web.bats"
cd "$TMP/p"
case_() { # <expected files> <flags...>
  want=$1; shift
  rm -rf build dist
  "$BATS" build "$@" > out 2> err || { echo "FAIL: build $*"; cat err out; exit 1; }
  got=$(find dist -type f 2>/dev/null | sort | tr '\n' ' ')
  [ "$got" = "$want" ] || { echo "FAIL: build $*: got $got"; exit 1; }
}
case_ "dist/debug/cli dist/debug/web.wasm dist/release/cli dist/release/web.wasm "
case_ "dist/debug/web.wasm dist/release/web.wasm " --only wasm
case_ "dist/debug/cli dist/release/cli " --only native
case_ "dist/debug/cli dist/debug/web.wasm " --only debug
case_ "dist/release/web.wasm " --only release --only wasm
case_ "dist/debug/cli dist/debug/web.wasm dist/release/cli dist/release/web.wasm " --only native --only wasm
echo "build-only: ok"
