#!/bin/sh
# `bats check` of a project whose bats.toml says seed = true compiles the C of each of its modules
# against the runtime header `bats build --to-c` writes, alone, as the seed in bootstrap/c is built
# (bats-lang/bats#624, keyword: runtime-header). bats#623 passed `bats check` and `bats build` with a
# prelude name the header does not declare (fileref_flush, atspre_exit) and broke the build of the seed.
#  * a module that uses only names the header declares is accepted;
#  * a module that uses a name it lacks is refused, naming the C file, the line and the name;
#  * the same module in a project that does not say seed = true is accepted: its C is built
#    with ATS2's own headers, which declare every prelude name;
#  * seed = false is the same as no key.
# usage: tests/seed-header/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$2
. "$(dirname "$0")/../keep-on-fail.sh"
fail() { echo "FAIL: $1"; exit 1; }
unset BATS_REPOSITORY BATS_SLOTS BATS_LOCK_DIR BATS_SLOT_HELD BATS_CACHE_DIR BATS_COMMIT

# project <name> <seed line, or empty> <source line>: a binary project in $TMP/<name>
project() {
  mkdir -p "$TMP/$1/src/bin"
  printf '[package]\nname = "seedheader"\nkind = "bin"\n%s\n' "$2" > "$TMP/$1/bats.toml"
  printf '%s\n' "$3" > "$TMP/$1/src/bin/seedheader.bats"
}
declared='implement main0 () = println! ("hello")'
undeclared='implement main0 () = fileref_flush (stdout_ref)'

# checked <name>: bats check of the project, its output in $TMP/<name>.log; the exit status
checked() {
  status=0
  (cd "$TMP/$1" && "$BATS" check --repository "$REPO" > "$TMP/$1.log" 2>&1) || status=$?
  return $status
}

project declared-seed 'seed = true' "$declared"
checked declared-seed || { tail -20 "$TMP/declared-seed.log"; fail "a module using only declared names was refused"; }
echo "ok   declared names are accepted"

project undeclared-seed 'seed = true' "$undeclared"
if checked undeclared-seed; then fail "a module using fileref_flush was accepted"; fi
grep -q 'seedheader_dats.c:[0-9][0-9]*' "$TMP/undeclared-seed.log" \
  || { cat "$TMP/undeclared-seed.log"; fail "the refusal does not name the C file and its line"; }
grep -q 'atspre_[A-Za-z_]*' "$TMP/undeclared-seed.log" \
  || { cat "$TMP/undeclared-seed.log"; fail "the refusal does not name the undeclared atspre_ name"; }
grep -q 'bootstrap/c' "$TMP/undeclared-seed.log" \
  || { cat "$TMP/undeclared-seed.log"; fail "the refusal does not say it is about the seed"; }
echo "ok   an undeclared name is refused with its file, line and name"

# the refusal is repeated: a failed module leaves no C to be taken for checked
if checked undeclared-seed; then fail "the second check of the module using fileref_flush was accepted"; fi
echo "ok   the refusal is repeated"

project undeclared-plain '' "$undeclared"
checked undeclared-plain || { tail -20 "$TMP/undeclared-plain.log"; fail "a project without seed = true was refused"; }
echo "ok   without seed = true the module is accepted"

project undeclared-false 'seed = false' "$undeclared"
checked undeclared-false || { tail -20 "$TMP/undeclared-false.log"; fail "seed = false was refused"; }
echo "ok   seed = false is the same"

echo "seed-header: ok"
