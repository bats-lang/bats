#!/bin/sh
# Every field of bats.toml that bats reads, and whether a changed one makes a
# restored build/ stale (bats-lang/bats#381): `unsafe` is the one field that
# reaches the emitted modules (a $UNSAFE block is kept in an unsafe package and
# an error in a safe one), and one reader gives it to emission and to
# validation, whole (a manifest over 4096 bytes made emission read a package
# with `unsafe = true` as safe). Each field the build does not read leaves a
# restored build/ as it is: no module is made again and build/ is the cold
# build's. A dependency's constraint and a path dependency reach build/ only
# through the sources in bats_modules, which are keyed by content.
# usage: tests/toml-fields/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_CACHE_DIR

# patsopt runs, not counting the entry's generated module, which every build
# makes again
ran() { grep -a -- '+ patsopt' "$1" | grep -av '_bats_entry_' | grep -avc '(cached)' || true; }
build() { # <dir> <log> [bats arguments]: -v build in <dir>, which must succeed
  d=$1; l=$2; shift 2
  (cd "$d" && "$BATS" -v build --only debug --only native "$@") > "$l" 2>&1 || { echo "FAIL: build in $d"; cat "$l"; exit 1; }
  sleep 1
}
program() { (cd "$1" && ./dist/debug/tf); }
# the files of build/ and their digests, without what is not the build's (the
# records of what passed, the stash of another mark, the graph of one run, and
# the objects, whose debug info names the directory they were made in)
tree() { (cd "$1/build" && find . -type f ! -path './.bats_valid/*' ! -path './.stash/*' ! -name .bats_graph ! -name '*.o' | LC_ALL=C sort | while read -r f; do printf '%s %s\n' "$(cksum < "$f")" "$f"; done); }

module() { # <dir> <bats.toml text>: a binary of two modules
  rm -rf "$1"; mkdir -p "$1/src/bin"
  printf '%s' "$2" > "$1/bats.toml"
  printf '#include "share/atspre_staload.hats"\n\n#pub fn f (): int\n\nimplement f () = 1\n' > "$1/src/m.bats"
  printf '#include "share/atspre_staload.hats"\nstaload "m.sats"\nimplement main0 () = println! (f ())\n' > "$1/src/bin/tf.bats"
}

# Fields the build does not read: a build/ made under the first manifest and
# restored under the second is kept whole, and is the build/ a cold build
# under the second makes
base='[package]
name = "tf"
kind = "bin"
'
unchanged() { # <name> <second manifest>
  module "$TMP/a" "$base"
  build "$TMP/a" "$TMP/a.log"
  module "$TMP/b" "$2"
  cp -R "$TMP/a/build" "$TMP/b/build"
  build "$TMP/b" "$TMP/b.log"
  [ "$(ran "$TMP/b.log")" = 0 ] || { echo "FAIL: $1: a restored build/ made $(ran "$TMP/b.log") modules again"; cat "$TMP/b.log"; exit 1; }
  if grep -aq '^bats: dropping build/' "$TMP/b.log"; then echo "FAIL: $1: build/ was dropped"; cat "$TMP/b.log"; exit 1; fi
  module "$TMP/c" "$2"
  build "$TMP/c" "$TMP/c.log"
  tree "$TMP/b" > "$TMP/b.tree"; tree "$TMP/c" > "$TMP/c.tree"
  cmp -s "$TMP/b.tree" "$TMP/c.tree" || { echo "FAIL: $1: the restored build/ is not the cold build's"; diff "$TMP/b.tree" "$TMP/c.tree"; exit 1; }
  [ "$(program "$TMP/b")" = 1 ] || { echo "FAIL: $1: the program"; exit 1; }
}
unchanged "name" '[package]
name = "another"
kind = "bin"
'
unchanged "version, trunk and ats2" '[package]
name = "tf"
kind = "bin"
version = "1.2.3"
trunk = "master"
ats2 = "x"
'
unchanged "tables nothing reads" '[package]
name = "tf"
kind = "bin"

[build]
opt = 3

[test]
timeout = 9
'
unchanged "unsafe = true with no unsafe block" '[package]
name = "tf"
kind = "bin"
unsafe = true
'

# kind: bats build refuses a library whatever build/ holds, and a bin again
# builds from the same build/ with nothing made again
module "$TMP/k" "$base"
build "$TMP/k" "$TMP/k1.log"
printf '[package]\nname = "tf"\nkind = "lib"\n' > "$TMP/k/bats.toml"
rc=0; (cd "$TMP/k" && "$BATS" build --only debug --only native) > "$TMP/k2.out" 2> "$TMP/k2.err" || rc=$?
[ "$rc" = 1 ] && [ "$(cat "$TMP/k2.err")" = "error: 'bats build' is only for binary packages (kind = \"bin\")" ] || { echo "FAIL: kind = lib built (rc $rc)"; cat "$TMP/k2.err"; exit 1; }
printf '%s' "$base" > "$TMP/k/bats.toml"
build "$TMP/k" "$TMP/k3.log"
[ "$(ran "$TMP/k3.log")" = 0 ] || { echo "FAIL: kind back to bin made modules again"; cat "$TMP/k3.log"; exit 1; }

# unsafe, the field the emitted modules depend on: a $UNSAFE block is kept
# under unsafe = true; the flag false over a restored build/ is an error and
# makes no program; true again builds
unsafe_module() { # <dir> <bats.toml text>
  module "$1" "$2"
  printf '#include "share/atspre_staload.hats"\n\n#pub fn f (): int\n\n$UNSAFE begin\n%%{\nstatic int unused_helper (void) { return 3; }\n%%}\nend\n\nimplement f () = 1\n' > "$1/src/m.bats"
}
yes_unsafe='[package]
name = "tf"
kind = "bin"
unsafe = true
'
unsafe_module "$TMP/u" "$yes_unsafe"
build "$TMP/u" "$TMP/u1.log"
printf '[package]\nname = "tf"\nkind = "bin"\nunsafe = false\n' > "$TMP/u/bats.toml"
rm -f "$TMP/u/dist/debug/tf"
rc=0; (cd "$TMP/u" && "$BATS" build --only debug --only native) > "$TMP/u2.out" 2> "$TMP/u2.err" || rc=$?
[ "$rc" = 1 ] && grep -aq '^error: error: .UNSAFE requires .unsafe = true. in bats.toml' "$TMP/u2.err" && [ ! -e "$TMP/u/dist/debug/tf" ] || { echo "FAIL: unsafe = false over a restored build/ (rc $rc)"; cat "$TMP/u2.err"; exit 1; }
printf '%s' "$yes_unsafe" > "$TMP/u/bats.toml"
build "$TMP/u" "$TMP/u3.log"
[ "$(program "$TMP/u")" = 1 ] || { echo "FAIL: unsafe again: the program"; exit 1; }

# a manifest over 4096 bytes: emission reads `unsafe = true` as validation does
{ for i in $(seq 1 100); do printf '# a line of padding that makes the manifest longer than the buffer it was once read in\n'; done; printf '%s' "$yes_unsafe"; } > "$TMP/big.toml"
[ "$(wc -c < "$TMP/big.toml")" -gt 8192 ] || { echo "FAIL: the manifest is not large"; exit 1; }
unsafe_module "$TMP/g" "$(cat "$TMP/big.toml")"
build "$TMP/g" "$TMP/g1.log"
[ "$(program "$TMP/g")" = 1 ] || { echo "FAIL: large manifest: the program"; exit 1; }

# [dependencies]: a constraint reaches build/ through the version it picks
# (sources in bats_modules, keyed by content), a path dependency through the
# directory it names
mkdir -p "$TMP/repo"
publish() { # <name> <commit date> <value>: a library whose f is value
  rm -rf "$TMP/p"; mkdir -p "$TMP/p/src"
  printf '[package]\nname = "%s"\nkind = "lib"\n' "$1" > "$TMP/p/bats.toml"
  printf '#pub fun f (): int\n\nimplement f () = %s\n' "$3" > "$TMP/p/src/lib.bats"
  printf 'build/\ndist/\ndocs/\nbats_modules/\nbats.lock\n' > "$TMP/p/.gitignore"
  (cd "$TMP/p" && git init -q -b main . && git add -A &&
   GIT_COMMITTER_DATE="$2" git -c user.name=t -c user.email=t@t commit -q -m "$2" &&
   "$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1) || { echo "FAIL: upload $1"; cat "$TMP/up.log"; exit 1; }
}
publish tfdep "2026-01-03T00:00:03Z" 1
publish tfdep "2026-01-04T00:00:04Z" 2
dependent() { # <dir> <[dependencies] value>
  rm -rf "$1/src"; mkdir -p "$1/src/bin"
  printf '[package]\nname = "tf"\nkind = "bin"\n\n[dependencies]\n"tfdep" = %s\n' "$2" > "$1/bats.toml"
  printf '#use tfdep as D\n\nimplement main0 () = println! ($D.f ())\n' > "$1/src/bin/tf.bats"
}
# with a bats.lock, a constraint that rules out the locked version is an error
# (what the build/ holds is never taken for the new constraint's), and after
# the relock the other version's sources replace the old ones, so build/ is
# made again from them; without a lock an installed package is kept, as the
# Rust bats did
mkdir -p "$TMP/d"
dependent "$TMP/d" '""'
(cd "$TMP/d" && "$BATS" lock --repository "$TMP/repo") > "$TMP/d0.log" 2>&1 || { echo "FAIL: lock"; cat "$TMP/d0.log"; exit 1; }
build "$TMP/d" "$TMP/d1.log" --repository "$TMP/repo"
[ "$(program "$TMP/d")" = 2 ] || { echo "FAIL: constraint none: the newest"; exit 1; }
printf '[package]\nname = "tf"\nkind = "bin"\n\n[dependencies]\n"tfdep" = "!= 2026.1.4.4"\n' > "$TMP/d/bats.toml"
rc=0; (cd "$TMP/d" && "$BATS" build --only debug --only native --repository "$TMP/repo") > "$TMP/d2.out" 2> "$TMP/d2.err" || rc=$?
[ "$rc" = 1 ] && grep -aq 'which does not meet' "$TMP/d2.err" || { echo "FAIL: a constraint that rules out the locked version (rc $rc)"; cat "$TMP/d2.err"; exit 1; }
(cd "$TMP/d" && "$BATS" lock --repository "$TMP/repo") > "$TMP/d3.log" 2>&1 || { echo "FAIL: relock"; cat "$TMP/d3.log"; exit 1; }
build "$TMP/d" "$TMP/d4.log" --repository "$TMP/repo"
[ "$(program "$TMP/d")" = 1 ] || { echo "FAIL: constraint != the newest: the program"; cat "$TMP/d4.log"; exit 1; }
printf '[package]\nname = "tf"\nkind = "bin"\n\n[dependencies]\n"tfdep" = ""\n' > "$TMP/d/bats.toml"
(cd "$TMP/d" && "$BATS" lock --repository "$TMP/repo") > "$TMP/d5.log" 2>&1 || { echo "FAIL: relock again"; cat "$TMP/d5.log"; exit 1; }
build "$TMP/d" "$TMP/d6.log" --repository "$TMP/repo"
[ "$(program "$TMP/d")" = 2 ] || { echo "FAIL: constraint dropped: the program"; cat "$TMP/d6.log"; exit 1; }

mkdir -p "$TMP/pd/one/src" "$TMP/pd/two/src" "$TMP/pd/app/src/bin"
for n in one two; do printf '[package]\nname = "tfdep"\nkind = "lib"\n' > "$TMP/pd/$n/bats.toml"; done
printf '#pub fun f (): int\n\nimplement f () = 7\n' > "$TMP/pd/one/src/lib.bats"
printf '#pub fun f (): int\n\nimplement f () = 8\n' > "$TMP/pd/two/src/lib.bats"
printf '#use tfdep as D\n\nimplement main0 () = println! ($D.f ())\n' > "$TMP/pd/app/src/bin/tf.bats"
printf '[package]\nname = "tf"\nkind = "bin"\n\n[dependencies]\n"tfdep" = { path = "../one" }\n' > "$TMP/pd/app/bats.toml"
build "$TMP/pd/app" "$TMP/pd1.log"
[ "$(program "$TMP/pd/app")" = 7 ] || { echo "FAIL: path dependency one"; exit 1; }
printf '[package]\nname = "tf"\nkind = "bin"\n\n[dependencies]\n"tfdep" = { path = "../two" }\n' > "$TMP/pd/app/bats.toml"
build "$TMP/pd/app" "$TMP/pd2.log"
[ "$(program "$TMP/pd/app")" = 8 ] || { echo "FAIL: path dependency two: the program"; cat "$TMP/pd2.log"; exit 1; }
echo "toml-fields: ok"
