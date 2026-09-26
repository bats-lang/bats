#!/bin/sh
# Before building, a { path = "<dir>" } dependency is copied afresh into
# bats_modules/<name> without its build, dist, docs and bats_modules
# directories (at any depth), as the Rust bats's copy_path_dep does; a
# missing directory or src/lib.bats is an error.
# usage: tests/build-path-deps/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/app/src/bin" "$TMP/app/bats_modules/pmine/old" "$TMP/pmine/src/sub/docs" "$TMP/pmine/src/sub/keep" "$TMP/pmine/build"
printf '[package]\nname = "papp"\nkind = "bin"\n\n[dependencies]\n"pmine" = { path = "../pmine" }\n' > "$TMP/app/bats.toml"
printf '#use pmine as M\n\nimplement main0 () = println! ("got ", $M.f ())\n' > "$TMP/app/src/bin/papp.bats"
printf '[package]\nname = "pmine"\nkind = "lib"\n' > "$TMP/pmine/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 7\n' > "$TMP/pmine/src/lib.bats"
echo stale > "$TMP/app/bats_modules/pmine/old/stale"
echo skipped > "$TMP/pmine/build/x"
echo skipped > "$TMP/pmine/src/sub/docs/y"
head -c 150000 /dev/zero | tr '\0' 'q' > "$TMP/pmine/src/sub/keep/big"
cd "$TMP/app"
"$BATS" build --only debug --only native > build.log 2>&1 || { echo "FAIL: build"; cat build.log; exit 1; }
[ "$(./dist/debug/papp)" = "got 7" ] || { echo "FAIL: the program"; exit 1; }
got=$(cd bats_modules/pmine && find . -type f | sort | tr '\n' ' ')
[ "$got" = "./bats.toml ./src/lib.bats ./src/sub/keep/big " ] || { echo "FAIL: copied $got"; exit 1; }
cmp -s "$TMP/pmine/src/sub/keep/big" bats_modules/pmine/src/sub/keep/big || { echo "FAIL: big differs"; exit 1; }
rm "$TMP/pmine/src/lib.bats"
rc=0; "$BATS" build --only debug --only native > /dev/null 2> err || rc=$?
[ "$rc" = 1 ] && [ "$(cat err)" = "error: path dependency 'pmine': no src/lib.bats found in '../pmine'" ] || { echo "FAIL: no lib.bats"; cat err; exit 1; }
rm -rf "$TMP/pmine"
rc=0; "$BATS" build --only debug --only native > /dev/null 2> err || rc=$?
[ "$rc" = 1 ] && [ "$(cat err)" = "error: path dependency 'pmine': directory '../pmine' does not exist" ] || { echo "FAIL: no directory"; cat err; exit 1; }
echo "build-path-deps: ok"
