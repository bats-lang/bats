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
# The variables the C compiler and the wasm linker read (put_cc_environment,
# bats-lang/bats#322) are unset here, so each case sets its own
for v in CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH OBJCPLUS_INCLUDE_PATH LIBRARY_PATH COMPILER_PATH SDKROOT DEVELOPER_DIR MACOSX_DEPLOYMENT_TARGET IPHONEOS_DEPLOYMENT_TARGET TVOS_DEPLOYMENT_TARGET WATCHOS_DEPLOYMENT_TARGET DRIVERKIT_DEPLOYMENT_TARGET RC_DEBUG_PREFIX_MAP RC_DEBUG_OPTIONS CCC_OVERRIDE_OPTIONS CLANG_NO_DEFAULT_CONFIG; do
  unset "$v"
done
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

# The C compiler's environment (bats-lang/bats#322): a variable clang
# reads that changes what it makes is digested into the cc line, so a
# build/ made with one value is dropped by a build with another, as by
# another clang. The issue's reproduction: CPATH holds a stdlib.h that adds a
# weak symbol, which the objects gain only in a build that sees it. Same
# value keeps build/; a variable no compiler reads changes nothing; unset and
# empty are different values.
EV=$TMP/env
mkdir -p "$EV" "$TMP/cpath"
cp -R "$P/bats.toml" "$P/src" "$EV/"
printf '#include_next <stdlib.h>\n__attribute__((weak)) int bats_cpath_probe = 7;\n' > "$TMP/cpath/stdlib.h"
probe() { grep -rq bats_cpath_probe "$EV/build"; }
build "$EV" "$TMP/env.cold.log"
[ "$(dropped "$TMP/env.cold.log")" = 0 ] || { echo "FAIL: a cold build with no CPATH dropped build/"; cat "$TMP/env.cold.log"; exit 1; }
settle "$EV"
probe && { echo "FAIL: the probe is in the objects without CPATH"; exit 1; } || true
settle_env() { settle "$EV" "$@"; }
# CPATH set after a build without it: dropped, named, and the probe is found
build "$EV" "$TMP/env.cpath.log" "CPATH=$TMP/cpath"
say "$TMP/env.cpath.log" "cc differs"
rebuilt "$TMP/env.cpath.log" "$COLD" "a build with CPATH"
probe || { echo "FAIL: a build with CPATH does not have the probe the issue names"; cat "$TMP/env.cpath.log"; exit 1; }
settle_env "CPATH=$TMP/cpath"
build "$EV" "$TMP/env.same.log" "CPATH=$TMP/cpath"
kept "$TMP/env.same.log" "a build with the same CPATH"
# An unrelated variable changes nothing
build "$EV" "$TMP/env.foo.log" "CPATH=$TMP/cpath" FOO=1
kept "$TMP/env.foo.log" "a build with an unrelated variable"
# CPATH unset after one with it: dropped
build "$EV" "$TMP/env.unset.log" -u CPATH
say "$TMP/env.unset.log" "cc differs"
rebuilt "$TMP/env.unset.log" "$COLD" "a build with CPATH unset"
settle_env
# CPATH empty is not unset: dropped, and kept again for empty
build "$EV" "$TMP/env.empty.log" CPATH=
say "$TMP/env.empty.log" "cc differs"
rebuilt "$TMP/env.empty.log" "$COLD" "a build with CPATH empty"
settle_env CPATH=
build "$EV" "$TMP/env.empty.same.log" CPATH=
kept "$TMP/env.empty.same.log" "a build with CPATH empty again"
build "$EV" "$TMP/env.empty.unset.log" -u CPATH
say "$TMP/env.empty.unset.log" "cc differs"
rebuilt "$TMP/env.empty.unset.log" "$COLD" "a build with CPATH unset after empty"
# SOURCE_DATE_EPOCH is not in the list (clang reads it only for __DATE__ and
# __TIME__, which no emitted C uses, and a reproducible-build setup sets it
# per commit): a value of it keeps build/
settle_env CPATH=
build "$EV" "$TMP/env.sde.log" CPATH= SOURCE_DATE_EPOCH=2
kept "$TMP/env.sde.log" "a build with another SOURCE_DATE_EPOCH"
# A Darwin deployment target is in the list: the Darwin driver picks the
# target the objects are made for by it (not run on a Mac here)
build "$EV" "$TMP/env.ios.log" CPATH= IPHONEOS_DEPLOYMENT_TARGET=17
say "$TMP/env.ios.log" "cc differs"
rebuilt "$TMP/env.ios.log" "$COLD" "a build with IPHONEOS_DEPLOYMENT_TARGET"

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
# The toolchain is judged by what it is, in each process (bats-lang/bats#305):
# patsopt replaced in place, with the same name and size, is another
# toolchain; a patsopt that is a link is judged by the file it reaches, so
# that file changed in place is seen too; and a prelude file changed in
# place, with the same size, is seen.
T3=$TMP/tool
mkdir -p "$T3/.bats/ats2"
for d in bin prelude libats share ccomp; do cp -R "$HOME/.bats/ats2/$d" "$T3/.bats/ats2/"; done
R3=$TMP/real-patsopt
cp "$T3/.bats/ats2/bin/patsopt" "$R3"
SZ=$(wc -c < "$R3")
standin() { # <file> <pad>: a stand-in of patsopt's size that runs the real one, padded with <pad>
  printf '#!/bin/sh\nexec %s "$@"\n' "$R3" > "$1"
  head -c $(( SZ - $(wc -c < "$1") )) /dev/zero | tr '\0' "$2" >> "$1"
  chmod +x "$1"
  [ "$(wc -c < "$1")" -eq "$SZ" ] || { echo "FAIL: the stand-in is not the size of patsopt"; exit 1; }
}
P3=$TMP/p3
mkdir -p "$P3"
cp -R "$P/bats.toml" "$P/src" "$P3/"
build "$P3" "$TMP/tool.cold.log" HOME="$T3"
[ "$(dropped "$TMP/tool.cold.log")" = 0 ] || { echo "FAIL: a build with a new toolchain dropped build/"; cat "$TMP/tool.cold.log"; exit 1; }
COLD3=$(ran "$TMP/tool.cold.log")
[ "$COLD3" -ge 2 ] || { echo "FAIL: a cold build ran patsopt $COLD3 times"; cat "$TMP/tool.cold.log"; exit 1; }
settle "$P3" HOME="$T3"
build "$P3" "$TMP/tool.same.log" HOME="$T3"
kept "$TMP/tool.same.log" "a build with the same toolchain"

standin "$T3/.bats/ats2/bin/patsopt" '#'
build "$P3" "$TMP/tool.inplace.log" HOME="$T3"
say "$TMP/tool.inplace.log" "patsopt differs"
rebuilt "$TMP/tool.inplace.log" "$COLD3" "a build with patsopt replaced in place"
settle "$P3" HOME="$T3"
build "$P3" "$TMP/tool.inplace.again.log" HOME="$T3"
kept "$TMP/tool.inplace.again.log" "the build after patsopt was replaced in place"

standin "$TMP/linked" '%'
rm -f "$T3/.bats/ats2/bin/patsopt"
ln -s "$TMP/linked" "$T3/.bats/ats2/bin/patsopt"
build "$P3" "$TMP/tool.link.log" HOME="$T3"
say "$TMP/tool.link.log" "patsopt differs"
rebuilt "$TMP/tool.link.log" "$COLD3" "a build with patsopt made a link"
settle "$P3" HOME="$T3"
build "$P3" "$TMP/tool.link.again.log" HOME="$T3"
kept "$TMP/tool.link.again.log" "the build after patsopt was made a link"
standin "$TMP/linked" '@'
build "$P3" "$TMP/tool.target.log" HOME="$T3"
say "$TMP/tool.target.log" "patsopt differs"
rebuilt "$TMP/tool.target.log" "$COLD3" "a build with the file its link reaches changed in place"
settle "$P3" HOME="$T3"
build "$P3" "$TMP/tool.target.again.log" HOME="$T3"
kept "$TMP/tool.target.again.log" "the build after the file its link reaches changed"

printf '(* a *)\n' > "$T3/.bats/ats2/prelude/zz_probe_305.sats"
build "$P3" "$TMP/tool.probe.log" HOME="$T3"
say "$TMP/tool.probe.log" "patsopt differs"
settle "$P3" HOME="$T3"
printf '(* b *)\n' > "$T3/.bats/ats2/prelude/zz_probe_305.sats"
build "$P3" "$TMP/tool.prelude.log" HOME="$T3"
say "$TMP/tool.prelude.log" "patsopt differs"
rebuilt "$TMP/tool.prelude.log" "$COLD3" "a build with a prelude file changed in place, the same size"
settle "$P3" HOME="$T3"
build "$P3" "$TMP/tool.prelude.again.log" HOME="$T3"
kept "$TMP/tool.prelude.again.log" "the build after the prelude file changed"
# A toolchain with a part missing is not stamped from what is left of it
# (bats-lang/bats#316): the listing that makes the stamp names each root
# (bin/patsopt, prelude, libats, share, ccomp) and a check fails at once with
# that name, before patsopt runs, and no stamp is written. Each farm is the
# five parts hard-linked (cheap) with one of them removed, and no install
# marker, so ATS2 is used as it is, as in the other farms above.
FULL=$TMP/ats2-full
mkdir -p "$FULL"
for d in bin prelude libats share ccomp; do cp -Rl "$HOME/.bats/ats2/$d" "$FULL/"; done
P5=$TMP/p5
for r in prelude libats share ccomp bin/patsopt; do
  n=$(echo "$r" | tr / _)
  F=$TMP/missing-$n
  mkdir -p "$F/.bats/ats2"
  cp -Rl "$FULL/." "$F/.bats/ats2/"
  rm -rf "$F/.bats/ats2/$r"
  rm -rf "$P5"; mkdir -p "$P5"; cp -R "$P/bats.toml" "$P/src" "$P5/"
  if (cd "$P5" && HOME="$F" "$BATS" check) > "$TMP/missing-$n.log" 2>&1; then
    echo "FAIL: a check with no $r passed"; cat "$TMP/missing-$n.log"; exit 1
  fi
  grep -q "has no $r" "$TMP/missing-$n.log" || { echo "FAIL: the check does not name $r"; cat "$TMP/missing-$n.log"; exit 1; }
  [ ! -e "$P5/build/.bats_stamp" ] || { echo "FAIL: a stamp was written from a toolchain with no $r"; cat "$P5/build/.bats_stamp"; exit 1; }
done
# A part the listing cannot pass through (a link back to its own parent) is
# refused the same way, with the name of what cannot be listed
F=$TMP/missing-loop
mkdir -p "$F/.bats/ats2"
cp -Rl "$FULL/." "$F/.bats/ats2/"
ln -s .. "$F/.bats/ats2/share/loop"
rm -rf "$P5"; mkdir -p "$P5"; cp -R "$P/bats.toml" "$P/src" "$P5/"
if (cd "$P5" && HOME="$F" "$BATS" check) > "$TMP/missing-loop.log" 2>&1; then
  echo "FAIL: a check with a link loop in the toolchain passed"; cat "$TMP/missing-loop.log"; exit 1
fi
grep -q "cannot be listed" "$TMP/missing-loop.log" || { echo "FAIL: the check does not say the toolchain cannot be listed"; cat "$TMP/missing-loop.log"; exit 1; }
[ ! -e "$P5/build/.bats_stamp" ] || { echo "FAIL: a stamp was written from a toolchain with a link loop"; exit 1; }
echo "build-stamp: ok"
