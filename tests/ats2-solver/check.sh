#!/bin/sh
# bats ats2 install's word on a toolchain bats did not make (bats-lang/bats#264):
# ~/.bats/ats2 with a bin/patsopt and no marker is used as it is, and
# bats says what its constraint solver does with the issue's false
# statement. patsopt is a stand-in here, one behaviour a case, in a private
# HOME, so no ATS2 is needed and a case takes a second (the hangs case
# takes the probe's 20 s cap).
#  * a toolchain that accepts the false statement is said to be the -int build
#  * one that refuses it is said not to be, and not to be the -int build
#  * one that gives no answer to it (it hangs past the cap) is "cannot tell"
#  * one that fails the control (a true statement) is "cannot tell" too
#  * each case says it is checking, and leaves no probe directory behind
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
# mode is read at each run from $TMP/mode.
cat > "$TMP/patsopt" <<'STUB'
#!/bin/sh
for a in "$@"; do f=$a; done
case $(cat "$MODE_FILE") in
  accepts) exit 0 ;;
  refuses) grep -q '1 == 2' "$f" && exit 1; exit 0 ;;
  hangs) grep -q '1 == 2' "$f" && exec sleep 300; exit 0 ;;
  broken) exit 2 ;;
esac
STUB
chmod +x "$TMP/patsopt"
MODE_FILE=$TMP/mode
export MODE_FILE

case_run() { # $1 the mode, $2 the name of its home directory
  echo "$1" > "$TMP/mode"
  H="$TMP/home-$2"; rm -rf "$H"; mkdir -p "$H/.bats/ats2/bin"
  cp "$TMP/patsopt" "$H/.bats/ats2/bin/patsopt"
  HOME="$H" "$BATS" ats2 install > "$TMP/out" 2>&1 || { cat "$TMP/out"; fail "$1: ats2 install failed on a toolchain it does not replace"; }
  grep -q "checking the ATS2 in" "$TMP/out" || { cat "$TMP/out"; fail "$1: no word that it is checking"; }
  [ -z "$(ls -d "$H"/.bats/ats2-probe.* 2>/dev/null)" ] || fail "$1: a probe directory was left behind"
  [ "$(head -1 "$H/.bats/ats2/bin/patsopt")" = "#!/bin/sh" ] || fail "$1: the toolchain was replaced"
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
grep -q "cannot tell which constraint solver it has" "$TMP/out" || { cat "$TMP/out"; fail "a toolchain that fails the control is not said to be undecided"; }
ok "a toolchain that fails the control is said to be undecided"
