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
# argument `memo` runs only those, which is how the mutants below are
# killed in a few minutes each):
#  * a second run serves every fixture from the memo (`ok   <member> (0 s)
#    [memo]`, `fixtures: N ok, 0 failed (N from the memo)`) and runs no
#    patsopt; the key holds no absolute path (a copy of the project at
#    another path, and the memo copied elsewhere, still hit);
#  * a changed module, a changed staloaded .sats (of the same size), a
#    changed snippet or `before`, a changed bats.toml, a module added, a
#    changed toolchain: each runs the fixture again; a change in a module
#    the fixture does not read, or in one that reads the module without
#    reading the interface the snippet left, does not; a snippet that loads
#    a file or changes the interface is never kept;
#  * a hit stands in for patsopt's answer, never for the validation of the
#    whole project (the call cycles of every module, the lexer's rules):
#    a cycle through another module's implement, made after the entry was
#    kept, is refused (the first version of this memo, df56636, served it
#    as a pass); and `bats check` of the same project refuses it with every
#    module warm, so the check memo of #298 has no such hole;
#  * a reject keeps patsopt's log, not a verdict: a changed or wrong expect
#    is judged again against the stored log, with no patsopt run;
#  * a failure is never kept as a pass (an accept that does not check, a
#    reject that checks, a check that fails with no error of patsopt's);
#  * a torn, garbled, truncated, empty, missing, foreign, other-key or
#    other-format .res or .key is a miss; four copies of the project side by
#    side, five rounds, never serve or leave a torn file; a run killed while
#    it checks leaves no file;
#  * --cold reads no memo, writes it, and reports a memo that no longer
#    says what a cold run does (STALE MEMO), replacing it;
#  * --prune lists and removes the .key and .res files the run did not use,
#    and nothing else (not a stray file, not a directory without the
#    memo's mark, not through a link, not in a directory that is no memo),
#    and is a usage error with --only.
# bats-lang/bats#305 is the bug the toolchain case works around.
#
# Mutants. Each is one edit of src/fixtures.bats (`old` -> `new`; rebuild
# with `bats build`, then run this script on the result with `memo`); the
# script must exit 1 and its FAIL line must hold the text after "killed by".
# The three last are equivalent: the field they edit is also determined by
# another (the spliced module's hash holds the snippet and where `before`
# put it; the entry's .key holds the toolchain's stamp), so no run can tell
# them from the original; the key names them anyway, as what it depends on.
#  1. validate-skipped: `else if ~validate_clean() then let val () = $B.builder_free(md) in 100 end` -> `else if false then let val () = $B.builder_free(md) in 100 end`
#     killed by: "a cycle through another module's implement was served from the memo"
#  2. interface-kept: `&& iface_same(cfg, w, bv_f, mlen) &&` -> `&& true &&`
#     killed by: "a snippet that loads a file, or one that changes the interface, was kept"
#  3. loads-kept: `~snippet_loads(cfg, w, mv, a, e)` -> `true`
#     killed by: "a snippet that loads a file, or one that changes the interface, was kept"
#  3b. load-as-text: `find_word_from(bv, sn, 0, "load")` -> `find_text_from(bv, sn, 0, "load")`
#     killed by: "Download is no loading word"
#  3c. leading-boundary-removed: `&& ~is_word_byte(byte_at(bv, len, p - 1))` -> `&& true`
#     killed by: "Download is no loading word"
#  3d. trailing-boundary-removed: `&& ~is_word_byte(byte_at(bv, len, p + g1u2i(string1_length(s))))` -> `&& true`
#     killed by: "included is no loading word"
#  3e. apostrophe-counted: `fn is_word_byte(b: int): bool = is_ident_byte(b)` -> `fn is_word_byte(b: int): bool = is_ident_byte(b) || b = 39`
#     killed by: "load' is a loading word"
#  3f. end-of-file-not-a-boundary: `&& ~is_word_byte(byte_at(bv, len, p + g1u2i(string1_length(s))))` -> `&& p + g1u2i(string1_length(s)) < len && ~is_word_byte(byte_at(bv, len, p + g1u2i(string1_length(s))))`
#     killed by: "load ending the file (no newline after it) is a loading word"
#  4. failure-kept-as-pass: `val want_pass = (is_accept && status = 0): bool` -> `val want_pass = (is_accept): bool`
#     killed by: "memo cold audit lie"
#  5. no-patsopt-error-kept: `ln0 > 0 && has_error_from(bv_l, ln, 0)` -> `ln0 > 0`
#     killed by: "the log of a check that failed with no error of patsopt's was kept"
#  6. audit-off: `val stale = (if usable then audit(cfg, w, want_pass, want_log, bv_n, nn, status, bv_m, mn, bv_k) else false): bool` -> `val stale = false: bool`
#     killed by: "memo: cold audit of a doctored log: status 0, not 1"
#  7. sum-unchecked: `in (if hex_is(sum, rv, n, n - 65) then cl else ~1) end` -> `in (if hex_is(sum, rv, n, n - 65) then cl else cl) end`
#     killed by: "memo torn: status 1"
#  8. closure-digest-unchecked: `val same_key = (if kdone then hex_is(kh2, bv_r, rn, cl) else` -> `val same_key = (if kdone then (hex_is(kh2, bv_r, rn, cl) || true) else`
#     killed by: "memo closure digest: 1 lines from the memo, not 0"
#  9. closure-key-unchecked: `val r = closure_key_equal(bv_a)` -> `val r = true`
#     killed by: "a changed staloaded .sats of the same size"
#  10. prune-mark-ignored: `val dmarked = (path_exists(memo_sub2(memo, mlen, bv_n, "/.memo-dir")) && physical_sub(memo, mlen, bv_n)): bool` -> `val dmarked = physical_sub(memo, mlen, bv_n)`
#     killed by: "memo prune: listed"
#  11. prune-link-followed: `"/.memo-dir")) && physical_sub(memo, mlen, bv_n)): bool` -> `"/.memo-dir")) && true): bool`
#     killed by: "memo prune: listed"
#  12. prune-unmarked-memo: `val marked = (have_dir && path_exists(memo_plus(bv_m, mn, "/.bats-fixtures-memo"))): bool\n  val ua` -> `val marked = (have_dir): bool\n  val ua`
#     killed by: "memo prune not a memo"
#  13. key-no-snippet: `val a2 = path_sha(fixture_text(cfg, w, mv, a, e, "snippet.bats"), t)` -> `val a2 = path_sha(fixture_text(cfg, w, mv, a, e, "before"), t)`
#     equivalent: survives
#  14. key-no-before: `val a1 = path_sha(fixture_text(cfg, w, mv, a, e, "before"), t)` -> `val a1 = path_sha(fixture_text(cfg, w, mv, a, e, "snippet.bats"), t)`
#     equivalent: survives
#  15. key-no-module: `val a3 = path_sha(mp, t)` -> `val a3 = path_sha(str_builder("bats.toml"), t)\n  val () = $B.builder_free(mp)`
#     killed by: "memo unrelated: 4 lines from the memo, not 2"
#  16. key-no-toml: `val a4 = path_sha(str_builder("bats.toml"), t)` -> `val a4 = path_sha(str_builder("src/helper.bats"), t)`
#     killed by: "memo toml: 1 lines from the memo, not 0"
#  17. key-no-stamp: `val a5 = path_sha(str_builder("build/.bats_stamp"), t)` -> `val a5 = path_sha(str_builder("bats.toml"), t)`
#     equivalent: survives
#  18. cold-serves: `      if cold then let\n        var pr` -> `      if false then let\n        var pr`
#     killed by: "memo cold audit"
#  19. prune-all: `val used = (if shaped then key_used(uv, un, 0, bv_n, nn) else true): bool` -> `val used = (if shaped then false else true): bool`
#     killed by: "memo prune: listed"
#  20. prune-stray: `val shaped = (nn = 68 && hex_run(bv_n, nn, 0)\n      && (text_has(bv_n, nn, 64, ".key") || text_has(bv_n, nn, 64, ".res"))): bool` -> `val shaped = true: bool`
#     killed by: "memo prune: listed"
#  21. store-in-no-memo: `&& memo_ready(bv_m, mn) &&` -> `&& true &&`
#     killed by: "the first run kept 0 files, not 8"
#
# usage: tests/fixtures/check.sh <bats-binary> <repository-dir> [memo]
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_CACHE_DIR BATS_COMMIT BATS_COLD BATS_MEMO_DIR XDG_CACHE_HOME
ONLY=${3:-}
T_START=$(date +%s)
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
# an existential's binder: patsopt's S2Eexi(n(8480); ... is compared as S2Eexi(n(_); ...
SEXI='fn h (f: char): [n:nat] bool = f'
# exi_expect <name> <number>: the expect for SEXI, with that binder name and number
# in its S2Eexi tokens only. Its S2Evar tokens stay n(14465), the value patsopt
# prints, so a near-miss differs from the real error in its S2Eexi token alone:
# the fixture then fails because of the S2Eexi rule and nothing else.
exi_expect() {
  printf 'function h\nline 1\nthe dynamic expression cannot be assigned the type [S2Eexi(%s(%s); S2Eapp(S2Ecst(>=); S2Evar(n(14465)), S2Eintinf(0)); S2Ecst(bool_t0ype))].\nmismatch of static terms (tyleq):\nThe actual term is: S2Ecst(char_t0ype)\nThe needed term is: S2Ecst(bool_t0ype)\nmismatch of static terms (tyleq):\nThe actual term is: S2Ecst(char_t0ype)\nThe needed term is: S2Eexi(%s(%s); S2Eapp(S2Ecst(>=); S2Evar(n(14465)), S2Eintinf(0)); S2Ecst(bool_t0ype))' "$1" "$2" "$1" "$2"
}
# a list of binders: patsopt's S2Eexi(n(8480), m(8481); ... compares every binder
SEXI_LIST='fn h (f: char): [n:nat; m:nat] bool = f'
# exi_list_expect <name> <number>: the second binder of the S2Eexi tokens, the first and every S2Evar token as patsopt-like values
exi_list_expect() {
  printf 'function h\nline 1\nthe dynamic expression cannot be assigned the type [S2Eexi(n(14465), %s(%s); S2Eapp(S2Ecst(>=); S2Evar(n(14465)), S2Eintinf(0)), S2Eapp(S2Ecst(>=); S2Evar(m(14466)), S2Eintinf(0)); S2Ecst(bool_t0ype))].\nmismatch of static terms (tyleq):\nThe actual term is: S2Ecst(char_t0ype)\nThe needed term is: S2Ecst(bool_t0ype)\nmismatch of static terms (tyleq):\nThe actual term is: S2Ecst(char_t0ype)\nThe needed term is: S2Eexi(n(14465), %s(%s); S2Eapp(S2Ecst(>=); S2Evar(n(14465)), S2Eintinf(0)), S2Eapp(S2Ecst(>=); S2Evar(m(14466)), S2Eintinf(0)); S2Ecst(bool_t0ype))' "$1" "$2" "$1" "$2"
}
# a name with copies: patsopt's S2Eexi(a$8630(14292); ... and S2Evar(a$8630$8631(14293)),
# the digits after each $ and the number are all variable numbers
SEXI_COPY='fn mk1 (): [a:nat] int a = 0
fn h (): bool = mk1 ()'
# exi_copy_expect <binder> <number>: the binder of the S2Eexi token (name with its $ copies, then number)
exi_copy_expect() {
  printf 'function h\nline 2\nthe dynamic expression cannot be assigned the type [S2Ecst(bool_t0ype)].\nmismatch of static terms (tyleq):\nThe actual term is: S2Eapp(S2Ecst(g1int_int_t0ype); S2Eextkind(atstype_int), S2Evar(a$7001$7002(15001)))\nThe needed term is: S2Ecst(bool_t0ype)\nmismatch of static terms (tyleq):\nThe actual term is: S2Eexi(%s(%s); S2Eapp(S2Ecst(>=); S2Evar(a$7001(15000)), S2Eintinf(0)); S2Eapp(S2Ecst(g1int_int_t0ype); S2Eextkind(atstype_int), S2Evar(a$7001(15000))))\nThe needed term is: S2Ecst(bool_t0ype)' "$1" "$2"
}
# both: two binders with copies
SEXI_COPY_LIST='fn mk2 (): [a:nat; b:nat] @(int a, int b) = @(0, 0)
fn h (): bool = mk2 ()'
# exi_copy_list_expect <name> <number>: the second binder of the S2Eexi token
exi_copy_list_expect() {
  printf 'function h\nline 2\nthe dynamic expression cannot be assigned the type [S2Ecst(bool_t0ype)].\nmismatch of static terms (tyleq):\nThe actual term is: S2Etyrec(flt0; npf=-1; 0=S2Eapp(S2Ecst(int); S2Evar(a$7001$7003(15002))), 1=S2Eapp(S2Ecst(int); S2Evar(b$7002$7004(15003))))\nThe needed term is: S2Ecst(bool_t0ype)\nmismatch of static terms (tyleq):\nThe actual term is: S2Eexi(a$7001(15000), %s(%s); S2Eapp(S2Ecst(>=); S2Evar(a$7001(15000)), S2Eintinf(0)), S2Eapp(S2Ecst(>=); S2Evar(b$7002(15001)), S2Eintinf(0)); S2Etyrec(flt0; npf=-1; 0=S2Eapp(S2Ecst(int); S2Evar(a$7001(15000))), 1=S2Eapp(S2Ecst(int); S2Evar(b$7002(15001)))))\nThe needed term is: S2Ecst(bool_t0ype)' "$1" "$2"
}
# an unsolved variable with no arrow: patsopt's S2EVar(5245), S2EVar(5246) is compared as S2EVar(_), S2EVar(_)
SEVAR='dataprop PA (int, int) = | PA0 (0, 0)
dataprop PB (int, int) = | PB0 (0, 0)
fn h {a:int} (pf: PB(a, a) | x: int): [k:int; j:int] (PA(k, j) | int) = (pf | x)'
# evar_expect <token>: the expect for SEVAR with <token> in the first S2EVar of its first needed term;
# every other number is a value other than patsopt's, so a near-miss differs in that token alone
evar_expect() {
  printf 'function h\nline 3\nthe dynamic expression cannot be assigned the type [S2Eexi(k(9002), j(9003); ; S2Etyrec(flt0; npf=1; 0=S2Eapp(S2Ecst(PA); S2Evar(k(9002)), S2Evar(j(9003))), 1=S2Ecst(int)))].\nmismatch of static terms (tyleq):\nThe actual term is: S2Eapp(S2Ecst(PB); S2Evar(a(9001)), S2Evar(a(9001)))\nThe needed term is: S2Eapp(S2Ecst(PA); S2EVar(%s), S2EVar(7102))\nmismatch of static terms (tyleq):\nThe actual term is: S2Etyrec(flt0; npf=1; 0=S2Eapp(S2Ecst(PB); S2Evar(a(9001)), S2Evar(a(9001))), 1=S2Eapp(S2Ecst(g0int_t0ype); S2Eextkind(atstype_int)))\nThe needed term is: S2Etyrec(flt0; npf=1; 0=S2Eapp(S2Ecst(PA); S2EVar(7101), S2EVar(7102)), 1=S2Ecst(int))\nmismatch of static terms (tyleq):\nThe actual term is: S2Etyrec(flt0; npf=1; 0=S2Eapp(S2Ecst(PB); S2Evar(a(9001)), S2Evar(a(9001))), 1=S2Eapp(S2Ecst(g0int_t0ype); S2Eextkind(atstype_int)))\nThe needed term is: S2Eexi(k(9002), j(9003); ; S2Etyrec(flt0; npf=1; 0=S2Eapp(S2Ecst(PA); S2Evar(k(9002)), S2Evar(j(9003))), 1=S2Ecst(int)))' "$1"
}
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
# the number of an existential's binder is other than patsopt's
fixture "$G" reject exi-numbered "$SEXI" "$(exi_expect n 14465)"
# the numbers of every binder of a list, and of a name's copies, are other than patsopt's
fixture "$G" reject exi-binders "$SEXI_LIST" "$(exi_list_expect m 14466)"
fixture "$G" reject exi-suffix "$SEXI_COPY" "$(exi_copy_expect 'a$7001' 15000)"
fixture "$G" reject exi-suffix-binders "$SEXI_COPY_LIST" "$(exi_copy_list_expect 'b$7002' 15001)"
# the number of a variable with no arrow is other than patsopt's
fixture "$G" reject evar-bare "$SEVAR" "$(evar_expect 7101)"
run "$TMP/good.log" "$G" --cold
[ $rc = 0 ] || { cat "$TMP/good.log"; fail "good fixtures: status $rc"; }
okline "$TMP/good.log" accept/ok good
okline "$TMP/good.log" reject/nonexhaustive good
okline "$TMP/good.log" reject/numbered good
okline "$TMP/good.log" reject/dollar good
okline "$TMP/good.log" reject/blank-line good
okline "$TMP/good.log" reject/exi-numbered good
okline "$TMP/good.log" reject/exi-binders good
okline "$TMP/good.log" reject/exi-suffix good
okline "$TMP/good.log" reject/exi-suffix-binders good
okline "$TMP/good.log" reject/evar-bare good
said "$TMP/good.log" "fixtures: 10 ok, 0 failed" good
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
# the binder's name is still compared, and so is a number that is not digits
fixture "$B" reject exi-other-name "$SEXI" "$(exi_expect m 14465)"
fixture "$B" reject exi-number-not-digits "$SEXI" "$(exi_expect n 14x65)"
# the second binder's name is still compared, and so is its number; so are a copy's digits
fixture "$B" reject exi-binders-other-name "$SEXI_LIST" "$(exi_list_expect k 14466)"
fixture "$B" reject exi-binders-number-not-digits "$SEXI_LIST" "$(exi_list_expect m 14x66)"
fixture "$B" reject exi-suffix-other-name "$SEXI_COPY" "$(exi_copy_expect 'b$7001' 15000)"
fixture "$B" reject exi-suffix-digits-and-letters "$SEXI_COPY" "$(exi_copy_expect 'a$70x01' 15000)"
fixture "$B" reject exi-suffix-binders-other-name "$SEXI_COPY_LIST" "$(exi_copy_list_expect 'c$7002' 15001)"
# a bare S2EVar's number is digits, not letters or a mix
fixture "$B" reject evar-bare-not-digits "$SEVAR" "$(evar_expect 71x1)"
fixture "$B" reject evar-bare-name "$SEVAR" "$(evar_expect name)"
run "$TMP/bad.log" "$B"
[ $rc = 1 ] || { cat "$TMP/bad.log"; fail "bad fixtures: status $rc, not 1"; }
L=$TMP/bad.log
failed "$L" "accept/does-not-check: should type-check" bad
failed "$L" "reject/passes: should be rejected" bad
saidpart "$L" "FAIL reject/other-word: rejected, but not as its expect says: its error is not the one expected:" bad
saidpart "$L" "FAIL reject/missing-line: rejected, but not as its expect says: its error is not the one expected:" bad
saidpart "$L" "FAIL reject/extra-line: rejected, but not as its expect says: its error is not the one expected:" bad
saidpart "$L" "FAIL reject/number-kept: rejected, but not as its expect says: its error is not the one expected:" bad
saidpart "$L" "FAIL reject/exi-other-name: rejected, but not as its expect says: its error is not the one expected:" bad
saidpart "$L" "FAIL reject/exi-number-not-digits: rejected, but not as its expect says: its error is not the one expected:" bad
for m in exi-binders-other-name exi-binders-number-not-digits exi-suffix-other-name exi-suffix-digits-and-letters exi-suffix-binders-other-name evar-bare-not-digits evar-bare-name; do
  saidpart "$L" "FAIL reject/$m: rejected, but not as its expect says: its error is not the one expected:" bad
done
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
said "$L" "fixtures: 0 ok, 26 failed" bad
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
# The solver of a stand-in patsopt is known (bats-lang/bats#264): bats probes a
# toolchain it did not install by running patsopt on two small files, which
# would be runs this test counts, so the answer is written first (the cksum of
# patsopt's bytes and 21, as src/ats2.bats keeps it).
printf '%s 21\n' "$(cksum < "$H/.bats/ats2/bin/patsopt")" > "$H/.bats/ats2.solver"

[ -z "${TIMES:-}" ] || echo "$(( $(date +%s) - T_START )) s before the memo" >> "$TMP/times"
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
# the files of a memo: <2 hex>/<64 hex>.key and .res (never the marks)
nfiles() { find "$1" -type f \( -name '[0-9a-f]*.key' -o -name '[0-9a-f]*.res' \) 2>/dev/null | wc -l | tr -d ' '; }
memoed() { # <log> <n>: exactly n of its ok lines are from the memo
  n=$(grep -ac '^ok   .* (0 s) \[memo\]$' "$1")
  [ "$n" = "$2" ] || { echo "--- $1"; cat "$1"; fail "$3: $n lines from the memo, not $2"; }
}
# a .res file made right again after an edit: its last line is the sha256 of the rest
resum() { sed '$d' "$1" > "$1.b"; { cat "$1.b"; printf '%s\n' "$(sum256 < "$1.b")"; } > "$1"; rm -f "$1.b"; }
keyof() { # <member>: the path (less .key/.res) of a fixture's entry, from the last run of the whole set
  i=$(grep -nx "$1" "$MW/members" | cut -d: -f1); k=$(sed -n "${i}p" "$MW/memo-used")
  echo "$M/$(printf '%s' "$k" | cut -c1-2)/$k"
}
bad_run() { # <log> <label> <modules that must have been checked: 111 style> args...
  l=$1; lab=$2; want=$3; shift 3
  mrun "$l" "$@"
  [ $rc = 0 ] || { cat "$l"; fail "memo $lab: status $rc"; }
  memoed "$l" 0 "memo $lab"
  [ "$(ranfx lib)$(ranfx other)$(ranfx unrelated)" = "$want" ] || fail "memo $lab: a damaged entry was trusted: $(cat "$PLOG")"
}

# ---- cold memo: runs, keeps; the second run serves all from the memo
mrun "$TMP/m1.log"
[ $rc = 0 ] || { cat "$TMP/m1.log"; fail "memo: first run: status $rc"; }
said "$TMP/m1.log" "fixtures: 4 ok, 0 failed" "memo first"
memoed "$TMP/m1.log" 0 "memo first"
[ "$(nfiles "$M")" = 8 ] || fail "memo: the first run kept $(nfiles "$M") files, not 8 (a .key and a .res each)"
[ "$(ranfx lib)$(ranfx other)$(ranfx unrelated)" = 111 ] || fail "memo: first run: patsopt did not check the fixtures"
mrun "$TMP/m2.log"
[ $rc = 0 ] || { cat "$TMP/m2.log"; fail "memo: second run: status $rc"; }
said "$TMP/m2.log" "fixtures: 4 ok, 0 failed (4 from the memo)" "memo second"
memoed "$TMP/m2.log" 4 "memo second"
okline "$TMP/m2.log" reject/lib-bad second
[ "$(ranfx lib)$(ranfx other)$(ranfx unrelated)" = 000 ] || fail "memo: second run ran patsopt on a fixture: $(cat "$PLOG")"
grep -aqE '^ok   accept/lib-ok \(0 s\) \[memo\]$' "$TMP/m2.log" || fail "memo: the marker is not after (N s)"

# ---- the key holds no absolute path, and the memo is where --memo says
for e in $(find "$M" -type f -name '[0-9a-f]*'); do
  ! grep -aqF -e "$TMP" "$e" || fail "memo: an entry holds an absolute path: $e"
done
# a copy of the project at another path, in another work directory, with
# the memo copied elsewhere: all from the memo
MP2=$TMP/mproj-copy; M2=$TMP/memo-copy
cp -R "$MP" "$MP2"; cp -R "$M" "$M2"
: > "$PLOG"; mrunx "$MP2" "$MF" "$TMP/mwork-copy" "$M2" "$TMP/m3.log"
[ $rc = 0 ] || { cat "$TMP/m3.log"; fail "memo: a copy: status $rc"; }
memoed "$TMP/m3.log" 4 "memo copy"
[ "$(ranfx lib)$(ranfx other)$(ranfx unrelated)" = 000 ] || fail "memo: a copy ran patsopt on a fixture"
rm -rf "$MP2" "$M2" "$TMP/mwork-copy"

# ---- --memo wins over BATS_MEMO_DIR, which wins over the user's cache
(cd "$MP" && HOME=$H BATS_MEMO_DIR=$TMP/memo-by-env "$BATS" fixtures "$MF" --work "$MW" --only accept/lone-ok > "$TMP/env.log" 2>&1) || { cat "$TMP/env.log"; fail "BATS_MEMO_DIR: failed"; }
[ "$(nfiles "$TMP/memo-by-env")" = 2 ] || fail "memo: BATS_MEMO_DIR was not used"
(cd "$MP" && env -u BATS_MEMO_DIR HOME=$H XDG_CACHE_HOME=$TMP/xdg "$BATS" fixtures "$MF" --work "$MW" --only accept/lone-ok > "$TMP/xdg.log" 2>&1) || { cat "$TMP/xdg.log"; fail "XDG_CACHE_HOME: failed"; }
[ "$(nfiles "$TMP/xdg/bats/fixtures")" = 2 ] || fail "memo: the user's cache was not used"
(cd "$MP" && env -u BATS_MEMO_DIR -u XDG_CACHE_HOME HOME=$H "$BATS" fixtures "$MF" --work "$MW" --only accept/lone-ok > "$TMP/home.log" 2>&1) || { cat "$TMP/home.log"; fail "HOME cache: failed"; }
[ "$(nfiles "$H/.cache/bats/fixtures")" = 2 ] || fail "memo: ~/.cache/bats/fixtures was not used"

# ---- what changes the key: an unrelated module and a dependent's body do not
printf '(* changed *)\n' >> "$MP/src/unrelated.bats"
printf '(* changed *)\n' >> "$MP/src/other.bats"
mrun "$TMP/m4.log"
[ $rc = 0 ] || { cat "$TMP/m4.log"; fail "memo: unrelated: status $rc"; }
memoed "$TMP/m4.log" 2 "memo unrelated"
[ "$(ranfx unrelated)$(ranfx other)" = 11 ] && [ "$(ranfx lib)" = 0 ] || fail "memo: a change in a module the fixture does not read, or in the body of one that reads its interface: $(cat "$PLOG")"
# the module itself changes: its fixtures run again, the others' do not
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
# a module added (a .sats that patsopt might read instead): the fixture runs again; the module is
# taken away again, and the entry that was written with it is a miss once more (the others are not touched)
printf '#include "share/atspre_staload.hats"\n\n#pub fn extra (): int\n\nimplement extra () = 9\n' > "$MP/src/extra.bats"
mrun "$TMP/m8.log" --only accept/lone-ok
[ $rc = 0 ] || { cat "$TMP/m8.log"; fail "memo: added module: status $rc"; }
memoed "$TMP/m8.log" 0 "memo added module"
[ "$(ranfx unrelated)" = 1 ] || fail "memo: a module added: $(cat "$PLOG")"
rm -f "$MP/src/extra.bats"

# ---- the fixture's own files: the snippet and `before`
printf '(* fixture-snippet *)\nfn g (x: int): int = x + 0\n' > "$MF/accept/lib-ok/snippet.bats"
mrun "$TMP/m9.log"
[ $rc = 0 ] || { cat "$TMP/m9.log"; fail "memo: snippet: status $rc"; }
memoed "$TMP/m9.log" 2 "memo snippet"
[ "$(ranfx lib)$(ranfx unrelated)" = 11 ] || fail "memo: a changed snippet (or the module taken away again): $(cat "$PLOG")"
printf 'implement f (x) = x + 2\n' > "$MF/accept/lib-ok/before"
mrun "$TMP/m10.log" --only accept/lib-ok
[ $rc = 0 ] || { cat "$TMP/m10.log"; fail "memo: before: status $rc"; }
memoed "$TMP/m10.log" 0 "memo before"
[ "$(ranfx lib)" = 1 ] || fail "memo: a changed before: $(cat "$PLOG")"
printf '(* end *)\n' > "$MF/accept/lib-ok/before"
printf '(* fixture-snippet *)\nfn g (x: int): int = x\n' > "$MF/accept/lib-ok/snippet.bats"

# ---- bats.toml is in the key
printf '# a comment\n' >> "$MP/bats.toml"
mrun "$TMP/m10t.log" --only accept/lone-ok
[ $rc = 0 ] || { cat "$TMP/m10t.log"; fail "memo: toml: status $rc"; }
memoed "$TMP/m10t.log" 0 "memo toml"
[ "$(ranfx unrelated)" = 1 ] || fail "memo: a changed bats.toml was served: $(cat "$PLOG")"

# ---- a changed toolchain: nothing is served
printf '# another patsopt\n' >> "$H/.bats/ats2/bin/patsopt"
# (another toolchain is another answer to ask: written again, as above)
printf '%s 21\n' "$(cksum < "$H/.bats/ats2/bin/patsopt")" > "$H/.bats/ats2.solver"
# (bats-lang/bats#305: bats trusts the toolchain listing it left in build/
# whatever patsopt is now, so the stamp does not see an edit in place; the
# listing is taken away here, as a restored build/ of another install would
# not have it. Not fixed in this change.)
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
# the log the memo holds is what is judged: change a word of it (with a sum that is right)
E=$(keyof reject/lib-bad)
sed 's/pattern match is nonexhaustive/pattern match is nonexhaustiv3/' "$E.res" > "$E.x" && mv "$E.x" "$E.res" && resum "$E.res"
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
mrun "$TMP/m18.log" --cold --only accept/lone-ok --only accept/lib-ok --only accept/other-ok
[ $rc = 0 ] || { cat "$TMP/m18.log"; fail "memo: cold run: status $rc"; }
memoed "$TMP/m18.log" 0 "memo cold"
notsaid "$TMP/m18.log" "STALE" "a right memo was called stale"
[ "$(ranfx lib)$(ranfx other)$(ranfx unrelated)" = 111 ] || fail "memo: --cold read the memo: $(cat "$PLOG")"
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
# a reject whose check fails with no error of patsopt's (the toolchain failed, not the snippet) is never kept as a log
M9=$TMP/memo9
mrunx "$MP" "$MF" "$MW" "$M9" "$TMP/m22b.log" --only reject/lib-bad
[ $rc = 1 ] || { cat "$TMP/m22b.log"; fail "memo: a reject on a failing toolchain: status $rc, not 1"; }
[ "$(nfiles "$M9")" = 0 ] || fail "memo: the log of a check that failed with no error of patsopt's was kept"
rm -f "$FLAG_FAIL"
mrun "$TMP/m23.log" --only accept/lone-ok
[ $rc = 0 ] || { cat "$TMP/m23.log"; fail "memo: lie gone: status $rc"; }

# ---- an entry that is torn, garbled, of another format or another key is a miss.
# Each batch damages one file of each of the four entries, runs all four, and all are checked again.
mrun "$TMP/t0.log"
[ $rc = 0 ] || { cat "$TMP/t0.log"; fail "memo damage: status $rc"; }
memoed "$TMP/t0.log" 4 "memo before the damage"
E1=$(keyof accept/lone-ok); E2=$(keyof accept/lib-ok); E3=$(keyof accept/other-ok); E4=$(keyof reject/lib-bad)
# 1. a .res cut in half; a .res with a byte changed (its sum is wrong); a .key cut in half;
#    a log with a word changed and the sum left as it was (the sum is what says the log is whole)
head -c $(( $(wc -c < "$E1.res") / 2 )) "$E1.res" > "$E1.x" && mv "$E1.x" "$E1.res"
sed 's/^pass$/pasz/' "$E3.res" > "$E3.x" && mv "$E3.x" "$E3.res"
head -c $(( $(wc -c < "$E2.key") / 2 )) "$E2.key" > "$E2.x" && mv "$E2.x" "$E2.key"
sed 's/pattern match is nonexhaustive/pattern match is nonexhaustiv3/' "$E4.res" > "$E4.x" && mv "$E4.x" "$E4.res"
bad_run "$TMP/t1.log" "torn" 111 --only accept/lone-ok --only accept/lib-ok --only accept/other-ok --only reject/lib-bad
[ "$(wc -c < "$E1.res")" -gt 200 ] || fail "memo: the torn .res was not written whole again"
# 2. another format with a right sum; another fixture's .res (a right sum, another key); a .key of another text;
#    an accept's .res put under the reject's key, its key line and sum made right (a reject is not served a pass)
cp "$E1.res" "$E4.res"; sed "2s/.*/$(basename "$E4")/" "$E4.res" > "$E4.x" && mv "$E4.x" "$E4.res"; resum "$E4.res"
sed 's/^bats-fixture-result 2$/bats-fixture-result 3/' "$E1.res" > "$E1.x" && mv "$E1.x" "$E1.res"; resum "$E1.res"
cp "$E3.res" "$E2.res"
sed 's/^bats-memo 1$/bats-memo 2/' "$E3.key" > "$E3.x" && mv "$E3.x" "$E3.key"
bad_run "$TMP/t2.log" "garbled" 111 --only accept/lone-ok --only accept/lib-ok --only accept/other-ok --only reject/lib-bad
# 3. the closure's digest the .res names is not the .key's (a right sum); a line dropped from the middle (a right sum);
#    an empty .res; a missing .key
sed '4s/.*/0000000000000000000000000000000000000000000000000000000000000000/' "$E1.res" > "$E1.x" && mv "$E1.x" "$E1.res"; resum "$E1.res"
sed '3d' "$E2.res" > "$E2.x" && mv "$E2.x" "$E2.res"; resum "$E2.res"
: > "$E3.res"; rm -f "$E4.key"
bad_run "$TMP/t3.log" "closure digest" 111 --only accept/lone-ok --only accept/lib-ok --only accept/other-ok --only reject/lib-bad
mrun "$TMP/t6.log"
memoed "$TMP/t6.log" 4 "memo after the damage"

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
[ "$(nfiles "$M3")" = 2 ] || fail "memo: failures left $(nfiles "$M3") files, not the .key and .res of the reject with a wrong expect"
: > "$PLOG"; mrunx "$MP" "$MF3" "$MW" "$M3" "$TMP/f2.log" --only accept/does-not-check --only reject/wrong-expect
[ $rc = 1 ] || fail "memo failures again: status $rc"
said "$TMP/f2.log" "fixtures: 0 ok, 2 failed" "memo failures again"
[ "$(ranfx lib)" = 1 ] || fail "memo: a failure was served from the memo: $(cat "$PLOG")"
saidpart "$TMP/f2.log" "FAIL accept/does-not-check: should type-check" "memo failures again"
saidpart "$TMP/f2.log" "FAIL reject/wrong-expect: rejected, but not as its expect says" "memo failures again"

# ---- a snippet that loads a file is never kept (it reads one the module's closure does not name),
# and neither is one that changes the interface other modules read
MF4=$TMP/mfix4
mfix "$MF4" accept loads src/lib.bats '(* end *)' '#include "share/atspre_staload.hats"

fn g (): int = 1'
mfix "$MF4" accept loads-sats src/lib.bats '(* end *)' 'staload "helper.sats"

fn g (): int = help ()'
mfix "$MF4" reject moves-limit src/lib.bats '(* end *)' 'fn g (x: int): int = x
#pub stadef limit = 2' 'function g
line 3
anything'
M4=$TMP/memo4
: > "$PLOG"; mrunx "$MP" "$MF4" "$MW" "$M4" "$TMP/l1.log"
[ $rc = 1 ] || { cat "$TMP/l1.log"; fail "memo load: status $rc, not 1"; }
okline "$TMP/l1.log" accept/loads "memo load"
okline "$TMP/l1.log" accept/loads-sats "memo load .sats"
saidpart "$TMP/l1.log" "FAIL reject/moves-limit: rejected, but not as its expect says: an error is in " "memo interface changed"
[ "$(nfiles "$M4")" = 0 ] || fail "memo: a snippet that loads a file, or one that changes the interface, was kept"

# ---- the word rule, one case each (bats#432): a snippet is kept when no loading word (staload,
# dynload, load, include) is a word of it and #use and #require are not in it. Each case is one
# fixture in a memo of its own, must check (status 0, its own accept line) and prints one line, `ok   word/<case>: <what> [<its accept line>]`, or
# `FAIL word/<case>: <what>: the snippet was kept` (or `not kept`); the section fails when one did not hold.
# It runs before the memo's own in-a-name case below, which stops the run when it fails.
wordfail=0
wordcase() { # <case> <kept|not> <what> <snippet>: the fixture alone; kept means it checks and is kept
  mfix "$TMP/word" accept "$1" src/lib.bats '(* end *)' "$4"
  # WORD_AT_EOF=1: the snippet ends with its last byte, mfix's newline taken away (the end of the file is the boundary)
  [ -z "${WORD_AT_EOF:-}" ] || printf '(* fixture-snippet *)\n%s' "$4" > "$TMP/word/accept/$1/snippet.bats"
  wm=$TMP/word-memo-$1; wl=$TMP/word-$1.log
  mrunx "$MP" "$TMP/word" "$MW" "$wm" "$wl" --only "accept/$1"
  kept=$(nfiles "$wm")
  if [ "$rc" = 0 ] && grep -aqE "^ok   accept/$1 \([0-9]+ s\)\$" "$wl"; then
    if { [ "$2" = kept ] && [ "$kept" = 2 ]; } || { [ "$2" = not ] && [ "$kept" = 0 ]; }; then
      echo "ok   word/$1: $3 [$(grep -aE "^ok   accept/$1 \([0-9]+ s\)\$" "$wl")]"
    else
      echo "FAIL word/$1: $3: the snippet was $([ "$kept" = 0 ] && echo 'not kept' || echo 'kept')"
      wordfail=1
    fi
  else
    echo "FAIL word/$1: $3: the snippet does not check (status $rc): $(grep -a '^FAIL' "$wl" | head -1)"
    wordfail=1
  fi
  WORD_AT_EOF=
}
wordcase download kept 'Download is no loading word (a longer name, bats#432)' 'fn Download (x: int): int = x'
wordcase included kept 'included is no loading word (include, then an identifier byte)' 'fn included (x: int): int = x'
wordcase loaded kept 'loaded is no loading word (load, then an identifier byte)' 'fn loaded (x: int): int = x'
wordcase apostrophe not "load' is a loading word (the apostrophe is not an identifier byte, so load is the word)" "fn load' (x: int): int = x"
wordcase comment not 'load in a comment is a loading word (a comment counts: the scan is conservative)' '(* load *)

fn g (x: int): int = x'
wordcase end-included kept 'a longer name on the last line (a newline follows it) is no loading word' 'fn g (): int = 1
// included'
WORD_AT_EOF=1 wordcase eof-included kept 'a longer name ending the file (no newline after it) is no loading word' 'fn g (): int = 1
// included'
WORD_AT_EOF=1 wordcase eof-load not 'load ending the file (no newline after it) is a loading word' 'fn g (): int = 1
// load'
wordcase staload not 'staload is a loading word' 'staload "helper.sats"

fn g (): int = help ()'
wordcase dynload not 'dynload is a loading word' 'dynload "helper.dats"

fn g (): int = 1'
wordcase hash-include not '#include is a loading word' '#include "share/atspre_staload.hats"

fn g (x: int): int = x'
wordcase load-word not 'load as a word is a loading word' 'fn load (x: int): int = x'
wordcase include-word not 'include as a word is a loading word' 'fn include (x: int): int = x'
wordcase last-line-load not 'load on the last line (a newline follows it) is a loading word' 'fn g (): int = 1
// load'
wordcase use not '#use is a loading word, anywhere in the snippet' '(* #use *)

fn g (x: int): int = x'
wordcase require not '#require is a loading word, anywhere in the snippet' '(* #require *)

fn g (x: int): int = x'
[ "$wordfail" = 0 ] || fail "word cases: one or more did not hold (the FAIL lines above)"

# ---- load and include inside a longer name load nothing (bats#432): the result is kept, and the
# second run serves it
MF4W=$TMP/mfix4w
mfix "$MF4W" accept in-a-name src/lib.bats '(* end *)' 'fn Download (x: int): int = x
fn unloaded_include_loader (x: int): int = Download (x)'
M4W=$TMP/memo4w
: > "$PLOG"; mrunx "$MP" "$MF4W" "$MW" "$M4W" "$TMP/w1.log"
[ $rc = 0 ] || { cat "$TMP/w1.log"; fail "memo word in a name: status $rc, not 0"; }
okline "$TMP/w1.log" accept/in-a-name "memo word in a name"
[ "$(nfiles "$M4W")" = 2 ] || fail "memo: a snippet with load or include inside a name was not kept"
: > "$PLOG"; mrunx "$MP" "$MF4W" "$MW" "$M4W" "$TMP/w2.log"
[ $rc = 0 ] || { cat "$TMP/w2.log"; fail "memo word in a name again: status $rc, not 0"; }
saidpart "$TMP/w2.log" "ok   accept/in-a-name (0 s) [memo]" "memo word in a name again"


# ---- a run killed while it checks leaves no file
M6=$TMP/memo6
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
[ "$(nfiles "$M6")" = 0 ] || fail "memo kill: a file was left: $(find "$M6" -type f)"
mrunx "$MP" "$MF" "$MW" "$M6" "$TMP/k2.log" --only accept/lone-ok
[ $rc = 0 ] || { cat "$TMP/k2.log"; fail "memo kill: the next run: status $rc"; }
memoed "$TMP/k2.log" 0 "memo kill next"

# ---- four copies side by side, five rounds: never a torn file served or left
for c in 1 2 3 4; do cp -R "$MP" "$TMP/par$c"; done
M7=$TMP/memo7
round=1
while [ $round -le 5 ]; do
  if [ $round -le 4 ]; then rm -rf "$M7"; fi
  pids=
  for c in 1 2 3 4; do
    extra=; if [ $round -eq 5 ] && [ $((c % 2)) = 0 ]; then extra=--cold; fi
    (cd "$TMP/par$c" && HOME=$H "$BATS" fixtures "$MF" --work "$TMP/parw$c" --memo "$M7" --only reject/lib-bad $extra > "$TMP/par$c.log" 2>&1; echo $? > "$TMP/par$c.rc") &
    pids="$pids $!"
  done
  wait $pids
  for c in 1 2 3 4; do
    [ "$(cat "$TMP/par$c.rc")" = 0 ] || { cat "$TMP/par$c.log"; fail "memo parallel: copy $c, round $round: status $(cat "$TMP/par$c.rc")"; }
    notsaid "$TMP/par$c.log" "FAIL" "memo parallel round $round copy $c"
  done
  [ "$(nfiles "$M7")" = 2 ] || fail "memo parallel: round $round: $(nfiles "$M7") files, not 2"
  round=$((round + 1))
done
mrunx "$TMP/par1" "$MF" "$TMP/parw1" "$M7" "$TMP/par-last.log" --only reject/lib-bad
memoed "$TMP/par-last.log" 1 "memo parallel last"
rm -rf "$TMP/par1" "$TMP/par2" "$TMP/par3" "$TMP/par4" "$TMP/parw1" "$TMP/parw2" "$TMP/parw3" "$TMP/parw4"

# ---- --prune: the files the run did not use, nothing else
M8=$TMP/memo8
cp -R "$M" "$M8"
MFP=$TMP/mfixp; cp -R "$MF" "$MFP"; rm -rf "$MFP/accept/other-ok"
H64=$(printf '1%.0s' $(seq 64)); O64=$(printf '2%.0s' $(seq 64)); U64=$(printf '4%.0s' $(seq 64))
# a linked directory whose target is marked as a memo's, a real one without the mark, a stray file, an orphan .key
mkdir -p "$TMP/outside"; printf bats-fixture-memo > "$TMP/outside/.memo-dir"; printf x > "$TMP/outside/$H64.key"
# (two-digit names no key of this memo starts with)
free=
for l in fe fd fc fb fa f9 f8 f7; do [ -e "$M8/$l" ] || free="$free $l"; done
set -- $free; LINKD=$1; BARED=$2
ln -s "$TMP/outside" "$M8/$LINKD"
mkdir -p "$M8/$BARED"; printf x > "$M8/$BARED/$U64.res"
printf keep > "$M8/note.txt"
sub=$(ls "$M8" | grep '^[0-9a-f][0-9a-f]$' | grep -v "^$LINKD\$" | grep -v "^$BARED\$" | head -1)
printf x > "$M8/$sub/$O64.key"
printf keep > "$M8/$sub/readme.txt"
n0=$(nfiles "$M8")
mrunx "$MP" "$MFP" "$MW" "$M8" "$TMP/p1.log" --prune
[ $rc = 0 ] || { cat "$TMP/p1.log"; fail "memo prune: status $rc"; }
said "$TMP/p1.log" "fixtures: 3 ok, 0 failed (3 from the memo)" "memo prune"
n=$(grep -ac '^pruned ' "$TMP/p1.log")
# (every file but the six of the three fixtures' entries and the unmarked directory's goes: the
# removed fixture's, the earlier keys of the memo's life, the orphan)
want=$((n0 - 7))
[ "$n" = "$want" ] || { cat "$TMP/p1.log"; fail "memo prune: listed $n removals, not $want"; }
saidpart "$TMP/p1.log" "memo: pruned $want files, kept 6" "memo prune"
[ "$(nfiles "$M8")" = 7 ] || fail "memo prune: $(nfiles "$M8") files left, not 7 (the six kept, and the unmarked directory's)"
[ -f "$TMP/outside/$H64.key" ] || fail "memo prune: removed through a link"
[ -f "$M8/$BARED/$U64.res" ] || fail "memo prune: removed from a directory without the memo's mark"
[ "$(cat "$M8/note.txt")" = keep ] || fail "memo prune: removed a file that is no entry"
[ ! -e "$M8/$sub/$O64.key" ] || fail "memo prune: the orphan stayed"
[ "$(cat "$M8/$sub/readme.txt")" = keep ] || fail "memo prune: removed a file of a subdirectory that is no entry"
# not a memo: nothing is touched; with --only: a usage error
NM=$TMP/not-a-memo; mkdir -p "$NM/ab"; printf x > "$NM/ab/$(printf '3%.0s' $(seq 64)).res"
mrunx "$MP" "$MFP" "$MW" "$NM" "$TMP/p2.log" --prune --only accept/lone-ok
[ $rc = 2 ] || fail "memo prune with --only: status $rc, not 2"
saidpart "$TMP/p2.log" "needs the whole set: not with --only" "memo prune --only"
MFQ=$TMP/mfixq; mfix "$MFQ" accept lone-ok src/unrelated.bats 'implement lone () = 4' 'fn g3 (x: int): int = x'
mrunx "$MP" "$MFQ" "$MW" "$NM" "$TMP/p3.log" --prune
saidpart "$TMP/p3.log" "memo: nothing pruned, $NM is not a fixtures memo" "memo prune not a memo"
[ "$(nfiles "$NM")" = 1 ] || fail "memo: wrote into a directory that is no memo, or removed its file"

# ---- a hit stands in for patsopt's answer, never for the validation: a cycle through another module's implement
# (bats-lang/bats#267: the lexer-level rules and the call cycles of every module are checked before the memo is asked)
MPC=$TMP/mproj-cycle; MFC=$TMP/mfix-cycle; MWC=$TMP/mwork-cycle; MC=$TMP/memo-cycle
mkdir -p "$MPC/src"
printf '[package]\nname = "fx"\nkind = "lib"\n' > "$MPC/bats.toml"
# ring.bats declares pong and implements it nowhere (a check runs no linker);
# back.bats calls pong from the body of lone, which the fixture's module reads only as an interface
printf '#include "share/atspre_staload.hats"\n' > "$MPC/src/lib.bats"
printf '#include "share/atspre_staload.hats"\n\n#pub fn pong (): int\n' > "$MPC/src/ring.bats"
printf '#include "share/atspre_staload.hats"\nstaload "ring.sats"\n\n#pub fn lone (): int\n\nimplement lone () = 4\n' > "$MPC/src/back.bats"
printf '#include "share/atspre_staload.hats"\nstaload "ring.sats"\nstaload "back.sats"\n\n(* end *)\n' > "$MPC/src/front.bats"
mfix "$MFC" accept pong-calls-lone src/front.bats '(* end *)' 'implement pong () = lone ()'
: > "$PLOG"; mrunx "$MPC" "$MFC" "$MWC" "$MC" "$TMP/c1.log"
[ $rc = 0 ] || { cat "$TMP/c1.log"; fail "memo cycle: first run: status $rc"; }
[ "$(nfiles "$MC")" = 2 ] || fail "memo cycle: the passing fixture was not kept"
mrunx "$MPC" "$MFC" "$MWC" "$MC" "$TMP/c2.log"
memoed "$TMP/c2.log" 1 "memo cycle second"
printf '#include "share/atspre_staload.hats"\nstaload "ring.sats"\n\n#pub fn lone (): int\n\nimplement lone () = pong ()\n' > "$MPC/src/back.bats"
mrunx "$MPC" "$MFC" "$MWC" "$MC" "$TMP/c3.log"
[ $rc = 1 ] || { cat "$TMP/c3.log"; fail "memo cycle: a cycle through another module's implement was served from the memo: status $rc"; }
memoed "$TMP/c3.log" 0 "memo cycle served"
saidpart "$TMP/c3.log" "FAIL accept/pong-calls-lone: should type-check" "memo cycle"
# the check memo of #298 sits inside `bats check`, after the validation: the same cycle, in a
# project whose modules are all warm, is refused by the check itself
printf '#include "share/atspre_staload.hats"\nstaload "ring.sats"\n\n#pub fn lone (): int\n\nimplement lone () = 4\n' > "$MPC/src/back.bats"
printf '#include "share/atspre_staload.hats"\nstaload "ring.sats"\nstaload "back.sats"\n\nimplement pong () = lone ()\n' > "$MPC/src/front.bats"
(cd "$MPC" && HOME=$H "$BATS" check > "$TMP/c4.log" 2>&1) || { cat "$TMP/c4.log"; fail "memo cycle: the acyclic project does not check"; }
printf '#include "share/atspre_staload.hats"\nstaload "ring.sats"\n\n#pub fn lone (): int\n\nimplement lone () = pong ()\n' > "$MPC/src/back.bats"
(cd "$MPC" && HOME=$H "$BATS" check > "$TMP/c6.log" 2>&1) && { cat "$TMP/c6.log"; fail "memo cycle: bats check passed a cycle through another module's implement"; }
rm -rf "$MPC" "$MWC" "$MC"

[ -z "${TIMES:-}" ] || cat "$TMP/times"
echo "ok"
