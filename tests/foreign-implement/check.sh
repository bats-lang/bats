#!/bin/sh
# An implement that replaces what another package implements is rejected before
# patsopt runs (bats-lang/bats#421, .claude/rules/overrides.md). A dependent that
# wrote 'implement{} $A.word32_rotr_inline' for a template of arith, which arith
# implements itself, got its own body at its own call sites and passed
# bats check. This plays, each in a project of its own with its dependencies in
# bats_modules:
#  * rejected, with the function and the package named, and no build/ made (patsopt did not
#    run): arith's template (word32_rotr_inline) and array's (barr_get_inline), each in a
#    project of its own; an ordinary function (word32_rotr: it failed only at link before); a concrete
#    instance against the template the package implements itself; the same instance of a name
#    that the package implements only for that instance; a dependency that replaces the
#    implement of its own dependency (transitive); the replacement in an unsafe dependency and
#    in an unsafe package, and inside its $UNSAFE begin ... end block
#    (the lexer makes no spans of it); the replacement in a #target block that the build keeps; a name longer than a name can be;
#  * accepted, and checked by patsopt: a package that declares and implements the name a
#    dependency declares too (toml's and array's get); a template defined and used in one
#    package; two dependencies that do not use each other and declare the same name; an
#    instance of a name that the package leaves for its dependents (promise's dispose<bool>
#    where the package implements dispose<int> only); an implement and a #use that are in
#    #target blocks for different targets (no build loads both);
#  * the names of a file are recorded under build/.bats_valid (facts <path>): a check in
#    which nothing changed lexes no file for them, and a record that holds the key of other
#    bats inputs (another compiler's stamp), garbled, empty or cut short is not trusted.
# bats#565: an implement of another package's template is for a type of the implementing package (the
# orphan rule, overrides.md). In the first compiler version that has it the finding is a warning, and
# BATS_ORPHAN_ERROR=1 makes it an error; the cases whose names start with orphan_ play it: accepted for
# an own type; a warning for a foreign type, a base type, a type the dependency does not implement, a
# generic instance and no instance; the error (denied) for the same, for a typedef, and for the same
# instance in two modules of one package; and the same finding, word for word, whether the dependency
# implements the instance or leaves it out (orphan_dep_without, orphan_dep_with).
# The expected text of a rejection is tests/foreign-implement/expected/<case>.txt;
# BLESS=1 writes it from the run, to be read before it is committed.
# Why this is a shell script (quire#646, CLAUDE.md "we do not write shell scripts"): the claims are about
# the built compiler run on planted projects (the status, the error text, no build/ made, the records
# under build/.bats_valid), and a bats test for that would have to plant the projects, run the built
# `bats` in each, read its streams and remove its temp directories. Searched: `bats test` ($UNITTEST
# blocks run in-process and link only src/'s modules, never the built binary; the logic they could reach
# is the project API of src/overrides.bats, but not the command); the file package (file_mkdir,
# file_chdir, file_exists, file_mode, file_chmod and file_open/read/write exist; no unlink, rmdir,
# rename or mktemp, so a test's directories could not be removed); the process package (spawn
# and spawn_inherit_env; a child cannot be given a working directory, only the process-wide
# file_chdir); tests/capture-outcome (a bats driver built as a second binary of a copy of the compiler's
# project, which runs library code, not the compiler on a project). bats#284 (a test driver in bats for
# tests/*/check.sh) is the open ticket that builds what is missing; until it lands a command-level test
# follows the existing check.sh style (tests/fixtures/bless.sh names the same avenues).
# Every case is its own: a failed case prints one FAIL line with its reason and the run goes on, a
# passing case prints one ok line, and the run exits 1 at the end when a case failed. The third
# argument selects cases (names separated by commas); an unknown name is exit 2, so a misspelt name
# never passes by running nothing. VERBOSE=1 prints the details of a failed case.
# usage: tests/foreign-implement/check.sh <bats-binary> <repository-dir> [<case>,...]
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
. "$(dirname "$0")/../keep-on-fail.sh"
unset BATS_CACHE_DIR BATS_COLD
NO_COLOR=1
export NO_COLOR

# project <case> <package kind> [unsafe]: a project in $TMP/<case> with its bats.toml
project() {
  mkdir -p "$TMP/$1/src/bin"
  printf '[package]\nname = "%s"\nkind = "%s"\n' "$1" "$2" > "$TMP/$1/bats.toml"
  if [ "${3:-}" = unsafe ]; then printf 'unsafe = true\n' >> "$TMP/$1/bats.toml"; fi
}
# dependency <case> <package> [unsafe]; the source of src/lib.bats is on stdin
dependency() {
  mkdir -p "$TMP/$1/bats_modules/$2/src"
  printf '[package]\nname = "%s"\nkind = "lib"\n' "$2" > "$TMP/$1/bats_modules/$2/bats.toml"
  if [ "${3:-}" = unsafe ]; then printf 'unsafe = true\n' >> "$TMP/$1/bats_modules/$2/bats.toml"; fi
  printf '#include "share/atspre_staload.hats"\n\n' > "$TMP/$1/bats_modules/$2/src/lib.bats"
  cat >> "$TMP/$1/bats_modules/$2/src/lib.bats"
}
# main <case>: the source of src/bin/m.bats is on stdin
main() {
  printf '#include "share/atspre_staload.hats"\n\n' > "$TMP/$1/src/bin/m.bats"
  cat >> "$TMP/$1/src/bin/m.bats"
}

CASES="override_arith override_array ordinary concrete same_instance transitive unsafe_dependency unsafe_package unsafe_block native_block oversized own_beside own_template siblings disjoint_targets orphan_own orphan_foreign orphan_base orphan_unimplemented orphan_no_instance orphan_foreign_denied orphan_base_denied orphan_unimplemented_denied orphan_generic_denied orphan_no_instance_denied orphan_staload_denied orphan_typedef_denied orphan_twice_denied orphan_dep_without orphan_dep_with orphan_dep_with_default orphan_dep_same record_unchanged record_other_key record_garbled record_empty record_cut"
SELECT=${3:-}
if [ -n "$SELECT" ]; then
  for want_name in $(printf '%s' "$SELECT" | tr ',' ' '); do
    case " $CASES " in *" $want_name "*) ;; *) echo "foreign-implement: unknown case $want_name"; exit 2 ;; esac
  done
fi
FAILED=0
RAN=0
want() { # <case>: whether the case is selected
  [ -z "$SELECT" ] && return 0
  case ",$SELECT," in *",$1,"*) return 0 ;; esac
  return 1
}
fail_case() { # <case> <reason>: the details are in $TMP/detail
  FAILED=$((FAILED + 1))
  echo "FAIL $1: $2"
  if [ -n "${VERBOSE:-}" ]; then cat "$TMP/detail"; fi
}
pass_case() { echo "ok $1"; }

reject() { # <case> <text each of the errors must hold>...
  c=$1; shift
  want "$c" || return 0
  RAN=$((RAN + 1))
  rc=0
  (cd "$TMP/$c" && env $ORPHAN "$BATS" check) > "$TMP/out" 2> "$TMP/err" || rc=$?
  # the notice of a busy machine slot (BATS_SLOTS) is not what the error says
  grep -av '^waiting for another bats' "$TMP/err" > "$TMP/err.only" || true
  mv "$TMP/err.only" "$TMP/err"
  cp "$TMP/err" "$TMP/detail"
  if [ "$rc" != 1 ]; then fail_case "$c" "status $rc (expected 1)"; return 0; fi
  if [ -d "$TMP/$c/build" ]; then fail_case "$c" "patsopt ran (build/ was made)"; return 0; fi
  for t in "$@"; do
    if ! grep -aqF -- "$t" "$TMP/err"; then fail_case "$c" "the error lacks: $t"; return 0; fi
  done
  if [ -n "${BLESS:-}" ]; then mkdir -p "$HERE/expected"; cp "$TMP/err" "$HERE/expected/$c.txt"; fi
  if ! cmp -s "$HERE/expected/$c.txt" "$TMP/err"; then
    diff "$HERE/expected/$c.txt" "$TMP/err" > "$TMP/detail" 2>&1
    fail_case "$c" "the error differs from expected/$c.txt"; return 0
  fi
  pass_case "$c"
}
accept() { # <case>
  want "$1" || return 0
  RAN=$((RAN + 1))
  rc=0
  (cd "$TMP/$1" && env $ORPHAN "$BATS" check) > "$TMP/out" 2> "$TMP/err" || rc=$?
  cat "$TMP/out" "$TMP/err" > "$TMP/detail"
  if [ "$rc" != 0 ]; then fail_case "$1" "the check failed (status $rc)"; return 0; fi
  if ! grep -aq 'check passed' "$TMP/err"; then fail_case "$1" "no check passed line"; return 0; fi
  if grep -aq '^warning:' "$TMP/err"; then fail_case "$1" "a warning was printed"; return 0; fi
  pass_case "$1"
}
# warns <case> <text>...: the check passes, and what it printed besides the pass line is expected/<case>.txt
warns() {
  c=$1; shift
  want "$c" || return 0
  RAN=$((RAN + 1))
  rc=0
  (cd "$TMP/$c" && env $ORPHAN "$BATS" check) > "$TMP/out" 2> "$TMP/err" || rc=$?
  grep -av '^waiting for another bats' "$TMP/err" | grep -av '^built ' > "$TMP/err.only" || true
  mv "$TMP/err.only" "$TMP/err"
  cat "$TMP/out" "$TMP/err" > "$TMP/detail"
  if [ "$rc" != 0 ]; then fail_case "$c" "the check failed (status $rc)"; return 0; fi
  if ! grep -aq 'check passed' "$TMP/err"; then fail_case "$c" "no check passed line"; return 0; fi
  for t in "$@"; do
    if ! grep -aqF -- "$t" "$TMP/err"; then fail_case "$c" "the output lacks: $t"; return 0; fi
  done
  grep -aq '^warning:' "$TMP/err" || { fail_case "$c" "no warning was printed"; return 0; }
  grep -av 'check passed' "$TMP/err" > "$TMP/err.warn"
  cp "$TMP/err.warn" "$TMP/err"
  if [ -n "${BLESS:-}" ]; then mkdir -p "$HERE/expected"; cp "$TMP/err" "$HERE/expected/$c.txt"; fi
  if ! cmp -s "$HERE/expected/$c.txt" "$TMP/err"; then
    diff "$HERE/expected/$c.txt" "$TMP/err" > "$TMP/detail" 2>&1
    fail_case "$c" "the output differs from expected/$c.txt"; return 0
  fi
  pass_case "$c"
}
ORPHAN="BATS_ORPHAN_ERROR=0"
denied() { ORPHAN="BATS_ORPHAN_ERROR=1"; }
default_env() { ORPHAN="BATS_ORPHAN_ERROR=0"; }

# ---- rejected ----
project override_arith bin
dependency override_arith arith <<'X'
#pub fun{} word32_rotr_inline (x: int): int

implement{} word32_rotr_inline (x) = x + 1
X
main override_arith <<'X'
#use arith as A

implement{} $A.word32_rotr_inline (x) = x + 2

implement main0 () = println! ($A.word32_rotr_inline (1))
X
reject override_arith "'implement word32_rotr_inline' replaces what the package 'arith' implements"

project override_array bin
dependency override_array array <<'X'
#pub fun{} barr_get_inline (x: int): int

implement{} barr_get_inline (x) = x + 1
X
main override_array <<'X'
#use array as AR

implement{} $AR.barr_get_inline (x) = x + 3

implement main0 () = println! ($AR.barr_get_inline (1))
X
reject override_array "'implement barr_get_inline' replaces what the package 'array' implements"

project ordinary bin
dependency ordinary arith <<'X'
#pub fun word32_rotr (x: int): int

implement word32_rotr (x) = x
X
main ordinary <<'X'
#use arith as A

implement $A.word32_rotr (x) = x + 2

implement main0 () = println! ($A.word32_rotr (1))
X
reject ordinary "'implement word32_rotr' replaces what the package 'arith' implements"

project concrete bin
dependency concrete box <<'X'
#pub fun{a:t@ype} put (v: a): int

implement{a} put (v) = 1
X
main concrete <<'X'
#use box as B

implement $B.put<int> (v) = 2

implement main0 () = println! ($B.put<int> (0))
X
reject concrete "'implement put' replaces what the package 'box' implements"

project same_instance bin
dependency same_instance box <<'X'
#pub fun{a:t@ype} put (v: a): int

implement put<int> (v) = 1
X
main same_instance <<'X'
#use box as B

implement $B.put< int > (v) = 2

implement main0 () = println! ($B.put<int> (0))
X
reject same_instance "'implement put' replaces what the package 'box' implements"

project transitive bin
dependency transitive arith <<'X'
#pub fun{} rotr (x: int): int

implement{} rotr (x) = x + 1
X
dependency transitive mid <<'X'
#use arith as A

#pub fun mid_rotr (x: int): int

implement{} $A.rotr (x) = x + 2

implement mid_rotr (x) = $A.rotr (x)
X
main transitive <<'X'
#use mid as M

implement main0 () = println! ($M.mid_rotr (1))
X
reject transitive "'implement rotr' replaces what the package 'arith' implements" "--> lib.bats:7:1"

project unsafe_dependency bin
dependency unsafe_dependency arith <<'X'
#pub fun{} rotr (x: int): int

implement{} rotr (x) = x + 1
X
dependency unsafe_dependency shim unsafe <<'X'
#use arith as A

#pub fun shim_rotr (x: int): int

implement{} $A.rotr (x) = x + 2

implement shim_rotr (x) = $A.rotr (x)
X
main unsafe_dependency <<'X'
#use shim as S

implement main0 () = println! ($S.shim_rotr (1))
X
reject unsafe_dependency "'implement rotr' replaces what the package 'arith' implements" "--> lib.bats:7:1"

project unsafe_package bin unsafe
dependency unsafe_package arith <<'X'
#pub fun{} rotr (x: int): int

implement{} rotr (x) = x + 1
X
main unsafe_package <<'X'
#use arith as A

implement{} $A.rotr (x) = x + 2

implement main0 () = println! ($A.rotr (1))
X
reject unsafe_package "'implement rotr' replaces what the package 'arith' implements"

project unsafe_block bin unsafe
dependency unsafe_block arith <<'X'
#pub fun{} rotr (x: int): int

implement{} rotr (x) = x + 1
X
main unsafe_block <<'X'
#use arith as A

$UNSAFE begin

implement{} $A.rotr (x) = x + 2

end

implement main0 () = println! ($A.rotr (1))
X
reject unsafe_block "'implement rotr' replaces what the package 'arith' implements"

project native_block bin
dependency native_block arith <<'X'
#pub fun{} rotr (x: int): int

implement{} rotr (x) = x + 1
X
main native_block <<'X'
#target native begin
#use arith as A

implement{} $A.rotr (x) = x + 2
end

implement main0 () = ()
X
reject native_block "'implement rotr' replaces what the package 'arith' implements"

project oversized bin
main oversized <<'X'
implement main0 () = ()
X
{ printf 'implement{} '; head -c 1100000 /dev/zero | tr '\000' a; printf ' (x) = x\n'; } >> "$TMP/oversized/src/bin/m.bats"
reject oversized "a name in this file is too long to compare"

# ---- accepted ----
project own_beside bin
dependency own_beside lib1 <<'X'
#pub fun get (): int

implement get () = 1
X
main own_beside <<'X'
#use lib1 as L

#pub fun get (): int

implement get () = 2

implement main0 () = println! (get (), " ", $L.get ())
X
accept own_beside

project own_template bin
main own_template <<'X'
#pub fun{} twice (x: int): int

implement{} twice (x) = x + x

implement main0 () = println! (twice (2))
X
accept own_template

project siblings bin
dependency siblings sa <<'X'
#pub fun{} sget (): int

implement{} sget () = 1
X
dependency siblings sb <<'X'
#pub fun{} sget (): int

implement{} sget () = 2
X
main siblings <<'X'
#use sa as SA
#use sb as SB

implement main0 () = println! ($SA.sget (), " ", $SB.sget ())
X
accept siblings

project disjoint_targets bin
dependency disjoint_targets arith <<'X'
#pub fun{} rotr (x: int): int

implement{} rotr (x) = x + 1
X
main disjoint_targets <<'X'
#target native begin
#use arith as A
end

#target wasm begin
implement{} $A.rotr (x) = x + 2
end

implement main0 () = ()
X
accept disjoint_targets

# ---- the orphan rule (bats#565) ----
# a template nobody implements, a template implemented for int only, a package with an abstract type
orphan_deps() { # <case>
  dependency "$1" pr <<'X'
#pub fun{a:t@ype} dispose (v: a): void
#pub fun{} hook (): void
X
  dependency "$1" ty <<'X'
#pub abstype stored
X
}
project orphan_own bin
orphan_deps orphan_own
main orphan_own <<'X'
#use pr as P

datatype mine = MineA | MineB

implement $P.dispose<mine> (_) = ()

implement main0 () = $P.dispose<mine> (MineA)
X
accept orphan_own

orphan_foreign_main() { # <case>
  main "$1" <<'X'
#use pr as P
#use ty as T

implement $P.dispose<$T.stored> (_) = ()

implement main0 () = ()
X
}
orphan_base_main() {
  main "$1" <<'X'
#use pr as P

implement $P.dispose<int> (_) = ()

implement main0 () = ()
X
}
orphan_unimplemented_main() {
  main "$1" <<'X'
#use pr as P

implement $P.dispose<bool> (_) = ()

implement main0 () = ()
X
}
orphan_generic_main() {
  main "$1" <<'X'
#use pr as P

implement{a} $P.dispose<a> (_) = ()

implement main0 () = ()
X
}
orphan_no_instance_main() {
  main "$1" <<'X'
#use pr as P

implement{} $P.hook () = ()

implement main0 () = ()
X
}
for kind in foreign base unimplemented generic no_instance; do
  for mode in warn denied; do
    if [ "$mode" = warn ]; then c=orphan_$kind; else c=orphan_${kind}_denied; fi
    project $c bin
    orphan_deps $c
    if [ "$kind" = unimplemented ]; then
      dependency $c pr <<'X'
#pub fun{a:t@ype} dispose (v: a): void
#pub fun{} hook (): void

implement dispose<int> (v) = ()
X
    fi
    orphan_${kind}_main $c
  done
done
default_env
warns orphan_foreign "warning: 'implement dispose<\$T.stored>' of the template dispose of the package 'pr'"
warns orphan_base "names the type 'int'"
warns orphan_unimplemented "names the type 'bool'"
warns orphan_no_instance "gives no type"
denied
reject orphan_foreign_denied "error: 'implement dispose<\$T.stored>' of the template dispose of the package 'pr'" "a type of the package 'ty'"
reject orphan_base_denied "names the type 'int'"
reject orphan_unimplemented_denied "names the type 'bool'"
reject orphan_generic_denied "names the type 'a'"
reject orphan_no_instance_denied "gives no type"
default_env

project orphan_staload_denied bin
orphan_deps orphan_staload_denied
main orphan_staload_denied <<'X'
#use pr as P
staload T = "ty/src/lib.sats"

implement $P.dispose<$T.stored> (_) = ()

implement main0 () = ()
X
denied
reject orphan_staload_denied "a type of the package 'ty'"
default_env

project orphan_typedef_denied bin
orphan_deps orphan_typedef_denied
main orphan_typedef_denied <<'X'
#use pr as P

typedef alias = int

implement $P.dispose<alias> (_) = ()

implement main0 () = ()
X
denied
reject orphan_typedef_denied "names the type 'alias'"
default_env

project orphan_twice_denied bin
orphan_deps orphan_twice_denied
mkdir -p "$TMP/orphan_twice_denied/src"
printf '#include "share/atspre_staload.hats"\n#use pr as P\n\n#pub datatype mine = MineA\n\nimplement $P.dispose<mine> (_) = ()\n' > "$TMP/orphan_twice_denied/src/other.bats"
main orphan_twice_denied <<'X'
#use pr as P

implement $P.dispose<mine> (_) = ()

implement main0 () = ()
X
denied
reject orphan_twice_denied "is implemented more than once by this package"
default_env

# the dependency implements the instance or leaves it out: the same orphan finding either way
for c in orphan_dep_without orphan_dep_with orphan_dep_with_default; do
  project $c bin
  if [ "$c" = orphan_dep_without ]; then
    dependency $c pr <<'X'
#pub fun{a:t@ype} dispose (v: a): void
X
  else
    dependency $c pr <<'X'
#pub fun{a:t@ype} dispose (v: a): void

implement dispose<bool> (v) = ()
X
  fi
  orphan_unimplemented_main $c
done
denied
reject orphan_dep_without "names the type 'bool'"
reject orphan_dep_with "names the type 'bool'"
default_env
reject orphan_dep_with_default "warning: 'implement dispose<bool>' of the template dispose of the package 'pr'" "error: 'implement dispose' replaces what the package 'pr' implements"
if want orphan_dep_same; then
  RAN=$((RAN + 1))
  if cmp -s "$HERE/expected/orphan_dep_without.txt" "$HERE/expected/orphan_dep_with.txt"; then pass_case orphan_dep_same
  else diff "$HERE/expected/orphan_dep_without.txt" "$HERE/expected/orphan_dep_with.txt" > "$TMP/detail" 2>&1; fail_case orphan_dep_same "the finding differs with what the dependency implements"; fi
fi

# ---- the record of the names ----
lexed() { grep -ac '^  ~ facts lexed ' "$1" || true; }
# record_case <case> <what>: a project of its own, checked twice so that the record exists (a record is
# never the first check's), then the step of the case
record_case() {
  c=$1; what=$2
  want "$c" || return 0
  RAN=$((RAN + 1))
  project "$c" bin
  main "$c" <<'X'
#pub fun{} twice (x: int): int

implement{} twice (x) = x + x

implement main0 () = println! (twice (2))
X
  cd "$TMP/$c" || return 1
  : > "$TMP/detail"
  if ! "$BATS" check > "$TMP/detail" 2>&1 || ! "$BATS" check >> "$TMP/detail" 2>&1; then fail_case "$c" "a priming check failed"; return 0; fi
  if [ "$what" = unchanged ]; then
    "$BATS" -v check > "$TMP/m.log" 2>&1
    cp "$TMP/m.log" "$TMP/detail"
    n=$(lexed "$TMP/m.log")
    if [ "$n" != 0 ]; then fail_case "$c" "lexed $n files for their names in a check in which nothing changed"; return 0; fi
    pass_case "$c"; return 0
  fi
  set -- build/.bats_valid/facts*
  if [ ! -f "$1" ]; then ls -A build/.bats_valid > "$TMP/detail" 2>&1; fail_case "$c" "no record under build/.bats_valid after the priming checks"; return 0; fi
  rec=$1
  cp "$rec" "$TMP/rec"
  case "$what" in
    # the key of other bats inputs: what another compiler's stamp would have written
    other_key) { printf '%064d\n' 0; tail -n +2 "$TMP/rec"; } > "$rec" ;;
    garbled) printf 'garbled\n' > "$rec" ;;
    empty) : > "$rec" ;;
    cut) head -c 100 "$TMP/rec" > "$rec" ;;
  esac
  # the next check lexes the file for its names and records them again
  "$BATS" -v check > "$TMP/m.log" 2>&1
  cp "$TMP/m.log" "$TMP/detail"
  n=$(lexed "$TMP/m.log")
  if [ "$n" != 1 ]; then fail_case "$c" "$n files lexed (expected 1)"; return 0; fi
  "$BATS" -v check > "$TMP/m.log" 2>&1
  cp "$TMP/m.log" "$TMP/detail"
  n=$(lexed "$TMP/m.log")
  if [ "$n" != 0 ]; then fail_case "$c" "the record was not written again ($n files lexed)"; return 0; fi
  pass_case "$c"
}
record_case record_unchanged unchanged
record_case record_other_key other_key
record_case record_garbled garbled
record_case record_empty empty
record_case record_cut cut

if [ "$FAILED" != 0 ]; then
  echo "foreign-implement: $FAILED of $RAN cases failed"
  exit 1
fi
echo "foreign-implement: ok ($RAN cases)"
