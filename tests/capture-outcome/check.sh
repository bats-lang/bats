#!/bin/sh
# run_cmd_capture_outcome (bats-lang/bats#444, capture area): real children
# that write in pieces with pauses, more than a pipe holds, and exit non-zero
# give the outcomes of the type, apart; and a caller that ignores the
# "longer" case does not compile.
# usage: tests/capture-outcome/check.sh <bats-binary> <repository-dir>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$(cd "$2" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
. "$(dirname "$0")/../keep-on-fail.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
# A copy of the compiler's project with the driver as a second binary
mkdir -p "$TMP/app"
cp -R "$ROOT/bats.toml" "$ROOT/src" "$TMP/app/"
[ ! -f "$ROOT/bats.lock" ] || cp "$ROOT/bats.lock" "$TMP/app/"
cp "$HERE/driver.bats" "$TMP/app/src/bin/capture-outcome.bats"
cd "$TMP/app"
"$BATS" build --repository "$REPO" > "$TMP/build.log" 2>&1 || { cat "$TMP/build.log"; fail "the driver did not build"; }
./dist/debug/capture-outcome > "$TMP/got" 2>&1 || { cat "$TMP/got"; fail "the driver failed"; }
cat > "$TMP/want" <<'WANT'
old-form: status=3 len=3
small: fits 3
empty: fits 0
paused: fits 8
failed: failed status=3 kept=3
exact: fits 4096
one-over: longer status=0 written=0*1048576+4097
pieces: longer status=0 written=0*1048576+10000
longer-failed: longer status=5 written=0*1048576+10000
pipe-full: longer status=0 written=0*1048576+300000
stderr-heavy: fits 2
killed: wait-failed kept=3 written=0*1048576+3
killed-longer: wait-failed kept=4096 written=0*1048576+5000
past-1gib: longer status=0 written=1024*1048576+5000
WANT
cat "$TMP/got"
diff "$TMP/want" "$TMP/got" || fail "outcomes differ"
# A caller that does not handle CaptureLonger is rejected
cat >> src/bin/capture-outcome.bats <<'BAD'

fn ignore_longer {le:agz}{lo:agz}{ne:pos}{cs:$A.cells}{k:nat | k < ne}
  (nul: $P.NUL_AT(cs, ne, k) | exec_bv: !$A.cborrow(le, ne, cs), argv: $L.listv($P.arg_entry),
   outbuf: !$A.arr(byte, lo, 4096)): int =
  case+ run_cmd_capture_outcome(nul | exec_bv, argv, outbuf) of
  | ~CaptureFits(n) => n
  | ~CaptureFailed(_, n) => n
  | ~CaptureReadFailed(n, _) => n
  | ~CaptureWaitFailed(n, _, _) => n
  | ~CaptureNotRun(_) => 0
BAD
if "$BATS" check --repository "$REPO" > "$TMP/bad.log" 2>&1; then
  fail "a match without CaptureLonger was accepted"
fi
# patsopt names the missing constructor, on the line after "nonexhaustive:", as these exact lines
grep -qx 'CaptureLonger(_, _, _)' "$TMP/bad.log" || { cat "$TMP/bad.log"; fail "rejected, but the error does not name the missing CaptureLonger arm"; }
grep -q 'error(3): pattern match is nonexhaustive:$' "$TMP/bad.log" || { cat "$TMP/bad.log"; fail "rejected, but not for a nonexhaustive match"; }
[ "$(grep -c 'error(3)' "$TMP/bad.log")" = 1 ] || { cat "$TMP/bad.log"; fail "rejected for more than the one missing arm"; }
echo "capture-outcome: ok"
