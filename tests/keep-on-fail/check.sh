#!/bin/sh
# keep-on-fail (bats-lang/bats#478): a script that sources tests/keep-on-fail.sh
# keeps its temp directory when it exits non-zero, ends stderr with
# `kept: <path> (<test>)`, and removes the directory when it exits 0. The directory's
# name is neutral (`bats-tmp.XXXXXX`) and carries no word of the test's name.
# Detail: .claude/rules/keep-on-fail.md.
# usage: tests/keep-on-fail/check.sh [ignored arguments]
set -eu
HELPER=$(cd "$(dirname "$0")/.." && pwd)/keep-on-fail.sh
. "$HELPER"
KEPT=$TMP/kept
mkdir -p "$TMP/scripts"
fail() { echo "FAIL: $*" >&2; exit 1; }

# a script that fails: it writes a file, prints its directory, exits 3
cat > "$TMP/scripts/fails.sh" <<EOF
set -eu
. "$HELPER"
echo "\$TMP" > "$TMP/fails.dir"
echo evidence > "\$TMP/log"
echo "some output" >&2
exit 3
EOF
status=0
BATS_KEPT_DIR=$KEPT sh "$TMP/scripts/fails.sh" 2> "$TMP/fails.err" || status=$?
[ "$status" = 3 ] || fail "exit status $status, not 3"
dir=$(cat "$TMP/fails.dir")
[ -d "$dir" ] || fail "failing script's directory $dir is gone"
[ "$(cat "$dir/log")" = evidence ] || fail "failing script's file is not in $dir"
case $dir in "$KEPT"/*) ;; *) fail "$dir is not under BATS_KEPT_DIR $KEPT" ;; esac
last=$(tail -n 1 "$TMP/fails.err")
[ "$last" = "kept: $dir (scripts)" ] || fail "last stderr line: $last"
base=$(basename "$dir")
case $base in
  *scripts*) fail "directory name $base carries the test's name (scripts)" ;;
  bats-tmp.??????) ;;
  *) fail "directory name $base is not bats-tmp.XXXXXX" ;;
esac
grep -q 'some output' "$TMP/fails.err" || fail "the script's own stderr is lost"

# a script that fails under set -e (a command that fails, no exit) is kept too
cat > "$TMP/scripts/errexit.sh" <<EOF
set -eu
. "$HELPER"
echo "\$TMP" > "$TMP/errexit.dir"
false
EOF
BATS_KEPT_DIR=$KEPT sh "$TMP/scripts/errexit.sh" 2> "$TMP/errexit.err" &&
  fail "errexit script passed"
dir2=$(cat "$TMP/errexit.dir")
[ -d "$dir2" ] || fail "set -e script's directory is gone"
last=$(tail -n 1 "$TMP/errexit.err")
[ "$last" = "kept: $dir2 (scripts)" ] || fail "set -e: no kept line"

# a script that passes: its directory is gone and nothing is said
cat > "$TMP/scripts/passes.sh" <<EOF
set -eu
. "$HELPER"
echo "\$TMP" > "$TMP/passes.dir"
echo data > "\$TMP/log"
EOF
BATS_KEPT_DIR=$KEPT sh "$TMP/scripts/passes.sh" 2> "$TMP/passes.err" || fail "passing script failed"
dir3=$(cat "$TMP/passes.dir")
[ ! -e "$dir3" ] || fail "passing script's directory $dir3 is still there"
[ ! -s "$TMP/passes.err" ] || fail "passing script said: $(cat "$TMP/passes.err")"

# KEEP_ON_FAIL_TEARDOWN runs on a pass and on a failure, before the directory goes: the
# hook records whether the directory still held the script's file when it ran
cat > "$TMP/scripts/teardown-ok.sh" <<EOF
set -eu
teardown() { [ -f "\$TMP/log" ] && echo "\$TMP" > "$TMP/teardown.ok.saw"; }
KEEP_ON_FAIL_TEARDOWN=teardown
. "$HELPER"
echo data > "\$TMP/log"
echo "\$TMP" > "$TMP/teardown.ok.dir"
EOF
BATS_KEPT_DIR=$KEPT sh "$TMP/scripts/teardown-ok.sh" || fail "teardown script failed"
[ -e "$TMP/teardown.ok.saw" ] || fail "no teardown on a pass, or it ran after the directory went"
dir5=$(cat "$TMP/teardown.ok.dir")
[ ! -e "$dir5" ] || fail "the passing teardown script's directory $dir5 is still there"
cat > "$TMP/scripts/teardown-bad.sh" <<EOF
set -eu
teardown() { [ -f "\$TMP/log" ] && echo "\$TMP" > "$TMP/teardown.bad.saw"; }
KEEP_ON_FAIL_TEARDOWN=teardown
. "$HELPER"
echo data > "\$TMP/log"
echo "\$TMP" > "$TMP/teardown.bad.dir"
exit 1
EOF
BATS_KEPT_DIR=$KEPT sh "$TMP/scripts/teardown-bad.sh" 2> "$TMP/teardown-bad.err" &&
  fail "bad teardown script passed"
[ -e "$TMP/teardown.bad.saw" ] || fail "no teardown on a failure, or it ran after the directory"
dir6=$(cat "$TMP/teardown.bad.dir")
[ -f "$dir6/log" ] || fail "the failing teardown script's directory $dir6 was not kept"
last=$(tail -n 1 "$TMP/teardown-bad.err")
[ "$last" = "kept: $dir6 (scripts)" ] || fail "teardown failure: last stderr line: $last"

# without BATS_KEPT_DIR the directory is under TMPDIR
BATS_KEPT_DIR= TMPDIR=$TMP/other sh "$TMP/scripts/fails.sh" 2> "$TMP/other.err" || true
dir4=$(cat "$TMP/fails.dir")
case $dir4 in "$TMP/other"/*) ;; *) fail "$dir4 is not under TMPDIR" ;; esac
echo "ok"
