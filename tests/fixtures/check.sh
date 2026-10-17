#!/bin/sh
# bats fixtures <dir> [--only <member>]... [--cold] [--work <dir>] [--memo <dir>] [--prune]
# (bats-lang/bats#267, item 4: the static-test runner of quire#598 in bats,
# with its memo).
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
# The memo (after the runner's own cases, from "the memo" below; a third
# argument `memo` runs only those, which is how the mutants of
# tests/fixtures/mutants.sh are killed in a few minutes):
#  * a second run serves every fixture from the memo (`ok   <member> (0 s)
#    [memo]`, `fixtures: N ok, 0 failed (N from the memo)`) and runs no
#    patsopt; the key holds no absolute path (a copy of the project at
#    another path, and the memo copied elsewhere, still hit);
#  * a changed module, a changed staloaded .sats (of the same size), a
#    changed snippet or `before`, a module added, a changed toolchain, a
#    snippet that loads a file, a changed module that reads the interface
#    a snippet changed: each runs the fixture again; a change in a module
#    the fixture does not read, or in one that reads the module without
#    reading the interface the snippet left, does not;
#  * a reject keeps patsopt's log, not a verdict: a changed or wrong expect
#    is judged again against the stored log, with no patsopt run;
#  * a failure is never kept as a pass (an accept that does not check, a
#    reject that checks, a check that fails with no error of patsopt's);
#  * a torn, garbled, truncated, foreign or other-format entry is a miss,
#    and four copies of the project side by side, five rounds, never serve
#    a torn one; a run killed while it checks leaves no entry;
#  * --cold reads no memo, writes it, and reports a memo that no longer
#    says what a cold run does (STALE MEMO), removing it;
#  * --prune lists and removes the entries the run did not use, and nothing
#    outside a memo's own entries (not a directory without the memo's mark,
#    not through a link), and is a usage error with --only;
#  * the script bats writes (the memo's: sh, since bats starts the system's
#    tools through sh, as it does everywhere in fixtures.bats) is one sh parses.
# usage: tests/fixtures/check.sh <bats-binary> <repository-dir> [memo]
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_CACHE_DIR BATS_COMMIT BATS_COLD BATS_MEMO_DIR XDG_CACHE_HOME
ONLY=${3:-}
fail() { echo "FAIL: $*" >&2; [ -z "${TIMES:-}" ] || cat "$TMP/times" 2>/dev/null >&2; exit 1; }
P=$TMP/proj
mkdir -p "$P/src" "$TMP/tmp"
printf '[package]\nname = "fx"\nkind = "lib"\n' > "$P/bats.toml"
printf '#include "share/atspre_staload.hats"\n\n#pub stadef limit = 1\n\n#pub fn f (x: int): int\n\nimplement f (x) = x + 1\n\n(* end *)\n' > "$P/src/lib.bats"
# a module that depends on lib's interface: a snippet can break it
printf '#include "share/atspre_staload.hats"\nstaload "lib.sats"\n\n#pub fn one (): int(limit)\n\nimplement one () = 1\n' > "$P/src/other.bats"
export TMPDIR=$TMP/tmp
# the memo of every run of this script is its own, never the user's
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
  rm -rf "$TMP/memo-env"
  (cd "$P" && BATS_MEMO_DIR=$TMP/memo-env "$BATS" fixtures "$@") > "$l" 2>&1; rc=$?
}
said() { grep -aqxF -- "$2" "$1" || { echo "--- $1"; cat "$1"; fail "$3: no line: $2"; }; }
saidpart() { grep -aqF -- "$2" "$1" || { echo "--- $1"; cat "$1"; fail "$3: no text: $2"; }; }
notsaid() { ! grep -aqF -- "$2" "$1" || { echo "--- $1"; cat "$1"; fail "$3: unexpected text: $2"; }; }
# a member's line, whose seconds vary: `ok   <member> (N s)`
okline() { grep -aqE "^ok   $2 \([0-9]+ s\)( \[memo\])?\$" "$1" || { echo "--- $1"; cat "$1"; fail "$3: no ok line for $2"; }; }
nofail() { notsaid "$1" "FAIL" "$2"; }
failed() { grep -aqF "FAIL $2" "$1" || { echo "--- $1"; cat "$1"; fail "$3: no FAIL line for $2"; }; }

# patsopt's own text for the snippet the norm fixture holds
SNORM='fn h {n:nat} (x: int n): [m:nat] int m = x - 1'
ENORM='unsolved constraint: C3NSTRprop(C3TKmain(); S2Eapp(S2Ecst(>=); S2EVar(1->S2Eapp(S2Ecst(sub_int_int); S2Evar(n(2)), S2Eintinf(1))), S2Eintinf(0)))'

if [ "$ONLY" != memo ]; then
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
fi

# ======================================================================
# the memo
# ======================================================================
sum256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
# a patsopt that says what it was asked to check: "snippet <file>" for a
# .dats that holds a fixture's snippet, "base <file>" for any other, to
# PLOG; while FLAG_FAIL is there it fails, while FLAG_HANG is there it
# waits (its pid in HANG_PID). The same file for every run, so the
# toolchain's digest is the same.
REAL=$HOME/.bats/ats2
H=$TMP/home
mkdir -p "$H/.bats/ats2/bin"
for d in prelude libats share ccomp; do ln -s "$REAL/$d" "$H/.bats/ats2/$d"; done
PLOG=$TMP/patsopt-log; FLAG_FAIL=$TMP/flag-fail; FLAG_HANG=$TMP/flag-hang; HANG_PID=$TMP/hang-pid
: > "$PLOG"
printf '#!/bin/sh\nd=; depgen=0; prev=; for a in "$@"; do [ "$a" = --depgen ] && depgen=1; [ "$prev" = -d ] && d=$a; prev=$a; done\nif [ $depgen = 0 ] && [ -n "$d" ]; then if grep -q "fixture-snippet" "$d" 2>/dev/null; then echo "snippet $d" >> "%s"; else echo "base $d" >> "%s"; fi; fi\nif [ $depgen = 0 ] && [ -f "%s" ]; then echo $$ > "%s"; exec sleep 600; fi\nif [ $depgen = 0 ] && [ -f "%s" ]; then exit 1; fi\nexec "%s" "$@"\n' "$PLOG" "$PLOG" "$FLAG_HANG" "$HANG_PID" "$FLAG_FAIL" "$REAL/bin/patsopt" > "$H/.bats/ats2/bin/patsopt"
chmod +x "$H/.bats/ats2/bin/patsopt"

mkproj() { # <dir>: lib (stadefs), other (reads lib's interface), unrelated, helper
  d=$1; mkdir -p "$d/src"
  printf '[package]\nname = "fx"\nkind = "lib"\n' > "$d/bats.toml"
  printf '#include "share/atspre_staload.hats"\n\n#pub stadef limit = 1\n\n#pub stadef spare = 1\n\n#pub fn f (x: int): int\n\nimplement f (x) = x + 1\n\n(* end *)\n' > "$d/src/lib.bats"
  printf '#include "share/atspre_staload.hats"\nstaload "lib.sats"\n\n#pub fn one (): int(limit)\n\nimplement one () = 1\n' > "$d/src/other.bats"
  printf '#include "share/atspre_staload.hats"\n\n#pub fn lone (): int\n\nimplement lone () = 4\n' > "$d/src/unrelated.bats"
  printf '#include "share/atspre_staload.hats"\n\n#pub fn help (): int\n\nimplement help () = 7\n' > "$d/src/helper.bats"
}
# mfix <dir> <accept|reject> <name> <module> <before> <snippet> [<expect>]
mfix() {
  d=$1/$2/$3; mkdir -p "$d"
  printf '%s\n' "$4" > "$d/file"; printf '%s\n' "$5" > "$d/before"
  printf '(* fixture-snippet *)\n%s\n' "$6" > "$d/snippet.bats"
  [ $# -lt 7 ] || printf '%s\n' "$7" > "$d/expect"
}
MP=$TMP/mproj; MF=$TMP/mfix; MW=$TMP/mwork; M=$TMP/memo
mkproj "$MP"
mfix "$MF" accept lib-ok src/lib.bats '(* end *)' 'fn g (x: int): int = x'
mfix "$MF" reject lib-bad src/lib.bats '(* end *)' 'fn h (x: int): int = case+ x of 0 => 1' 'function h
line 2
pattern match is nonexhaustive:
[^0]'
mfix "$MF" accept other-ok src/other.bats 'implement one () = 1' 'fn g2 (x: int): int = x'
mfix "$MF" accept lone-ok src/unrelated.bats 'implement lone () = 4' 'fn g3 (x: int): int = x'
mrunx() { # <proj> <fixtures> <work> <memo> <log> args...: the status in $rc
  px=$1; fx=$2; wx=$3; mx=$4; l=$5; shift 5
  t0=$(date +%s)
  (cd "$px" && HOME=$H "$BATS" fixtures "$fx" --work "$wx" --memo "$mx" "$@") > "$l" 2>&1; rc=$?
  echo "$(( $(date +%s) - t0 )) s $(basename "$l")" >> "$TMP/times"
}
mrun() { l=$1; shift; : > "$PLOG"; mrunx "$MP" "$MF" "$MW" "$M" "$l" "$@"; }
# 1 when patsopt checked a .dats holding a snippet of module $1 (a check
# runs it more than once), else 0
ranfx() { n=$(grep -c "^snippet build/src/$1\\.dats\$" "$PLOG"); if [ "${n:-0}" -gt 0 ]; then echo 1; else echo 0; fi; }
nentries() { find "$1" -type f -name '[0-9a-f]*' ! -name '.*' 2>/dev/null | wc -l | tr -d ' '; }
memoed() { # <log> <n>: exactly n of its ok lines are from the memo
  n=$(grep -ac '^ok   .* (0 s) \[memo\]$' "$1")
  [ "$n" = "$2" ] || { echo "--- $1"; cat "$1"; fail "$3: $n lines from the memo, not $2"; }
}
resum() { sed '$d' "$1" > "$1.b"; { cat "$1.b"; printf 'sum %s\n' "$(sum256 < "$1.b")"; } > "$1"; rm -f "$1.b"; }
entry_of() { # <member>: the memo's entry of a fixture (runs it)
  mrun "$TMP/entry.log" --only "$1"
  k=$(cat "$MW/memo.key"); echo "$M/$(printf '%s' "$k" | cut -c1-2)/$k"
}

# ---- cold memo: runs, keeps; the second run serves all from the memo
mrun "$TMP/m1.log"
[ $rc = 0 ] || { cat "$TMP/m1.log"; fail "memo: first run: status $rc"; }
said "$TMP/m1.log" "fixtures: 4 ok, 0 failed" "memo first"
memoed "$TMP/m1.log" 0 "memo first"
[ "$(nentries "$M")" = 4 ] || fail "memo: the first run kept $(nentries "$M") entries, not 4"
[ "$(ranfx lib)$(ranfx other)$(ranfx unrelated)" = 111 ] || fail "memo: first run: patsopt did not check the fixtures"
mrun "$TMP/m2.log"
[ $rc = 0 ] || { cat "$TMP/m2.log"; fail "memo: second run: status $rc"; }
said "$TMP/m2.log" "fixtures: 4 ok, 0 failed (4 from the memo)" "memo second"
memoed "$TMP/m2.log" 4 "memo second"
okline "$TMP/m2.log" reject/lib-bad second
[ "$(ranfx lib)$(ranfx other)$(ranfx unrelated)" = 000 ] || fail "memo: second run ran patsopt on a fixture: $(cat "$PLOG")"
# the quire log shape is kept: ok   <member> (N s) first, the marker after
grep -aqE '^ok   accept/lib-ok \(0 s\) \[memo\]$' "$TMP/m2.log" || fail "memo: the marker is not after (N s)"

# ---- the key holds no absolute path, and the memo is where --memo says
for e in $(find "$M" -type f -name '[0-9a-f]*' ! -name '.*'); do
  ! grep -aqF -e "$TMP" "$e" || fail "memo: an entry holds an absolute path: $e"
  ! grep -aqF -e "$MP" -e "$MW" "$e" || fail "memo: an entry holds the project's or work path"
done
# a copy of the project at another path, in another work directory, with
# the memo copied elsewhere: all from the memo
MP2=$TMP/mproj-copy; M2=$TMP/memo-copy
cp -R "$MP" "$MP2"; cp -R "$M" "$M2"
: > "$PLOG"; mrunx "$MP2" "$MF" "$TMP/mwork-copy" "$M2" "$TMP/m3.log"
[ $rc = 0 ] || { cat "$TMP/m3.log"; fail "memo: a copy: status $rc"; }
memoed "$TMP/m3.log" 4 "memo copy"
[ "$(ranfx lib)$(ranfx other)$(ranfx unrelated)" = 000 ] || fail "memo: a copy ran patsopt on a fixture"

# ---- --memo wins over BATS_MEMO_DIR, which wins over the user's cache
(cd "$MP" && HOME=$H BATS_MEMO_DIR=$TMP/memo-by-env "$BATS" fixtures "$MF" --work "$MW" --only accept/lone-ok > "$TMP/env.log" 2>&1) || { cat "$TMP/env.log"; fail "BATS_MEMO_DIR: failed"; }
[ "$(nentries "$TMP/memo-by-env")" = 1 ] || fail "memo: BATS_MEMO_DIR was not used"
(cd "$MP" && env -u BATS_MEMO_DIR HOME=$H XDG_CACHE_HOME=$TMP/xdg "$BATS" fixtures "$MF" --work "$MW" --only accept/lone-ok > "$TMP/xdg.log" 2>&1) || { cat "$TMP/xdg.log"; fail "XDG_CACHE_HOME: failed"; }
[ "$(nentries "$TMP/xdg/bats/fixtures")" = 1 ] || fail "memo: the user's cache was not used"
(cd "$MP" && env -u BATS_MEMO_DIR -u XDG_CACHE_HOME HOME=$H "$BATS" fixtures "$MF" --work "$MW" --only accept/lone-ok > "$TMP/home.log" 2>&1) || { cat "$TMP/home.log"; fail "HOME cache: failed"; }
[ "$(nentries "$H/.cache/bats/fixtures")" = 1 ] || fail "memo: ~/.cache/bats/fixtures was not used"

# ---- an unrelated module changes: only its own fixture runs again
printf '(* changed *)\n' >> "$MP/src/unrelated.bats"
mrun "$TMP/m4.log" --only accept/lone-ok --only accept/lib-ok --only accept/other-ok
[ $rc = 0 ] || { cat "$TMP/m4.log"; fail "memo: unrelated: status $rc"; }
memoed "$TMP/m4.log" 2 "memo unrelated"
[ "$(ranfx unrelated)" = 1 ] && [ "$(ranfx lib)$(ranfx other)" = 00 ] || fail "memo: an unrelated change: $(cat "$PLOG")"
# the body of a module that reads lib's interface is not the interface: lib's fixtures are served
printf '(* changed *)\n' >> "$MP/src/other.bats"
mrun "$TMP/m5.log"
[ $rc = 0 ] || { cat "$TMP/m5.log"; fail "memo: dependent body: status $rc"; }
memoed "$TMP/m5.log" 3 "memo dependent body"
[ "$(ranfx other)" = 1 ] && [ "$(ranfx lib)" = 0 ] || fail "memo: a dependent's body invalidated the module it reads: $(cat "$PLOG")"

# ---- the module itself changes: its fixtures run again, the others' do not
sed -i.bak 's/^implement f (x) = x + 1/implement f (x) = x + 2/' "$MP/src/lib.bats"
mrun "$TMP/m6.log"
[ $rc = 0 ] || { cat "$TMP/m6.log"; fail "memo: module: status $rc"; }
memoed "$TMP/m6.log" 2 "memo module"
[ "$(ranfx lib)" = 1 ] && [ "$(ranfx other)$(ranfx unrelated)" = 00 ] || fail "memo: a changed module: $(cat "$PLOG")"
# a staloaded .sats changes, to one of the same size: the module that reads it runs again
sed -i.bak 's/#pub stadef spare = 1/#pub stadef spare = 2/' "$MP/src/lib.bats"
mrun "$TMP/m7.log"
[ $rc = 0 ] || { cat "$TMP/m7.log"; fail "memo: .sats: status $rc"; }
[ "$(ranfx other)" = 1 ] && [ "$(ranfx unrelated)" = 0 ] || fail "memo: a changed staloaded .sats of the same size: $(cat "$PLOG")"
memoed "$TMP/m7.log" 1 "memo .sats"
# a module added (a .sats that patsopt might read instead): everything runs again
printf '#include "share/atspre_staload.hats"\n\n#pub fn extra (): int\n\nimplement extra () = 9\n' > "$MP/src/extra.bats"
mrun "$TMP/m8.log"
[ $rc = 0 ] || { cat "$TMP/m8.log"; fail "memo: added module: status $rc"; }
memoed "$TMP/m8.log" 0 "memo added module"
[ "$(ranfx lib)$(ranfx other)$(ranfx unrelated)" = 111 ] || fail "memo: a module added: $(cat "$PLOG")"

# ---- the fixture's own files: the snippet and `before`
printf '(* fixture-snippet *)\nfn g (x: int): int = x + 0\n' > "$MF/accept/lib-ok/snippet.bats"
mrun "$TMP/m9.log"
[ $rc = 0 ] || { cat "$TMP/m9.log"; fail "memo: snippet: status $rc"; }
memoed "$TMP/m9.log" 3 "memo snippet"
[ "$(ranfx lib)" = 1 ] || fail "memo: a changed snippet: $(cat "$PLOG")"
printf 'implement f (x) = x + 2\n' > "$MF/accept/lib-ok/before"
mrun "$TMP/m10.log"
[ $rc = 0 ] || { cat "$TMP/m10.log"; fail "memo: before: status $rc"; }
memoed "$TMP/m10.log" 3 "memo before"
[ "$(ranfx lib)" = 1 ] || fail "memo: a changed before: $(cat "$PLOG")"
printf '(* end *)\n' > "$MF/accept/lib-ok/before"
printf '(* fixture-snippet *)\nfn g (x: int): int = x\n' > "$MF/accept/lib-ok/snippet.bats"

# ---- a changed toolchain: nothing is served
printf '# another patsopt\n' >> "$H/.bats/ats2/bin/patsopt"
# (bats trusts the toolchain listing it left in build/ whatever patsopt is now,
# so the stamp does not see an edit in place: the listing is taken away here
# as a restored build/ of another install would not have it)
rm -f "$MW/app/build/.bats_toolchain"
mrun "$TMP/m11.log"
[ $rc = 0 ] || { cat "$TMP/m11.log"; fail "memo: toolchain: status $rc"; }
memoed "$TMP/m11.log" 0 "memo toolchain"
[ "$(ranfx lib)" = 1 ] || fail "memo: a changed toolchain was served"
mrun "$TMP/m11b.log"
memoed "$TMP/m11b.log" 4 "memo toolchain again"

# ---- a reject keeps patsopt's log: the expect is judged again each run
cp "$MF/reject/lib-bad/expect" "$TMP/expect.good"
printf 'function h\nline 2\npattern match is nonexhaustive!\n[^0]\n' > "$MF/reject/lib-bad/expect"
mrun "$TMP/m12.log"
[ $rc = 1 ] || { cat "$TMP/m12.log"; fail "memo: a wrong expect: status $rc, not 1"; }
saidpart "$TMP/m12.log" "FAIL reject/lib-bad: rejected, but not as its expect says: its error is not the one expected:" "memo wrong expect"
[ "$(ranfx lib)" = 0 ] || fail "memo: a changed expect ran patsopt: $(cat "$PLOG")"
cp "$TMP/expect.good" "$MF/reject/lib-bad/expect"
mrun "$TMP/m13.log"
[ $rc = 0 ] || { cat "$TMP/m13.log"; fail "memo: expect put back: status $rc"; }
memoed "$TMP/m13.log" 4 "memo expect back"
[ "$(ranfx lib)" = 0 ] || fail "memo: the expect put back ran patsopt"
# the log the memo holds is what is judged: change a word of it (with a sum that is right)
E=$(entry_of reject/lib-bad)
sed 's/pattern match is nonexhaustive/pattern match is nonexhaustiv3/' "$E" > "$E.x" && mv "$E.x" "$E" && resum "$E"
mrun "$TMP/m14.log" --only reject/lib-bad
[ $rc = 1 ] || { cat "$TMP/m14.log"; fail "memo: a stored log of another word: status $rc"; }
saidpart "$TMP/m14.log" "FAIL reject/lib-bad: rejected, but not as its expect says" "memo stored log judged"
[ "$(ranfx lib)" = 0 ] || fail "memo: a hit ran patsopt"
# --cold: reads no memo, runs everything, writes, and says the memo lied
mrun "$TMP/m15.log" --cold --only reject/lib-bad
[ $rc = 1 ] || { cat "$TMP/m15.log"; fail "memo: cold audit of a doctored log: status $rc, not 1"; }
saidpart "$TMP/m15.log" "FAIL reject/lib-bad: STALE MEMO: the log the memo holds is not the cold run's (key " "memo cold audit"
[ "$(ranfx lib)" = 1 ] || fail "memo: --cold did not run the fixture"
mrun "$TMP/m16.log" --only reject/lib-bad
[ $rc = 0 ] || { cat "$TMP/m16.log"; fail "memo: after a stale memo: status $rc"; }
memoed "$TMP/m16.log" 1 "memo after stale (the cold run wrote it right)"
[ "$(ranfx lib)" = 0 ] || fail "memo: the doctored entry was served again"
# --cold on a memo that is right says nothing, reads nothing, and writes it again
mrun "$TMP/m18.log" --cold
[ $rc = 0 ] || { cat "$TMP/m18.log"; fail "memo: cold run: status $rc"; }
memoed "$TMP/m18.log" 0 "memo cold"
notsaid "$TMP/m18.log" "STALE" "a right memo was called stale"
[ "$(ranfx lib)$(ranfx other)$(ranfx unrelated)" = 111 ] || fail "memo: --cold read the memo: $(cat "$PLOG")"
said "$TMP/m18.log" "fixtures: 4 ok, 0 failed" "memo cold"
mrun "$TMP/m19.log"
memoed "$TMP/m19.log" 4 "memo after cold"
# a toolchain that now says another thing than the memo (outside the key): --cold finds it, and drops the entry
: > "$FLAG_FAIL"
mrun "$TMP/m20.log" --only accept/lone-ok
memoed "$TMP/m20.log" 1 "memo lie served"
mrun "$TMP/m21.log" --cold --only accept/lone-ok
[ $rc = 1 ] || { cat "$TMP/m21.log"; fail "memo: cold audit of a lie: status $rc"; }
saidpart "$TMP/m21.log" "FAIL accept/lone-ok: STALE MEMO: the memo says the check passes, the cold run's status is 1 (key " "memo cold audit lie"
mrun "$TMP/m22.log" --only accept/lone-ok
[ $rc = 1 ] || { cat "$TMP/m22.log"; fail "memo: after the lie was dropped: status $rc"; }
saidpart "$TMP/m22.log" "FAIL accept/lone-ok: should type-check" "memo lie dropped"
rm -f "$FLAG_FAIL"
mrun "$TMP/m23.log"
[ $rc = 0 ] || { cat "$TMP/m23.log"; fail "memo: lie gone: status $rc"; }

# ---- an entry that is torn, garbled, of another format or another key is a miss
E=$(entry_of accept/lone-ok)
cp "$E" "$TMP/entry.keep"
total=$(wc -c < "$E" | tr -d ' ')
head -c $((total / 2)) "$TMP/entry.keep" > "$E"
mrun "$TMP/m24.log" --only accept/lone-ok
memoed "$TMP/m24.log" 0 "memo truncated"; [ "$(ranfx unrelated)" = 1 ] || fail "memo: a truncated entry was trusted"
[ "$(cat "$E")" = "$(cat "$TMP/entry.keep")" ] || fail "memo: the truncated entry was not written whole again"
sed 's/^lock none$/lock nonf/' "$TMP/entry.keep" > "$E"
mrun "$TMP/m25.log" --only accept/lone-ok
memoed "$TMP/m25.log" 0 "memo garbled"; [ "$(ranfx unrelated)" = 1 ] || fail "memo: a garbled entry (right length, wrong sum) was trusted"
sed 's/^bats-fixture-memo 1$/bats-fixture-memo 2/' "$TMP/entry.keep" > "$E"; resum "$E"
mrun "$TMP/m26.log" --only accept/lone-ok
memoed "$TMP/m26.log" 0 "memo format"; [ "$(ranfx unrelated)" = 1 ] || fail "memo: an entry of another format was trusted"
E2=$(entry_of accept/lib-ok)
cp "$E2" "$TMP/entry2.keep"
cp "$TMP/entry.keep" "$E2"
mrun "$TMP/m27.log" --only accept/lib-ok
memoed "$TMP/m27.log" 0 "memo foreign"; [ "$(ranfx lib)" = 1 ] || fail "memo: another fixture's entry (a right sum) was trusted"
# with one line dropped from the middle and the sum made right: the count is wrong
sed '8d' "$TMP/entry.keep" > "$E"; resum "$E"
mrun "$TMP/m28.log" --only accept/lone-ok
memoed "$TMP/m28.log" 0 "memo short"; [ "$(ranfx unrelated)" = 1 ] || fail "memo: an entry with a line missing was trusted"
# a reject's entry is not an accept's: a pass entry under a reject's key is not served
E3=$(entry_of reject/lib-bad)
cp "$TMP/entry.keep" "$E3"
sed -i.bak "s/^key .*/key $(basename "$E3")/" "$E3"; rm -f "$E3.bak"; resum "$E3"
mrun "$TMP/m29.log" --only reject/lib-bad
[ $rc = 0 ] || { cat "$TMP/m29.log"; fail "memo: a pass entry under a reject: status $rc"; }
memoed "$TMP/m29.log" 0 "memo kind"; [ "$(ranfx lib)" = 1 ] || fail "memo: a reject was served a pass"

# ---- failures are never kept as a pass
MF3=$TMP/mfix3
mfix "$MF3" accept does-not-check src/lib.bats '(* end *)' 'fn g (x: int): int = case+ x of 0 => 1'
mfix "$MF3" reject passes src/lib.bats '(* end *)' 'fn g (x: int): int = x' 'function g
line 2
anything'
mfix "$MF3" reject no-patsopt-error src/lib.bats '(* end *)' 'fun h (x: int): int = x' 'function h
line 2
anything'
mfix "$MF3" reject wrong-expect src/lib.bats '(* end *)' 'fn h (x: int): int = case+ x of 0 => 1' 'function h
line 2
pattern match is nonexhaustive!
[^0]'
M3=$TMP/memo3
: > "$PLOG"; mrunx "$MP" "$MF3" "$MW" "$M3" "$TMP/f1.log"
[ $rc = 1 ] || { cat "$TMP/f1.log"; fail "memo failures: status $rc, not 1"; }
said "$TMP/f1.log" "fixtures: 0 ok, 4 failed" "memo failures"
[ "$(nentries "$M3")" = 1 ] || fail "memo: failures left $(nentries "$M3") entries, not the one log of the reject with a wrong expect"
: > "$PLOG"; mrunx "$MP" "$MF3" "$MW" "$M3" "$TMP/f2.log"
[ $rc = 1 ] || fail "memo failures again: status $rc"
said "$TMP/f2.log" "fixtures: 0 ok, 4 failed" "memo failures again"
[ "$(ranfx lib)" = 1 ] || fail "memo: a failure was served from the memo: $(cat "$PLOG")"
saidpart "$TMP/f2.log" "FAIL accept/does-not-check: should type-check" "memo failures again"
saidpart "$TMP/f2.log" "FAIL reject/passes: should be rejected" "memo failures again"
saidpart "$TMP/f2.log" "FAIL reject/wrong-expect: rejected, but not as its expect says" "memo failures again"

# ---- a snippet that loads a file is never kept: it reads one the module's closure does not name
MF4=$TMP/mfix4
mfix "$MF4" accept loads src/lib.bats '(* end *)' 'staload "helper.sats"

fn g (): int = help ()'
M4=$TMP/memo4
: > "$PLOG"; mrunx "$MP" "$MF4" "$MW" "$M4" "$TMP/l1.log"
[ $rc = 0 ] || { cat "$TMP/l1.log"; fail "memo load: status $rc"; }
[ "$(nentries "$M4")" = 0 ] || fail "memo: a snippet that loads a file was kept"
: > "$PLOG"; mrunx "$MP" "$MF4" "$MW" "$M4" "$TMP/l2.log"
memoed "$TMP/l2.log" 0 "memo load"
[ "$(ranfx lib)" = 1 ] || fail "memo: a snippet that loads a file was served"

# ---- a module that reads the interface the snippet changed is in the entry
MF5=$TMP/mfix5
mfix "$MF5" reject moves-limit src/lib.bats '(* end *)' 'fn g (x: int): int = x
#pub stadef limit = 2' 'function g
line 3
anything'
M5=$TMP/memo5
: > "$PLOG"; mrunx "$MP" "$MF5" "$MW" "$M5" "$TMP/d1.log"
[ $rc = 1 ] || { cat "$TMP/d1.log"; fail "memo dependents: status $rc, not 1"; }
saidpart "$TMP/d1.log" "FAIL reject/moves-limit: rejected, but not as its expect says: an error is in " "memo dependents"
[ "$(nentries "$M5")" = 1 ] || fail "memo: the log of an error in a dependent was not kept"
mrunx "$MP" "$MF5" "$MW" "$M5" "$TMP/d2.log"
saidpart "$TMP/d2.log" "FAIL reject/moves-limit: rejected, but not as its expect says: an error is in " "memo dependents again"
cp "$MP/src/other.bats" "$TMP/other.keep"
printf '#include "share/atspre_staload.hats"\nstaload "lib.sats"\n\n#pub fn one (): int\n\nimplement one () = 1\n' > "$MP/src/other.bats"
: > "$PLOG"; mrunx "$MP" "$MF5" "$MW" "$M5" "$TMP/d3.log"
[ "$(ranfx lib)" = 1 ] || fail "memo: the log of a check whose dependent has changed was served: $(cat "$PLOG")"
saidpart "$TMP/d3.log" "FAIL reject/moves-limit: should be rejected" "memo dependents changed"
cp "$TMP/other.keep" "$MP/src/other.bats"

# ---- a run killed while it checks leaves no entry
M6=$TMP/memo6
mrunx "$MP" "$MF" "$MW" "$M6" "$TMP/k0.log" --only accept/lone-ok
[ "$(nentries "$M6")" = 1 ] || fail "memo kill: no first entry"
rm -rf "$M6"; : > "$HANG_PID"
: > "$FLAG_HANG"
(cd "$MP" && HOME=$H exec "$BATS" fixtures "$MF" --work "$MW" --memo "$M6" --only accept/lone-ok > "$TMP/k1.log" 2>&1) &
bats_pid=$!
n=0; while [ ! -s "$HANG_PID" ] && [ $n -lt 600 ]; do sleep 0.1; n=$((n + 1)); done
[ -s "$HANG_PID" ] || { kill -9 $bats_pid 2>/dev/null; rm -f "$FLAG_HANG"; fail "memo kill: the check never started"; }
kill -9 "$bats_pid" 2>/dev/null; kill -9 "$(cat "$HANG_PID")" 2>/dev/null
wait "$bats_pid" 2>/dev/null
rm -f "$FLAG_HANG"
sleep 1
[ "$(find "$M6" -type f -name '[0-9a-f]*' | wc -l | tr -d ' ')" = 0 ] || fail "memo kill: an entry or a temporary file was left: $(find "$M6" -type f)"
mrunx "$MP" "$MF" "$MW" "$M6" "$TMP/k2.log" --only accept/lone-ok
[ $rc = 0 ] || { cat "$TMP/k2.log"; fail "memo kill: the next run: status $rc"; }
memoed "$TMP/k2.log" 0 "memo kill next"

# ---- four copies side by side, five rounds: never a torn entry
for c in 1 2 3 4; do cp -R "$MP" "$TMP/par$c"; done
M7=$TMP/memo7
round=1
while [ $round -le 5 ]; do
  if [ $round -le 4 ]; then rm -rf "$M7"; fi
  pids=
  for c in 1 2 3 4; do
    extra=; if [ $round -eq 5 ] && [ $((c % 2)) = 0 ]; then extra=--cold; fi
    (cd "$TMP/par$c" && HOME=$H "$BATS" fixtures "$MF" --work "$TMP/parw$c" --memo "$M7" --only accept/lone-ok --only reject/lib-bad $extra > "$TMP/par$c.log" 2>&1; echo $? > "$TMP/par$c.rc") &
    pids="$pids $!"
  done
  wait $pids
  for c in 1 2 3 4; do
    [ "$(cat "$TMP/par$c.rc")" = 0 ] || { cat "$TMP/par$c.log"; fail "memo parallel: copy $c, round $round: status $(cat "$TMP/par$c.rc")"; }
    notsaid "$TMP/par$c.log" "FAIL" "memo parallel round $round copy $c"
  done
  [ "$(find "$M7" -name '.tmp.*' | wc -l | tr -d ' ')" = 0 ] || fail "memo parallel: a temporary file was left"
  [ "$(nentries "$M7")" = 2 ] || fail "memo parallel: round $round: $(nentries "$M7") entries, not 3"
  round=$((round + 1))
done
mrunx "$TMP/par1" "$MF" "$TMP/parw1" "$M7" "$TMP/par-last.log" --only accept/lone-ok --only reject/lib-bad
memoed "$TMP/par-last.log" 2 "memo parallel last"

# ---- --prune
M8=$TMP/memo8
mrunx "$MP" "$MF" "$MW" "$M8" "$TMP/p0.log"
[ "$(nentries "$M8")" = 4 ] || fail "memo prune: $(nentries "$M8") entries, not 4"
MFP=$TMP/mfixp; cp -R "$MF" "$MFP"; rm -rf "$MFP/accept/other-ok"
mkdir -p "$TMP/outside/ab"; printf x > "$TMP/outside/ab/$(printf '1%.0s' $(seq 64))"
ln -s "$TMP/outside" "$M8/ab" 2>/dev/null || true
printf keep > "$M8/note.txt"
dead=$M8/$(ls "$M8" | grep '^[0-9a-f][0-9a-f]$' | head -1)/.tmp.$(printf '2%.0s' $(seq 64)).999999
printf x > "$dead"
mrunx "$MP" "$MFP" "$MW" "$M8" "$TMP/p1.log" --prune
[ $rc = 0 ] || { cat "$TMP/p1.log"; fail "memo prune: status $rc"; }
said "$TMP/p1.log" "fixtures: 3 ok, 0 failed (3 from the memo)" "memo prune"
n=$(grep -ac '^pruned ' "$TMP/p1.log")
[ "$n" = 2 ] || { cat "$TMP/p1.log"; fail "memo prune: listed $n removals, not 2 (the fixture's entry and the dead temporary file)"; }
saidpart "$TMP/p1.log" "memo: pruned 2 entries, kept 3" "memo prune"
[ "$(nentries "$M8")" = 3 ] || fail "memo prune: $(nentries "$M8") entries left, not 3"
[ ! -e "$dead" ] || fail "memo prune: the dead temporary file stayed"
[ -f "$TMP/outside/ab/$(printf '1%.0s' $(seq 64))" ] || fail "memo prune: removed through a link"
[ "$(cat "$M8/note.txt")" = keep ] || fail "memo prune: removed a file that is no entry"
# not a memo: nothing is touched
NM=$TMP/not-a-memo; mkdir -p "$NM/ab"; printf x > "$NM/ab/$(printf '3%.0s' $(seq 64))"
mrunx "$MP" "$MFP" "$MW" "$NM" "$TMP/p2.log" --prune --only accept/lone-ok 2>/dev/null
[ $rc = 2 ] || fail "memo prune with --only: status $rc, not 2"
saidpart "$TMP/p2.log" "needs the whole set: not with --only" "memo prune --only"
mrunx "$MP" "$MFP" "$MW" "$NM" "$TMP/p3.log" --prune
saidpart "$TMP/p3.log" "memo: nothing pruned, $NM is not a fixtures memo" "memo prune not a memo"
[ "$(nentries "$NM")" = 1 ] || fail "memo: wrote entries into a directory that is no memo"
[ -f "$NM/ab/$(printf '3%.0s' $(seq 64))" ] || fail "memo prune: removed a file of a directory that is no memo"

# ---- the script bats runs is the one in the source
sh -n "$MW/memo.sh" || fail "the memo script bats writes is not a shell script"
[ "$(head -c 10 "$MW/memo.sh")" = "#!/bin/sh$(printf '\n')" ] || fail "the memo script bats writes does not begin as it should"

[ -z "${TIMES:-}" ] || cat "$TMP/times"
echo "ok"
