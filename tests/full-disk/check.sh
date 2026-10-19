#!/bin/sh
# A write that fails is an error, never a file taken as whole (bats-lang/bats#359,
# #360): the shared host's disk filled in the middle of a run and bats built
# from a C file cut short at the point the write failed. This plays the same
# failure without filling a disk: a limit on the size of a file
# (`ulimit -f`, SIGXFSZ ignored, so a write past it fails with EFBIG as a
# write on a full file system fails with ENOSPC), and a project whose files
# are of very different sizes (a module's .sats and .dats are a few tens of
# kilobytes, its C a few hundred times that), so each limit stops the
# writers of the files over it and no others. patsopt is a wrapper that lifts
# the limit for the real one: the limit is for what bats itself writes.
#
# For each limit, a check in a fresh copy of the project must
#  * fail (status 1, not a signal), the first error saying "error: cannot
#    write '<path>': <the system's reason> (os error <n>)" with the path of
#    a file under build/, and no other write tried after it,
#  * leave no module's C that is not the C of an unlimited check, or a key
#    that says it is fresh: the next check, with no limit, makes the build/
#    the unlimited check of a clean copy makes, file for file.
# The limits: one that only the C is over (relative_c's), one that the .dats
# and the C are over, one that the .sats and everything bigger is over, and
# 0, which every file with a byte in it is over (the stamp, the keys, the
# digests: the small writers).
# usage: tests/full-disk/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$(cd "$2" && pwd)
TMP=$(mktemp -d)
MOUNTED=
as_root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo -n "$@"; fi; }
cleanup() {
  if [ -n "$MOUNTED" ]; then as_root umount "$TMP/full" || true; fi
  rm -rf "$TMP"
}
trap cleanup EXIT
unset BATS_CACHE_DIR BATS_COLD
# the real ATS2 of this machine, behind a patsopt that lifts the limit
REAL=$HOME/.bats/ats2
H=$TMP/home
mkdir -p "$H/.bats/ats2/bin"
for d in prelude libats share ccomp; do ln -s "$REAL/$d" "$H/.bats/ats2/$d"; done
printf '#!/bin/sh\nulimit -S -f unlimited\nexec "%s" "$@"\n' "$REAL/bin/patsopt" > "$H/.bats/ats2/bin/patsopt"
chmod +x "$H/.bats/ats2/bin/patsopt"

# a project of 400 functions, each declared with a long type, so that its
# .sats, .dats and C are of three different sizes (some 30 KB, 40 KB and 2.4
# MB), all over the 22 KB of the toolchain's listing, which a child of bats
# writes and which is the biggest other file of build/
mkdir -p "$TMP/project/src"
printf '[package]\nname = "app"\nkind = "lib"\n' > "$TMP/project/bats.toml"
{
  printf '#include "share/atspre_staload.hats"\n\n'
  i=0; while [ $i -lt 400 ]; do
    printf '#pub fun f%d {a,b,c:int | a >= 0; b >= 0; c >= 0} (x: int a, y: int b): int\n\n' $i
    i=$((i + 1))
  done
  i=0; while [ $i -lt 400 ]; do
    printf 'implement f%d (x, y) = if x > y then (x + y) * (x - y) else (if x = y then x * y else y - x)\n' $i
    i=$((i + 1))
  done
} > "$TMP/project/src/lib.bats"

# the unit of ulimit -f here: 512 or 1024 bytes (it differs between shells)
unit=1024
( ulimit -S -f 1; trap "" XFSZ; yes | head -c 700 > "$TMP/unit.probe" ) 2> "$TMP/unit.err" || true
[ "$(wc -c < "$TMP/unit.probe")" = 700 ] || unit=512

fresh() { # <dir>: a copy of the project
  mkdir -p "$1"
  cp -R "$TMP/project/src" "$TMP/project/bats.toml" "$1/"
}
# <dir> <log> <limit in bytes or -> : bats check in dir, with files limited;
# its output is read through a pipe and written to the log from here, since
# the log is a file too (with a limit of 0 nothing can be written to it by
# the limited shell); the status is the function's (set -e would end the
# subshell at a failed check, before it says the status)
run() {
  out=$(cd "$1"
    if [ "$3" = - ]; then
      st=0
      HOME="$H" BATS_REPOSITORY="$REPO" "$BATS" check 2>&1 || st=$?
      echo "bats-status=$st"
    else
      blocks=$(( ($3 + unit - 1) / unit ))
      ( trap '' XFSZ
        ulimit -S -f "$blocks"
        st=0
        HOME="$H" BATS_REPOSITORY="$REPO" "$BATS" check 2>&1 || st=$?
        echo "bats-status=$st" )
    fi)
  status=${out##*bats-status=}
  printf '%s\n' "${out%bats-status=*}" > "$2"
  return "$status"
}

fresh "$TMP/ref"
run "$TMP/ref" "$TMP/ref.log" - || { echo "FAIL: the unlimited check failed"; cat "$TMP/ref.log"; exit 1; }
c_size=$(wc -c < "$TMP/ref/build/src/lib_dats.c")
dats_size=$(wc -c < "$TMP/ref/build/src/lib.dats")
sats_size=$(wc -c < "$TMP/ref/build/src/lib.sats")
# the biggest of the other files of build/ (not the stashes' copies)
rest=$(find "$TMP/ref/build" -type f ! -path '*/.stash/*' ! -name 'lib_dats.c' ! -name 'lib.dats' ! -name 'lib.sats' -exec wc -c {} + | grep -v ' total$' | sort -n | tail -1 | awk '{print $1}')
[ "$c_size" -gt $((dats_size * 4)) ] && [ "$dats_size" -gt $((sats_size + unit * 4)) ] && [ "$sats_size" -gt $((rest + unit * 4)) ] || {
  echo "FAIL (the test): the sizes are not in the order the limits need: C $c_size, .dats $dats_size, .sats $sats_size, the rest $rest"; exit 1; }
only_c=$(( (c_size + dats_size) / 2 ))
dats_c=$(( (dats_size + sats_size) / 2 ))
sats_up=$(( (sats_size + rest) / 2 ))

n=0
try() { # <name> <limit in bytes> <a file name the first error names, or -> [many]
  n=$((n + 1))
  d="$TMP/case$n"
  fresh "$d"
  status=0
  run "$d" "$TMP/case$n.log" "$2" || status=$?
  if [ "$status" != 1 ]; then
    echo "FAIL: $1 (limit $2 bytes): the check ended with status $status, not 1"
    cat "$TMP/case$n.log"; exit 1
  fi
  # the first error is the write that failed, and no other write is tried
  line=$(grep -a '^error: ' "$TMP/case$n.log" | head -1)
  if [ -z "$line" ]; then
    echo "FAIL: $1 (limit $2 bytes): no error line"; ls -R "$d/build" | head -30
    cat "$TMP/case$n.log"; exit 1
  fi
  if [ "${4:-}" != many ] && [ "$(grep -ac "cannot write" "$TMP/case$n.log")" != 1 ]; then
    echo "FAIL: $1 (limit $2 bytes): not exactly one write reported as failed"
    cat "$TMP/case$n.log"; exit 1
  fi
  case "$line" in
    "error: cannot write '"*"build/"*"': "*"(os error "*")") ;;
    *) echo "FAIL: $1 (limit $2 bytes): the first error does not say 'cannot write <file under build/>: <reason> (os error n)':"
       cat "$TMP/case$n.log"; exit 1;;
  esac
  case "$3" in -) ;; *)
    case "$line" in *"$3"*) ;; *) echo "FAIL: $1 (limit $2 bytes): the error does not name $3:"; cat "$TMP/case$n.log"; exit 1;; esac;;
  esac
  case "$line" in
    *"o space"*|*"ile too large"*) ;;
    *) echo "FAIL: $1: the reason is not that the file is too large or the space gone:"; cat "$TMP/case$n.log"; exit 1;;
  esac
  # the next check, with room, is the clean build's, file for file (but for
  # the records of what was judged, the stamp of changed .sats and the
  # stash of the other mode's build, which hold the history of the runs)
  run "$d" "$TMP/case$n.next.log" - || { echo "FAIL: $1: the check after it failed"; cat "$TMP/case$n.next.log"; exit 1; }
  if ! diff -r -x .bats_valid -x .sats_changed -x .stash "$TMP/ref/build" "$d/build" > "$TMP/case$n.diff" 2>&1; then
    echo "FAIL: $1 (limit $2 bytes): the build/ after the next check is not the clean build's:"
    head -20 "$TMP/case$n.diff"; exit 1
  fi
  echo "ok   $1"
}
try "a C that does not fit" "$only_c" "lib_dats.c"
try "a .dats and a C that do not fit" "$dats_c" "lib.dats"
try "a .sats and everything bigger that do not fit" "$sats_up" "lib.sats"
# (every small file fails, each independent writer says so, and the tools bats
# starts fail too: only the first error and the recovery are asked)
try "no file with a byte in it fits" 0 - many

# A file system that really is full, where one can be mounted (root, or sudo
# with no password: CI's runners have it; a small tmpfs, never the disk the
# test runs on): the write fails with ENOSPC, "No space left on device", and
# the free space of build/ is said (bats-lang/bats#314); the next check, once
# the file system has room, is the clean build's.
if as_root true 2> "$TMP/sudo.err" && mkdir -p "$TMP/full" && as_root mount -t tmpfs -o size=3m tmpfs "$TMP/full" 2> "$TMP/mount.err"; then
  MOUNTED=1
  as_root chown "$(id -u)" "$TMP/full"
  fresh "$TMP/full/app"
  status=0
  run "$TMP/full/app" "$TMP/full.log" - || status=$?
  if [ "$status" != 1 ]; then
    echo "FAIL: a full tmpfs: the check ended with status $status, not 1"; cat "$TMP/full.log"; exit 1
  fi
  line=$(grep -a '^error: ' "$TMP/full.log" | head -1)
  case "$line" in
    "error: cannot write '"*"lib_dats.c.new': No space left on device (os error 28); "*" MB free in build") ;;
    *) echo "FAIL: a full tmpfs: the first error does not say that the C could not be written for want of space, with the free space:"
       cat "$TMP/full.log"; exit 1;;
  esac
  as_root mount -o remount,size=64m "$TMP/full"
  run "$TMP/full/app" "$TMP/full.next.log" - || { echo "FAIL: a full tmpfs: the check after it failed"; cat "$TMP/full.next.log"; exit 1; }
  if ! diff -r -x .bats_valid -x .sats_changed -x .stash "$TMP/ref/build" "$TMP/full/app/build" > "$TMP/full.diff" 2>&1; then
    echo "FAIL: a full tmpfs: the build/ after the next check is not the clean build's:"; head -20 "$TMP/full.diff"; exit 1
  fi
  echo "ok   a file system that is full"
else
  echo "skip a file system that is full (no tmpfs can be mounted here: needs root, or sudo with no password)"
fi
echo "full-disk: all passed"
