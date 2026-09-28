#!/bin/sh
# A dependency's module other than its lib uses another package (as
# gestures' decode module uses arith): the binary links and dynloads
# that package too. The closure read only each dependency's lib.dats,
# so the package was left out and the link failed ("undefined reference
# to ...low_byte").
# usage: tests/dep-module-use/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
p=$TMP/p
mkdir -p "$p/src/bin" "$p/bats_modules/q/src" "$p/bats_modules/r/src"
printf '[package]\nname = "mu"\nkind = "bin"\n' > "$p/bats.toml"
printf '[package]\nname = "q"\nkind = "lib"\n' > "$p/bats_modules/q/bats.toml"
printf '[package]\nname = "r"\nkind = "lib"\n' > "$p/bats_modules/r/bats.toml"
# r has a module val, set only by its dynload
printf '#include "share/atspre_staload.hats"\n\nval cell = ref<int>(41)\n\n#pub fn get (): int\n\nimplement get () = !cell\n' > "$p/bats_modules/r/src/lib.bats"
# q uses r only from util.bats, not from lib.bats
printf '#include "share/atspre_staload.hats"\n#use r as R\n\n#pub fn helper (): int\n\nimplement helper () = $R.get ()\n' > "$p/bats_modules/q/src/util.bats"
printf '#include "share/atspre_staload.hats"\nstaload "./util.sats"\n\n#pub fn one (): int\n\nimplement one () = helper () + 1\n' > "$p/bats_modules/q/src/lib.bats"
printf '#include "share/atspre_staload.hats"\n#use q as Q\nimplement main0 () = println! ($Q.one ())\n' > "$p/src/bin/mu.bats"
cd "$p"
"$BATS" build --only native > out 2> err || { echo "FAIL: build"; cat err out; exit 1; }
[ "$(./dist/debug/mu)" = "42" ] || { echo "FAIL: output $(./dist/debug/mu)"; exit 1; }
echo "dep-module-use: ok"
