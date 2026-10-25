#!/bin/sh
# The line patsopt dates its C by (bats-lang/bats#354). patsopt writes
# "** The starting compilation time is: 2026-10-18: 22h:29m" as the 4th line
# of every C, the time of the run to the minute and the only thing in the C
# that depends on when it ran, so a cold build and an incremental one that
# straddled a minute differed in that line alone. bats writes the line as
# one text ("left out") while it puts the C in place (relative_c in
# src/cache.bats: one pass over the bytes, the same that leaves the
# project's directory out of the paths; no sed, no other program), and it
# does so as a function of the bytes. A stand-in patsopt runs the real one
# and then shapes the 4th line of its C, so each case is played on the
# bytes of a real C:
#   * as patsopt writes it: the line is the fixed text;
#   * the hour and the minute padded with spaces (" 0h: 1m"): the same;
#   * a C with no such line (the line removed): left as it is, no error;
#   * the line not at line 4 (a line before it): left as it is;
#   * another text at line 4 that merely starts like it ("...time is:"
#     without the space): left as it is;
#   * in every case the lines are as many as patsopt wrote.
# usage: tests/dating-line/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
. "$(dirname "$0")/../keep-on-fail.sh"
unset BATS_CACHE_DIR BATS_SLOTS BATS_LOCK_DIR BATS_SLOT_HELD BATS_PATSOPT_TIMEOUT_S BATS_PATSOPT_MEM_MB
REAL=$HOME/.bats/ats2
H=$TMP/home
mkdir -p "$H/.bats/ats2/bin" "$TMP/raw"
for d in prelude libats share ccomp; do ln -s "$REAL/$d" "$H/.bats/ats2/$d"; done
PREFIX='** The starting compilation time is: '
FIXED="${PREFIX}left out"

# the stand-in: the real patsopt, then (FAKE) the 4th line of its C shaped;
# the C it hands to bats is kept in $TMP/raw (its name is the key)
cat > "$H/.bats/ats2/bin/patsopt" <<SH
#!/bin/sh
for a in "\$@"; do
  if [ "\$a" = --depgen ]; then exec "$REAL/bin/patsopt" "\$@"; fi
done
"$REAL/bin/patsopt" "\$@" || exit \$?
prev=
out=
for a in "\$@"; do
  if [ "\$prev" = -o ]; then out=\$a; fi
  prev=\$a
done
[ -n "\$out" ] || exit 0
t="\$out.shaped"
case "\${FAKE:-}" in
  padded) sed -e '4s/.*/${PREFIX}2026-01-02:  0h: 1m/' "\$out" > "\$t" ;;
  removed) sed -e '4d' "\$out" > "\$t" ;;
  moved) sed -e '3a\\
**' "\$out" > "\$t" ;;
  lookalike) sed -e '4s/.*/** The starting compilation time is:2026-01-02: 0h: 1m/' "\$out" > "\$t" ;;
  plain|*) cp "\$out" "\$t" ;;
esac
cp "\$t" "$TMP/raw/\$(basename "\$out" .raw)"
mv "\$t" "\$out"
SH
chmod +x "$H/.bats/ats2/bin/patsopt"
mkdir -p "$H/.bats/ats2" && "$BATS" ats2 marker > "$H/.bats/ats2/.bats-ats2"

# check <case>: the case's project checked from nothing, then every C of it
# looked at; $TMP/raw holds what the stand-in's patsopt handed to bats
# (the line shaped), so the lines of the C that was made can be counted
fail() { echo "FAIL: $1"; exit 1; }
play() { # <case>
  d=$TMP/$1
  mkdir -p "$d/src/bin"
  printf '[package]\nname = "p"\nkind = "bin"\n' > "$d/bats.toml"
  printf 'implement main0 () = println! (1)\n' > "$d/src/bin/p.bats"
  rm -f "$TMP"/raw/*
  (cd "$d" && NO_COLOR=1 HOME="$H" FAKE="$1" "$BATS" check) > "$TMP/$1.log" 2>&1 || { cat "$TMP/$1.log"; fail "$1: bats check failed"; }
  made=0
  for c in $(find "$d/build" -name '*_dats.c' | sort); do
    made=$((made + 1))
    name=$(basename "$c")
    [ -f "$TMP/raw/$name" ] || continue # a C patsopt did not write (a dependency's)
    eval "check_$1" "$c" "$TMP/raw/$name"
  done
  [ "$made" -ge 1 ] || fail "$1: no C was made"
}
line4() { sed -n '4p' "$1"; }
# the two files have as many lines
same_lines() { # <made> <raw> <case>
  a=$(awk 'END { print NR }' "$1")
  b=$(awk 'END { print NR }' "$2")
  [ "$a" = "$b" ] || fail "$3: $1 has $a lines, bats was given $b"
}
fixed_at_4() { # <made> <case>
  [ "$(line4 "$1")" = "$FIXED" ] || fail "$2: $1 line 4 is: $(line4 "$1")"
  [ "$(grep -ac 'The starting compilation time is' "$1")" = 1 ] || fail "$2: $1 has not one dating line"
}
check_plain() { fixed_at_4 "$1" plain; same_lines "$1" "$2" plain; }
check_padded() {
  [ "$(line4 "$2")" = "${PREFIX}2026-01-02:  0h: 1m" ] || fail "padded: the stand-in did not pad the line"
  fixed_at_4 "$1" padded; same_lines "$1" "$2" padded
}
check_removed() {
  grep -aq 'The starting compilation time is' "$1" && fail "removed: $1 has a dating line"
  same_lines "$1" "$2" removed
}
check_moved() {
  [ "$(sed -n '5p' "$1")" = "$(sed -n '5p' "$2")" ] || fail "moved: the dating line at line 5 was changed: $(sed -n '5p' "$1")"
  grep -aq "^$PREFIX.*[0-9]h" "$1" || fail "moved: the line was changed"
  grep -aqx "${PREFIX}left out" "$1" && fail "moved: a line not at line 4 was made 'left out'"
  same_lines "$1" "$2" moved
}
check_lookalike() {
  [ "$(line4 "$1")" = "** The starting compilation time is:2026-01-02: 0h: 1m" ] || fail "lookalike: line 4 was changed: $(line4 "$1")"
  same_lines "$1" "$2" lookalike
}
for c in plain padded removed moved lookalike; do play $c; done
echo ok
