#!/bin/sh
# An implement that replaces what another package implements is rejected before
# patsopt runs (bats-lang/bats#421, .claude/rules/overrides.md). A dependent that
# wrote 'implement{} $A.word32_rotr_inline' for a template of arith, which arith
# implements itself, got its own body at its own call sites and passed
# bats check. This plays, each in a project of its own with its dependencies in
# bats_modules:
#  * rejected, with the function and the package named, and no build/ made (patsopt did not
#    run): arith's template (word32_rotr_inline) and array's (barr_get_inline) in one
#    project; an ordinary function (word32_rotr: it failed only at link before); a concrete
#    instance against the template the package implements itself; the same instance of a name
#    that the package implements only for that instance; a dependency that replaces the
#    implement of its own dependency (transitive); the replacement in an unsafe dependency and
#    in an unsafe package, and inside its $UNSAFE begin ... end block
#    (the lexer makes no spans of it); the replacement in a #target block that the build keeps;
#  * accepted, and checked by patsopt: a package that declares and implements the name a
#    dependency declares too (toml's and array's get); a template defined and used in one
#    package; two dependencies that do not use each other and declare the same name; an
#    instance of a name that the package leaves for its dependents (promise's dispose<bool>
#    where the package implements dispose<int> only); an implement and a #use that are in
#    #target blocks for different targets (no build loads both);
#  * the names of a file are recorded under build/.bats_valid (facts <path>): a check in
#    which nothing changed lexes no file for them, and a record that holds the key of other
#    bats inputs (another compiler's stamp), garbled or cut short is not trusted.
# The expected text of a rejection is tests/foreign-implement/expected/<case>.txt;
# BLESS=1 writes it from the run, to be read before it is committed.
# usage: tests/foreign-implement/check.sh <bats-binary> <repository-dir>
set -eu
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

reject() { # <case> <text each of the errors must hold>...
  c=$1; shift
  rc=0
  (cd "$TMP/$c" && "$BATS" check) > "$TMP/out" 2> "$TMP/err" || rc=$?
  # the notice of a busy machine slot (BATS_SLOTS) is not part of the error
  grep -av '^waiting for another bats' "$TMP/err" > "$TMP/err.only" || true
  mv "$TMP/err.only" "$TMP/err"
  [ "$rc" = 1 ] || { echo "FAIL: $c: status $rc (expected 1)"; cat "$TMP/err"; exit 1; }
  [ ! -d "$TMP/$c/build" ] || { echo "FAIL: $c: patsopt ran (build/ was made)"; exit 1; }
  for t in "$@"; do
    grep -aqF -- "$t" "$TMP/err" || { echo "FAIL: $c: the error lacks: $t"; cat "$TMP/err"; exit 1; }
  done
  if [ -n "${BLESS:-}" ]; then mkdir -p "$HERE/expected"; cp "$TMP/err" "$HERE/expected/$c.txt"; fi
  cmp -s "$TMP/err" "$HERE/expected/$c.txt" || { echo "FAIL: $c: the error differs from expected/$c.txt"; diff "$HERE/expected/$c.txt" "$TMP/err"; exit 1; }
}
accept() { # <case>
  (cd "$TMP/$1" && "$BATS" check) > "$TMP/out" 2> "$TMP/err" || { echo "FAIL: $1: the check failed"; cat "$TMP/out" "$TMP/err"; exit 1; }
  grep -aq 'check passed' "$TMP/err" || { echo "FAIL: $1: no 'check passed'"; cat "$TMP/err"; exit 1; }
}

# ---- rejected ----
project override bin
dependency override arith <<'X'
#pub fun{} word32_rotr_inline (x: int): int

implement{} word32_rotr_inline (x) = x + 1
X
dependency override array <<'X'
#pub fun{} barr_get_inline (x: int): int

implement{} barr_get_inline (x) = x + 1
X
main override <<'X'
#use arith as A
#use array as AR

implement{} $A.word32_rotr_inline (x) = x + 2

implement{} $AR.barr_get_inline (x) = x + 3

implement main0 () = println! ($A.word32_rotr_inline (1), " ", $AR.barr_get_inline (1))
X
reject override "'implement word32_rotr_inline' replaces what the package 'arith' implements" \
  "'implement barr_get_inline' replaces what the package 'array' implements"

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

project other_instance bin
dependency other_instance pr <<'X'
#pub fun{a:t@ype} dispose (v: a): void

implement dispose<int> (v) = ()
X
main other_instance <<'X'
#use pr as P

implement $P.dispose<bool> (v) = ()

implement main0 () = $P.dispose<bool> (true)
X
accept other_instance

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

# ---- the record of the names ----
lexed() { grep -ac '^  ~ facts lexed ' "$1" || true; }
cd "$TMP/own_template"
"$BATS" check > "$TMP/prime.log" 2>&1 || { echo "FAIL: the priming check"; cat "$TMP/prime.log"; exit 1; }   # a record never makes build/: the second check writes them
"$BATS" -v check > "$TMP/m1.log" 2>&1 || { echo "FAIL: the second check"; cat "$TMP/m1.log"; exit 1; }
[ "$(lexed "$TMP/m1.log")" = 0 ] || { echo "FAIL: a check in which nothing changed lexed $(lexed "$TMP/m1.log") files for their names"; cat "$TMP/m1.log"; exit 1; }
set -- build/.bats_valid/facts*
[ -f "$1" ] || { echo "FAIL: no record of names under build/.bats_valid"; ls -A build/.bats_valid; exit 1; }
rec=$1
tamper() { # <what> <command that rewrites $rec from a copy in $TMP/rec>
  cp "$rec" "$TMP/rec"
  "$@"
}
check_lexed() { # <what>: the next check lexes the file for its names, and records them again
  "$BATS" -v check > "$TMP/m.log" 2>&1 || { echo "FAIL: $1: the check failed"; cat "$TMP/m.log"; exit 1; }
  [ "$(lexed "$TMP/m.log")" = 1 ] || { echo "FAIL: $1: $(lexed "$TMP/m.log") files lexed (expected 1)"; cat "$TMP/m.log"; exit 1; }
  "$BATS" -v check > "$TMP/m.log" 2>&1
  [ "$(lexed "$TMP/m.log")" = 0 ] || { echo "FAIL: $1: the record was not written again"; cat "$TMP/m.log"; exit 1; }
}
cp "$rec" "$TMP/rec"
# the key of other bats inputs: what another compiler's stamp would have written
{ printf '%064d\n' 0; tail -n +2 "$TMP/rec"; } > "$rec"
check_lexed "a record under the key of other bats inputs"
{ printf 'garbled\n'; } > "$rec"
check_lexed "a garbled record"
: > "$rec"
check_lexed "an empty record"
head -c 100 "$TMP/rec" > "$rec"
check_lexed "a record cut short"
echo "foreign-implement: ok"
