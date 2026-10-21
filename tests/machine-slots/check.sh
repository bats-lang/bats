#!/bin/sh
# The machine's slots (bats-lang/bats#252): with BATS_SLOTS set, check,
# build, test and run's build each hold one of that many slots, flock on
# <BATS_LOCK_DIR>/slot-<i>.lock, across projects. A stand-in patsopt
# logs when each run starts and ends, and which bats ran it, and takes a
# second.
#  * One slot, two projects: the second bats says it waits, naming who
#    took the slot, and no patsopt run of one falls inside the other's.
#  * Two slots: both run at once, and neither waits.
#  * A bats killed holding the slot leaves it free once what it started
#    has ended.
#  * A bats that a slot's holder starts (BATS_SLOT_HELD, here from the
#    stand-in patsopt) runs in that slot, not waiting for it; a
#    BATS_SLOT_HELD that no one holds is not trusted.
#  * BATS_SLOTS unset or empty: nothing is made, read or said.
# usage: tests/machine-slots/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_CACHE_DIR BATS_SLOTS BATS_LOCK_DIR BATS_SLOT_HELD
REAL=$HOME/.bats/ats2
H=$TMP/home
mkdir -p "$H/.bats/ats2/bin"
for d in prelude libats share ccomp; do ln -s "$REAL/$d" "$H/.bats/ats2/$d"; done
LOG=$TMP/runs
NESTED=$TMP/nested
cat > "$H/.bats/ats2/bin/patsopt" <<SH
#!/bin/sh
case "\$*" in *ats2-probe*) exec "$REAL/bin/patsopt" "\$@" ;; esac
owner=\$PPID
echo "start \$owner" >> "$LOG"
# the kill case: a run waits here until the test has killed the bats that
# started it, so that bats is killed while it still holds the slot
if [ -f "$TMP/gate" ]; then while [ ! -f "$TMP/gate.open" ]; do sleep 0.1; done; fi
# the nested case: once, a bats run by what holds the slot
if [ -f "$NESTED/on" ] && [ -z "\${INNER:-}" ]; then
  rm -f "$NESTED/on"
  echo "\${BATS_SLOT_HELD:-}" > "$NESTED/held"
  (cd "$TMP/p3" && INNER=1 "$BATS" check > "$NESTED/log" 2>&1; echo \$? > "$NESTED/rc")
fi
sleep 1
"$REAL/bin/patsopt" "\$@"
rc=\$?
echo "end \$owner" >> "$LOG"
exit \$rc
SH
chmod +x "$H/.bats/ats2/bin/patsopt"
project() {
  mkdir -p "$TMP/$1/src/bin"
  printf '[package]\nname = "%s"\nkind = "bin"\n' "$1" > "$TMP/$1/bats.toml"
  printf '#pub fn h (): int\n\nimplement h () = 1\n' > "$TMP/$1/src/m.bats"
  printf 'staload "m.sats"\nimplement main0 () = println! (h ())\n' > "$TMP/$1/src/bin/$1.bats"
}
for p in p1 p2 p3 p4 p5; do project $p; done
SLOTS=$TMP/slots
fresh() { rm -rf "$TMP/p1/build" "$TMP/p1/dist" "$TMP/p2/build" "$TMP/p2/dist"; : > "$LOG"; }
# no run of one bats starts while the other bats's run is going
apart() {
  awk '
    $1 == "start" { if (open != "" && open != $2) { print "overlap: " $2 " started inside " open; bad = 1 } open = $2; n[$2]++ }
    $1 == "end" { n[$2]--; if (n[$2] == 0) open = "" }
    END { exit bad }' "$LOG"
}
build() { (cd "$TMP/$1" && HOME="$H" "$BATS" build --only debug --only native); }
# Waits, bounded, until the stand-in has logged a start: a bats that has
# started patsopt holds its slot, so what follows can wait for that
await_started() {
  i=0
  until grep -q '^start ' "$LOG"; do
    i=$((i + 1))
    if [ $i -gt 600 ]; then echo "FAIL: nothing started in 120 s"; cat "$LOG"; ps -ef | grep "$TMP" | grep -v grep; exit 1; fi
    sleep 0.2
  done
}
# Waits, bounded, until every run the stand-in logged for bats $1 has ended
await_ended() {
  i=0
  while [ "$(grep -c "^start $1\$" "$LOG")" != "$(grep -c "^end $1\$" "$LOG")" ]; do
    i=$((i + 1))
    if [ $i -gt 600 ]; then echo "FAIL: a patsopt of killed bats $1 has not ended in 120 s, so it still holds the slot"; cat "$LOG"; ps -ef | grep "$TMP" | grep -v grep; exit 1; fi
    sleep 0.2
  done
}

# one slot, two projects: they take turns
fresh
BATS_SLOTS=1 BATS_LOCK_DIR=$SLOTS build p1 > "$TMP/a.log" 2>&1 &
a=$!
await_started
BATS_SLOTS=1 BATS_LOCK_DIR=$SLOTS build p2 > "$TMP/b.log" 2>&1 &
b=$!
wait $a || { echo "FAIL: the first build"; cat "$TMP/a.log"; exit 1; }
wait $b || { echo "FAIL: the second build"; cat "$TMP/b.log"; exit 1; }
grep -qF "waiting for another bats on this machine (1 at once, BATS_SLOTS; $SLOTS/slot-0.lock was last taken by bats build in " "$TMP/b.log" || { echo "FAIL: the second bats did not say it waited, and for whom"; cat "$TMP/b.log"; exit 1; }
grep -q "was last taken by bats build in .*/p1)" "$TMP/b.log" || { echo "FAIL: the waiting line does not name the first project"; cat "$TMP/b.log"; exit 1; }
if grep -q "waiting" "$TMP/a.log"; then echo "FAIL: the first bats waited"; cat "$TMP/a.log"; exit 1; fi
[ "$(grep -c '^start' "$LOG")" -ge 4 ] || { echo "FAIL: too few patsopt runs"; cat "$LOG"; exit 1; }
apart || { echo "FAIL: one slot, but the two builds ran patsopt at once"; cat "$LOG"; exit 1; }
# the holder clears its note as it releases the slot
[ "$(head -n 1 "$SLOTS/slot-0.lock")" = "" ] || { echo "FAIL: a released slot keeps its note"; cat "$SLOTS/slot-0.lock"; exit 1; }

# two slots: both at once
fresh
BATS_SLOTS=2 BATS_LOCK_DIR=$SLOTS build p1 > "$TMP/a.log" 2>&1 &
a=$!
await_started
BATS_SLOTS=2 BATS_LOCK_DIR=$SLOTS build p2 > "$TMP/b.log" 2>&1 &
b=$!
wait $a || { echo "FAIL: the first build (2 slots)"; cat "$TMP/a.log"; exit 1; }
wait $b || { echo "FAIL: the second build (2 slots)"; cat "$TMP/b.log"; exit 1; }
if grep -q "waiting" "$TMP/a.log" "$TMP/b.log"; then echo "FAIL: a bats waited with 2 slots"; cat "$TMP/a.log" "$TMP/b.log"; exit 1; fi
if apart > /dev/null; then echo "FAIL: 2 slots, but the builds took turns"; cat "$LOG"; exit 1; fi

# a bats killed holding the slot leaves it free
fresh
rm -f "$TMP/gate.open"; : > "$TMP/gate"
# exec: $c is the bats itself, so the kill reaches it (a subshell's pid
# would leave bats running as an orphan that still holds the slot)
( cd "$TMP/p1" && exec env HOME="$H" BATS_SLOTS=1 BATS_LOCK_DIR=$SLOTS "$BATS" build --only debug --only native ) > "$TMP/c.log" 2>&1 &
c=$!
await_started
kill -KILL $c
wait $c 2>/dev/null || true
# what it started inherited the slot (its patsopt, held at the gate): let it
# run on, and wait for that run to end, so nothing holds the slot
rm -f "$TMP/gate"; : > "$TMP/gate.open"
await_ended $c
BATS_SLOTS=1 BATS_LOCK_DIR=$SLOTS build p2 > "$TMP/d.log" 2>&1 || { echo "FAIL: build after a killed one"; cat "$TMP/d.log"; exit 1; }
if grep -q "waiting" "$TMP/d.log"; then echo "FAIL: a killed bats left the slot held"; cat "$TMP/d.log"; exit 1; fi
[ "$("$TMP/p2/dist/debug/p2")" = 1 ] || { echo "FAIL: the binary"; cat "$TMP/d.log"; ls -R "$TMP/p2/dist" || true; exit 1; }

# nested: the slot's holder runs a bats (in another project), which runs
# in its slot instead of waiting for it
fresh
mkdir -p "$NESTED"
touch "$NESTED/on"
BATS_SLOTS=1 BATS_LOCK_DIR=$SLOTS build p1 > "$TMP/e.log" 2>&1 &
e=$!
waited=0
while kill -0 $e 2>/dev/null; do
  sleep 1
  waited=$((waited + 1))
  if [ $waited -gt 120 ]; then kill -KILL $e; pkill -KILL -f "$TMP/p3" || true; echo "FAIL: the nested bats deadlocked"; cat "$NESTED/log" 2>/dev/null; exit 1; fi
done
wait $e || { echo "FAIL: the outer build"; cat "$TMP/e.log"; exit 1; }
[ "$(cat "$NESTED/held")" = "$SLOTS/slot-0.lock" ] || { echo "FAIL: what the holder starts is not told the slot: '$(cat "$NESTED/held")'"; exit 1; }
[ "$(cat "$NESTED/rc")" = 0 ] || { echo "FAIL: the nested check"; cat "$NESTED/log"; exit 1; }
if grep -q "waiting" "$NESTED/log"; then echo "FAIL: the nested bats waited"; cat "$NESTED/log"; exit 1; fi
# a BATS_SLOT_HELD that no one holds is not trusted: that bats takes the
# slot, and another waits for it
fresh
BATS_SLOT_HELD=$SLOTS/slot-0.lock BATS_SLOTS=1 BATS_LOCK_DIR=$SLOTS build p1 > "$TMP/f.log" 2>&1 &
f=$!
await_started
BATS_SLOTS=1 BATS_LOCK_DIR=$SLOTS build p2 > "$TMP/g.log" 2>&1
wait $f || { echo "FAIL: the build with a stale BATS_SLOT_HELD"; cat "$TMP/f.log"; exit 1; }
grep -q "waiting for another bats on this machine" "$TMP/g.log" || { echo "FAIL: a stale BATS_SLOT_HELD let a bats run without its slot"; cat "$TMP/g.log"; exit 1; }
apart || { echo "FAIL: a stale BATS_SLOT_HELD let two builds run at once"; cat "$LOG"; exit 1; }

# not set, or empty: nothing made under ~/.cache, nothing said, the same
# output as before
rm -rf "$H/.cache"
(cd "$TMP/p4" && HOME="$H" "$BATS" check > "$TMP/unset.log" 2>&1) || { echo "FAIL: check with BATS_SLOTS unset"; cat "$TMP/unset.log"; exit 1; }
(cd "$TMP/p5" && BATS_SLOTS= HOME="$H" "$BATS" check > "$TMP/empty.log" 2>&1) || { echo "FAIL: check with BATS_SLOTS empty"; cat "$TMP/empty.log"; exit 1; }
[ ! -e "$H/.cache" ] || { echo "FAIL: BATS_SLOTS unset, but bats made $H/.cache"; ls -R "$H/.cache"; exit 1; }
# Only the project's own name is renamed, and only on its built line: the
# logs also hold the temporary directory (the toolchain warning names H),
# which mktemp draws at random and may hold p5, so a global s/p5/p4/ fails
# at random (bats#264 put that path in the logs).
sed 's/^built \.\/dist\/debug\/p5 (debug)$/built .\/dist\/debug\/p4 (debug)/' "$TMP/empty.log" | cmp -s - "$TMP/unset.log" || { echo "FAIL: BATS_SLOTS empty said something unset does not"; diff "$TMP/unset.log" "$TMP/empty.log"; exit 1; }
if grep -qi "slot" "$TMP/unset.log"; then echo "FAIL: BATS_SLOTS unset, but bats spoke of slots"; cat "$TMP/unset.log"; exit 1; fi
# a value that is not a slot count is said, and the command runs
(cd "$TMP/p4" && BATS_SLOTS=two HOME="$H" "$BATS" check > "$TMP/bad.log" 2>&1) || { echo "FAIL: check with BATS_SLOTS=two"; cat "$TMP/bad.log"; exit 1; }
grep -q "warning: BATS_SLOTS is not a number from 1 to 64" "$TMP/bad.log" || { echo "FAIL: BATS_SLOTS=two was not said"; cat "$TMP/bad.log"; exit 1; }
echo "machine-slots: ok"
