#!/bin/sh
# In check mode, a module whose .sats has only moved is checked again on
# its own, in each of check's two passes (native, then wasm, each with a
# cache of its own): a private declaration added before m's #pub one
# moves it to another line of m.sats (the private lines are kept blank,
# so patsopt's line numbers are the .bats's), and main, which staloads
# m.sats, keeps its C. Each pass used to find the other's cache and
# emit everything again, and every .sats change made every module's C
# stale, so a static test that adds a snippet to one module checked the
# whole project again, twice. What still makes main's C stale: a change
# to a #pub declaration; a newline that may be in a string literal of
# the .sats (a string's length is part of its type); and any .sats
# change in build mode, whose C is shipped.
# usage: tests/sats-moved/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
P=$TMP/p
mkdir -p "$P/src/bin"
printf '[package]\nname = "sm"\nkind = "bin"\n' > "$P/bats.toml"
m() { # <private lines before the #pub ones> <#pub lines>
  printf '#include "share/atspre_staload.hats"\n\n%s\n#pub fn f (): int\n\n%s\nimplement f () = 1\n' "$1" "$2" > "$P/src/m.bats"
}
m '' ''
printf '#include "share/atspre_staload.hats"\nstaload "m.sats"\nimplement main0 () = println! (f ())\n' > "$P/src/bin/sm.bats"
# check builds native, then wasm; sm is a native binary, so what is
# checked is in the native pass's cache, kept aside in build/.stash/2
# (its mark: native, in check mode) while build/ holds the wasm pass's
cache() { # <directory under build/, or nothing>
  S=$P/build/$1src/m.sats
  C=$P/build/$1src/bin/sm_dats.c
  MC=$P/build/$1src/m_dats.c
}
cache .stash/2/
run() { # <bats command> <step>
  if [ "$1" = build ]; then set -- "$1" "$2" --only debug --only native; else set -- "$1" "$2"; fi
  command=$1; name=$2; shift 2
  (cd "$P" && "$BATS" "$command" "$@") > "$TMP/out" 2>&1 || { echo "FAIL: $name: bats $command"; cat "$TMP/out"; exit 1; }
  # Freshness is by whole-second mtimes, and patsopt takes less than a
  # second here: C made in the second its .dats was would be taken for
  # stale. Every input of patsopt's (the .dats, the .sats, the stamp) is
  # made older than the C made from it, as in a project whose modules
  # take longer.
  find "$P/build" -type f ! -name '*_dats.c' -exec touch -d "@$(( $(date +%s) - 10 ))" {} +
}
# Freshness is by whole-second mtimes: each change is a second later
step() { # <bats command> <step>: m changed, then bats run
  touch -r "$S" "$TMP/sats"; touch -r "$C" "$TMP/main"; touch -r "$MC" "$TMP/m"
  run "$1" "$2"
}
run check first
# with nothing changed, nothing is checked again: each pass finds its
# own cache, not the other's
sleep 1
step check "nothing changed"
[ ! "$C" -nt "$TMP/main" ] || { echo "FAIL: main was checked again with nothing changed"; exit 1; }
[ ! "$MC" -nt "$TMP/m" ] || { echo "FAIL: m was checked again with nothing changed"; exit 1; }
sleep 1
m 'fn g (): int = 2
fn h (): int = g () + 1
' ''
step check "a private declaration added"
[ "$S" -nt "$TMP/sats" ] || { echo "FAIL: m.sats did not move"; exit 1; }
[ "$MC" -nt "$TMP/m" ] || { echo "FAIL: m was not checked again"; exit 1; }
[ ! "$C" -nt "$TMP/main" ] || { echo "FAIL: main was checked again for a .sats that only moved"; exit 1; }
sleep 1
m 'fn g (): int = 2
fn h (): int = g () + 1
' '#pub fn k (): int

implement k () = 3
'
step check "a #pub declaration added"
[ "$C" -nt "$TMP/main" ] || { echo "FAIL: main was not checked again for a #pub change"; exit 1; }
sleep 1
m '' '#pub macdef s = "a
b"
'
step check "a #pub string literal with a newline"
sleep 1
m 'fn g (): int = 2
' '#pub macdef s = "a
b"
'
step check "moved, with a newline in a string literal"
[ "$C" -nt "$TMP/main" ] || { echo "FAIL: main was not checked again for a .sats with a newline in a string"; exit 1; }
sleep 1
m '' ''
step build "build"
cache ''
sleep 1
m 'fn g (): int = 2
' ''
step build "moved, in build mode"
[ "$C" -nt "$TMP/main" ] || { echo "FAIL: main's C was kept in build mode"; exit 1; }
echo "sats-moved: ok"
