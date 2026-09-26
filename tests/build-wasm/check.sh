#!/bin/sh
# A wasm binary is linked to dist/<profile>/<name>.wasm and reported as
# "built <path> (wasm)" on stderr, as Rust's build does (out_dir is
# dist/debug or dist/release); it used to go to dist/wasm/app.wasm with
# "  built: dist/wasm/app.wasm" on stdout.
# usage: tests/build-wasm/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "wz"\nkind = "bin"\n' > "$TMP/p/bats.toml"
printf '#target wasm binary\n\nimplement main0 () = ()\n' > "$TMP/p/src/bin/web.bats"
cd "$TMP/p"
"$BATS" build > out 2> err || { echo "FAIL: build"; cat err out; exit 1; }
[ "$(cat err)" = "built ./dist/debug/web.wasm (wasm)
built ./dist/release/web.wasm (wasm)" ] || { echo "FAIL: stderr"; cat err; exit 1; }
[ ! -s out ] || { echo "FAIL: stdout"; cat out; exit 1; }
for f in dist/debug/web.wasm dist/release/web.wasm; do
  [ "$(head -c 4 "$f" | od -An -c | tr -d ' ')" = '\0asm' ] || { echo "FAIL: $f is not wasm"; exit 1; }
done
[ ! -e dist/wasm ] || { echo "FAIL: dist/wasm exists"; exit 1; }
echo "build-wasm: ok"
