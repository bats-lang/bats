#!/bin/sh
# A no-change check or build runs no patsopt and no cc on a dependency
# that lives under a namespace directory (bats_modules/<namespace>/<name>,
# as bridge and dom do), as it runs none on a plain one (bats-lang/bats
# #254): the namespaced branch ran patsopt on the dependency's lib.dats
# every time, with no freshness test, which made its C newer than its
# object and ran cc again. Checked for one native and one wasm binary,
# which makes check two passes. The entry's generated module is made again
# by every build, and is not counted.
# usage: tests/build-ns-deps/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_CACHE_DIR
mkdir -p "$TMP/app/src/bin" "$TMP/mine/src"
printf '[package]\nname = "app"\nkind = "bin"\n\n[dependencies]\n"ns.example/mine" = { path = "../mine" }\n' > "$TMP/app/bats.toml"
printf '[package]\nname = "mine"\nkind = "lib"\n' > "$TMP/mine/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 7\n' > "$TMP/mine/src/lib.bats"
printf '#target native\n#use ns.example/mine as M\n\nimplement main0 () = println! ("got ", $M.f ())\n' > "$TMP/app/src/bin/tool.bats"
printf '#target wasm binary\n#use ns.example/mine as M\n\nimplement main0 () = let val _ = $M.f () in () end\n' > "$TMP/app/src/bin/web.bats"
cd "$TMP/app"
# Freshness is by whole-second mtimes: each run ends a second on
run() { # <log> <command...>
  l=$1; shift
  "$BATS" -v "$@" > "$l" 2>&1 || { echo "FAIL: $*"; cat "$l"; exit 1; }
  sleep 1
}
# runs of a tool that are not the entry's generated module
count() { grep -a -- "+ $2" "$1" | grep -av '_bats_entry_' | grep -avc '(cached)' || true; }
run cold.log check
[ "$(count cold.log patsopt)" -ge 1 ] || { echo "FAIL: a cold check ran no patsopt on the dependency"; cat cold.log; exit 1; }
# one more run lets the mtimes of a check that ended in the second its C was made in settle
run settle.log check
for i in 1 2; do
  run again$i.log check
  [ "$(count again$i.log patsopt)" = 0 ] || { echo "FAIL: a no-change check ran patsopt on the dependency"; cat again$i.log; exit 1; }
  [ "$(count again$i.log cc)" = 0 ] || { echo "FAIL: a no-change check ran cc on the dependency"; cat again$i.log; exit 1; }
done
run b0.log build --only debug --only native
run b1.log build --only debug --only native
run b2.log build --only debug --only native
[ "$(count b2.log patsopt)" = 0 ] || { echo "FAIL: a no-change build ran patsopt on the dependency"; cat b2.log; exit 1; }
[ "$(count b2.log cc)" = 0 ] || { echo "FAIL: a no-change build ran cc on the dependency"; cat b2.log; exit 1; }
echo "build-ns-deps: ok"
