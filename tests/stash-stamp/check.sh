#!/bin/sh
# A stash is judged by its own stamp when it is swapped in (bats-lang/bats#337).
# cache_swap moves a mark's build/ in from build/.stash/<n>, and a stash keeps
# the stamp of whoever made it, so JUDGE compares that stamp with the one this
# bats would write before anything in the stash is used (stamp.bats). A check
# leaves the other mark's cache in build/.stash/2 (mark 2, the native check's;
# build/ holds mark 3). This plays that stash:
#   * each stamp line of it edited in turn (bats, patsopt, cc, flags, mark):
#     the check that swaps it in drops it with one line naming the line, makes
#     every module again (the count of a cold check), and leaves the stash
#     with the stamp this bats writes, byte for byte as it was;
#   * the same stash unedited: it is kept, and patsopt does not run.
#   * a stash with no stamp, and one whose first line is not `bats-stamp 1`:
#     dropped with "no stamp" and "the stamp format differs", made again.
# A stash of a stamp this bats would not write is never taken for this build's.
# Not yet covered (bats-lang/bats#347): a stamp with a line that is not
# `name value` after its first line. JUDGE (stamp.bats) answers "the stamp
# differs" for it, not "the stamp format differs", which needs a change to
# stamp.bats, not to this test.
# usage: tests/stash-stamp/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_CACHE_DIR BATS_COLD
P=$TMP/p
mkdir -p "$P/src/bin"
printf '[package]\nname = "ss"\nkind = "bin"\n' > "$P/bats.toml"
printf '#include "share/atspre_staload.hats"\n\n#pub fn f (): int\n\nimplement f () = 1\n' > "$P/src/m.bats"
printf '#include "share/atspre_staload.hats"\n\n#pub fn g (): int\n\nimplement g () = 2\n' > "$P/src/n.bats"
printf '#include "share/atspre_staload.hats"\nstaload "m.sats"\nstaload "n.sats"\nimplement main0 () = println! (f () + g ())\n' > "$P/src/bin/ss.bats"

check() { # <dir> <log>: bats -v check in <dir>, which must pass
  (cd "$1" && "$BATS" -v check) > "$2" 2>&1 || { echo "FAIL: check in $1"; cat "$2"; exit 1; }
}
# patsopt ran on a module (not counted as cached)
ran() { grep -a -- '+ patsopt' "$1" | grep -avc '(cached)' || true; }
dropped() { grep -ac '^bats: dropping build/' "$1" || true; }
say() { # <log> <what differs>: exactly one drop, and the line names it
  [ "$(dropped "$1")" = 1 ] || { echo "FAIL: $1 has $(dropped "$1") drop lines, expected 1"; cat "$1"; exit 1; }
  grep -aqx "bats: dropping build/ (made by another bats: $2)" "$1" || { echo "FAIL: the drop line does not say '$2'"; cat "$1"; exit 1; }
}
kept() { # <log> <what>: nothing dropped, patsopt did not run, and a module was said unchanged
  [ "$(dropped "$1")" = 0 ] || { echo "FAIL: $2 dropped build/"; cat "$1"; exit 1; }
  [ "$(ran "$1")" = 0 ] || { echo "FAIL: $2 ran patsopt $(ran "$1") times"; cat "$1"; exit 1; }
  grep -aq '(unchanged)' "$1" || { echo "FAIL: $2 did not say a module was unchanged"; cat "$1"; exit 1; }
}
rebuilt() { # <log> <cold count> <what>: patsopt ran again for every module, once
  [ "$(ran "$1")" = "$2" ] || { echo "FAIL: $3 ran patsopt $(ran "$1") times, a cold check $2"; cat "$1"; exit 1; }
}
value() { # <stamp file> <name>: the value of the line `name value` (none: empty)
  while IFS= read -r l || [ -n "$l" ]; do
    case $l in "$2 "*) printf '%s\n' "${l#"$2 "}"; return 0 ;; esac
  done < "$1"
}
edit() { # <stamp file> <name> <new value>: the line `name value` rewritten
  grep -q "^$2 " "$1" || { echo "FAIL: no line $2 in $1"; cat "$1"; exit 1; }
  { while IFS= read -r l || [ -n "$l" ]; do
      case $l in "$2 "*) printf '%s %s\n' "$2" "$3" ;; *) printf '%s\n' "$l" ;; esac
    done < "$1"; } > "$1.edit"
  mv -f "$1.edit" "$1"
}
put_line() { # <stamp file> <n> <text>: line n of the file replaced by text
  i=0
  { while IFS= read -r l || [ -n "$l" ]; do
      i=$((i + 1))
      if [ "$i" = "$2" ]; then printf '%s\n' "$3"; else printf '%s\n' "$l"; fi
    done < "$1"; } > "$1.edit"
  mv -f "$1.edit" "$1"
}

# A cold check, and the next one, which keeps everything: build/ is mark 3
# and the native check's stash is mark 2
check "$P" "$TMP/cold.log"
COLD=$(ran "$TMP/cold.log")
[ "$COLD" -ge 3 ] || { echo "FAIL: a cold check ran patsopt $COLD times"; cat "$TMP/cold.log"; exit 1; }
[ "$(dropped "$TMP/cold.log")" = 0 ] || { echo "FAIL: a cold check dropped build/"; cat "$TMP/cold.log"; exit 1; }
check "$P" "$TMP/second.log"
kept "$TMP/second.log" "a second check"
S2=build/.stash/2
[ "$(value "$P/$S2/.bats_stamp" mark)" = 2 ] || { echo "FAIL: the check left no mark 2 stash in $S2"; ls -a "$P/build"; exit 1; }
SAVE=$TMP/saved
cp -Rp "$P" "$SAVE"
D=$TMP/case

for line in bats patsopt cc flags mark; do
  case $line in
    flags) value="clang -c -O3" ;;
    mark) value=3 ;;
    *) value=0000000000000000000000000000000000000000000000000000000000000000 ;;
  esac
  rm -rf "$D"
  cp -Rp "$SAVE" "$D"
  edit "$D/$S2/.bats_stamp" "$line" "$value"
  check "$D" "$TMP/$line.log"
  case $line in
    mark) want="mark differs" ;;
    *) want="$line differs" ;;
  esac
  say "$TMP/$line.log" "$want"
  rebuilt "$TMP/$line.log" "$COLD" "a stash with another $line"
  cmp "$D/$S2/.bats_stamp" "$SAVE/$S2/.bats_stamp" || { echo "FAIL: after a stash with another $line was dropped, its stamp is not this build's"; cat "$D/$S2/.bats_stamp"; exit 1; }
  echo "stash-stamp: a stash with another $line: dropped, named, and made again"
done

# A stash with no stamp, and one whose first line is not `bats-stamp 1`:
# each is dropped, the drop line names the reason, and the build is made again
rm -rf "$D"
cp -Rp "$SAVE" "$D"
rm -f "$D/$S2/.bats_stamp"
check "$D" "$TMP/nostamp.log"
say "$TMP/nostamp.log" "no stamp"
rebuilt "$TMP/nostamp.log" "$COLD" "a stash with no stamp"
cmp "$D/$S2/.bats_stamp" "$SAVE/$S2/.bats_stamp" || { echo "FAIL: after a stash with no stamp was dropped, its stamp is not this build's"; exit 1; }
echo "stash-stamp: a stash with no stamp: dropped, named, and made again"

for first in garbage "bats-stamp 2"; do
  rm -rf "$D"
  cp -Rp "$SAVE" "$D"
  put_line "$D/$S2/.bats_stamp" 1 "$first"
  check "$D" "$TMP/format.log"
  say "$TMP/format.log" "the stamp format differs"
  rebuilt "$TMP/format.log" "$COLD" "a stash whose first line is '$first'"
  cmp "$D/$S2/.bats_stamp" "$SAVE/$S2/.bats_stamp" || { echo "FAIL: after a stash whose first line is '$first' was dropped, its stamp is not this build's"; exit 1; }
  echo "stash-stamp: a stash whose first line is '$first': dropped, named, and made again"
done

# The same stash, unedited, is kept (the control of the cases above)
rm -rf "$D"
cp -Rp "$SAVE" "$D"
check "$D" "$TMP/same.log"
kept "$TMP/same.log" "a stash with the same stamp"
echo "stash-stamp: a stash with the same stamp: kept"
echo "stash-stamp: ok"
