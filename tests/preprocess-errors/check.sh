#!/bin/sh
# check, build, run and test stop before patsopt when a package breaks a
# rule, printing every error as the Rust bats does (project::preprocess_all,
# emit::validate, BatsError::display_fancy): the package's shared modules,
# then its dependencies, src/lib.bats and src/bin/, one after the other,
# each error with its file, line, column and source line. A %{ ... %}
# block outside $UNSAFE used to pass unnoticed. expected.txt is what the
# Rust bats prints for this package.
# usage: tests/preprocess-errors/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
p=$TMP/p
mkdir -p "$p/src/bin" "$p/bats_modules/dep/src"
printf '[package]\nname = "pp"\nkind = "bin"\n' > "$p/bats.toml"
printf '[package]\nname = "dep"\nkind = "lib"\nunsafe = true\n' > "$p/bats_modules/dep/bats.toml"
printf 'fn a (): int = $extfcall(int, "a")\n' > "$p/src/zeta.bats"
printf '#include "share/atspre_staload.hats"\n\nfn b (): int =\n  $extval(int, "b")\n\n%%{\nint k;\n%%}\n' > "$p/src/alpha.bats"
printf 'fn c (): int = $extfcall(int, "c")\n$UNSAFE begin\nfn q (): int = 1\nend\n#pub prfun lemma (): void\n' > "$p/src/lib.bats"
printf 'fn d (): int = 4\n' > "$p/bats_modules/dep/src/lib.bats"
printf '#use nothere as N\n$UNSAFE begin\nfn e (): int = 1\nend\n' > "$p/bats_modules/dep/src/lib2.bats"
printf 'fn g (): int = $extfcall(int, "g")\nimplement main0 () = ()\n' > "$p/src/bin/m.bats"
for cmd in check build; do
  rc=0
  (cd "$p" && NO_COLOR=1 "$BATS" $cmd) > "$TMP/out" 2> "$TMP/err" || rc=$?
  [ "$rc" = 1 ] || { echo "FAIL: $cmd: rc $rc"; cat "$TMP/err"; exit 1; }
  cmp -s "$TMP/err" "$HERE/expected.txt" || { echo "FAIL: $cmd"; diff "$HERE/expected.txt" "$TMP/err"; exit 1; }
  [ ! -d "$p/build" ] || { echo "FAIL: $cmd: ran patsopt"; exit 1; }
done
echo "preprocess-errors: ok"
