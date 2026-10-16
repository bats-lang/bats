#!/bin/sh
# bats record-commit <commit> (bats-lang/bats#283): BATS_COMMIT=<commit> on
# stdout when the commit is in the repository of the working directory,
# else an error that says to check out with fetch-depth: 2.
#  * a commit of the checkout, the merge's second parent included
#  * a commit that is not there, a branch, a short sha, none: refused, stdout empty
# usage: tests/record-commit/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
ok() { echo "ok   $1"; }
unset BATS_COMMIT BATS_SLOTS BATS_LOCK_DIR BATS_SLOT_HELD
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q "$TMP/w"; cd "$TMP/w"
echo a > f; git add f; git commit -q -m a
head=$(git rev-parse HEAD)
git checkout -q -b side; echo b > g; git add g; git commit -q -m b; side=$(git rev-parse HEAD)
git checkout -q -; git merge -q --no-ff -m merge side
merge=$(git rev-parse HEAD)
[ "$(git rev-parse 'HEAD^2')" = "$side" ]
"$BATS" record-commit "$merge" > "$TMP/out" 2> "$TMP/err" || { cat "$TMP/err"; fail "HEAD was refused"; }
[ "$(cat "$TMP/out")" = "BATS_COMMIT=$merge" ] || fail "stdout is '$(cat "$TMP/out")'"
"$BATS" record-commit "$side" > "$TMP/out" 2> "$TMP/err" || fail "the second parent was refused"
[ "$(cat "$TMP/out")" = "BATS_COMMIT=$side" ] || fail "stdout for the second parent"
ok "a commit of the checkout"
for bad in 0000000000000000000000000000000000000001 main "$(echo "$head" | cut -c1-7)" ""; do
  if "$BATS" record-commit "$bad" > "$TMP/out" 2> "$TMP/err"; then fail "'$bad' was accepted"; fi
  [ ! -s "$TMP/out" ] || fail "'$bad' printed"
done
"$BATS" record-commit 0000000000000000000000000000000000000001 2>&1 >/dev/null | grep -q "fetch-depth: 2" || fail "the missing commit does not say what to do"
ok "a commit that is not there, a branch, a short sha and none are refused"
"$BATS" record-commit "$merge" extra > "$TMP/out" 2> "$TMP/err" && fail "an extra argument was accepted"
[ ! -s "$TMP/out" ] || fail "an extra argument printed"
"$BATS" abcdefghijklm "$merge" 2>&1 | grep -q "BATS_COMMIT" && fail "a command of the same length ran record-commit"
ok "an extra argument is refused, and the command word must match"
echo "all passed"
