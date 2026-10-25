#!/bin/sh
# With BATS_CACHE_DIR, patsopt's C is shared between checkouts of a
# project (bats-lang/bats#250). The C names the project's files relative
# to it, so a copy of the project at another path builds every module
# from the cache, into the same C. A module's entry is keyed by what
# patsopt reads (its .dats and each file its staloads reach, by content,
# and the toolchain), so a changed .sats misses for the modules that
# staload it and no other, another toolchain misses, and a module that
# fails is never kept: a hit never passes what a cold build fails.
# usage: tests/shared-cache/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
. "$(dirname "$0")/../keep-on-fail.sh"
. "$(dirname "$0")/../ats2-marker.sh"
export BATS_CACHE_DIR="$TMP/cache"
A=$TMP/a
mkdir -p "$A/src/bin"
printf '[package]\nname = "sh"\nkind = "bin"\n' > "$A/bats.toml"
m() { # <dir> <value>
  printf '#include "share/atspre_staload.hats"\n\n#pub macdef kval = %s\n\n#pub fn f (): int\n\nimplement f () = kval\n' "$2" > "$1/src/m.bats"
}
m "$A" 1
printf '#include "share/atspre_staload.hats"\n\n#pub fn g (): int\n\nimplement g () = 7\n' > "$A/src/n.bats"
printf '#include "share/atspre_staload.hats"\nstaload "m.sats"\nstaload "n.sats"\nimplement main0 () = println! (f () + g ())\n' > "$A/src/bin/sh.bats"
build() { # <dir> <log>
  (cd "$1" && "$BATS" -v build --only debug --only native) > "$2" 2>&1 || { echo "FAIL: build in $1"; cat "$2"; exit 1; }
}
ran() { grep -a -- '+ patsopt' "$1" | grep -avc '(cached)' || true; }
hits() { grep -a -- '+ patsopt' "$1" | grep -ac '(cached)' || true; }

build "$A" "$TMP/a.log"
[ "$(hits "$TMP/a.log")" = 0 ] || { echo "FAIL: a cold build hit"; cat "$TMP/a.log"; exit 1; }
[ "$(ran "$TMP/a.log")" -ge 4 ] || { echo "FAIL: a cold build ran patsopt $(ran "$TMP/a.log") times"; cat "$TMP/a.log"; exit 1; }
[ "$("$A/dist/debug/sh")" = 8 ] || { echo "FAIL: a's binary"; exit 1; }
if grep -rl "$A" "$A/build" --include='*.c' >/dev/null; then
  echo "FAIL: the C names the project's directory"; grep -rl "$A" "$A/build" --include='*.c'; exit 1
fi

# The same project at another path: every module from the cache
B=$TMP/elsewhere/deeper/b
mkdir -p "$B"
cp -R "$A/bats.toml" "$A/src" "$B/"
build "$B" "$TMP/b.log"
[ "$(ran "$TMP/b.log")" = 0 ] || { echo "FAIL: the copy ran patsopt"; cat "$TMP/b.log"; exit 1; }
[ "$(hits "$TMP/b.log")" = "$(ran "$TMP/a.log")" ] || { echo "FAIL: the copy hit $(hits "$TMP/b.log") of $(ran "$TMP/a.log")"; cat "$TMP/b.log"; exit 1; }
[ "$("$B/dist/debug/sh")" = 8 ] || { echo "FAIL: b's binary"; exit 1; }
for c in $(cd "$A/build" && find . -name '*_dats.c'); do
  cmp "$A/build/$c" "$B/build/$c" || { echo "FAIL: $c differs between the two paths"; exit 1; }
done

# m.sats changes: m and what staloads it miss, n hits
sleep 1
m "$B" 2
build "$B" "$TMP/b2.log"
grep -a -- '+ patsopt' "$TMP/b2.log" | grep -a 'src/n_dats.c' | grep -aq '(cached)' || { echo "FAIL: n missed for a change to m.sats"; cat "$TMP/b2.log"; exit 1; }
grep -a -- '+ patsopt' "$TMP/b2.log" | grep -a 'src/bin/sh_dats.c' | grep -avq '(cached)' || { echo "FAIL: the binary hit with m.sats changed"; cat "$TMP/b2.log"; exit 1; }
[ "$("$B/dist/debug/sh")" = 9 ] || { echo "FAIL: b's binary after m.sats changed printed $("$B/dist/debug/sh")"; exit 1; }

# Another toolchain (a prelude file changed): every module misses
H=$TMP/home
mkdir -p "$H/.bats/ats2"
for d in bin prelude libats share ccomp; do cp -R "$HOME/.bats/ats2/$d" "$H/.bats/ats2/"; done
printf '\n(* another toolchain *)\n' >> "$H/.bats/ats2/prelude/basics_pre.sats"
ats2_marker "$H"
C=$TMP/c
mkdir -p "$C"
cp -R "$A/bats.toml" "$A/src" "$C/"
(cd "$C" && HOME="$H" "$BATS" -v build --only debug --only native) > "$TMP/c.log" 2>&1 || { echo "FAIL: build with the other toolchain"; cat "$TMP/c.log"; exit 1; }
[ "$(hits "$TMP/c.log")" = 0 ] || { echo "FAIL: another toolchain hit"; cat "$TMP/c.log"; exit 1; }

# A module that fails is not kept: the same source fails again cold
D=$TMP/d
mkdir -p "$D"
cp -R "$A/bats.toml" "$A/src" "$D/"
printf '#include "share/atspre_staload.hats"\n\n#pub fn g (): int\n\nimplement g () = "seven"\n' > "$D/src/n.bats"
n0=$(find "$BATS_CACHE_DIR" -name '*.c' | wc -l)
if (cd "$D" && "$BATS" build --only debug --only native) > "$TMP/d.log" 2>&1; then
  echo "FAIL: a type error built"; exit 1
fi
cp -R "$D" "$TMP/d2"
rm -rf "$TMP/d2/build" "$TMP/d2/dist"
if (cd "$TMP/d2" && "$BATS" build --only debug --only native) > "$TMP/d2.log" 2>&1; then
  echo "FAIL: a type error built from the cache"; exit 1
fi
n1=$(find "$BATS_CACHE_DIR" -name '*.c' | wc -l)
[ "$n0" = "$n1" ] || { echo "FAIL: a failed build kept $((n1 - n0)) entries"; exit 1; }
# The size bound (bats#483): with the cache over BATS_CACHE_MAX_MB, a store
# removes the least recently used entries first, and what was used last stays
SC=$TMP/sized
E=$TMP/e
mkdir -p "$E"
cp -R "$A/bats.toml" "$A/src" "$E/"
m "$E" 1
(export BATS_CACHE_DIR="$SC" BATS_CACHE_MAX_MB=1; build "$E" "$TMP/e.log")
kept_before=$(find "$SC" -name '*.c' | wc -l)
[ "$kept_before" -ge 4 ] || { echo "FAIL: the sized cache holds $kept_before entries"; exit 1; }
# every entry made so far is old, the copy at another path then hits them all
find "$SC" -name '*.c' -exec touch -t 200001010000 {} +
F=$TMP/elsewhere/f
mkdir -p "$F"
cp -R "$E/bats.toml" "$E/src" "$F/"
(export BATS_CACHE_DIR="$SC" BATS_CACHE_MAX_MB=1; build "$F" "$TMP/f.log")
[ "$(ran "$TMP/f.log")" = 0 ] || { echo "FAIL: the copy ran patsopt"; cat "$TMP/f.log"; exit 1; }
find "$SC" -name '*.c' > "$TMP/used.list"
# the fillers: four entries of 300000 bytes, 1.2 MB over the 1 MB limit with the rest, each older than the last
mkdir -p "$SC/patsopt-1/ff"
n=1
for stamp in 200101010000 200201010000 200301010000 200401010000; do
  head -c 300000 /dev/zero > "$SC/patsopt-1/ff/filler$n.c"
  touch -t "$stamp" "$SC/patsopt-1/ff/filler$n.c"
  n=$((n + 1))
done
# a module that is new makes a store, which prunes
G=$TMP/g
mkdir -p "$G"
cp -R "$E/bats.toml" "$E/src" "$G/"
printf '#include "share/atspre_staload.hats"\n\n#pub fn g (): int\n\nimplement g () = 11\n' > "$G/src/n.bats"
(export BATS_CACHE_DIR="$SC" BATS_CACHE_MAX_MB=1; build "$G" "$TMP/g.log")
[ -e "$SC/patsopt-1/ff/filler1.c" ] && { echo "FAIL: the least recently used entry is still there"; exit 1; }
[ -e "$SC/patsopt-1/ff/filler4.c" ] || { echo "FAIL: the most recent filler was removed"; exit 1; }
while IFS= read -r used; do
  [ -e "$used" ] || { echo "FAIL: $used, used by the copy, was removed"; exit 1; }
done < "$TMP/used.list"
size=$(find "$SC" -name '*.c' -exec wc -c {} + | awk '$2 == "total" { total = $1 } END { print total + 0 }')
[ "$size" -le 1048576 ] || { echo "FAIL: the cache holds $size bytes, over 1 MB"; exit 1; }
# a build against the pruned cache gives the C of a cold build
H=$TMP/h
mkdir -p "$H"
cp -R "$G/bats.toml" "$G/src" "$H/"
(export BATS_CACHE_DIR="$SC" BATS_CACHE_MAX_MB=1; build "$H" "$TMP/h.log")
[ "$(hits "$TMP/h.log")" -ge 1 ] || { echo "FAIL: the pruned cache served nothing"; cat "$TMP/h.log"; exit 1; }
I=$TMP/i
mkdir -p "$I"
cp -R "$G/bats.toml" "$G/src" "$I/"
(export BATS_CACHE_DIR=; build "$I" "$TMP/i.log")
[ "$(hits "$TMP/i.log")" = 0 ] || { echo "FAIL: the cold build hit"; exit 1; }
for c in $(cd "$I/build" && find . -name '*_dats.c'); do
  cmp "$I/build/$c" "$H/build/$c" || { echo "FAIL: $c of the pruned cache differs from the cold build"; exit 1; }
done
# a limit that is not a number is said, and the default is used
J=$TMP/j
mkdir -p "$J"
cp -R "$G/bats.toml" "$G/src" "$J/"
printf '#include "share/atspre_staload.hats"\n\n#pub fn g (): int\n\nimplement g () = 12\n' > "$J/src/n.bats"
(export BATS_CACHE_DIR="$SC" BATS_CACHE_MAX_MB=banana; build "$J" "$TMP/j.log")
grep -aq "BATS_CACHE_MAX_MB='banana' is not a whole number" "$TMP/j.log" || { echo "FAIL: a limit that is no number was not said"; cat "$TMP/j.log"; exit 1; }
echo "shared-cache: ok"
