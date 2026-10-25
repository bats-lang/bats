#!/bin/sh
# bats fixtures <dir> --bless [--only <member>]... (bats-lang/bats#522; the rule is in
# .claude/rules/fixtures.md, "--bless"): writes a reject fixture's `expect` from the error patsopt
# gives, in the form the matcher compares, and refuses what has no error to write.
# Why this is a shell script: it runs the built bats on planted projects and compares the files it
# writes, as every test of this directory does (tests/fixtures/check.sh; `bats test` of a package runs
# functions in-process and cannot start the compiler binary under test); the avenue `bats test`
# is exhausted for a test whose subject is the command line of the binary.
#  * every kind of case writes an expect that passes a following run without --bless: a function
#    name that is not the first declaration, a line other than 1, several error lines, a patsopt
#    variable number (S2EVar(n->, S2Evar(name(n)), $n(, a binder of S2Eexi), a fixture with no
#    expect file;
#  * the prints are one line per fixture: `wrote`, or `left` for an expect that already passes
#    (which is not rewritten, its raw numbers kept);
#  * a fixture that type-checks, one with an error in another module, one with an error at two
#    lines, one with no declaration at its line and one with no patsopt error (bats refuses the
#    snippet first) are each `FAIL <member>: not blessed: <why>`, the status is 1, and their
#    expects are as they were;
#  * an accept fixture's files are never written to, and an accept that does not check fails the run;
#  * --only blesses the named members and no other;
#  * the memo: an expect blessed from a memo hit passes the next run (served from the memo again),
#    --cold and --prune behave as they do without --bless;
#  * usage: --bless is in the usage text.
#
# usage: tests/fixtures/bless.sh <bats-binary> <repository-dir>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
. "$(dirname "$0")/../keep-on-fail.sh"
unset BATS_CACHE_DIR BATS_COMMIT BATS_COLD BATS_MEMO_DIR XDG_CACHE_HOME
fail() { echo "FAIL: $*" >&2; exit 1; }
P=$TMP/proj
mkdir -p "$P/src" "$TMP/tmp"
printf '[package]\nname = "fx"\nkind = "lib"\n' > "$P/bats.toml"
printf '#include "share/atspre_staload.hats"\n\n#pub stadef limit = 1\n\n#pub fn f (x: int): int\n\nimplement f (x) = x + 1\n\n(* end *)\n' > "$P/src/lib.bats"
printf '#include "share/atspre_staload.hats"\nstaload "lib.sats"\n\n#pub fn one (): int(limit)\n\nimplement one () = 1\n' > "$P/src/other.bats"
export TMPDIR=$TMP/tmp
export BATS_MEMO_DIR=$TMP/memo-env

# fixture <dir> <accept|reject> <name> <snippet text> [<expect text>]
fixture() {
  d=$1/$2/$3; mkdir -p "$d"
  printf 'src/lib.bats\n' > "$d/file"
  printf '(* end *)\n' > "$d/before"
  printf '%s\n' "$4" > "$d/snippet.bats"
  [ $# -lt 5 ] || printf '%s\n' "$5" > "$d/expect"
}
run() { # <log> args...: bats fixtures in the project, its status in $rc
  l=$1; shift
  (cd "$P" && "$BATS" fixtures "$@") > "$l" 2>&1; rc=$?
  # BLESS_SHOW=1 prints each run as a terminal would (the command, its output, its status)
  [ -z "${BLESS_SHOW:-}" ] || { echo "\$ bats fixtures $*"; cat "$l"; echo "exit status $rc"; }
}
# expects <dir>: with BLESS_SHOW=1, the expect files of a directory of fixtures
expects() { [ -z "${BLESS_SHOW:-}" ] || for f in "$1"/reject/*/expect; do echo "\$ cat $f"; cat "$f"; done; }
said() { grep -aqxF -- "$2" "$1" || { echo "--- $1"; cat "$1"; fail "$3: no line: $2"; }; }
saidpart() { grep -aqF -- "$2" "$1" || { echo "--- $1"; cat "$1"; fail "$3: no text: $2"; }; }
notsaid() { ! grep -aqF -- "$2" "$1" || { echo "--- $1"; cat "$1"; fail "$3: unexpected text: $2"; }; }
line() { grep -aqE "^$2 $3 \([0-9]+ s\)( \[memo\])?\$" "$1" || { echo "--- $1"; cat "$1"; fail "$4: no '$2 $3' line"; }; }
same() { cmp -s "$1" "$2" || { diff "$1" "$2" >&2; fail "$3: $1 changed"; }; }

# ---- every kind of case: a name, a line, several lines, variable numbers, no expect file
G=$TMP/good
# the first declaration is not the one the error is in
fixture "$G" reject function-name 'fn g (x: int): int = x
fn h (x: int): int = case+ x of 0 => 1' 'function g
line 1
stale'
# the error is at line 3 of the snippet
fixture "$G" reject line-three 'absvtype lin_t

fn h (x: lin_t): void = ()' 'function h
line 1
stale'
# several error lines (the lines patsopt adds to a message)
fixture "$G" reject several-lines 'fn h (x: int): int = case+ x of 0 => 1' ''
# a variable number of kind 1, S2EVar(n->
fixture "$G" reject unification 'fn h {n:nat} (x: int n): [m:nat] int m = x - 1' 'function h
line 1
stale'
# a dynamic variable, $n(
fixture "$G" reject dynamic 'absvtype lin_t

fn h (x: lin_t): void = ()' 'function h
line 3
stale'
# an existential's binder list
fixture "$G" reject binders 'fn h (f: char): [n:nat; m:nat] bool = f' 'function h
line 1
stale'
# an unsolved variable with no arrow
fixture "$G" reject bare-evar 'dataprop PA (int, int) = | PA0 (0, 0)
dataprop PB (int, int) = | PB0 (0, 0)
fn h {a:int} (pf: PB(a, a) | x: int): [k:int; j:int] (PA(k, j) | int) = (pf | x)' 'function h
line 3
stale'
# no expect file at all
fixture "$G" reject no-expect-file 'fn h (x: int): int = case+ x of 0 => 1'
rm -f "$G/reject/no-expect-file/expect"
fixture "$G" accept ok 'fn g (x: int): int = x'
mkdir -p "$TMP/accept-before"; cp -R "$G/accept" "$TMP/accept-before/"

run "$TMP/bless1.log" "$G" --bless
[ $rc = 0 ] || { cat "$TMP/bless1.log"; fail "bless: status $rc"; }
for m in function-name line-three several-lines unification dynamic binders bare-evar no-expect-file; do
  line "$TMP/bless1.log" wrote "reject/$m" bless
done
line "$TMP/bless1.log" "ok  " "accept/ok" bless
said "$TMP/bless1.log" "bless: 8 written, 0 left as they were" bless
saidpart "$TMP/bless1.log" "fixtures: 9 ok, 0 failed" bless
expects "$G"
# the form: function, line, then the error with its variable numbers as _
head -n 2 "$G/reject/function-name/expect" | tr '\n' ' ' | grep -qx 'function h line 2 ' || { cat "$G/reject/function-name/expect"; fail "function-name: not 'function h' / 'line 2'"; }
head -n 2 "$G/reject/line-three/expect" | tr '\n' ' ' | grep -qx 'function h line 3 ' || fail "line-three: not 'function h' / 'line 3'"
[ "$(wc -l < "$G/reject/several-lines/expect")" -ge 4 ] || { cat "$G/reject/several-lines/expect"; fail "several-lines: fewer than 4 lines"; }
grep -qF 'S2EVar(_->' "$G/reject/unification/expect" || { cat "$G/reject/unification/expect"; fail "unification: no S2EVar(_->"; }
grep -qF '$_(' "$G/reject/dynamic/expect" || { cat "$G/reject/dynamic/expect"; fail "dynamic: no \$_("; }
grep -qF 'S2Eexi(n(_), m(_);' "$G/reject/binders/expect" || { cat "$G/reject/binders/expect"; fail "binders: no S2Eexi(n(_), m(_);"; }
grep -qF 'S2EVar(_)' "$G/reject/bare-evar/expect" || { cat "$G/reject/bare-evar/expect"; fail "bare-evar: no S2EVar(_)"; }
grep -q '[0-9]\{4\}' "$G/reject/unification/expect" && { cat "$G/reject/unification/expect"; fail "unification: a patsopt number was written"; }
# a following run without --bless passes every one of them
run "$TMP/verify1.log" "$G"
[ $rc = 0 ] || { cat "$TMP/verify1.log"; fail "after bless: status $rc"; }
for m in function-name line-three several-lines unification dynamic binders bare-evar no-expect-file; do
  line "$TMP/verify1.log" "ok  " "reject/$m" "after bless"
done
saidpart "$TMP/verify1.log" "fixtures: 9 ok, 0 failed" "after bless"
# an accept fixture is not written to
for f in file before snippet.bats; do same "$G/accept/ok/$f" "$TMP/accept-before/accept/ok/$f" accept; done
[ ! -e "$G/accept/ok/expect" ] || fail "an accept fixture got an expect"

# ---- a second bless leaves what passes; an expect with other numbers than patsopt's passes and is kept
cp -R "$G" "$TMP/good-before"
run "$TMP/bless2.log" "$G" --bless
[ $rc = 0 ] || { cat "$TMP/bless2.log"; fail "bless again: status $rc"; }
for m in function-name line-three several-lines unification dynamic binders bare-evar no-expect-file; do
  line "$TMP/bless2.log" "left " "reject/$m" "bless again"
  same "$G/reject/$m/expect" "$TMP/good-before/reject/$m/expect" "bless again"
done
said "$TMP/bless2.log" "bless: 0 written, 8 left as they were" "bless again"
# an expect that has patsopt's own numbers is not rewritten
N=$TMP/numbered
fixture "$N" reject numbered 'fn h {n:nat} (x: int n): [m:nat] int m = x - 1' 'function h
line 1
unsolved constraint: C3NSTRprop(C3TKmain(); S2Eapp(S2Ecst(>=); S2EVar(1->S2Eapp(S2Ecst(sub_int_int); S2Evar(n(2)), S2Eintinf(1))), S2Eintinf(0)))'
cp "$N/reject/numbered/expect" "$TMP/numbered-expect"
run "$TMP/bless3.log" "$N" --bless
[ $rc = 0 ] || { cat "$TMP/bless3.log"; fail "numbered: status $rc"; }
line "$TMP/bless3.log" "left " "reject/numbered" numbered
same "$N/reject/numbered/expect" "$TMP/numbered-expect" numbered

# ---- a changed snippet: only the expect that no longer passes is rewritten
printf 'fn h (x: int): int = case+ x of 1 => 1\n' > "$G/reject/several-lines/snippet.bats"
run "$TMP/verify2.log" "$G"
[ $rc = 1 ] || { cat "$TMP/verify2.log"; fail "changed snippet: status $rc, not 1"; }
saidpart "$TMP/verify2.log" "FAIL reject/several-lines: rejected, but not as its expect says" "changed snippet"
run "$TMP/bless4.log" "$G" --bless
[ $rc = 0 ] || { cat "$TMP/bless4.log"; fail "changed snippet bless: status $rc"; }
line "$TMP/bless4.log" wrote "reject/several-lines" "changed snippet"
line "$TMP/bless4.log" "left " "reject/dynamic" "changed snippet"
said "$TMP/bless4.log" "bless: 1 written, 7 left as they were" "changed snippet"
run "$TMP/verify3.log" "$G"
[ $rc = 0 ] || { cat "$TMP/verify3.log"; fail "changed snippet after bless: status $rc"; }

# ---- what is refused: FAIL, status 1, the expects as they were
B=$TMP/bad
fixture "$B" reject passes 'fn g (x: int): int = x' 'function g
line 1
kept'
# an error in another module: the snippet breaks the module that depends on lib.bats
fixture "$B" reject other-module 'fn g (x: int): int = x
#pub stadef limit = 2' 'function g
line 2
kept'
# two errors, at two lines
fixture "$B" reject two-lines 'fn h (x: int): int = case+ x of 0 => 1
fn g (x: int): int = case+ x of 0 => 1' 'function h
line 1
kept'
# an error at a line that is in no declaration
fixture "$B" reject no-declaration '#error "first"' 'function h
line 1
kept'
# bats refuses the snippet (a fun with no metric) before patsopt runs
fixture "$B" reject no-patsopt-error 'fun h (x: int): int = x' 'function h
line 1
kept'
fixture "$B" accept does-not-check 'fn g (x: int): int = case+ x of 0 => 1'
cp -R "$B" "$TMP/bad-before"
run "$TMP/bless5.log" "$B" --bless
[ $rc = 1 ] || { cat "$TMP/bless5.log"; fail "refusals: status $rc, not 1"; }
saidpart "$TMP/bless5.log" "FAIL reject/passes: not blessed: it type-checks, so there is no error to write" refusals
saidpart "$TMP/bless5.log" "FAIL reject/other-module: not blessed: an error is in " refusals
saidpart "$TMP/bless5.log" "/src/other.bats, not src/lib.bats: " refusals
saidpart "$TMP/bless5.log" "FAIL reject/two-lines: not blessed: an error is at line 2 of its snippet, not 1: " refusals
saidpart "$TMP/bless5.log" "FAIL reject/no-declaration: not blessed: line 1 of its snippet is in no declaration" refusals
saidpart "$TMP/bless5.log" "FAIL reject/no-patsopt-error: not blessed: no error of patsopt's" refusals
saidpart "$TMP/bless5.log" "FAIL accept/does-not-check: should type-check" refusals
said "$TMP/bless5.log" "bless: 0 written, 0 left as they were" refusals
saidpart "$TMP/bless5.log" "fixtures: 0 ok, 6 failed" refusals
for m in passes other-module two-lines no-declaration no-patsopt-error; do
  same "$B/reject/$m/expect" "$TMP/bad-before/reject/$m/expect" refusals
done
for f in file before snippet.bats; do same "$B/accept/does-not-check/$f" "$TMP/bad-before/accept/does-not-check/$f" refusals; done
expects "$B"

# ---- --only: the named member, and no other
O=$TMP/only
fixture "$O" reject first 'fn h (x: int): int = case+ x of 0 => 1' 'function h
line 1
old'
fixture "$O" reject second 'fn h (x: int): int = case+ x of 0 => 1' 'function h
line 1
old'
run "$TMP/only.log" "$O" --bless --only reject/first
[ $rc = 0 ] || { cat "$TMP/only.log"; fail "--only: status $rc"; }
line "$TMP/only.log" wrote "reject/first" "--only"
notsaid "$TMP/only.log" "reject/second" "--only blessed another"
[ "$(tail -n 1 "$O/reject/second/expect")" = old ] || fail "--only: the other expect changed"
[ "$(tail -n 1 "$O/reject/first/expect")" != old ] || fail "--only: the named expect did not"
run "$TMP/only2.log" "$O" --bless --only reject/nope
[ $rc = 2 ] || fail "--bless --only of no fixture: status $rc, not 2"

# ---- the memo: a hit gives the log, never the old expect
M=$TMP/memo-fx
fixture "$M" reject stale 'fn h (x: int): int = case+ x of 0 => 1' 'function h
line 1
old'
fixture "$M" accept fine 'fn g (x: int): int = x'
MEMO=$TMP/memo-dir
run "$TMP/m1.log" "$M" --memo "$MEMO"
[ $rc = 1 ] || { cat "$TMP/m1.log"; fail "memo: the stale expect passed (status $rc)"; }
run "$TMP/m2.log" "$M" --bless --memo "$MEMO"
[ $rc = 0 ] || { cat "$TMP/m2.log"; fail "memo bless: status $rc"; }
line "$TMP/m2.log" wrote "reject/stale" "memo bless"
saidpart "$TMP/m2.log" "reject/stale (0 s) [memo]" "memo bless: the log was not the memo's"
expects "$M"
run "$TMP/m3.log" "$M" --memo "$MEMO"
[ $rc = 0 ] || { cat "$TMP/m3.log"; fail "memo after bless: status $rc"; }
saidpart "$TMP/m3.log" "ok   reject/stale (0 s) [memo]" "memo after bless"
saidpart "$TMP/m3.log" "fixtures: 2 ok, 0 failed (2 from the memo)" "memo after bless"
# --cold reads no memo and blesses
printf 'function h\nline 1\nold\n' > "$M/reject/stale/expect"
run "$TMP/m4.log" "$M" --bless --cold --memo "$MEMO"
[ $rc = 0 ] || { cat "$TMP/m4.log"; fail "cold bless: status $rc"; }
line "$TMP/m4.log" wrote "reject/stale" "cold bless"
notsaid "$TMP/m4.log" "[memo]" "cold bless"
notsaid "$TMP/m4.log" "STALE MEMO" "cold bless"
# --prune after a bless removes what no fixture used, as it does without --bless
mkdir -p "$MEMO/00"; : > "$MEMO/00/.memo-dir"
printf 'x\n' > "$MEMO/00/0000000000000000000000000000000000000000000000000000000000000000.key"
run "$TMP/m5.log" "$M" --bless --prune --memo "$MEMO"
[ $rc = 0 ] || { cat "$TMP/m5.log"; fail "prune bless: status $rc"; }
saidpart "$TMP/m5.log" "pruned 00/0000000000000000000000000000000000000000000000000000000000000000.key" "prune bless"
saidpart "$TMP/m5.log" "memo: pruned 1 files, kept 4" "prune bless"
run "$TMP/m6.log" "$M" --bless --prune --only accept/fine --memo "$MEMO"
[ $rc = 2 ] || fail "--bless --prune --only: status $rc, not 2"

# ---- usage
run "$TMP/usage.log" --bogus
saidpart "$TMP/usage.log" "[--bless]" usage
echo "ok"
