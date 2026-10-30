#!/bin/sh
# tests/run-fixtures.sh prints how long each group and each ok case took, live, and ends with the ten slowest groups (bats-lang/bats#595, keyword: fixture-times).
# A group that sleeps a known number of seconds is reported with that number and listed first.
# usage: tests/run-fixtures/check.sh <bats-binary> <repository-dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
runner=$here/../run-fixtures.sh
. "$here/../keep-on-fail.sh"
cd "$TMP"

# make_group NAME BODY: a stand-in group tests/NAME/check.sh
make_group() {
  mkdir -p "groups/$1"
  printf '#!/bin/sh\n%s\n' "$2" > "groups/$1/check.sh"
  chmod +x "groups/$1/check.sh"
}

# the sleeping group: one case after 1 s, a second after 2 s more, 3 s in all
make_group quick 'echo "ok   only case"; echo "quick: ok"'
make_group mid 'sleep 1; echo "ok   waited"; echo "mid: ok"'
make_group slow 'sleep 1; echo "ok   one"; sleep 2; echo "ok   two (refused)"; echo "slow: ok"'
# liveness: this group runs after slow and reads the runner's output file as it is so far
make_group zlive 'grep -q "^group slow: ok in 3 s\$" "$OUT" || { echo "FAIL: the result line of slow is not in the output yet"; exit 1; }
echo "zlive: ok"'

OUT=$TMP/out.log
export OUT
"$runner" dummy-bats dummy-repository groups/quick/check.sh groups/mid/check.sh groups/slow/check.sh groups/zlive/check.sh > "$OUT" 2> err.log \
  || { echo "FAIL: the runner failed"; cat "$OUT" err.log; exit 1; }
want() {
  grep -qxF -- "$1" "$OUT" || { echo "FAIL: no line '$1' in:"; cat "$OUT"; exit 1; }
}
want "ok   one in 1 s"
want "ok   two (refused) in 2 s"
want "ok   only case in 0 s"
want "group quick: ok in 0 s"
want "group mid: ok in 1 s"
want "group slow: ok in 3 s"
want "slow: ok"
echo "ok   a group that sleeps 1 + 2 s is 3 s, its cases 1 s and 2 s, and the line is printed when it ends"

first=$(sed -n '/^slowest groups:$/{n;p;}' "$OUT")
[ "$first" = "     3 s  slow" ] || { echo "FAIL: first of the summary is '$first'"; cat "$OUT"; exit 1; }
second=$(sed -n '/^slowest groups:$/{n;n;p;}' "$OUT")
[ "$second" = "     1 s  mid" ] || { echo "FAIL: second of the summary is '$second'"; exit 1; }
grep -Eq '^total: [0-9]+ s$' "$OUT" || { echo "FAIL: no total line"; cat "$OUT"; exit 1; }
total=$(sed -n 's/^total: \([0-9]*\) s$/\1/p' "$OUT")
[ "$total" -ge 4 ] || { echo "FAIL: total $total s is under the 4 s the groups slept"; exit 1; }
echo "ok   the summary lists the sleeping group first, then the next slowest, and the total"

# the summary has ten rows at most
for n in 01 02 03 04 05 06 07 08 09 10 11 12; do
  make_group "g$n" "echo \"g$n: ok\""
done
"$runner" dummy-bats dummy-repository groups/g*/check.sh > many.log 2> err.log \
  || { echo "FAIL: the runner failed on twelve groups"; exit 1; }
rows=$(sed -n '/^slowest groups:$/,/^total:/p' many.log | grep -c ' s  g')
[ "$rows" = 10 ] || { echo "FAIL: $rows rows in the summary of twelve groups"; cat many.log; exit 1; }
echo "ok   twelve groups give ten rows"

# a failing group ends the run with its status, and the summary is still printed
make_group bad 'sleep 1; echo "FAIL: on purpose"; exit 3'
make_group never 'echo "never: ok"'
status=0
"$runner" dummy-bats dummy-repository groups/quick/check.sh groups/bad/check.sh groups/never/check.sh > bad.log 2> err.log || status=$?
[ "$status" = 3 ] || { echo "FAIL: status $status, want 3"; cat bad.log; exit 1; }
grep -qxF "group bad: FAILED with status 3 in 1 s" bad.log || { echo "FAIL: no failure line"; cat bad.log; exit 1; }
grep -q '^     1 s  bad$' bad.log || { echo "FAIL: the failed group is not in the summary"; cat bad.log; exit 1; }
grep -q '^total: ' bad.log || { echo "FAIL: no total after a failure"; exit 1; }
if grep -q '^never: ok' bad.log; then echo "FAIL: ran on after a failure"; exit 1; fi
echo "ok   a failed group is timed, summarised, and stops the run with its status"

# the arguments reach the group
make_group args 'echo "ok   $1 $2"'
"$runner" the-bats the-repository groups/args/check.sh > args.log 2> err.log
grep -qxF "ok   the-bats the-repository in 0 s" args.log || { echo "FAIL: arguments not passed"; cat args.log; exit 1; }
echo "ok   the compiler and the repository are passed to each group"
echo "run-fixtures: ok"
