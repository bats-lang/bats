#!/bin/sh
# A write that is refused only at the final flush is an error, never success
# (bats-lang/bats#508, keyword: write-errors): a writer holds its bytes in a
# buffer, so the small marker of the target is written by the flush at the
# close, and a close that drops the flush's answer takes a refused write for
# a good one. build/.bats_target is a link to /dev/full, which opens for
# writing and refuses every write (ENOSPC), so only the final flush fails.
# The check must fail (status 1), its first error naming the marker with the
# system's reason (ENOSPC, os error 28), and write nothing after it: the
# native runtime is the next write.
# usage: tests/final-flush/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$(cd "$2" && pwd)
. "$(dirname "$0")/../keep-on-fail.sh"
unset BATS_CACHE_DIR BATS_COLD BATS_COMMIT

d="$TMP/project"
mkdir -p "$d/src" "$d/build"
printf '[package]\nname = "flush"\nkind = "bin"\n' > "$d/bats.toml"
printf '#include "share/atspre_staload.hats"\nimplement main0 () = println! ("hi")\n' > "$d/src/flush.bats"
ln -s /dev/full "$d/build/.bats_target"
status=0
out=$(cd "$d" && BATS_REPOSITORY="$REPO" "$BATS" check 2>&1) || status=$?
if [ "$status" != 1 ]; then
  echo "FAIL: a marker whose final flush is refused: the check ended with status $status, not 1"
  printf '%s\n' "$out"; exit 1
fi
line=$(printf '%s\n' "$out" | grep -a '^error: ' | head -1)
case "$line" in
  "error: cannot write 'build/.bats_target': No space left on device (os error 28)"*) ;;
  *) echo "FAIL: the first error does not name the marker and the refused flush:"
     printf '%s\n' "$out"; exit 1;;
esac
if [ -e "$d/build/_bats_native_runtime.c" ]; then
  echo "FAIL: the native runtime was written after the marker's flush was refused"
  printf '%s\n' "$out"; exit 1
fi
echo "ok   a marker whose final flush is refused"
echo "final-flush: all passed"
