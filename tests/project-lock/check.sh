#!/bin/sh
# Two bats on one project take turns (bats-lang/bats#250): each holds
# the project's lock (flock on bats.toml) while it writes build/, and
# the one that waits says so. A stand-in patsopt logs when each run
# starts and ends, and which bats ran it, and takes a second: no run of
# one bats falls inside a run of the other. A bats killed while it holds
# the lock leaves nothing held once what it started (a patsopt, which
# inherits the lock as it inherits the open file) has ended.
# usage: tests/project-lock/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
. "$(dirname "$0")/../keep-on-fail.sh"
. "$(dirname "$0")/../ats2-marker.sh"
unset BATS_CACHE_DIR
REAL=$HOME/.bats/ats2
H=$TMP/home
mkdir -p "$H/.bats/ats2/bin"
for d in prelude libats share ccomp; do ln -s "$REAL/$d" "$H/.bats/ats2/$d"; done
LOG=$TMP/runs
printf '#!/bin/sh\necho "start $PPID" >> "%s"\nsleep 1\n"%s" "$@"\nrc=$?\necho "end $PPID" >> "%s"\nexit $rc\n' "$REAL/bin/patsopt" "$LOG" "$REAL/bin/patsopt" "$LOG" > "$H/.bats/ats2/bin/patsopt"
chmod +x "$H/.bats/ats2/bin/patsopt"
ats2_marker "$H"
P=$TMP/p
mkdir -p "$P/src/bin"
printf '[package]\nname = "pl"\nkind = "bin"\n' > "$P/bats.toml"
printf '#pub fn h (): int\n\nimplement h () = 1\n' > "$P/src/m.bats"
printf 'staload "m.sats"\nimplement main0 () = println! (h ())\n' > "$P/src/bin/pl.bats"
cd "$P"
HOME="$H" "$BATS" build --only debug --only native > "$TMP/a.log" 2>&1 &
a=$!
# the second starts while the first runs patsopt
sleep 1
HOME="$H" "$BATS" build --only debug --only native > "$TMP/b.log" 2>&1 &
b=$!
wait $a || { echo "FAIL: the first build"; cat "$TMP/a.log"; exit 1; }
wait $b || { echo "FAIL: the second build"; cat "$TMP/b.log"; exit 1; }
grep -q "waiting for another bats running in this project" "$TMP/b.log" || { echo "FAIL: the second bats did not say it waited"; cat "$TMP/b.log"; exit 1; }
[ "$(grep -c '^start' "$LOG")" -ge 3 ] || { echo "FAIL: too few patsopt runs"; cat "$LOG"; exit 1; }
# no run starts while another bats's run is going
awk '
  $1 == "start" { if (open != "" && open != $2) { print "overlap: " $2 " started inside " open; bad = 1 } open = $2; n[$2]++ }
  $1 == "end" { n[$2]--; if (n[$2] == 0) open = "" }
  END { exit bad }' "$LOG" || { echo "FAIL: the two builds ran patsopt at once"; cat "$LOG"; exit 1; }
# a bats killed holding the lock leaves it free
: > "$LOG"
rm -rf build dist
HOME="$H" "$BATS" build --only debug --only native > "$TMP/c.log" 2>&1 &
c=$!
sleep 1
kill -KILL $c
wait $c 2>/dev/null || true
# the patsopt it started inherited the lock and still writes build/:
# once it ends, nothing holds the lock
sleep 4
HOME="$H" "$BATS" build --only debug --only native > "$TMP/d.log" 2>&1 || { echo "FAIL: build after a killed one"; cat "$TMP/d.log"; exit 1; }
if grep -q "waiting for another bats" "$TMP/d.log"; then echo "FAIL: a killed bats left the lock held"; exit 1; fi
[ "$(./dist/debug/pl)" = 1 ] || { echo "FAIL: the binary"; exit 1; }
echo "project-lock: ok"
