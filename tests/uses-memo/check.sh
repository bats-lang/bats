#!/bin/sh
# The #use packages of a file are kept by content (bats-lang/bats#310).
# Every check lexes each .bats file of the project, of its path dependencies
# and of its locked packages for its #use lines (resolve_deps, collect_uses),
# and that was 8% of a check in which nothing had changed on quire's set. A
# file that was lexed leaves a record under build/.bats_valid/, named
# "uses <path>", keyed by the sha256 of bats's inputs, the path and the bytes
# of the file, with the names its #use lines give. -v says each file lexed
# ("  ~ uses lexed <path>"). This plays:
#  * a #use added, removed, and changed in a file with its size kept
#    (ghost_a for ghost_b) is noticed: the check names the package it misses;
#  * a check in which nothing changed lexes no file, with every file given a
#    time in the future and then long ago (no time is read);
#  * a changed file, with its time put back, is lexed alone;
#  * a record that is garbled, cut short, or another file's is not trusted:
#    the file is lexed again, and its record is written again;
#  * --cold lexes every file;
#  * a path dependency's file, read through bats.lock, is recorded by lock and
#    by check, and a #use added to it is noticed.
# usage: tests/uses-memo/check.sh <bats-binary>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_CACHE_DIR BATS_COLD

lexed() { grep -ac '^  ~ uses lexed ' "$1" || true; }
run() { # <log> <command...>: bats -v <command>, which must pass
  l=$1; shift
  "$BATS" -v "$@" > "$l" 2>&1 || { echo "FAIL: $*"; cat "$l"; exit 1; }
}
expect_lexed() { # <log> <what> <files lexed>
  [ "$(lexed "$1")" = "$3" ] || { echo "FAIL: $2: $(lexed "$1") files lexed (expected $3)"; cat "$1"; exit 1; }
}
missing() { # <log> <name that must be named> [<name that must not be>]
  if "$BATS" -v check > "$1" 2>&1; then echo "FAIL: the check passed, with $2 missing"; cat "$1"; exit 1; fi
  grep -a '^error: missing dependencies: ' "$1" | grep -q "$2" || { echo "FAIL: $2 not named"; cat "$1"; exit 1; }
  if [ -n "${3:-}" ] && grep -a '^error: missing dependencies: ' "$1" | grep -q "$3"; then
    echo "FAIL: $3 is still named"; cat "$1"; exit 1
  fi
}

# ---- 1. A #use is noticed, added, changed in place, removed ----
mkdir -p "$TMP/app/src/sub"
printf '[package]\nname = "app"\nkind = "lib"\n' > "$TMP/app/bats.toml"
printf '#use ghost_a as GA\n\n#pub fun g (): int\n\nimplement g () = 1\n' > "$TMP/app/src/lib.bats"
printf '#pub fun k (): int\n\nimplement k () = 2\n' > "$TMP/app/src/sub/more.bats"
cd "$TMP/app"
missing m0.log ghost_a
printf '#use ghost_b as GA\n\n#pub fun g (): int\n\nimplement g () = 1\n' > src/lib.bats
touch -d '2001-01-01 00:00:00' src/lib.bats
missing m1.log ghost_b ghost_a
printf '#use ghost_b as GA\n#use ghost_c as GC\n\n#pub fun g (): int\n\nimplement g () = 1\n' > src/lib.bats
missing m2.log ghost_c
grep -a '^error: missing dependencies: ' m2.log | grep -q ghost_b || { echo "FAIL: ghost_b lost with ghost_c added"; cat m2.log; exit 1; }
printf '#use ghost_c as GC\n\n#pub fun g (): int\n\nimplement g () = 1\n' > src/lib.bats
missing m3.log ghost_c ghost_b
printf '#pub fun g (): int\n\nimplement g () = 1\n' > src/lib.bats
run p0.log check
cd "$TMP"

# ---- 2. Lexing: once per changed file, none when nothing changed ----
mkdir -p "$TMP/b/src/sub"
printf '[package]\nname = "b"\nkind = "lib"\n' > "$TMP/b/bats.toml"
printf '#pub fun g (): int\n\nimplement g () = 1\n' > "$TMP/b/src/lib.bats"
printf '#pub fun k (): int\n\nimplement k () = 2\n' > "$TMP/b/src/sub/more.bats"
cd "$TMP/b"
R1=build/.bats_valid/uses\ src%lib.bats
R2=build/.bats_valid/uses\ src%sub%more.bats
run b0.log check
expect_lexed b0.log "a first check, which makes no build/ for records" 2
grep -aq '^  ~ uses lexed src/lib.bats$' b0.log || { echo "FAIL: lib.bats not named"; cat b0.log; exit 1; }
grep -aq '^  ~ uses lexed src/sub/more.bats$' b0.log || { echo "FAIL: sub/more.bats not named"; cat b0.log; exit 1; }
[ ! -e "$R1" ] || { echo "FAIL: a record was written by the check that made build/"; exit 1; }
run b1.log check
expect_lexed b1.log "the check that writes the records" 2
[ -f "$R1" ] && [ -f "$R2" ] || { echo "FAIL: no record of each file"; ls -A build/.bats_valid; exit 1; }
run b1b.log check
expect_lexed b1b.log "the next no-change check" 0
run b2.log check
expect_lexed b2.log "a no-change check" 0
find build -type f -exec touch -d '2040-01-01 00:00:00' {} +
find src -type f -exec touch -d '2040-01-01 00:00:00' {} +
run b3.log check
expect_lexed b3.log "a check with every file in the future" 0
find build -type f -exec touch -d '2001-01-01 00:00:00' {} +
find src -type f -exec touch -d '2001-01-01 00:00:00' {} +
run b4.log check
expect_lexed b4.log "a check with every file long ago" 0
# A changed body, its size kept and its time put back: that file alone
printf '#pub fun g (): int\n\nimplement g () = 3\n' > src/lib.bats
touch -d '2001-01-01 00:00:00' src/lib.bats
run b5.log check
expect_lexed b5.log "a changed body" 1
grep -aq '^  ~ uses lexed src/lib.bats$' b5.log || { echo "FAIL: not lib.bats"; cat b5.log; exit 1; }
run b6.log check
expect_lexed b6.log "the check after it" 0
# Records that are not trusted: garbled, cut short, another file's
printf 'garbage that is not a record\n' > "$R2"
run b7.log check
expect_lexed b7.log "a garbled record" 1
grep -aq '^  ~ uses lexed src/sub/more.bats$' b7.log || { echo "FAIL: garbled record not lexed"; cat b7.log; exit 1; }
run b8.log check
expect_lexed b8.log "the check after a garbled record" 0
head -c 100 "$R2" > "$R2.cut" && mv "$R2.cut" "$R2"
run b9.log check
expect_lexed b9.log "a cut-short record" 1
run c0.log check
expect_lexed c0.log "the check after a cut-short record" 0
cp "$R1" "$R2"
run c1.log check
expect_lexed c1.log "another file's record" 1
run c2.log check
expect_lexed c2.log "the check after another file's record" 0
# --cold lexes every file, and writes the records again
"$BATS" -v check --cold > c3.log 2>&1 || { echo "FAIL: --cold"; cat c3.log; exit 1; }
expect_lexed c3.log "--cold" 2

# ---- 3. A path dependency's file, through bats.lock ----
mkdir -p "$TMP/plain/src" "$TMP/repo" "$TMP/d/src"
printf '[package]\nname = "plain"\nkind = "lib"\n' > "$TMP/plain/bats.toml"
printf '#pub fun h (): int\n\nimplement h () = 9\n' > "$TMP/plain/src/lib.bats"
printf '[package]\nname = "d"\nkind = "bin"\n\n[dependencies]\n"plain" = { path = "../plain" }\n' > "$TMP/d/bats.toml"
mkdir -p "$TMP/d/src/bin"
printf '#target native\n#include "share/atspre_staload.hats"\n\nimplement main0 () = println! ("d")\n' > "$TMP/d/src/bin/d.bats"
cd "$TMP/d"
"$BATS" lock --repository "$TMP/repo" > lock.log 2>&1 || { echo "FAIL: lock"; cat lock.log; exit 1; }
run d0.log check
expect_lexed d0.log "the first check after the lock, which makes no build/" 2
run d00.log check
expect_lexed d00.log "the check that writes the records" 2
run d01.log check
expect_lexed d01.log "the check after it" 0
printf '#use ghost_p as GP\n#pub fun h (): int\n\nimplement h () = 9\n' > "$TMP/plain/src/lib.bats"
touch -d '2001-01-01 00:00:00' "$TMP/plain/src/lib.bats"
if "$BATS" -v check > d1.log 2>&1; then echo "FAIL: a #use added to a path dependency passed"; cat d1.log; exit 1; fi
grep -aq ghost_p d1.log || { echo "FAIL: ghost_p not named"; cat d1.log; exit 1; }
expect_lexed d1.log "a changed path dependency" 1
printf '#pub fun h (): int\n\nimplement h () = 9\n' > "$TMP/plain/src/lib.bats"
touch -d '2001-01-01 00:00:00' "$TMP/plain/src/lib.bats"
run d2.log check
expect_lexed d2.log "the check after the path dependency is put back" 1
run d3.log check
expect_lexed d3.log "the next check" 0
echo "uses-memo: ok"
