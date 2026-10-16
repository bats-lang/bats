#!/bin/sh
# bats clone-repository <commit> --repository <dir> (bats-lang/bats#283):
# the package repository at a full commit, with BATS_REPOSITORY=<dir> on
# stdout and the rest on stderr. The remote is a local bare repository:
# git's url.<base>.insteadOf (in the environment) sends the repository's
# URL to it, so bats has no test override.
#  * a fresh clone is at the commit, and stdout is the one line
#  * a second run says it is there already and fetches nothing
#  * another commit moves the clone to it
#  * a branch, a tag, a short or upper case sha, and no commit are refused
#  * a commit the remote lacks fails and leaves nothing
#  * a directory that is not empty and not a clone is not replaced
#  * no directory is an error; BATS_REPOSITORY names it as --repository does
# usage: tests/clone-repository/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
ok() { echo "ok   $1"; }
unset BATS_REPOSITORY BATS_SLOTS BATS_LOCK_DIR BATS_SLOT_HELD
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q "$TMP/work"
echo one > "$TMP/work/f"; git -C "$TMP/work" add f; git -C "$TMP/work" commit -q -m one
first=$(git -C "$TMP/work" rev-parse HEAD)
echo two > "$TMP/work/f"; git -C "$TMP/work" commit -q -a -m two
second=$(git -C "$TMP/work" rev-parse HEAD)
git -C "$TMP/work" tag v1 "$first"
git clone -q --bare "$TMP/work" "$TMP/remote.git"
git -C "$TMP/remote.git" config uploadpack.allowAnySHA1InWant true
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="url.file://$TMP/remote.git.insteadOf"
export GIT_CONFIG_VALUE_0="https://github.com/bats-lang/repository-prototype.git"
D=$TMP/clone

"$BATS" clone-repository "$first" --repository "$D" > "$TMP/out" 2> "$TMP/err" || { cat "$TMP/err"; fail "the clone failed"; }
[ "$(git -C "$D" rev-parse HEAD)" = "$first" ] || fail "not at the commit"
[ "$(cat "$TMP/out")" = "BATS_REPOSITORY=$D" ] || fail "stdout is '$(cat "$TMP/out")'"
ok "a fresh clone"

"$BATS" clone-repository "$first" --repository "$D" > "$TMP/out" 2> "$TMP/err" || fail "the second run failed"
grep -q "at the commit already" "$TMP/err" || fail "the second run does not say so"
[ "$(cat "$TMP/out")" = "BATS_REPOSITORY=$D" ] || fail "stdout of the second run"
ok "the second run does nothing"

"$BATS" clone-repository "$second" --repository "$D" > /dev/null 2>&1 || fail "another commit failed"
[ "$(git -C "$D" rev-parse HEAD)" = "$second" ] && [ "$(cat "$D/f")" = two ] || fail "not moved"
ok "another commit moves the clone"

for bad in main v1 "${first%??????????????????????????????}" "$(echo "$first" | tr a-f A-F)" ""; do
  rm -rf "$TMP/refused"
  if "$BATS" clone-repository "$bad" --repository "$TMP/refused" > "$TMP/out" 2> "$TMP/err"; then fail "'$bad' was accepted"; fi
  [ ! -s "$TMP/out" ] && [ ! -e "$TMP/refused" ] || fail "'$bad' left something"
done
"$BATS" clone-repository main --repository "$TMP/refused" 2>&1 >/dev/null | grep -q "full commit" || fail "a refused commit does not say what a commit is"
ok "a branch, a tag, a short or upper case sha and no commit are refused"

rm -rf "$TMP/absent"
"$BATS" clone-repository 0000000000000000000000000000000000000001 --repository "$TMP/absent" > "$TMP/out" 2> "$TMP/err" && fail "a commit the remote lacks was accepted"
[ ! -s "$TMP/out" ] || fail "a failed clone printed on stdout"
[ -s "$TMP/err" ] || fail "a failed clone says nothing"
ok "a commit the remote lacks fails"

mkdir -p "$TMP/mine"; echo precious > "$TMP/mine/keep"
"$BATS" clone-repository "$first" --repository "$TMP/mine" > "$TMP/out" 2> "$TMP/err" && fail "a directory with files was replaced"
[ "$(cat "$TMP/mine/keep")" = precious ] || fail "the directory was touched"
grep -q "not replaced" "$TMP/err" || fail "not said"
ok "a directory that is not a clone is not replaced"

mkdir -p "$TMP/empty"
"$BATS" clone-repository "$first" --repository "$TMP/empty" > /dev/null 2>&1 || fail "an empty directory was refused"
ok "an empty directory is cloned into"

"$BATS" clone-repository "$first" > "$TMP/out" 2> "$TMP/err" && fail "no directory was accepted"
grep -q "BATS_REPOSITORY" "$TMP/err" || fail "no directory is not said"
BATS_REPOSITORY=$TMP/viaenv "$BATS" clone-repository "$first" > "$TMP/out" 2>/dev/null || fail "BATS_REPOSITORY was not used"
[ "$(cat "$TMP/out")" = "BATS_REPOSITORY=$TMP/viaenv" ] || fail "stdout via the environment"
ok "the directory is --repository or BATS_REPOSITORY"
echo "all passed"
