#!/bin/sh
# bats ats2 install's word on a toolchain bats did not make (bats-lang/bats#264):
# ~/.bats/ats2 with a bin/patsopt and no marker is used as it is, and
# bats says what its constraint solver does with the issue's false
# statement. patsopt is a stand-in here, one behaviour a case, in a private
# HOME, so no ATS2 is needed and a case takes a second (the cases that hang
# take the probe's 20 s and 25 s caps).
#  * a toolchain that accepts the false statement is said to be the -int build
#  * one that refuses it is said not to be, and not to be the -int build
#  * one that gives no answer to it (it hangs past the cap) is "cannot tell"
#  * one that ignores the TERM at the cap is ended by the KILL after it
#  * one that kills its parent (its status is never written) is "cannot tell"
#    after a few seconds, not a wait for ever, and leaves no probe directory
#  * one that fails the control (a true statement) is "cannot tell" too
#  * one that dies by a signal or with another status than 1 is "cannot tell"
#    and not kept
#  * each case says it is checking, and leaves no probe directory behind
#  * an answer is kept by the cksum of patsopt's bytes: the second run does not
#    run patsopt, a changed patsopt is asked again, a moved one is not, and an
#    answer that is not an answer is not kept
#  * with HOME unset there is no probe
# usage: tests/ats2-solver/check.sh <bats-binary>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
ok() { echo "ok   $1"; }
unset BATS_SLOTS BATS_LOCK_DIR BATS_SLOT_HELD BATS_CACHE_DIR BATS_PATSOPT_TIMEOUT_S BATS_PATSOPT_MEM_MB

# The stand-in patsopt: its last argument is the file it checks. The
# probe's control has no "1 == 2" in it, its false statement has. Its
# mode is read at each run from $TMP/mode, and each run is logged.
cat > "$TMP/patsopt" <<'STUB'
#!/bin/sh
for a in "$@"; do f=$a; done
echo run >> "$RUN_LOG"
case $(cat "$MODE_FILE") in
  accepts) exit 0 ;;
  refuses) grep -q '1 == 2' "$f" && exit 1; exit 0 ;;
  hangs) grep -q '1 == 2' "$f" && exec sleep 300; exit 0 ;;
  ignores) grep -q '1 == 2' "$f" && { trap '' TERM; exec sleep 300; }; exit 0 ;;
  kills) grep -q '1 == 2' "$f" && { kill -9 $PPID; exit 1; }; exit 0 ;;
  crashes) grep -q '1 == 2' "$f" && exit 3; exit 0 ;;
  broken) exit 2 ;;
esac
STUB
chmod +x "$TMP/patsopt"
MODE_FILE=$TMP/mode
RUN_LOG=$TMP/runs
export MODE_FILE RUN_LOG

new_home() { # $1 the mode, $2 the name of its home directory: sets H
  echo "$1" > "$TMP/mode"
  H="$TMP/home-$2"; rm -rf "$H"; mkdir -p "$H/.bats/ats2/bin"
  cp "$TMP/patsopt" "$H/.bats/ats2/bin/patsopt"
}
install_run() { # $1 the case: bats ats2 install in $H, its output in $TMP/out
  : > "$RUN_LOG"
  HOME="$H" "$BATS" ats2 install > "$TMP/out" 2>&1 || { cat "$TMP/out"; fail "$1: ats2 install failed on a toolchain it does not replace"; }
  grep -q "checking the ATS2 in" "$TMP/out" || { cat "$TMP/out"; fail "$1: no word that it is checking"; }
  [ -z "$(ls -d "$H"/.bats/ats2-probe.* 2>/dev/null)" ] || fail "$1: a probe directory was left behind"
  [ "$(head -1 "$H/.bats/ats2/bin/patsopt")" = "#!/bin/sh" ] || fail "$1: the toolchain was replaced"
}
case_run() { new_home "$1" "$2"; install_run "$1"; }
runs() { wc -l < "$RUN_LOG" | tr -d ' '; }
kept() { cat "$H/.bats/ats2.solver" 2>/dev/null || true; }
now() { date +%s; }
undecided() { # $1 the case
  grep -q "cannot tell which constraint solver it has" "$TMP/out" || { cat "$TMP/out"; fail "$1: not said to be undecided"; }
  grep -q "accepts a false statement" "$TMP/out" && { cat "$TMP/out"; fail "$1: said to be the -int build"; }
  [ ! -e "$H/.bats/ats2.solver" ] || fail "$1: an answer that is not one was kept"
  return 0
}

case_run accepts accepts
grep -q "accepts a false statement, so it is the -int build" "$TMP/out" || { cat "$TMP/out"; fail "an accepting toolchain is not said to be the -int build"; }
grep -q "cannot tell" "$TMP/out" && { cat "$TMP/out"; fail "an accepting toolchain is said to be undecided"; }
ok "a toolchain that accepts the false statement is said to be the -int build"

case_run refuses refuses
grep -q "refuses the false statement that the -int build accepts" "$TMP/out" || { cat "$TMP/out"; fail "a refusing toolchain is not said to refuse"; }
grep -q "accepts a false statement" "$TMP/out" && { cat "$TMP/out"; fail "a refusing toolchain is said to be the -int build"; }
ok "a toolchain that refuses the false statement is not said to be the -int build"

case_run hangs hangs
grep -q "cannot tell which constraint solver it has" "$TMP/out" || { cat "$TMP/out"; fail "a toolchain that gives no answer is not said to be undecided"; }
grep -q "accepts a false statement" "$TMP/out" && { cat "$TMP/out"; fail "a toolchain that gives no answer is said to be the -int build"; }
ok "a toolchain that gives no answer within the cap is said to be undecided"

case_run broken broken
undecided "a failed control"
ok "a toolchain that fails the control is said to be undecided, and not kept"

case_run crashes crashes
undecided "a status of 3"
ok "a toolchain that answers the false statement with a status other than 1 is undecided, and not kept"

# A patsopt that ignores the TERM sent at 20 s is ended by the KILL at 25 s
new_home ignores ignores
t0=$(now)
install_run "a patsopt that ignores TERM"
t1=$(now)
[ $((t1 - t0)) -lt 45 ] || fail "a patsopt that ignores TERM took $((t1 - t0)) s"
grep -q "cannot tell which constraint solver it has" "$TMP/out" || { cat "$TMP/out"; fail "a patsopt that ignores TERM is not said to be undecided"; }
ok "a patsopt that ignores the TERM at the cap is ended, and the answer is 'cannot tell'"

# A patsopt that kills the shell it was started by never lets a status be
# written: the probe gives up in a few seconds (it waited for ever), says it
# cannot tell, keeps nothing and leaves nothing
new_home kills kills
t0=$(now)
install_run "a patsopt that kills its parent"
t1=$(now)
[ $((t1 - t0)) -lt 15 ] || fail "a patsopt that kills its parent took $((t1 - t0)) s"
undecided "a patsopt that kills its parent"
ok "a patsopt that kills its parent is 'cannot tell' within seconds, not kept, and leaves no probe directory"

# The cache: ~/.bats/ats2.solver is "<cksum of patsopt's bytes> <answer>"
new_home accepts cached
install_run "the first run"
[ "$(runs)" = 2 ] || fail "the first run made $(runs) patsopt runs, not the control and the false statement"
sum=$(cksum < "$H/.bats/ats2/bin/patsopt")
[ "$(kept)" = "$sum 20" ] || fail "the answer kept is '$(kept)', not '$sum 20'"
install_run "the second run"
[ "$(runs)" = 0 ] || fail "the second run ran patsopt $(runs) times: the kept answer was not used"
grep -q "accepts a false statement, so it is the -int build" "$TMP/out" || { cat "$TMP/out"; fail "the second run did not say what the kept answer says"; }
ok "an answer is kept by the cksum of patsopt, and the second run does not run patsopt"

# A changed patsopt is asked again, even at the same path
echo refuses > "$TMP/mode"
printf '# another patsopt\n' >> "$H/.bats/ats2/bin/patsopt"
install_run "a changed patsopt"
[ "$(runs)" = 2 ] || fail "a changed patsopt made $(runs) patsopt runs, not 2"
grep -q "refuses the false statement" "$TMP/out" || { cat "$TMP/out"; fail "a changed patsopt was not asked again"; }
sum=$(cksum < "$H/.bats/ats2/bin/patsopt")
[ "$(kept)" = "$sum 21" ] || fail "the answer kept is '$(kept)', not '$sum 21'"
ok "a changed patsopt is asked again"

# The same bytes elsewhere are the same answer
cp "$H/.bats/ats2/bin/patsopt" "$TMP/moved"
rm "$H/.bats/ats2/bin/patsopt"; mv "$TMP/moved" "$H/.bats/ats2/bin/patsopt"
install_run "a moved patsopt"
[ "$(runs)" = 0 ] || fail "the same bytes were asked again ($(runs) runs)"
ok "the same bytes are not asked again"

# A hang is kept too: it is how the GMP build is told
case_run hangs hangs-kept
sum=$(cksum < "$H/.bats/ats2/bin/patsopt")
[ "$(kept)" = "$sum 22" ] || fail "a hang kept '$(kept)', not '$sum 22'"
install_run "a kept hang"
[ "$(runs)" = 0 ] || fail "a kept hang was asked again"
grep -q "cannot tell which constraint solver it has" "$TMP/out" || { cat "$TMP/out"; fail "a kept hang is not said to be undecided"; }
ok "a hang is kept, and not waited for again"

# HOME unset: bats cannot find ATS2 at all, and there is nothing to probe
: > "$RUN_LOG"
if env -u HOME "$BATS" ats2 install > "$TMP/out" 2>&1; then cat "$TMP/out"; fail "ats2 install with HOME unset succeeded"; fi
grep -q "HOME is not set" "$TMP/out" || { cat "$TMP/out"; fail "with HOME unset the word is not that HOME is not set"; }
grep -q "checking the ATS2" "$TMP/out" && { cat "$TMP/out"; fail "with HOME unset something was checked"; }
[ "$(runs)" = 0 ] || fail "with HOME unset patsopt was run"
ok "with HOME unset there is no probe"

# The answer is written by bats, through write_settle (bats-lang/bats#359): an
# answer that cannot be kept is said with its path and the system's reason,
# fails the build, and leaves no probe directory behind
new_home refuses unwritable
mkdir -p "$H/.bats/ats2.solver"
if HOME="$H" "$BATS" ats2 install > "$TMP/out" 2>&1; then cat "$TMP/out"; fail "an answer that cannot be kept did not fail the build"; fi
grep -q "error: cannot write '.*ats2.solver': Is a directory (os error 21)" "$TMP/out" || { cat "$TMP/out"; fail "an answer that cannot be kept is not said"; }
[ -z "$(ls -d "$H"/.bats/ats2-probe.* 2>/dev/null)" ] || fail "a probe directory was left behind by a failed answer"
ok "an answer that cannot be written is said, fails the build, and leaves no probe directory"
