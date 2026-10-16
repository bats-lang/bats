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
#  * nothing is deleted that the run did not make: a directory with files, a
#    git project of the user's and a file are refused and unchanged (the
#    directory is compared, not only the messages); a good clone survives a
#    fetch that fails; a failed clone leaves nothing; a control character in
#    the name, and an extra argument, are refused
#  * no directory is an error; BATS_REPOSITORY names it as --repository does
#  * a dangling link, a failed clone under new parents (which it removes, and
#    only those), the mode of an empty directory (setgid and sticky), a git
#    repository with no origin (refused, said), a directory named -foo, and a
#    run killed while it fetches (the next run clears its marked sibling)
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

# nothing that this run did not make is deleted or changed
# (.git/FETCH_HEAD is git's note of the last fetch, rewritten even by a failed one)
snapshot() { (cd "$1" && find . -path ./.git/objects -prune -o ! -name FETCH_HEAD -print | LC_ALL=C sort; find . -path ./.git/objects -prune -o -type f ! -name FETCH_HEAD -exec cksum {} + | LC_ALL=C sort); }
mkdir -p "$TMP/mine"; echo precious > "$TMP/mine/keep"
snapshot "$TMP/mine" > "$TMP/before"
"$BATS" clone-repository "$first" --repository "$TMP/mine" > "$TMP/out" 2> "$TMP/err" && fail "a directory with files was replaced"
snapshot "$TMP/mine" > "$TMP/after"; cmp -s "$TMP/before" "$TMP/after" || fail "the directory was touched"
grep -q "not replaced" "$TMP/err" || fail "not said"
ok "a directory that is not a clone is not replaced"

git init -q "$TMP/users"; echo mine > "$TMP/users/work"; git -C "$TMP/users" add work; git -C "$TMP/users" commit -q -m work
users_head=$(git -C "$TMP/users" rev-parse HEAD); snapshot "$TMP/users" > "$TMP/before"
"$BATS" clone-repository "$first" --repository "$TMP/users" > "$TMP/out" 2> "$TMP/err" && fail "the user's own git project was replaced"
[ ! -s "$TMP/out" ] || fail "stdout on a refusal"
grep -q "not a clone of the package repository" "$TMP/err" || fail "the refusal does not say why"
[ "$(git -C "$TMP/users" rev-parse HEAD)" = "$users_head" ] && [ "$(cat "$TMP/users/work")" = mine ] || fail "the user's project changed"
snapshot "$TMP/users" > "$TMP/after"; cmp -s "$TMP/before" "$TMP/after" || fail "the user's project was touched"
ok "a git project of the user's survives"

# a good clone survives a fetch that fails (the remote is gone)
snapshot "$D" > "$TMP/before"; head_before=$(git -C "$D" rev-parse HEAD)
GIT_CONFIG_VALUE_0="file://$TMP/no-such-remote" \
  "$BATS" clone-repository "$first" --repository "$D" > "$TMP/out" 2> "$TMP/err" && fail "an offline fetch succeeded"
[ ! -s "$TMP/out" ] || fail "stdout on a failed fetch"
[ "$(git -C "$D" rev-parse HEAD)" = "$head_before" ] || fail "the good clone moved"
[ -z "$(git -C "$D" status --porcelain)" ] || fail "the good clone is not clean"
snapshot "$D" > "$TMP/after"; cmp -s "$TMP/before" "$TMP/after" || { diff "$TMP/before" "$TMP/after"; fail "the good clone changed"; }
ok "a good clone survives a failed fetch"

# a failed clone leaves nothing: no directory, no temporary sibling; an empty
# directory stays as it was
mkdir -p "$TMP/par"; rm -rf "$TMP/par/fresh"
"$BATS" clone-repository 0000000000000000000000000000000000000001 --repository "$TMP/par/fresh" > /dev/null 2>&1 && fail "accepted"
[ -z "$(ls -A "$TMP/par")" ] || fail "a failed clone left $(ls -A "$TMP/par")"
mkdir -p "$TMP/par/emptied"
"$BATS" clone-repository 0000000000000000000000000000000000000001 --repository "$TMP/par/emptied" > /dev/null 2>&1 && fail "accepted"
[ -d "$TMP/par/emptied" ] && [ -z "$(ls -A "$TMP/par/emptied")" ] && [ "$(ls -A "$TMP/par")" = emptied ] || fail "a failed clone changed the empty directory or left files"
ok "a failed clone leaves nothing"

: > "$TMP/afile"
"$BATS" clone-repository "$first" --repository "$TMP/afile" > /dev/null 2>&1 && fail "a file was replaced"
[ -f "$TMP/afile" ] || fail "the file went"
nl=$(printf 'a\nb')
"$BATS" clone-repository "$first" --repository "$TMP/$nl" > "$TMP/out" 2> "$TMP/err" && fail "a name with a newline was accepted"
[ ! -s "$TMP/out" ] && grep -q "control character" "$TMP/err" || fail "a newline in the name is not refused"
ok "a file and a name with a control character are refused"

"$BATS" clone-repository "$first" --repository "$TMP/with space/clone/" > "$TMP/out" 2> "$TMP/err" || { cat "$TMP/err"; fail "a path with a space and a trailing slash failed"; }
[ "$(git -C "$TMP/with space/clone" rev-parse HEAD)" = "$first" ] || fail "not at the commit"
mkdir -p "$TMP/empty"
"$BATS" clone-repository "$first" --repository "$TMP/empty" > /dev/null 2>&1 || fail "an empty directory was refused"
[ "$(git -C "$TMP/empty" rev-parse HEAD)" = "$first" ] && [ "$(stat -c %a "$TMP/empty")" = 755 ] || fail "the empty directory did not become the clone"
ok "a path with a space, a trailing slash, and an empty directory"

# a link is neither followed nor replaced, and leaves no debris
mkdir -p "$TMP/par2/real"; ln -s real "$TMP/par2/lnk"
"$BATS" clone-repository "$first" --repository "$TMP/par2/lnk" > "$TMP/out" 2> "$TMP/err" && fail "a link was accepted"
[ "$(ls -A "$TMP/par2" | sort | tr '\n' ' ')" = "lnk real " ] && [ -z "$(ls -A "$TMP/par2/real")" ] || fail "a link left debris: $(ls -A "$TMP/par2")"
# a killed run's sibling is cleared (it is marked); one not marked is not ours
mkdir -p "$TMP/par3/clone.new.AAAAAA" "$TMP/par3/clone.new.BBBBBB"; : > "$TMP/par3/clone.new.AAAAAA/.bats-clone-pending"; echo mine > "$TMP/par3/clone.new.BBBBBB/keep"
"$BATS" clone-repository "$first" --repository "$TMP/par3/clone" > /dev/null 2>&1 || fail "the clone with a stale sibling failed"
[ ! -e "$TMP/par3/clone.new.AAAAAA" ] && [ "$(cat "$TMP/par3/clone.new.BBBBBB/keep")" = mine ] || fail "stale siblings: the marked one stays or the unmarked one went"
# a rename that fails leaves nothing and the empty directory as it was, with its mode
mkdir -p "$TMP/failbin"; printf '#!/bin/sh\nexit 1\n' > "$TMP/failbin/mv"; chmod +x "$TMP/failbin/mv"
mkdir -p "$TMP/par4/dir"; chmod 700 "$TMP/par4/dir"
PATH="$TMP/failbin:$PATH" "$BATS" clone-repository "$first" --repository "$TMP/par4/dir" > /dev/null 2>&1 && fail "a failing rename was accepted"
[ "$(ls -A "$TMP/par4")" = dir ] && [ -z "$(ls -A "$TMP/par4/dir")" ] && [ "$(stat -c %a "$TMP/par4/dir")" = 700 ] || fail "a failing rename left debris or changed the directory"
"$BATS" clone-repository "$first" --repository "$TMP/par4/dir" > /dev/null 2>&1 || fail "the clone into the 700 directory failed"
[ "$(stat -c %a "$TMP/par4/dir")" = 700 ] && [ "$(git -C "$TMP/par4/dir" rev-parse HEAD)" = "$first" ] || fail "the mode of the empty directory was not kept"
ok "a link, a killed run's sibling, a failing rename, and the mode of an empty directory"

# a dangling link is refused and neither followed nor replaced
mkdir -p "$TMP/dangle"; ln -s "$TMP/nowhere" "$TMP/dangle/lnk"
"$BATS" clone-repository "$first" --repository "$TMP/dangle/lnk" > "$TMP/out" 2> "$TMP/err" && fail "a dangling link was accepted"
[ -L "$TMP/dangle/lnk" ] && [ "$(readlink "$TMP/dangle/lnk")" = "$TMP/nowhere" ] && [ ! -e "$TMP/nowhere" ] && [ ! -s "$TMP/out" ] || fail "a dangling link was replaced or followed"
ok "a dangling link is refused and left as it was"

# a link to a clone is refused, not followed: without the check the script
# would fetch and check out into the clone the link names
ln -s "$D" "$TMP/dangle/toclone"; snapshot "$D" > "$TMP/before"; head_before=$(git -C "$D" rev-parse HEAD)
"$BATS" clone-repository "$first" --repository "$TMP/dangle/toclone" > "$TMP/out" 2> "$TMP/err" && fail "a link to a clone was followed"
[ ! -s "$TMP/out" ] && grep -q "symbolic link" "$TMP/err" || { cat "$TMP/err"; fail "a link to a clone is not refused as a link"; }
[ -L "$TMP/dangle/toclone" ] && [ "$(git -C "$D" rev-parse HEAD)" = "$head_before" ] || fail "the clone behind a link moved"
snapshot "$D" > "$TMP/after"; cmp -s "$TMP/before" "$TMP/after" || fail "the clone behind a link was touched"
ok "a link to a clone is refused and the clone is untouched"

# a failed clone removes the parents it made (and only those): a/b/c under an
# existing empty a leaves a, and nothing of a/b
mkdir -p "$TMP/deep/a"
"$BATS" clone-repository 0000000000000000000000000000000000000001 --repository "$TMP/deep/a/b/c" > /dev/null 2>&1 && fail "a commit the remote lacks was accepted under new parents"
[ -d "$TMP/deep/a" ] && [ -z "$(ls -A "$TMP/deep/a")" ] && [ "$(ls -A "$TMP/deep")" = a ] || fail "a failed clone left parents it made: $(find "$TMP/deep" | tr '\n' ' ')"
ok "a failed clone removes the parent directories it made"

# a directory's mode is kept, setgid and sticky too
for m in 2755 1777; do
  rm -rf "$TMP/mode-$m"; mkdir "$TMP/mode-$m"; chmod "$m" "$TMP/mode-$m"
  "$BATS" clone-repository "$first" --repository "$TMP/mode-$m" > /dev/null 2>&1 || fail "the clone into a $m directory failed"
  [ "$(stat -c %a "$TMP/mode-$m")" = "$m" ] || fail "the mode $m of an empty directory became $(stat -c %a "$TMP/mode-$m")"
done
ok "the mode of an empty directory is kept, setgid and sticky included"

# a git repository with no origin (what the old setup action's git init made) is refused, said, untouched
git init -q "$TMP/noorigin"; echo keep > "$TMP/noorigin/k"
snapshot "$TMP/noorigin" > "$TMP/before"
"$BATS" clone-repository "$first" --repository "$TMP/noorigin" > "$TMP/out" 2> "$TMP/err" && fail "a repository with no origin was replaced"
grep -q "no origin" "$TMP/err" || { cat "$TMP/err"; fail "the refusal does not say there is no origin"; }
snapshot "$TMP/noorigin" > "$TMP/after"; cmp -s "$TMP/before" "$TMP/after" || fail "the repository with no origin was touched"
ok "a git repository with no origin is refused, and the message says so"

# an option-like directory name is a directory, not an option of dirname
mkdir -p "$TMP/dashrun" && cd "$TMP/dashrun" && "$BATS" clone-repository "$first" --repository -foo > "$TMP/out" 2> "$TMP/err" || { cat "$TMP/err"; fail "a directory named -foo was refused"; }
[ "$(git -C "$TMP/dashrun/-foo" rev-parse HEAD)" = "$first" ] || fail "-foo is not the clone"
cd "$TMP"
ok "a directory whose name starts with a dash"

# a real kill: the run is killed while it fetches, leaving its marked sibling;
# the next run clears that sibling and clones
mkdir -p "$TMP/killfake"
REAL_GIT=$(command -v git)
cat > "$TMP/killfake/git" <<SH
#!/bin/sh
case " \$* " in *" fetch "*) sleep 60 ;; esac
exec "$REAL_GIT" "\$@"
SH
chmod +x "$TMP/killfake/git"
kd=$TMP/kill/clone
mkdir -p "$TMP/kill"
PATH="$TMP/killfake:$PATH" "$BATS" clone-repository "$first" --repository "$kd" > /dev/null 2>&1 &
bpid=$!
i=0
until ls "$TMP"/kill/clone.new.*/.bats-clone-pending > /dev/null 2>&1; do
  i=$((i + 1)); [ $i -lt 200 ] || fail "the killed run never made its sibling"; sleep 0.1
done
kids() { for k in $(pgrep -P "$1" 2>/dev/null); do kids "$k"; echo "$k"; done; }
victims="$(kids "$bpid") $bpid"
kill -9 $victims 2>/dev/null || true
wait "$bpid" 2>/dev/null || true
ls -d "$TMP"/kill/clone.new.* > /dev/null 2>&1 || fail "the kill left no sibling to clear"
[ ! -e "$kd" ] || fail "the killed run made the target"
"$BATS" clone-repository "$first" --repository "$kd" > /dev/null 2>&1 || fail "the run after a kill failed"
[ "$(git -C "$kd" rev-parse HEAD)" = "$first" ] || fail "the run after a kill is not at the commit"
[ -z "$(ls -A "$TMP/kill" | grep '^clone\.new\.')" ] || fail "the run after a kill left its sibling: $(ls -A "$TMP/kill")"
ok "a run killed while it fetches leaves a marked sibling, which the next run clears"

"$BATS" clone-repository "$first" extra --repository "$TMP/x1" > /dev/null 2>&1 && fail "an extra argument was accepted"
[ ! -e "$TMP/x1" ] || fail "an extra argument cloned"
"$BATS" clone-repository "$first" --repository "$TMP/x2" -- extra > /dev/null 2>&1 && fail "words after -- were accepted"
"$BATS" clone-repository "$first" --repository "$TMP/x4" --release > /dev/null 2>&1 && fail "an unknown option was accepted"
[ ! -e "$TMP/x4" ] || fail "an unknown option cloned"
"$BATS" cXone-repository "$first" --repository "$TMP/x3" > /dev/null 2>&1; [ ! -e "$TMP/x3" ] || fail "a near miss of the command word cloned"
ok "an extra argument, words after --, and a near miss of the command word are refused"

"$BATS" clone-repository "$first" > "$TMP/out" 2> "$TMP/err" && fail "no directory was accepted"
grep -q "BATS_REPOSITORY" "$TMP/err" || fail "no directory is not said"
BATS_REPOSITORY=$TMP/viaenv "$BATS" clone-repository "$first" > "$TMP/out" 2>/dev/null || fail "BATS_REPOSITORY was not used"
[ "$(cat "$TMP/out")" = "BATS_REPOSITORY=$TMP/viaenv" ] || fail "stdout via the environment"
ok "the directory is --repository or BATS_REPOSITORY"
echo "all passed"
