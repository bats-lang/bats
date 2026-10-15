#!/bin/sh
# build/ carries a stamp of who made it (bats-lang/bats#267), and is kept
# only when this bats would write the same one: build/.bats_stamp holds
# the running bats's digest (`bats`), the ATS2 toolchain's (`patsopt`),
# the C compiler's (`cc`), the flag templates (`flags`) and the target
# and mode (`mark`). A difference in any line drops build/ with one line
# on stderr naming it, and every module is made again; an unchanged
# stamp keeps everything (patsopt does not run); a build/ with no stamp
# (made before stamps) is dropped once; a stash (a build/ of another
# target or mode, put aside by check) is judged when it is swapped in; a
# build/ copied to another directory is kept, since no path is in the
# stamp.
# usage: tests/build-stamp/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_CACHE_DIR
P=$TMP/p
mkdir -p "$P/src/bin"
printf '[package]\nname = "bs"\nkind = "bin"\n' > "$P/bats.toml"
printf '#include "share/atspre_staload.hats"\n\n#pub fn f (): int\n\nimplement f () = 1\n' > "$P/src/m.bats"
printf '#include "share/atspre_staload.hats"\n\n#pub fn g (): int\n\nimplement g () = 2\n' > "$P/src/n.bats"
printf '#include "share/atspre_staload.hats"\nstaload "m.sats"\nstaload "n.sats"\nimplement main0 () = println! (f () + g ())\n' > "$P/src/bin/bs.bats"

# Freshness is by whole-second mtimes: each run ends a second on, so the
# next finds what this one made older than now
build() { # <dir> <log> [env assignment...]: bats -v build in <dir>
  d=$1; l=$2; shift 2
  (cd "$d" && env "$@" "$BATS" -v build --only debug --only native) > "$l" 2>&1 || { echo "FAIL: build in $d"; cat "$l"; exit 1; }
  sleep 1
}
check() { # <dir> <log>: bats -v check in <dir>
  (cd "$1" && "$BATS" -v check) > "$2" 2>&1 || { echo "FAIL: check in $1"; cat "$2"; exit 1; }
  sleep 1
}
# patsopt runs, not counting the entry's generated module, which every
# build makes again whatever it finds (with or without a stamp)
ran() { grep -a -- '+ patsopt' "$1" | grep -av '_bats_entry_' | grep -avc '(cached)' || true; }
# A build or check that ends in the second its modules' C was made in
# finds some stale (the .sats stamp is touched as later modules are
# written), whatever the stamp: one more run lets the mtimes settle
settle() { d=$1; shift; build "$d" "$TMP/settle.log" "$@"; }
settle_check() { check "$1" "$TMP/settle.log"; }
dropped() { grep -ac '^bats: dropping build/' "$1" || true; }
say() { # <log> <what differs>: the one line that names it
  [ "$(dropped "$1")" = 1 ] || { echo "FAIL: $1 has $(dropped "$1") drop lines, expected 1"; cat "$1"; exit 1; }
  grep -aqx "bats: dropping build/ (made by another bats: $2)" "$1" || { echo "FAIL: the line does not say '$2'"; cat "$1"; exit 1; }
}
kept() { # <log> <what>: nothing was dropped and patsopt did not run
  [ "$(dropped "$1")" = 0 ] || { echo "FAIL: $2 dropped build/"; cat "$1"; exit 1; }
  [ "$(ran "$1")" = 0 ] || { echo "FAIL: $2 ran patsopt $(ran "$1") times"; cat "$1"; exit 1; }
}
rebuilt() { # <log> <cold count> <what>: patsopt ran again for every module
  [ "$(ran "$1")" = "$2" ] || { echo "FAIL: $3 ran patsopt $(ran "$1") times, a cold build $2"; cat "$1"; exit 1; }
}
edit() { # <stamp file> <name> <new value>: the line `name value` rewritten
  grep -q "^$2 " "$1" || { echo "FAIL: no line $2 in $1"; cat "$1"; exit 1; }
  sed -e "s|^$2 .*|$2 $3|" "$1" > "$1.edit" && mv -f "$1.edit" "$1"
}

# A cold build writes the stamp, with no path in it
build "$P" "$TMP/cold.log"
[ "$(dropped "$TMP/cold.log")" = 0 ] || { echo "FAIL: a build in an empty directory dropped build/"; cat "$TMP/cold.log"; exit 1; }
COLD=$(ran "$TMP/cold.log")
[ "$COLD" -ge 3 ] || { echo "FAIL: a cold build ran patsopt $COLD times"; cat "$TMP/cold.log"; exit 1; }
settle "$P"
S=$P/build/.bats_stamp
[ -f "$S" ] || { echo "FAIL: no build/.bats_stamp"; exit 1; }
[ "$(sed -n 1p "$S")" = "bats-stamp 1" ] || { echo "FAIL: the stamp's first line"; cat "$S"; exit 1; }
for n in bats patsopt cc flags mark; do
  [ "$(grep -c "^$n " "$S")" = 1 ] || { echo "FAIL: the stamp has not one line $n"; cat "$S"; exit 1; }
done
[ "$(wc -l < "$S")" -eq 6 ] || { echo "FAIL: the stamp has other lines than the format and five"; cat "$S"; exit 1; }
grep -q -E '^bats [0-9a-f]{64}$' "$S" || { echo "FAIL: bats is not a digest"; cat "$S"; exit 1; }
grep -q -E '^patsopt [0-9a-f]{64}$' "$S" || { echo "FAIL: patsopt is not a digest"; cat "$S"; exit 1; }
grep -q -E '^cc [0-9a-f]{64}$' "$S" || { echo "FAIL: cc is not a digest"; cat "$S"; exit 1; }
grep -q '^flags .*\$(PATSHOME)' "$S" || { echo "FAIL: flags do not write PATSHOME as a variable"; cat "$S"; exit 1; }
[ "$(sed -n 's/^mark //p' "$S")" = 0 ] || { echo "FAIL: mark of a native build is not 0"; cat "$S"; exit 1; }
if grep -q -e "$P" -e "$HOME" -e "$TMP" "$S"; then echo "FAIL: the stamp holds a path"; cat "$S"; exit 1; fi
cp "$S" "$TMP/stamp.good"
[ "$("$P/dist/debug/bs")" = 3 ] || { echo "FAIL: the binary"; exit 1; }

# An unchanged stamp keeps everything
build "$P" "$TMP/same.log"
kept "$TMP/same.log" "a second build"
cmp "$S" "$TMP/stamp.good" || { echo "FAIL: the kept stamp changed"; exit 1; }

# One line differs: build/ is dropped and made again, the line named
for line in bats patsopt cc; do
  edit "$S" "$line" "0000000000000000000000000000000000000000000000000000000000000000"
  build "$P" "$TMP/$line.log"
  say "$TMP/$line.log" "$line differs"
  rebuilt "$TMP/$line.log" "$COLD" "a build with another $line"
  cmp "$S" "$TMP/stamp.good" || { echo "FAIL: the stamp was not written again after $line"; exit 1; }
  [ "$("$P/dist/debug/bs")" = 3 ] || { echo "FAIL: the binary after $line"; exit 1; }
  settle "$P"
  build "$P" "$TMP/$line.again.log"
  kept "$TMP/$line.again.log" "the build after $line was made again"
done
edit "$S" flags "clang -c -O3"
build "$P" "$TMP/flags.log"
say "$TMP/flags.log" "flags differs"
rebuilt "$TMP/flags.log" "$COLD" "a build with other flags"
cmp "$S" "$TMP/stamp.good" || { echo "FAIL: the stamp was not written again after flags"; exit 1; }
settle "$P"
edit "$S" mark 3
build "$P" "$TMP/mark.log"
say "$TMP/mark.log" "mark differs"
rebuilt "$TMP/mark.log" "$COLD" "a build with another mark"

# The format's line and an unknown line count too
printf 'bats-stamp 2\n' > "$TMP/f"; sed -n '2,$p' "$S" >> "$TMP/f"; cp "$TMP/f" "$S"
build "$P" "$TMP/format.log"
say "$TMP/format.log" "the stamp format differs"
rebuilt "$TMP/format.log" "$COLD" "a build with another format"
printf 'extra line\n' >> "$S"
build "$P" "$TMP/extra.log"
say "$TMP/extra.log" "the stamp differs"
rebuilt "$TMP/extra.log" "$COLD" "a build with a stamp of more lines"

# A build/ with no stamp (made before stamps) is dropped once
rm -f "$S"
build "$P" "$TMP/nostamp.log"
say "$TMP/nostamp.log" "no stamp"
rebuilt "$TMP/nostamp.log" "$COLD" "a build with no stamp"
settle "$P"
build "$P" "$TMP/nostamp.again.log"
kept "$TMP/nostamp.again.log" "the build after a stampless one"

# Another ATS2 (a prelude file changed) is another patsopt line, and the
# original brings it back; build/ is dropped each time
H=$TMP/home
mkdir -p "$H/.bats/ats2"
for d in bin prelude libats share ccomp; do cp -R "$HOME/.bats/ats2/$d" "$H/.bats/ats2/"; done
printf '\n(* another toolchain *)\n' >> "$H/.bats/ats2/prelude/basics_pre.sats"
build "$P" "$TMP/home.log" HOME="$H"
say "$TMP/home.log" "patsopt differs"
rebuilt "$TMP/home.log" "$COLD" "a build with another ATS2"
build "$P" "$TMP/home.back.log"
say "$TMP/home.back.log" "patsopt differs"
rebuilt "$TMP/home.back.log" "$COLD" "a build with the first ATS2 again"

# Another C compiler (clang printing another --version, through a shim
# first in PATH) is another cc line
REAL=$(command -v clang)
mkdir -p "$TMP/shim"
cat > "$TMP/shim/clang" <<SHIM
#!/bin/sh
if [ "\$1" = --version ]; then echo "clang version 0.0.0 (another)"; exit 0; fi
exec "$REAL" "\$@"
SHIM
chmod +x "$TMP/shim/clang"
build "$P" "$TMP/cc.shim.log" PATH="$TMP/shim:$PATH"
say "$TMP/cc.shim.log" "cc differs"
rebuilt "$TMP/cc.shim.log" "$COLD" "a build with another clang"
settle "$P" PATH="$TMP/shim:$PATH"
build "$P" "$TMP/cc.back.log"
say "$TMP/cc.back.log" "cc differs"
settle "$P"
build "$P" "$TMP/cc.kept.log"
kept "$TMP/cc.kept.log" "the build after the clang came back"

# A build/ copied to another directory is kept: no path is in the stamp
Q=$TMP/elsewhere/deeper/q
mkdir -p "$Q"
cp -Rp "$P/bats.toml" "$P/src" "$P/build" "$Q/"
build "$Q" "$TMP/copy.log"
kept "$TMP/copy.log" "a build/ copied to another directory"
[ "$("$Q/dist/debug/bs")" = 3 ] || { echo "FAIL: the copy's binary"; exit 1; }

# A stash is judged when it is swapped in. check makes the native check's
# build (mark 2), then the wasm check's (mark 3), putting each aside as
# the other comes: build/ holds mark 3 and .stash/2 mark 2 after it. A
# stamp edited in the stash is found when the next check swaps it back,
# and so is one edited in build/ (it is put aside and swapped back for
# the wasm leg).
C=$TMP/c
mkdir -p "$C"
cp -R "$P/bats.toml" "$P/src" "$C/"
check "$C" "$TMP/check.log"
CHK=$(ran "$TMP/check.log")
[ "$CHK" -ge 3 ] || { echo "FAIL: a cold check ran patsopt $CHK times"; cat "$TMP/check.log"; exit 1; }
[ "$(dropped "$TMP/check.log")" = 0 ] || { echo "FAIL: a cold check dropped build/"; cat "$TMP/check.log"; exit 1; }
[ "$(sed -n 's/^mark //p' "$C/build/.bats_stamp")" = 3 ] || { echo "FAIL: check's build/ is not mark 3"; cat "$C/build/.bats_stamp"; exit 1; }
[ "$(sed -n 's/^mark //p' "$C/build/.stash/2/.bats_stamp")" = 2 ] || { echo "FAIL: check's stash is not mark 2"; ls -a "$C/build/.stash/2"; exit 1; }
settle_check "$C"
check "$C" "$TMP/check.same.log"
kept "$TMP/check.same.log" "a second check"
edit "$C/build/.stash/2/.bats_stamp" flags "another flags"
check "$C" "$TMP/check.stash.log"
say "$TMP/check.stash.log" "flags differs"
rebuilt "$TMP/check.stash.log" "$CHK" "a check with a stash of other flags"
settle_check "$C"
check "$C" "$TMP/check.after.log"
kept "$TMP/check.after.log" "the check after the stash was dropped"
edit "$C/build/.bats_stamp" cc "0000000000000000000000000000000000000000000000000000000000000000"
check "$C" "$TMP/check.build.log"
say "$TMP/check.build.log" "cc differs"
settle_check "$C"
check "$C" "$TMP/check.last.log"
kept "$TMP/check.last.log" "the last check"
echo "build-stamp: ok"
