#!/bin/sh
# A module that staloads "_bats_inputs.sats" gets the digest of the
# project's inputs (bats-lang/bats#267): bats_inputs_sha256 (), 64 hex
# digits of the sha256 over bats.toml, bats.lock (when there is one) and
# every src/**/*.bats. It is the same under another commit, in another
# directory and with other mtimes (and without git), and another for a
# changed byte of any of them, a new file under src/ and a file taken
# away. A project that does not staload it (though its sources write the
# name in a comment and a string) gets no module and runs nothing.
# usage: tests/build-inputs/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_COMMIT
export BATS_CACHE_DIR="$TMP/cache"
P=$TMP/p
mkdir -p "$P/src/bin/sub" "$P/src/deep"
printf '[package]\nname = "inp"\nkind = "bin"\n' > "$P/bats.toml"
printf 'build/\ndist/\n' > "$P/.gitignore"
printf '#include "share/atspre_staload.hats"\n\n#pub fn h (): int\n\nimplement h () = 1\n' > "$P/src/other.bats"
printf '#include "share/atspre_staload.hats"\n\n#pub fn g (): int\n\nimplement g () = 2\n' > "$P/src/deep/nested.bats"
printf '#include "share/atspre_staload.hats"\nstaload I = "_bats_inputs.sats"\nstaload "other.sats"\nimplement main0 () = let\n  val () = println! ($I.bats_inputs_sha256 ())\nin println! (h ()) end\n' > "$P/src/bin/inp.bats"
cd "$P"
git init -q -b main .
git add -A && git -c user.name=t -c user.email=t@t commit -q -m first
build() { # <dir> <log>
  (cd "$1" && "$BATS" build --only debug --only native) > "$2" 2>&1 || { echo "FAIL: build"; cat "$2"; exit 1; }
}
digest() { # <dir>: the digest the project prints, checked to be 64 hex digits
  d=$("$1/dist/debug/inp" | head -n 1)
  printf '%s' "$d" | grep -q -E '^[0-9a-f]{64}$' || { echo "FAIL: '$d' is not 64 hex digits"; exit 1; }
  printf '%s' "$d"
}
differs() { # <what> <digest before> <digest now>
  [ "$2" != "$3" ] || { echo "FAIL: the digest did not change with $1"; exit 1; }
}
build "$P" "$TMP/1.log"
d1=$(digest "$P")
# the digest is what the listing says: sha256 of "bats-inputs 1" and a
# line "<path> <sha256>" for each input, in byte order of path
want=$({ echo "bats-inputs 1"; { echo bats.toml; find src -type f -name '*.bats'; } | LC_ALL=C sort | while read -r f; do
  printf '%s ' "$f"; cat "$f" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -d' ' -f1; done; } | { sha256sum 2>/dev/null || shasum -a 256; } | cut -d' ' -f1)
[ "$d1" = "$want" ] || { echo "FAIL: digest $d1, listing says $want"; exit 1; }
# the same under another commit
sleep 1
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m second
build "$P" "$TMP/2.log"
[ "$(digest "$P")" = "$d1" ] || { echo "FAIL: a new commit changed the digest"; exit 1; }
# the same from scratch, and from a copy at another path with other mtimes
rm -rf build dist
build "$P" "$TMP/3.log"
[ "$(digest "$P")" = "$d1" ] || { echo "FAIL: a build from scratch changed the digest"; exit 1; }
Q=$TMP/elsewhere/q
mkdir -p "$TMP/elsewhere"
cp -R "$P" "$Q"
rm -rf "$Q/build" "$Q/dist" "$Q/.git"
find "$Q" -exec touch -t 200001010000 {} +
build "$Q" "$TMP/4.log"
[ "$(digest "$Q")" = "$d1" ] || { echo "FAIL: another directory, other mtimes and no git changed the digest"; exit 1; }
# a change to the module alone compiles it again and nothing else
sleep 1
printf '(* a comment *)\n' >> "$P/src/other.bats"
build "$P" "$TMP/5.log"
d2=$(digest "$P")
differs "a byte of src/other.bats" "$d1" "$d2"
# a byte of a file under src/bin, in a deeper directory, bats.toml, bats.lock
printf '(* a comment *)\n' >> "$P/src/deep/nested.bats"
sleep 1
build "$P" "$TMP/6.log"
d3=$(digest "$P")
differs "a byte of src/deep/nested.bats" "$d2" "$d3"
printf '(* a comment *)\n' >> "$P/src/bin/inp.bats"
build "$P" "$TMP/7.log"
d4=$(digest "$P")
differs "a byte of src/bin/inp.bats" "$d3" "$d4"
printf '# a comment\n' >> "$P/bats.toml"
build "$P" "$TMP/8.log"
d5=$(digest "$P")
differs "a byte of bats.toml" "$d4" "$d5"
# a bats.lock (made by bats lock, for a project with no dependencies)
(cd "$P" && "$BATS" lock --repository "$2") > "$TMP/lock.log" 2>&1 || { echo "FAIL: bats lock"; cat "$TMP/lock.log"; exit 1; }
[ -f "$P/bats.lock" ] || { echo "FAIL: no bats.lock was made"; exit 1; }
build "$P" "$TMP/9.log"
d6=$(digest "$P")
differs "a bats.lock" "$d5" "$d6"
printf '\n' >> "$P/bats.lock"
build "$P" "$TMP/10.log"
d7=$(digest "$P")
differs "a byte of bats.lock" "$d6" "$d7"
# a new file under src/, and a file taken away
printf '#include "share/atspre_staload.hats"\n\n#pub fn k (): int\n\nimplement k () = 3\n' > "$P/src/extra.bats"
build "$P" "$TMP/11.log"
d8=$(digest "$P")
differs "a new file under src/" "$d7" "$d8"
rm "$P/src/extra.bats"
build "$P" "$TMP/12.log"
[ "$(digest "$P")" = "$d7" ] || { echo "FAIL: taking the new file away did not give the digest back"; exit 1; }
# a project that does not staload it gets none and runs nothing, though it
# writes the name in a comment and a string (as bats's own sources do)
R=$TMP/r
mkdir -p "$R/src/bin"
cp "$P/bats.toml" "$R/"
printf '(* not a staload of "_bats_inputs.sats" *)\nimplement main0 () = println! ("_bats_inputs.sats")\n' > "$R/src/bin/inp.bats"
build "$R" "$TMP/13.log"
[ ! -e "$R/build/src/_bats_inputs.dats" ] && [ ! -e "$R/build/src/_bats_inputs.sats" ] || { echo "FAIL: the inputs were written for a project that does not name them"; exit 1; }
[ ! -e "$R/build/.bats_inputs" ] || { echo "FAIL: a listing was left behind"; exit 1; }
# and a module written before is taken away when the project stops naming it
printf '#include "share/atspre_staload.hats"\nimplement main0 () = println! ("none")\n' > "$P/src/bin/inp.bats"
build "$P" "$TMP/14.log"
[ ! -e "$P/build/src/_bats_inputs.dats" ] || { echo "FAIL: a stale inputs module was kept"; exit 1; }
echo "build-inputs: ok"
