#!/bin/bash
# bats affected <base> <head> (bats-lang/bats#481): a change whose paths are all
# *.md files outside tests/ and bootstrap/ is inert, so check.yml runs only the cheap
# jobs; every other change (src, bootstrap/c, tests, the workflow, a mix, an empty or
# unreadable one) is not inert and runs everything. One fixture per kind of change.
# Detail: .claude/rules/affected.md.
# usage: tests/affected/check.sh <bats-binary> <repository-dir>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
. "$(dirname "$0")/../keep-on-fail.sh"
fail() { echo "FAIL: $*" >&2; cat "$TMP/out" "$TMP/err" >&2; exit 1; }

git_in() { git -C "$TMP/repo" -c user.name=t -c user.email=t@example.com "$@"; }

# the repository every fixture starts from: one file of each place the rule names
start() {
  rm -rf "$TMP/repo"
  mkdir -p "$TMP/repo"
  git -C "$TMP/repo" init -q
  mkdir -p "$TMP/repo"/{src,bootstrap/c/src,tests/docs/expected,.claude/rules,.github/workflows}
  for f in src/helpers.bats bootstrap/c/src/helpers_dats.c tests/docs/check.sh \
    tests/docs/expected/index.md .claude/rules/stamp.md README.md CLAUDE.md \
    .github/workflows/check.yml; do
    echo "start" > "$TMP/repo/$f"
  done
  git_in add -A
  git_in commit -q -m start
  base=$(git_in rev-parse HEAD)
}
# <name> <inert|not-inert> <shell commands run in the repository>
fixture() {
  start
  (cd "$TMP/repo" && eval "$3")
  git_in add -A
  git_in commit -q -m change --allow-empty
  head=$(git_in rev-parse HEAD)
  (cd "$TMP/repo" && "$BATS" affected "$base" "$head") > "$TMP/out" 2> "$TMP/err" || fail "$1: the command failed"
  if [ "$2" = inert ]; then want='inert=true'; else want='inert=false'; fi
  [ "$(cat "$TMP/out")" = "$want" ] || fail "$1: wanted $want"
  echo "ok   $1 ($want)"
}

fixture rules-only inert 'echo more >> .claude/rules/stamp.md'
fixture rules-new-file inert 'echo new > .claude/rules/new-area.md'
fixture readme-and-claude inert 'echo more >> README.md; echo more >> CLAUDE.md'
fixture rules-file-deleted inert 'git rm -q .claude/rules/stamp.md'
fixture src-change not-inert 'echo more >> src/helpers.bats'
fixture bootstrap-change not-inert 'echo more >> bootstrap/c/src/helpers_dats.c'
fixture tests-change not-inert 'echo more >> tests/docs/check.sh'
fixture tests-markdown-change not-inert 'echo more >> tests/docs/expected/index.md'
fixture bootstrap-markdown-change not-inert 'echo note > bootstrap/c/NOTES.md'
fixture workflow-change not-inert 'echo more >> .github/workflows/check.yml'
fixture mixed-change not-inert 'echo more >> .claude/rules/stamp.md; echo more >> src/helpers.bats'
fixture mixed-with-tests not-inert 'echo more >> README.md; echo more >> tests/docs/check.sh'
fixture source-renamed-to-markdown not-inert 'git mv src/helpers.bats src/helpers.md'
fixture markdown-renamed-out-of-rules not-inert 'git mv .claude/rules/stamp.md src/stamp.bats'
fixture file-without-markdown-suffix not-inert 'echo more >> .claude/rules/stamp.md.txt'
fixture markdown-name-in-directory not-inert 'mkdir -p src/x.md && echo more > src/x.md/code.bats'
fixture empty-change not-inert 'true'

# a revision git cannot find is not inert, and not an error of the command
start
(cd "$TMP/repo" && "$BATS" affected 0000000000000000000000000000000000000001 HEAD) > "$TMP/out" 2> "$TMP/err" || fail "unknown revision: the command failed"
[ "$(cat "$TMP/out")" = inert=false ] || fail "unknown revision was inert"
echo "ok   unknown-revision (inert=false)"

# outside a repository nothing can be listed
(cd "$TMP" && "$BATS" affected HEAD~1 HEAD) > "$TMP/out" 2> "$TMP/err" || fail "outside a repository: the command failed"
[ "$(cat "$TMP/out")" = inert=false ] || fail "outside a repository was inert"
echo "ok   outside-repository (inert=false)"

# the arguments: exactly two revisions, none an option
usage() { # <name> <arguments...>
  name=$1; shift
  (cd "$TMP/repo" && "$BATS" affected "$@") > "$TMP/out" 2> "$TMP/err"
  status=$?
  [ "$status" -eq 2 ] || fail "$name: status $status, wanted 2"
  [ ! -s "$TMP/out" ] || fail "$name: printed a verdict"
  grep -q '^usage: bats affected' "$TMP/err" || fail "$name: no usage"
  echo "ok   $name (usage, status 2)"
}
usage no-arguments
usage one-argument HEAD
usage three-arguments HEAD HEAD HEAD
usage option-as-base --output=x HEAD
usage option-as-head HEAD --output=x
usage empty-base "" HEAD
usage empty-head HEAD ""
echo "affected: all passed"
