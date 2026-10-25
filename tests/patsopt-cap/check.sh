#!/bin/sh
# The optional cap on every patsopt run (bats-lang/quire#594: the GMP
# solver can run away in time and memory on a proof the machine-integer
# solver answers at once). BATS_PATSOPT_TIMEOUT_S (wall clock seconds)
# and BATS_PATSOPT_MEM_MB (address space, megabytes) hold each patsopt
# run to a limit; a run the cap ends fails the build naming its module,
# the cap and how to raise it, with its own exit status (124 time, 125
# memory), not a patsopt error. A stand-in patsopt stands for the
# solver's runaway: it sleeps, or allocates until malloc fails (and then
# says what ATS's allocator says, or aborts).
#  * Unset or empty: patsopt is started by bats itself, nothing is said,
#    and the output is that of an uncapped bats.
#  * Generous caps change nothing but who starts patsopt: the C is the
#    same, and no timer outlives the run (bats returns at once and the
#    project is not left locked).
#  * The time cap ends a run that does not finish, and says so; so does it
#    patsopt --depgen, which the check memo runs after a module passed.
#  * The memory cap ends a run that allocates too much, whether it says
#    so or aborts, and says so.
#  * A patsopt error under a cap is still a patsopt error, exit status 1.
#  * A value that is not a count is said and ignored.
# usage: tests/patsopt-cap/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
. "$(dirname "$0")/../keep-on-fail.sh"
. "$(dirname "$0")/../ats2-marker.sh"
unset BATS_CACHE_DIR BATS_SLOTS BATS_LOCK_DIR BATS_SLOT_HELD BATS_PATSOPT_TIMEOUT_S BATS_PATSOPT_MEM_MB
REAL=$HOME/.bats/ats2
H=$TMP/home
mkdir -p "$H/.bats/ats2/bin"
for d in prelude libats share ccomp; do ln -s "$REAL/$d" "$H/.bats/ats2/$d"; done
LOG=$TMP/parents
: > "$LOG"

# a program that allocates 64 MiB blocks (touching them) until malloc
# fails, at most 16 of them: then it says what ATS's allocator says
# (hog), or aborts (abort)
cat > "$TMP/hog.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
  int i;
  for (i = 0; i < 16; i++) {
    char *p = malloc((size_t)64 << 20);
    if (!p) {
      if (argc > 1 && argv[1][0] == 'a') abort();
      fputs("exit(ATS): [ats_malloc_gc] failed.\n", stderr);
      return 1;
    }
    memset(p, 1, (size_t)64 << 20);
  }
  return 0;
}
C
${CC:-cc} -o "$TMP/hog" "$TMP/hog.c"

# the stand-in patsopt: notes the name of its parent (bats, or sh when
# the cap started it), then does what FAKE says, else runs the real one
cat > "$H/.bats/ats2/bin/patsopt" <<SH
#!/bin/sh
# patsopt --depgen lists the files a module reads (the check memo runs it
# after a module passed, bats#267). It is held to the caps like any patsopt
# run, but it is started by sh in every case, so its parent says nothing of
# whether a cap is set: it is not logged. FAKE=depgen-sleep makes it hang.
for a in "\$@"; do
  if [ "\$a" = --depgen ]; then
    if [ "\${FAKE:-}" = depgen-sleep ]; then exec sleep 60; fi
    exec "$REAL/bin/patsopt" "\$@"
  fi
done
basename "\$(ps -o comm= -p \$PPID | tr -d ' ')" >> "$LOG"
case "\${FAKE:-}" in
  sleep) exec sleep 60 ;;
  hog) exec "$TMP/hog" hog ;;
  abort) exec "$TMP/hog" abort ;;
esac
exec "$REAL/bin/patsopt" "\$@"
SH
chmod +x "$H/.bats/ats2/bin/patsopt"
ats2_marker "$H"

project() { # <directory>: a project of one binary, named p
  mkdir -p "$1/src/bin"
  printf '[package]\nname = "p"\nkind = "bin"\n' > "$1/bats.toml"
  printf 'implement main0 () = println! (1)\n' > "$1/src/bin/p.bats"
}
for d in plain empty generous time mem broken warn depgen; do project "$TMP/$d"; done
printf '#include "share/atspre_staload.hats"\n\nval x: int = "s"\nimplement main0 () = ()\n' > "$TMP/broken/src/bin/p.bats"

# run <directory> <log>: check in the directory with the environment given
# before it; the status in $rc, the seconds it took in $secs
run() {
  d=$1
  shift
  start=$(date +%s)
  rc=0
  (cd "$TMP/$d" && NO_COLOR=1 HOME="$H" "$@" "$BATS" check) > "$TMP/$d.log" 2>&1 || rc=$?
  secs=$(($(date +%s) - start))
}
fail() { echo "FAIL: $1"; cat "$TMP/$2.log"; exit 1; }
parent_of_last() { tail -n 1 "$LOG"; }
is_sh() { case $1 in sh|dash|bash|ash|ksh|zsh) return 0 ;; esac; return 1; }

# unset: bats starts patsopt itself, says nothing of caps
run plain env
[ $rc = 0 ] || fail "check with no cap" plain
is_sh "$(parent_of_last)" && fail "with no cap, patsopt was started by sh, not bats ($(parent_of_last))" plain
if grep -q "PATSOPT" "$TMP/plain.log"; then fail "with no cap, bats spoke of one" plain; fi
# empty: the same
: > "$LOG"
run empty env BATS_PATSOPT_TIMEOUT_S= BATS_PATSOPT_MEM_MB=
[ $rc = 0 ] || fail "check with empty caps" empty
is_sh "$(parent_of_last)" && fail "with empty caps, patsopt was started by sh, not bats" empty
sed 's/empty/plain/g' "$TMP/empty.log" | cmp -s - "$TMP/plain.log" || { echo "FAIL: empty caps said something unset caps do not"; diff "$TMP/plain.log" "$TMP/empty.log"; exit 1; }

# generous caps: the same C, no timer left behind (it would hold the
# project's lock and the stderr pipe until its seconds were up)
(cd "$TMP/plain" && HOME="$H" "$BATS" build --only debug --only native > "$TMP/plain-build.log" 2>&1) || fail "build with no cap" plain-build
# patsopt writes the minute it started in the first lines of its C: not a difference of the C (it failed in CI when a minute passed between the two builds)
cs_plain=$(cd "$TMP/plain/build" && find . -name '*.c' | sort | xargs cat | sed '/^\*\* The starting compilation time is:/d' | cksum)
run generous env BATS_PATSOPT_TIMEOUT_S=600 BATS_PATSOPT_MEM_MB=8192
[ $rc = 0 ] || fail "check with generous caps" generous
[ $secs -lt 120 ] || fail "check with generous caps took ${secs}s: a timer outlived patsopt" generous
is_sh "$(parent_of_last)" || fail "with caps, patsopt was not started by sh ($(parent_of_last))" generous
if grep -q "waiting" "$TMP/generous.log"; then fail "waited" generous; fi
(cd "$TMP/generous" && HOME="$H" BATS_PATSOPT_TIMEOUT_S=600 BATS_PATSOPT_MEM_MB=8192 "$BATS" build --only debug --only native > "$TMP/generous-build.log" 2>&1) || fail "build with generous caps" generous-build
cs_generous=$(cd "$TMP/generous/build" && find . -name '*.c' | sort | xargs cat | sed '/^\*\* The starting compilation time is:/d' | cksum)
[ "$cs_plain" = "$cs_generous" ] || {
  echo "FAIL: the C differs under a cap"; echo "$cs_plain / $cs_generous"
  (cd "$TMP/plain/build" && find . -name '*.c' | sort) > "$TMP/c-plain.list"
  (cd "$TMP/generous/build" && find . -name '*.c' | sort) > "$TMP/c-generous.list"
  diff "$TMP/c-plain.list" "$TMP/c-generous.list" || true
  for f in $(cat "$TMP/c-plain.list"); do
    cmp -s "$TMP/plain/build/$f" "$TMP/generous/build/$f" || { echo "--- $f differs:"; diff "$TMP/plain/build/$f" "$TMP/generous/build/$f" | head -20; }
  done
  exit 1
}
# the next bats in the project is not made to wait for a leftover timer
start=$(date +%s)
(cd "$TMP/generous" && HOME="$H" BATS_PATSOPT_TIMEOUT_S=600 "$BATS" clean > "$TMP/generous-clean.log" 2>&1) || fail "clean after a capped run" generous-clean
[ $(($(date +%s) - start)) -lt 60 ] || fail "a bats after a capped run waited for a leftover" generous-clean
if grep -q "waiting" "$TMP/generous-clean.log"; then fail "a leftover timer held the project's lock" generous-clean; fi

# the time cap
run time env FAKE=sleep BATS_PATSOPT_TIMEOUT_S=1
[ $rc = 124 ] || fail "the time cap's status was $rc, not 124" time
[ $secs -lt 40 ] || fail "the time cap took ${secs}s: the run was not stopped" time
grep -q "error: patsopt on src/bin/p.bats was stopped by the time cap: it did not finish within BATS_PATSOPT_TIMEOUT_S=1 seconds. Raise BATS_PATSOPT_TIMEOUT_S, or unset it for no time cap." "$TMP/time.log" || fail "the time cap was not said, naming the module" time
if grep -q "patsopt error" "$TMP/time.log"; then fail "the time cap was reported as a patsopt error" time; fi

# patsopt --depgen, which the check memo runs once a module passed, is held
# to the time cap too: a hang there used to run on, outside every cap
run depgen env FAKE=depgen-sleep BATS_PATSOPT_TIMEOUT_S=3
[ $rc = 124 ] || fail "the time cap's status on --depgen was $rc, not 124" depgen
[ $secs -lt 40 ] || fail "--depgen was not stopped by the time cap: it ran ${secs}s" depgen
grep -q "was stopped by the time cap: it did not finish within BATS_PATSOPT_TIMEOUT_S=3 seconds" "$TMP/depgen.log" || fail "the time cap on --depgen was not said" depgen

# the memory cap, where sh can lower the limit
if sh -c 'ulimit -v 262144' 2>/dev/null; then
  for mode in hog abort; do
    run mem env FAKE=$mode BATS_PATSOPT_MEM_MB=256
    [ $rc = 125 ] || fail "the memory cap's status ($mode) was $rc, not 125" mem
    grep -q "error: patsopt on src/bin/p.bats was stopped by the memory cap: it ran out of memory under BATS_PATSOPT_MEM_MB=256 megabytes of address space. Raise BATS_PATSOPT_MEM_MB, or unset it for no memory cap." "$TMP/mem.log" || fail "the memory cap ($mode) was not said, naming the module" mem
    if grep -q "patsopt error" "$TMP/mem.log"; then fail "the memory cap ($mode) was reported as a patsopt error" mem; fi
  done
else
  echo "patsopt-cap: sh cannot lower the address space limit here (ulimit -v): the memory cap is not tested"
fi

# a patsopt error under both caps is still one
run broken env BATS_PATSOPT_TIMEOUT_S=600 BATS_PATSOPT_MEM_MB=8192
[ $rc = 1 ] || fail "a patsopt error under caps had status $rc, not 1" broken
grep -q "error: patsopt error:" "$TMP/broken.log" || fail "a patsopt error under caps was not reported as one" broken
if grep -q "time cap\|memory cap" "$TMP/broken.log"; then fail "a patsopt error under caps was blamed on a cap" broken; fi

# what is not a count is said, and patsopt runs uncapped
run warn env BATS_PATSOPT_TIMEOUT_S=soon BATS_PATSOPT_MEM_MB=0
[ $rc = 0 ] || fail "check with caps that are not counts" warn
grep -q "warning: BATS_PATSOPT_TIMEOUT_S is not a number of seconds from 1 up, so patsopt runs without a time cap" "$TMP/warn.log" || fail "BATS_PATSOPT_TIMEOUT_S=soon was not said" warn
grep -q "warning: BATS_PATSOPT_MEM_MB is not a number of megabytes from 1 up, so patsopt runs without a memory cap" "$TMP/warn.log" || fail "BATS_PATSOPT_MEM_MB=0 was not said" warn
is_sh "$(parent_of_last)" && fail "caps that are not counts still started patsopt through sh" warn
echo "patsopt-cap: ok"
