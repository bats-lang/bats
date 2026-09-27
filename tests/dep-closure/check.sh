#!/bin/sh
# A binary dynloads and links every dependency its code reaches through
# staloads: those its entry staloads, those the package's modules
# staload, and those their dependencies staload, to any depth, each
# once. Here the entry uses a, a uses b, b uses c, a module of the
# package uses d, and d uses c again; each has a module val (initialized
# only by its dynload) that the output shows.
# usage: tests/dep-closure/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
p=$TMP/p
mkdir -p "$p/src/bin"
printf '[package]\nname = "dc"\nkind = "bin"\n' > "$p/bats.toml"
dep() { # <name> <value> [<used dep>]
  mkdir -p "$p/bats_modules/$1/src"
  printf '[package]\nname = "%s"\nkind = "lib"\n' "$1" > "$p/bats_modules/$1/bats.toml"
  if [ $# -ge 3 ]; then
    printf '#include "share/atspre_staload.hats"\n#use %s as U\n\nval cell = ref<int>(%s)\n\n#pub fn get (): int\n\nimplement get () = !cell + $U.get ()\n' "$3" "$2" > "$p/bats_modules/$1/src/lib.bats"
  else
    printf '#include "share/atspre_staload.hats"\n\nval cell = ref<int>(%s)\n\n#pub fn get (): int\n\nimplement get () = !cell\n' "$2" > "$p/bats_modules/$1/src/lib.bats"
  fi
}
dep c 1
dep b 10 c
dep a 100 b
dep d 1000 c
printf '#include "share/atspre_staload.hats"\n#use d as D\n\n#pub fn via_d (): int\n\nimplement via_d () = $D.get ()\n' > "$p/src/shared.bats"
printf '#include "share/atspre_staload.hats"\n#use a as A\nstaload "shared.sats"\n\nimplement main0 () = println! ($A.get () + via_d ())\n' > "$p/src/bin/dc.bats"
cd "$p"
"$BATS" build --only native --only debug > out 2> err || { echo "FAIL: build"; cat err out; exit 1; }
[ "$(./dist/debug/dc)" = "1112" ] || { echo "FAIL: output $(./dist/debug/dc), not 1112"; exit 1; }
n=$(grep -c 'dynload "./bats_modules/c/src/lib.dats"' build/_bats_entry_dc.dats)
[ "$n" = 1 ] || { echo "FAIL: c dynloaded $n times"; exit 1; }
echo "dep-closure: ok"
