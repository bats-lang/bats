#!/bin/sh
# bats fixtures <dir> [--only <member>]... [--cold] [--work <dir>]
# (bats-lang/bats#267, item 4: the static-test runner of quire#598 in bats).
# <dir> holds accept/<name>/ and reject/<name>/, each with file, before,
# snippet.bats (and expect for a reject): the snippet is put into a copy of
# the project, in the module `file` names, before the first line that is
# exactly `before`. An accept must pass `bats check`; a reject must fail it
# exactly as its `expect` says: "function <name>", "line <n>" and patsopt's
# error word for word, all its errors in the module, at that line of the
# snippet, with only patsopt's variable numbers compared as "_".
#  * a good accept and a good reject (whose expect has other variable
#    numbers than patsopt gave) pass, one `ok   <member> (N s)` line each;
#  * an accept that does not check, a reject that does, a reject whose
#    error text differs by a word, whose line or function differs, are each
#    a FAIL line saying why, and the exit status is 1;
#  * an expect that is not "function <name>", "line <n>", then the error
#    (two lines, a word missing, a line that is no number, empty, absent) is
#    a FAIL line, never a pass; so is a `before` that is not in the module;
#  * --only picks fixtures, a name that is none is status 2, so is an
#    unknown option, no directory, or two; --cold is accepted;
#  * --work keeps the copy (its build/ reused by the next run), a run
#    without it leaves no temporary directory;
#  * a project that does not check fails the run before any fixture.
# usage: tests/fixtures/check.sh <bats-binary> <repository-dir>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_CACHE_DIR BATS_COMMIT
fail() { echo "FAIL: $*" >&2; exit 1; }
P=$TMP/proj
mkdir -p "$P/src" "$TMP/tmp"
printf '[package]\nname = "fx"\nkind = "lib"\n' > "$P/bats.toml"
printf '#include "share/atspre_staload.hats"\n\n#pub stadef limit = 1\n\n#pub fn f (x: int): int\n\nimplement f (x) = x + 1\n\n(* end *)\n' > "$P/src/lib.bats"
# a module that depends on lib's interface: a snippet can break it
printf '#include "share/atspre_staload.hats"\nstaload "lib.sats"\n\n#pub fn one (): int(limit)\n\nimplement one () = 1\n' > "$P/src/other.bats"
export TMPDIR=$TMP/tmp

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
}
said() { grep -aqxF -- "$2" "$1" || { echo "--- $1"; cat "$1"; fail "$3: no line: $2"; }; }
saidpart() { grep -aqF -- "$2" "$1" || { echo "--- $1"; cat "$1"; fail "$3: no text: $2"; }; }
notsaid() { ! grep -aqF -- "$2" "$1" || { echo "--- $1"; cat "$1"; fail "$3: unexpected text: $2"; }; }
# a member's line, whose seconds vary: `ok   <member> (N s)`
okline() { grep -aqE "^ok   $2 \([0-9]+ s\)\$" "$1" || { echo "--- $1"; cat "$1"; fail "$3: no ok line for $2"; }; }
nofail() { notsaid "$1" "FAIL" "$2"; }
failed() { grep -aqF "FAIL $2" "$1" || { echo "--- $1"; cat "$1"; fail "$3: no FAIL line for $2"; }; }

# patsopt's own text for the snippet the norm fixture holds
SNORM='fn h {n:nat} (x: int n): [m:nat] int m = x - 1'
ENORM='unsolved constraint: C3NSTRprop(C3TKmain(); S2Eapp(S2Ecst(>=); S2EVar(1->S2Eapp(S2Ecst(sub_int_int); S2Evar(n(2)), S2Eintinf(1))), S2Eintinf(0)))'

# ---- the good ones
G=$TMP/good
fixture "$G" accept ok 'fn g (x: int): int = x'
fixture "$G" reject nonexhaustive 'fn h (x: int): int = case+ x of 0 => 1' 'function h
line 1
pattern match is nonexhaustive:
[^0]'
# the variable numbers patsopt gave are other than the expect's
fixture "$G" reject numbered "$SNORM" "function h
line 1
$ENORM"
# a variable of the dynamic kind: patsopt's x$4738(-1) is compared as x$_(-1)
fixture "$G" reject dollar 'absvtype lin_t

fn h (x: lin_t): void = ()' 'function h
line 3
the linear dynamic variable [x$1(-1)] needs to be consumed but it is preserved with the type [S2Ecst(lin_t)] instead.'
# a blank line ends the lines patsopt adds to an error: "second" is not the error's
fixture "$G" reject blank-line 'fn g (x: int): int = x
#error "first\n\nsecond"' 'function g
line 2
[#error] directive is encountered: first'
run "$TMP/good.log" "$G" --cold
[ $rc = 0 ] || { cat "$TMP/good.log"; fail "good fixtures: status $rc"; }
okline "$TMP/good.log" accept/ok good
okline "$TMP/good.log" reject/nonexhaustive good
okline "$TMP/good.log" reject/numbered good
okline "$TMP/good.log" reject/dollar good
okline "$TMP/good.log" reject/blank-line good
said "$TMP/good.log" "fixtures: 5 ok, 0 failed" good
nofail "$TMP/good.log" good
[ -z "$(ls "$TMP/tmp")" ] || fail "the run left a temporary directory: $(ls "$TMP/tmp")"
# the project is as it was
[ "$(cat "$P/src/lib.bats")" = "$(printf '#include "share/atspre_staload.hats"\n\n#pub stadef limit = 1\n\n#pub fn f (x: int): int\n\nimplement f (x) = x + 1\n\n(* end *)')" ] || fail "the project's module changed"
[ ! -d "$P/build" ] || fail "the project was built in place"

# ---- the bad ones: each is a FAIL line that says why
B=$TMP/bad
fixture "$B" accept does-not-check 'fn g (x: int): int = case+ x of 0 => 1'
fixture "$B" reject passes 'fn g (x: int): int = x' 'function g
line 1
anything'
fixture "$B" reject other-word 'fn h (x: int): int = case+ x of 0 => 1' 'function h
line 1
pattern match is nonexhaustive!
[^0]'
fixture "$B" reject missing-line 'fn h (x: int): int = case+ x of 0 => 1' 'function h
line 1
pattern match is nonexhaustive:'
fixture "$B" reject extra-line 'fn h (x: int): int = case+ x of 0 => 1' 'function h
line 1
pattern match is nonexhaustive:
[^0]
and more'
fixture "$B" reject other-line 'fn h (x: int): int = case+ x of 0 => 1' 'function h
line 2
pattern match is nonexhaustive:
[^0]'
fixture "$B" reject other-function 'fn h (x: int): int = case+ x of 0 => 1' 'function g
line 1
pattern match is nonexhaustive:
[^0]'
fixture "$B" reject no-declaration 'fn h (x: int): int = case+ x of 0 => 1' 'function h
line 0
pattern match is nonexhaustive:
[^0]'
fixture "$B" reject two-lines 'fn h (x: int): int = case+ x of 0 => 1' 'function h
line 1'
fixture "$B" reject no-function-word 'fn h (x: int): int = case+ x of 0 => 1' 'name h
line 1
pattern match is nonexhaustive:
[^0]'
fixture "$B" reject line-not-a-number 'fn h (x: int): int = case+ x of 0 => 1' 'function h
line one
pattern match is nonexhaustive:
[^0]'
fixture "$B" reject empty-expect 'fn h (x: int): int = case+ x of 0 => 1' ''
fixture "$B" reject no-expect 'fn h (x: int): int = case+ x of 0 => 1'
# the snippet is fine where it is, and breaks the module that depends on it
fixture "$B" reject other-module 'fn g (x: int): int = x
#pub stadef limit = 2' 'function g
line 2
anything'
# bats refuses the snippet (a fun with no termination metric) before patsopt
# runs: a check that fails with no error of patsopt's is not a rejection
fixture "$B" reject no-patsopt-error 'fun h (x: int): int = x' 'function h
line 1
anything'
fixture "$B" accept no-such-line 'fn g (x: int): int = x'
printf '(* not in the module *)\n' > "$B/accept/no-such-line/before"
# a number that is not a variable's stays: n(2) is a variable, 2 is not
fixture "$B" reject number-kept "$SNORM" "function h
line 1
$(printf '%s' "$ENORM" | sed -e 's/Eintinf(1)/Eintinf(7)/')"
run "$TMP/bad.log" "$B"
[ $rc = 1 ] || { cat "$TMP/bad.log"; fail "bad fixtures: status $rc, not 1"; }
L=$TMP/bad.log
failed "$L" "accept/does-not-check: should type-check" bad
failed "$L" "reject/passes: should be rejected" bad
saidpart "$L" "FAIL reject/other-word: rejected, but not as its expect says: its error is not the one expected:" bad
saidpart "$L" "FAIL reject/missing-line: rejected, but not as its expect says: its error is not the one expected:" bad
saidpart "$L" "FAIL reject/extra-line: rejected, but not as its expect says: its error is not the one expected:" bad
saidpart "$L" "FAIL reject/number-kept: rejected, but not as its expect says: its error is not the one expected:" bad
saidpart "$L" "FAIL reject/other-line: rejected, but not as its expect says: an error is at line 1 of its snippet, not 2: " bad
saidpart "$L" "FAIL reject/other-function: rejected, but not as its expect says: line 1 of its snippet is not in g" bad
saidpart "$L" "FAIL reject/no-declaration: rejected, but not as its expect says: line 0 of its snippet is not in h" bad
for m in two-lines no-function-word line-not-a-number empty-expect; do
  saidpart "$L" "FAIL reject/$m: rejected, but not as its expect says: its expect is not \"function <name>\", \"line <n>\", then the error" bad
done
saidpart "$L" "FAIL reject/no-expect: a file of the fixture" bad
saidpart "$L" "FAIL reject/no-patsopt-error: rejected, but not as its expect says: no error of patsopt's" bad
saidpart "$L" "FAIL reject/other-module: rejected, but not as its expect says: an error is in " bad
saidpart "$L" "/src/other.bats, not src/lib.bats: unsolved constraint" bad
saidpart "$L" "FAIL accept/no-such-line: no line \"(* not in the module *)\" in src/lib.bats" bad
said "$L" "fixtures: 0 ok, 17 failed" bad
# the raw error is shown for a mismatch, so the reader can fix the expect
saidpart "$L" "pattern match is nonexhaustive:" bad

# ---- --only, and usage errors
run "$TMP/only.log" "$G" --only reject/nonexhaustive
[ $rc = 0 ] || { cat "$TMP/only.log"; fail "--only: status $rc"; }
okline "$TMP/only.log" reject/nonexhaustive only
notsaid "$TMP/only.log" "accept/ok" "--only ran another"
notsaid "$TMP/only.log" "reject/numbered" "--only ran another"
said "$TMP/only.log" "fixtures: 1 ok, 0 failed" only
run "$TMP/two.log" "$G" --only accept/ok --only reject/numbered
[ $rc = 0 ] || { cat "$TMP/two.log"; fail "two --only: status $rc"; }
okline "$TMP/two.log" accept/ok two; okline "$TMP/two.log" reject/numbered two
notsaid "$TMP/two.log" "reject/nonexhaustive" "two --only ran a third"
run "$TMP/none.log" "$G" --only accept/nope
[ $rc = 2 ] || fail "--only of no fixture: status $rc, not 2"
saidpart "$TMP/none.log" "no fixture accept/nope" "--only of no fixture"
notsaid "$TMP/none.log" "ok   " "--only of no fixture ran one"
run "$TMP/none.log" "$G" --only ok
[ $rc = 2 ] || fail "--only of a bare name: status $rc, not 2"
run "$TMP/opt.log" "$G" --bogus
[ $rc = 2 ] || fail "an unknown option: status $rc, not 2"
saidpart "$TMP/opt.log" "unknown option --bogus" "unknown option"
run "$TMP/dir.log" --cold
[ $rc = 2 ] || fail "no directory: status $rc, not 2"
saidpart "$TMP/dir.log" "usage: bats fixtures" "no directory"
run "$TMP/dir2.log" "$G" "$B"
[ $rc = 2 ] || fail "two directories: status $rc, not 2"
run "$TMP/val.log" "$G" --only
[ $rc = 2 ] || fail "--only with no value: status $rc, not 2"
# no fixtures at all is a usage error (a typo in a path must not pass)
run "$TMP/empty.log" "$TMP/no-such-dir"
[ $rc = 2 ] || fail "a directory that is not there: status $rc, not 2"
saidpart "$TMP/empty.log" "no fixtures in $TMP/no-such-dir" "no directory"
mkdir -p "$TMP/empty-dir"
run "$TMP/empty.log" "$TMP/empty-dir"
[ $rc = 2 ] || fail "an empty directory: status $rc, not 2"
mkdir -p "$TMP/only-accept-dirs/accept" "$TMP/only-accept-dirs/reject"
run "$TMP/empty.log" "$TMP/only-accept-dirs"
[ $rc = 2 ] || fail "a directory with no fixture in it: status $rc, not 2"

# ---- --work: kept, and its build reused
W=$TMP/work
run "$TMP/w1.log" "$G" --work "$W" --only accept/ok
[ $rc = 0 ] || { cat "$TMP/w1.log"; fail "--work: status $rc"; }
[ -d "$W/app/build" ] && [ -d "$W/build-checked" ] || fail "--work did not keep the copy"
run "$TMP/w2.log" "$G" --work "$W" --only accept/ok
[ $rc = 0 ] || { cat "$TMP/w2.log"; fail "--work again: status $rc"; }
okline "$TMP/w2.log" accept/ok "--work again"
# a relative --work works as an absolute one does
(cd "$TMP" && mkdir -p rel && cd proj && "$BATS" fixtures "$G" --work ../rel/w --only accept/ok > "$TMP/w3.log" 2>&1) || { cat "$TMP/w3.log"; fail "a relative --work"; }
okline "$TMP/w3.log" accept/ok "relative --work"

# ---- --work inside the project is not copied into the copy
for wk in ./w "$P/w2"; do
  for again in 1 2; do
    (cd "$P" && "$BATS" fixtures "$G" --work "$wk" --only accept/ok > "$TMP/wi.log" 2>&1) || { cat "$TMP/wi.log"; fail "--work $wk inside the project (run $again)"; }
    okline "$TMP/wi.log" accept/ok "--work inside"
  done
done
[ ! -e "$P/w/app/w" ] && [ ! -e "$P/w2/app/w2" ] && [ ! -e "$P/w/app/w2" ] || fail "--work inside the project was copied into the copy"
rm -rf "$P/w" "$P/w2"

# ---- a snippet that cannot be put in is a FAIL of that fixture, judged
# against no log (not the last fixture's)
P2=$TMP/splice
mkdir -p "$P2/src/other.bats.fixture"
cp "$P/bats.toml" "$P2/"; cp "$P/src/lib.bats" "$P/src/other.bats" "$P2/src/"
SP=$TMP/splicefx
fixture "$SP" accept a-ok 'fn g (x: int): int = x'
fixture "$SP" reject b-splice 'fn g (x: int): int = x' 'function g
line 1
anything'
printf 'src/other.bats\n' > "$SP/reject/b-splice/file"
printf 'implement one () = 1\n' > "$SP/reject/b-splice/before"
(cd "$P2" && "$BATS" fixtures "$SP" > "$TMP/splice.log" 2>&1); rc=$?
[ $rc = 1 ] || { cat "$TMP/splice.log"; fail "a snippet that cannot be put in: status $rc, not 1"; }
okline "$TMP/splice.log" accept/a-ok splice
saidpart "$TMP/splice.log" "FAIL reject/b-splice: the check's log cannot be read" splice
notsaid "$TMP/splice.log" "no error of patsopt" "splice judged a stale log"

# ---- a project that does not check fails the run, before any fixture
BP=$TMP/broken
mkdir -p "$BP/src"
cp "$P/bats.toml" "$BP/"
printf '#include "share/atspre_staload.hats"\n\n#pub fn f (x: int): int\n\nimplement f (x) = case+ x of 0 => 1\n\n(* end *)\n' > "$BP/src/lib.bats"
(cd "$BP" && "$BATS" fixtures "$G" > "$TMP/broken.log" 2>&1); rc=$?
[ $rc = 1 ] || fail "a project that does not check: status $rc, not 1"
said "$TMP/broken.log" "FAIL check (the app, which the fixtures start from):" "broken project"
notsaid "$TMP/broken.log" "ok   " "a fixture ran on a project that does not check"
echo "ok"
