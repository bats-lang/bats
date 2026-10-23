#!/bin/sh
# What validate_project has judged is kept by content (bats-lang/bats#296):
# every source of the project and of its dependencies is lexed for the safety
# rules, and the package's implements are looked at for a call cycle, and on
# quire's set that was 23% of the instructions of a check in which nothing
# had changed. A file that passed is recorded under build/.bats_valid/ with
# a key that holds everything the judgment read (bats's inputs, the
# listing of ./bats_modules, the package's unsafe flag, the path and the
# sha256 of the file), and a package's cycle check with the path and sha256
# of each of its files. -v says each file lexed ("  ~ lexed <path>") and each
# package whose cycles are looked at ("  ~ call cycles of the package of
# <file>"). This plays, on a bin with two modules and a plain dependency
# with two:
#  * a cold check judges all 5 files and both packages; the next judges none,
#    also with every file of build/ and of the sources given a time in the
#    future or long ago (no time is read);
#  * a body changed with its size kept and its time put back is judged, alone,
#    and with its package's cycles, not the other package;
#  * a changed dependency file is judged with its own package only;
#  * a record that is missing, empty, garbled, cut short, or the key of another
#    file is not trusted;
#  * a file that fails is never recorded: it fails again, and once fixed it is
#    judged and then recorded; a validation in which anything fails records
#    nothing, and leaves no build/ in a project that had none;
#  * the unsafe flag is in the key: a file recorded in an unsafe package is
#    judged again, and rejected, when the package is safe, with the file as it
#    was;
#  * a call cycle through two files, of which only one changed, is found (the
#    package's key holds both files), and the check passes again, with the
#    old record, when the cycle is gone;
#  * --cold and BATS_COLD judge everything again;
#  * the listing of ./bats_modules is in every key: a file added to a
#    dependency judges every file again.
# usage: tests/check-validated/check.sh <bats-binary>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
. "$(dirname "$0")/../keep-on-fail.sh"
unset BATS_CACHE_DIR BATS_COLD
mkdir -p "$TMP/app/src/bin" "$TMP/plain/src"
printf '[package]\nname = "app"\nkind = "bin"\n\n[dependencies]\n"plain" = { path = "../plain" }\n' > "$TMP/app/bats.toml"
printf '[package]\nname = "plain"\nkind = "lib"\n' > "$TMP/plain/bats.toml"
printf '#pub fun h (): int\n\nimplement h () = 9\n' > "$TMP/plain/src/lib.bats"
printf '#pub fun k (): int\n\nimplement k () = 10\n' > "$TMP/plain/src/more.bats"
A=$TMP/app/src
printf '#pub fun fb (): int\n\nimplement fb () = 7\n' > "$A/b.bats"
printf 'staload "b.sats"\n\n#pub fun fa (): int\n\nimplement fa () = fb ()\n' > "$A/a.bats"
printf '#target native\n#include "share/atspre_staload.hats"\n#use plain as PL\n\nimplement main0 () = println! ("got ", $PL.h ())\n' > "$A/bin/tool.bats"
# A validation that fails leaves no build/ behind, whatever else passed
mkdir -p "$TMP/bad/src/bin"
printf '[package]\nname = "bad"\nkind = "bin"\n' > "$TMP/bad/bats.toml"
printf '#pub fun fine (): int\n\nimplement fine () = 1\n' > "$TMP/bad/src/fine.bats"
printf '$UNSAFE begin\nend\n\nimplement main0 () = ()\n' > "$TMP/bad/src/bin/m.bats"
if (cd "$TMP/bad" && "$BATS" check > "$TMP/bad.log" 2>&1); then echo "FAIL: an unsafe block in a safe package passed"; cat "$TMP/bad.log"; exit 1; fi
grep -aq 'UNSAFE requires' "$TMP/bad.log" || { echo "FAIL: not rejected for its unsafe block"; cat "$TMP/bad.log"; exit 1; }
[ ! -e "$TMP/bad/build" ] || { echo "FAIL: a failed validation left a build/"; ls -A "$TMP/bad/build"; exit 1; }
cd "$TMP/app"
N=0
run() { # <log> <command...>: bats -v <command>, which must pass
  l=$1; shift
  N=$((N + 1))
  "$BATS" -v "$@" > "$l" 2>&1 || { echo "FAIL: $*"; cat "$l"; exit 1; }
}
fails() { # <log> <command...>: bats -v <command>, which must fail
  l=$1; shift
  if "$BATS" -v "$@" > "$l" 2>&1; then echo "FAIL: $* passed"; cat "$l"; exit 1; fi
}
lexed() { grep -ac '^  ~ lexed ' "$1" || true; }
cycles() { grep -ac '^  ~ call cycles of ' "$1" || true; }
expect() { # <log> <what> <files lexed> <packages looked at for cycles>
  [ "$(lexed "$1")" = "$3" ] && [ "$(cycles "$1")" = "$4" ] || {
    echo "FAIL: $2: $(lexed "$1") files lexed (expected $3), $(cycles "$1") packages looked at for cycles (expected $4)"
    cat "$1"; exit 1; }
}
# A cold check judges everything; the next, and the one after, nothing
run c0.log check
expect c0.log "a cold check" 5 2
for f in a.bats b.bats bin%tool.bats; do
  [ -f "build/.bats_valid/.%src%$f" ] || { echo "FAIL: no record of src/$f"; ls -A build/.bats_valid; exit 1; }
done
run c1.log check
expect c1.log "the first no-change check" 0 0
run c2.log check
expect c2.log "the second no-change check" 0 0
# Times are not read
find build -type f -exec touch -d '2040-01-01 00:00:00' {} +
find src -type f -exec touch -d '2040-01-01 00:00:00' {} +
run c3.log check
expect c3.log "a check with every file in the future" 0 0
find build -type f -exec touch -d '2001-01-01 00:00:00' {} +
find src -type f -exec touch -d '2001-01-01 00:00:00' {} +
run c4.log check
expect c4.log "a check with every file long ago" 0 0
# A file changed, its time put back: that file, and its package's cycles
printf 'staload "b.sats"\n\n#pub fun fa (): int\n\nimplement fa () = fb ()\n\n(* changed *)\n' > "$A/a.bats"
touch -d '2001-01-01 00:00:00' "$A/a.bats"
run d0.log check
expect d0.log "a changed body" 1 1
grep -aq '~ lexed ./src/a.bats$' d0.log || { echo "FAIL: not src/a.bats"; cat d0.log; exit 1; }
run d1.log check
expect d1.log "the check after a changed body" 0 0
# The same size: 7 and 8
printf '#pub fun fb (): int\n\nimplement fb () = 8\n' > "$A/b.bats"
touch -d '2001-01-01 00:00:00' "$A/b.bats"
run d2.log check
expect d2.log "a body changed with its size kept" 1 1
run d3.log check
expect d3.log "the check after it" 0 0
# A dependency's file: its own package only (the copy in bats_modules is made
# again by the check, with the new time)
printf '#pub fun k (): int\n\nimplement k () = 11\n' > "$TMP/plain/src/more.bats"
run e0.log check
expect e0.log "a changed dependency file" 1 1
grep -aq 'call cycles of the package of ./bats_modules/plain/' e0.log || { echo "FAIL: not plain's cycles"; cat e0.log; exit 1; }
run e1.log check
expect e1.log "the check after a changed dependency file" 0 0
# A record that is missing, empty, garbled, cut short or another file's is
# not trusted: the file is judged, and recorded again
R=build/.bats_valid/.%src%b.bats
O=build/.bats_valid/.%src%a.bats
rm "$R"
run f0.log check
expect f0.log "a missing record" 1 0
: > "$R"
run f1.log check
expect f1.log "an empty record" 1 0
printf 'garbled\n' > "$R"
run f2.log check
expect f2.log "a garbled record" 1 0
head -c 63 "$O" > "$R"
run f3.log check
expect f3.log "a record cut short" 1 0
cp "$O" "$R"
run f4.log check
expect f4.log "another file's key" 1 0
cat "$O" "$O" > "$R"
run f5.log check
expect f5.log "a record twice as long" 1 0
run f6.log check
expect f6.log "the check after those" 0 0
# A file that fails is not recorded: it fails again, and once fixed it passes
cp "$A/b.bats" "$TMP/b.keep"
printf '#pub fun fb (): int\n\nextern fun hidden (): int\n\nimplement fb () = 8\n' > "$A/b.bats"
fails g0.log check
grep -aq 'extern' g0.log || { echo "FAIL: no word on the rejected construct"; cat g0.log; exit 1; }
[ ! -f "$R" ] || [ "$(cat "$R")" != "$(cat "$O")" ] || { echo "FAIL: a failed file was recorded under another's key"; exit 1; }
fails g1.log check
[ "$(lexed g1.log)" = 1 ] || { echo "FAIL: the failing file was not judged again ($(lexed g1.log))"; cat g1.log; exit 1; }
cp "$TMP/b.keep" "$A/b.bats"
run g2.log check
# (nothing is recorded by a run that failed, and the records of the file as
# it was before still hold)
expect g2.log "a fixed file" 0 0
run g3.log check
expect g3.log "the check after a fix" 0 0
# The unsafe flag is in the key: a file recorded in an unsafe package is
# judged again, and rejected, when the package is safe
printf '[package]\nname = "app"\nkind = "bin"\nunsafe = true\n\n[dependencies]\n"plain" = { path = "../plain" }\n' > bats.toml
printf '$UNSAFE begin\n\n%%{\nint square(int x) { return x * x; }\n%%}\n\nend\n' > "$A/c.bats"
run h0.log check
# (every file of the package is judged again: its flag is in each key)
expect h0.log "an unsafe package with an unsafe block" 4 1
run h1.log check
expect h1.log "the check after it" 0 0
printf '[package]\nname = "app"\nkind = "bin"\n\n[dependencies]\n"plain" = { path = "../plain" }\n' > bats.toml
fails h2.log check
grep -aq 'UNSAFE requires' h2.log || { echo "FAIL: the unsafe block was not rejected in a safe package"; cat h2.log; exit 1; }
[ "$(lexed h2.log)" = 4 ] || { echo "FAIL: the files recorded as unsafe were not judged again ($(lexed h2.log))"; cat h2.log; exit 1; }
rm "$A/c.bats"
run h3.log check
# (the failed run recorded nothing: the three that passed are judged for a
# safe package, and the package's files are not the ones it was recorded with)
expect h3.log "the check after the file is gone" 3 1
# A call cycle through two files, of which one changed: both files pass on
# their own, and the package's key holds both
cp "$A/b.bats" "$TMP/b.keep"
printf 'staload "a.sats"\n\n#pub fun fb (): int\n\nimplement fb () = fa ()\n' > "$A/b.bats"
fails i0.log check
grep -aq "calls itself" i0.log || { echo "FAIL: the cycle was not found"; cat i0.log; exit 1; }
[ "$(lexed i0.log)" = 1 ] || { echo "FAIL: the cycle: $(lexed i0.log) files lexed"; cat i0.log; exit 1; }
fails i1.log check
grep -aq "calls itself" i1.log || { echo "FAIL: the cycle was not found again"; cat i1.log; exit 1; }
cp "$TMP/b.keep" "$A/b.bats"
run i2.log check
[ "$(cycles i2.log)" = 0 ] || { echo "FAIL: the package's old record was not trusted once the cycle was gone"; cat i2.log; exit 1; }
run i3.log check
expect i3.log "the check after the cycle is gone" 0 0
# --cold and BATS_COLD judge everything again
run j0.log check --cold
expect j0.log "check --cold" 5 2
run j1.log check
expect j1.log "the check after --cold" 0 0
BATS_COLD=1 run j2.log check
expect j2.log "BATS_COLD" 5 2
# Which packages are installed is read by the judgment of each #use, so the
# listing of ./bats_modules is in every key: a file added to a dependency
# judges every file again (the new one too)
printf '#pub fun m (): int\n\nimplement m () = 12\n' > "$TMP/plain/src/extra.bats"
run k0.log check
expect k0.log "a file added to a dependency" 6 2
run k1.log check
expect k1.log "the check after it" 0 0
echo "check-validated: ok"
