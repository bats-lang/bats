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
MOUNTED=
as_root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo -n "$@"; fi; }
# the mount goes on every exit; the rest of TMP stays on a failure (keep-on-fail)
unmount_full() {
  if [ -n "$MOUNTED" ]; then as_root umount "$TMP/full" || true; fi
}
KEEP_ON_FAIL_TEARDOWN=unmount_full
. "$(dirname "$0")/../keep-on-fail.sh"
unset BATS_CACHE_DIR BATS_COLD BATS_COMMIT
# the real ATS2 of this machine, behind a patsopt that lifts the limit
REAL=$HOME/.bats/ats2
H=$TMP/home
mkdir -p "$H/.bats/ats2/bin"
for d in prelude libats share ccomp; do ln -s "$REAL/$d" "$H/.bats/ats2/$d"; done
printf '#!/bin/sh\nulimit -S -f unlimited\nexec "%s" "$@"\n' "$REAL/bin/patsopt" > "$H/.bats/ats2/bin/patsopt"
chmod +x "$H/.bats/ats2/bin/patsopt"
mkdir -p "$H/.bats/ats2" && "$BATS" ats2 marker > "$H/.bats/ats2/.bats-ats2"

# a project of 800 functions, each declared with a long type, so that its
# .sats, .dats and C are of three different sizes (some 59 KB, 77 KB and 4.4
# MB), all over the 47 KB of the toolchain's listing (.bats_toolchain: one
# sha256 line per file of patsopt, prelude, libats, share and ccomp since
# bats#318; it was a cksum line per file, 22 KB), which a child of bats
# writes and which is the biggest other file of build/. The order the limits
# need is checked below, so a listing that grows again fails there, named.
mkdir -p "$TMP/project/src"
printf '[package]\nname = "app"\nkind = "lib"\n' > "$TMP/project/bats.toml"
{
  printf '#include "share/atspre_staload.hats"\n\n'
  i=0; while [ $i -lt 800 ]; do
    printf '#pub fun f%d {a,b,c:int | a >= 0; b >= 0; c >= 0} (x: int a, y: int b): int\n\n' $i
    i=$((i + 1))
  done
  i=0; while [ $i -lt 800 ]; do
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
VERB=check # the command run() plays: check, or build for a case that needs an object
run() {
  out=$(cd "$1"
    if [ "$3" = - ]; then
      st=0
      HOME="$H" BATS_REPOSITORY="$REPO" "$BATS" "$VERB" 2>&1 || st=$?
      echo "bats-status=$st"
    else
      blocks=$(( ($3 + unit - 1) / unit ))
      ( trap '' XFSZ
        ulimit -S -f "$blocks"
        st=0
        HOME="$H" BATS_REPOSITORY="$REPO" "$BATS" "$VERB" 2>&1 || st=$?
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

# A write that fails at the stamp (bats-lang/bats#335): build/.sats_changed is
# a directory, so the stamp cannot be written (EISDIR). No size limit singles
# it out, since it is smaller than any .sats. A project that staloads
# _bats_inputs.sats or _bats_facts.sats writes the stamp, then that .sats, then
# its .dats, the order of build.bats (bats-lang/bats#400): the check must fail
# (status 1), its first error naming the stamp, and write no .sats or .dats;
# the next check, with the directory gone, is the
# clean build's, file for file.
stamp_case() { # <name> <the staloaded file> <its module> <expression>
  d="$TMP/stamp-$1"
  mkdir -p "$d/src" "$d/build/.sats_changed"
  printf '[package]\nname = "stamp"\nkind = "bin"\n' > "$d/bats.toml"
  printf 'build/\ndist/\n' > "$d/.gitignore"
  printf '#include "share/atspre_staload.hats"\nstaload X = "%s"\nimplement main0 () = println! (%s)\n' "$2" "$4" > "$d/src/stamp.bats"
  (cd "$d" && git init -q -b main . && git add -A && git -c user.name=t -c user.email=t@t commit -q -m first)
  status=0
  run "$d" "$TMP/stamp-$1.log" - || status=$?
  if [ "$status" != 1 ]; then
    echo "FAIL: $1: a stamp that cannot be written: the check ended with status $status, not 1"
    cat "$TMP/stamp-$1.log"; exit 1
  fi
  line=$(grep -a '^error: ' "$TMP/stamp-$1.log" | head -1)
  case "$line" in
    "error: cannot write 'build/.sats_changed': "*"(os error "*")") ;;
    *) echo "FAIL: $1: the first error does not name the stamp:"; cat "$TMP/stamp-$1.log"; exit 1;;
  esac
  if [ -e "$d/build/src/$3.dats" ]; then
    echo "FAIL: $1: the $3.dats was written after the stamp failed"; cat "$TMP/stamp-$1.log"; exit 1
  fi
  # the stamp comes before the .sats (bats-lang/bats#400): no .sats after a stamp that failed
  if [ -e "$d/build/src/$3.sats" ]; then
    echo "FAIL: $1: the $3.sats was written before the stamp, which failed"; cat "$TMP/stamp-$1.log"; exit 1
  fi
  rmdir "$d/build/.sats_changed"
  run "$d" "$TMP/stamp-$1.next.log" - || { echo "FAIL: $1: the check after it failed"; cat "$TMP/stamp-$1.next.log"; exit 1; }
  ref="$TMP/stamp-$1-ref"
  # the same commit (the facts name it), with no build/
  rm -rf "$ref"; cp -R "$d" "$ref"; rm -rf "$ref/build"
  run "$ref" "$TMP/stamp-$1-ref.log" - || { echo "FAIL: $1: the clean check failed"; exit 1; }
  if ! diff -r -x .bats_valid -x .sats_changed -x .stash "$ref/build" "$d/build" > "$TMP/stamp-$1.diff" 2>&1; then
    echo "FAIL: $1: the build/ after the next check is not the clean build's:"
    head -20 "$TMP/stamp-$1.diff"; exit 1
  fi
  echo "ok   a stamp that cannot be written: $1"
}
stamp_case inputs _bats_inputs.sats _bats_inputs '$X.bats_inputs_sha256 ()'
stamp_case facts _bats_facts.sats _bats_facts '$X.bats_commit_short ()'

# The same for build.bats's own writer (bats-lang/bats#400): a module with a
# #pub declaration has its .sats written after the stamp, and neither it nor
# its .dats is written when the stamp cannot be.
module_dir="$TMP/stamp-module"
mkdir -p "$module_dir/src" "$module_dir/build/.sats_changed"
printf '[package]\nname = "stampmodule"\nkind = "lib"\n' > "$module_dir/bats.toml"
printf '#include "share/atspre_staload.hats"\n#pub fun one (): int\nimplement one () = 1\n' > "$module_dir/src/lib.bats"
status=0
run "$module_dir" "$TMP/stamp-module.log" - || status=$?
if [ "$status" != 1 ]; then
  echo "FAIL: a module: a stamp that cannot be written: the check ended with status $status, not 1"; cat "$TMP/stamp-module.log"; exit 1
fi
line=$(grep -a '^error: ' "$TMP/stamp-module.log" | head -1)
case "$line" in
  "error: cannot write 'build/.sats_changed': "*"(os error "*")") ;;
  *) echo "FAIL: a module: the first error does not name the stamp:"; cat "$TMP/stamp-module.log"; exit 1;;
esac
if [ -e "$module_dir/build/src/lib.sats" ] || [ -e "$module_dir/build/src/lib.dats" ]; then
  echo "FAIL: a module: its .sats or .dats was written although the stamp failed"; cat "$TMP/stamp-module.log"; exit 1
fi
rmdir "$module_dir/build/.sats_changed"
run "$module_dir" "$TMP/stamp-module.next.log" - || { echo "FAIL: a module: the check after it failed"; cat "$TMP/stamp-module.next.log"; exit 1; }
[ -f "$module_dir/build/src/lib.sats" ] && [ -f "$module_dir/build/src/lib.dats" ] || {
  echo "FAIL: a module: the check after it did not make the .sats and .dats"; exit 1; }
echo "ok   a stamp that cannot be written: a module's own .sats"

# A write that fails at the target marker (bats-lang/bats#367): build/.bats_target
# is a directory (EISDIR). The marker is one byte, so no size limit singles it
# out. The check must fail (status 1), its first error naming the marker, and
# write nothing after it: the native runtime is the next write, and it is made
# only by a run that went on as if the marker had been written. The next
# check, with the directory gone, is the clean one's, file for file.
marker_dir="$TMP/marker"
mkdir -p "$marker_dir/src" "$marker_dir/build/.bats_target"
printf '[package]\nname = "marker"\nkind = "bin"\n' > "$marker_dir/bats.toml"
printf '#include "share/atspre_staload.hats"\nimplement main0 () = println! ("hi")\n' > "$marker_dir/src/marker.bats"
status=0
run "$marker_dir" "$TMP/marker.log" - || status=$?
if [ "$status" != 1 ]; then
  echo "FAIL: a marker that cannot be written: the check ended with status $status, not 1"; cat "$TMP/marker.log"; exit 1
fi
line=$(grep -a '^error: ' "$TMP/marker.log" | head -1)
case "$line" in
  "error: cannot write 'build/.bats_target': "*"(os error "*")") ;;
  *) echo "FAIL: a marker that cannot be written: the first error does not name the marker:"; cat "$TMP/marker.log"; exit 1;;
esac
if [ -e "$marker_dir/build/_bats_native_runtime.c" ]; then
  echo "FAIL: a marker that cannot be written: the native runtime was written after it"; cat "$TMP/marker.log"; exit 1
fi
rmdir "$marker_dir/build/.bats_target"
run "$marker_dir" "$TMP/marker.next.log" - || { echo "FAIL: a marker that cannot be written: the check after it failed"; cat "$TMP/marker.next.log"; exit 1; }
[ -f "$marker_dir/build/.bats_target" ] && [ -f "$marker_dir/build/_bats_native_runtime.c" ] || {
  echo "FAIL: a marker that cannot be written: the check after it did not make the marker and the runtime"; exit 1; }
echo "ok   a marker that cannot be written"

# A write that fails at an object's key (bats-lang/bats#367): the key beside the
# object is a directory with a file in it, so it cannot be removed or written.
# The build must fail (status 1) saying so, naming the key, and the build after
# it, with the directory gone, makes the key again.
key_dir="$TMP/objkey"
mkdir -p "$key_dir/src/bin" "$key_dir/build/src/bin/marker_dats.o.key/x"
printf '[package]\nname = "objkey"\nkind = "bin"\n' > "$key_dir/bats.toml"
printf '#include "share/atspre_staload.hats"\nimplement main0 () = println! ("hi")\n' > "$key_dir/src/bin/marker.bats"
VERB=build
status=0
run "$key_dir" "$TMP/objkey.log" - || status=$?
if [ "$status" != 1 ]; then
  echo "FAIL: a key that cannot be written: the build ended with status $status, not 1"; cat "$TMP/objkey.log"; exit 1
fi
line=$(grep -a '^error: ' "$TMP/objkey.log" | head -1)
case "$line" in
  "error: cannot write 'build/src/bin/marker_dats.o.key': "*"(os error "*")") ;;
  *) echo "FAIL: a key that cannot be written: the first error does not name the key:"; cat "$TMP/objkey.log"; exit 1;;
esac
rm -rf "$key_dir/build/src/bin/marker_dats.o.key"
run "$key_dir" "$TMP/objkey.next.log" - || { echo "FAIL: a key that cannot be written: the build after it failed"; cat "$TMP/objkey.next.log"; exit 1; }
# (a build leaves the other mode's build/ in the stash, so the key is in one of the two)
[ -n "$(find "$key_dir/build" -type f -name marker_dats.o.key)" ] || { echo "FAIL: a key that cannot be written: the build after it made no key"; exit 1; }
VERB=check
echo "ok   a key that cannot be written"

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
