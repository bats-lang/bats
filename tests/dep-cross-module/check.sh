#!/bin/sh
# A dependency's modules call each other's #pub functions (as bridge's
# do). The Rust bats renamed each dependency file's #pub names to
# __BATS__<pkg>_<name> on its own, so a call from another module of the
# same package no longer resolved ("the dynamic identifier [helper] is
# unrecognized"); this compiler does not rename them (an allowed
# divergence).
# usage: tests/dep-cross-module/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin" "$TMP/p/bats_modules/dq/src"
printf '[package]\nname = "mm"\nkind = "bin"\n' > "$TMP/p/bats.toml"
printf '[package]\nname = "dq"\nkind = "lib"\n' > "$TMP/p/bats_modules/dq/bats.toml"
printf '#pub fn helper (): int\n\nimplement helper () = 41\n' > "$TMP/p/bats_modules/dq/src/util.bats"
printf '#include "share/atspre_staload.hats"\nstaload "./util.sats"\n#pub fn one (): int\n\nimplement one () = helper () + 1\n' > "$TMP/p/bats_modules/dq/src/lib.bats"
printf '#include "share/atspre_staload.hats"\n#use dq as D\nimplement main0 () = println! ($D.one ())\n' > "$TMP/p/src/bin/mm.bats"
cd "$TMP/p"
"$BATS" build > out 2> err || { echo "FAIL: build"; cat err out; exit 1; }
[ "$(./dist/debug/mm)" = "42" ] || { echo "FAIL: output $(./dist/debug/mm)"; exit 1; }
echo "dep-cross-module: ok"
