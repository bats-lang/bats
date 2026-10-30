#!/bin/bash
# bats merge-proof <reviewed-sha> <head> (bats-lang/bats#530): OK only for a head that is the reviewed head
# plus a merge of main whose pull-request diff is unchanged and whose bootstrap/c regenerates to itself;
# a hand-resolved conflict prints its resolved hunks and nothing else. Detail: .claude/rules/merge-proof.md.
# The fixtures plant git repositories with git, as tests/affected does.
# usage: tests/merge-proof/check.sh <bats-binary> <repository-dir>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
. "$(dirname "$0")/../keep-on-fail.sh"
fail() { echo "FAIL: $*" >&2; echo "--- stdout" >&2; cat "$TMP/out" >&2; echo "--- stderr" >&2; cat "$TMP/err" >&2; exit 1; }

git_in() { git -C "$TMP/repo" -c user.name=t -c user.email=t@example.com "$@"; }

# the pull request edits line 31 of src/a.txt, main line 3 of src/b.txt: far apart, so their merge is clean
edit_a() { { seq 1 30; echo "$1"; seq 32 40; } > "$TMP/repo/src/a.txt"; }
edit_b() { { seq 101 102; echo "$1"; seq 104 140; } > "$TMP/repo/src/b.txt"; }
regenerate() { [ -x "$TMP/repo/scripts/bootstrap-c.sh" ] || return 0; (cd "$TMP/repo" && scripts/bootstrap-c.sh); }

# main with the stand-in for scripts/bootstrap-c.sh: bootstrap/c is a function of src
start() {
  rm -rf "$TMP/repo"
  mkdir -p "$TMP/repo/src" "$TMP/repo/scripts"
  git -C "$TMP/repo" init -q -b main
  printf '#!/bin/sh\nmkdir -p bootstrap/c\ncat src/a.txt src/b.txt > bootstrap/c/generated\n' > "$TMP/repo/scripts/bootstrap-c.sh"
  chmod +x "$TMP/repo/scripts/bootstrap-c.sh"
  seq 1 40 > "$TMP/repo/src/a.txt"
  seq 101 140 > "$TMP/repo/src/b.txt"
  regenerate
  git_in add -A
  git_in commit -q -m base
}
# main of a repository with no scripts/ directory and no bootstrap/c (pwa, bridge, capacitor-plugins; bats#592)
start_plain() {
  rm -rf "$TMP/repo"
  mkdir -p "$TMP/repo/src"
  git -C "$TMP/repo" init -q -b main
  seq 1 40 > "$TMP/repo/src/a.txt"
  seq 101 140 > "$TMP/repo/src/b.txt"
  git_in add -A
  git_in commit -q -m base
}
# the pull request branch from main, one commit, regenerated
pr_commit() { # <line 31 of src/a.txt>
  git_in checkout -q -b pr
  edit_a "$1"
  regenerate
  git_in commit -q -a -m pr
  reviewed=$(git_in rev-parse HEAD)
}
# a commit on main
main_commit() { # <edit_a|edit_b> <text>
  git_in checkout -q main
  "$1" "$2"
  regenerate
  git_in commit -q -a -m main
  git_in update-ref refs/remotes/origin/main HEAD
}
# runs the command in the checkout of the head
prove() { # <reviewed> <head> [arguments]
  git_in checkout -q "$2"
  local r=$1 h=$2; shift 2
  (cd "$TMP/repo" && "$BATS" merge-proof "$r" "$h" "$@") > "$TMP/out" 2> "$TMP/err"
  status=$?
}
expect() { # <name> <status> <first line of stdout starts with>
  [ "$status" -eq "$2" ] || fail "$1: status $status, wanted $2"
  case "$(head -n 1 "$TMP/out")" in "$3"*) ;; *) fail "$1: stdout does not start with '$3'" ;; esac
  echo "ok   $1"
}
contains() { grep -qF -- "$2" "$TMP/out" || fail "$1: stdout lacks '$2'"; }

# 1. a clean main merge
start; git_in update-ref refs/remotes/origin/main HEAD
pr_commit "PR CHANGE"; main_commit edit_b "MAIN CHANGE"
git_in checkout -q pr; git_in merge -q --no-edit main > /dev/null; head=$(git_in rev-parse HEAD)
prove "$reviewed" "$head" --repository unused
expect clean-main-merge 0 "OK: $head is the reviewed $reviewed"
[ "$(wc -l < "$TMP/out")" -eq 1 ] || fail "clean-main-merge: more than one line"
[ ! -s "$TMP/err" ] || fail "clean-main-merge: wrote to stderr"
git_in status --porcelain | grep -q . && fail "clean-main-merge: left the working tree changed"

# the repository from the environment instead of the flag
(cd "$TMP/repo" && BATS_REPOSITORY=unused "$BATS" merge-proof "$reviewed" "$head") > "$TMP/out" 2> "$TMP/err"; status=$?
expect repository-from-environment 0 "OK: $head"
(cd "$TMP/repo" && env -u BATS_REPOSITORY "$BATS" merge-proof "$reviewed" "$head") > "$TMP/out" 2> "$TMP/err"; status=$?
[ "$status" -eq 2 ] || fail "no repository: status $status, wanted 2"
echo "ok   no-repository (status 2)"

# 1b. a clean main merge in a repository without scripts/bootstrap-c.sh: proofs 1 to 3 decide, no repository is named (bats#592)
start_plain; git_in update-ref refs/remotes/origin/main HEAD
[ ! -e "$TMP/repo/scripts" ] && [ ! -e "$TMP/repo/bootstrap" ] || fail "no-bootstrap-script: the fixture has scripts/ or bootstrap/"
pr_commit "PR CHANGE"; main_commit edit_b "MAIN CHANGE"
git_in checkout -q pr; git_in merge -q --no-edit main > /dev/null; head=$(git_in rev-parse HEAD)
(cd "$TMP/repo" && env -u BATS_REPOSITORY "$BATS" merge-proof "$reviewed" "$head") > "$TMP/out" 2> "$TMP/err"; status=$?
expect no-bootstrap-script 0 "OK: $head is the reviewed $reviewed"
[ "$(wc -l < "$TMP/out")" -eq 1 ] || fail "no-bootstrap-script: more than one line"
[ ! -s "$TMP/err" ] || fail "no-bootstrap-script: wrote to stderr"
# and the proofs before proof 4 still decide there: the same repository with main's change already in the pull request's hunk
start_plain; git_in update-ref refs/remotes/origin/main HEAD
pr_commit "SAME CHANGE"; main_commit edit_a "SAME CHANGE"
git_in checkout -q pr; git_in merge -q --no-edit main > /dev/null; head=$(git_in rev-parse HEAD)
(cd "$TMP/repo" && env -u BATS_REPOSITORY "$BATS" merge-proof "$reviewed" "$head") > "$TMP/out" 2> "$TMP/err"; status=$?
expect no-bootstrap-script-changed-hunk 1 "NOT OK: the diff of the head against main differs"

# 2. the pull request's diff changed: main already has the pull request's own change, so the merge is clean and the diff shrinks
start; git_in update-ref refs/remotes/origin/main HEAD
pr_commit "SAME CHANGE"; main_commit edit_a "SAME CHANGE"
git_in checkout -q pr; git_in merge -q --no-edit main > /dev/null; head=$(git_in rev-parse HEAD)
prove "$reviewed" "$head" --repository unused
expect changed-hunk 1 "NOT OK: the diff of the head against main differs"
contains changed-hunk "-+SAME CHANGE"

# 3. a hand-resolved conflict prints the resolved hunks and nothing else
start; git_in update-ref refs/remotes/origin/main HEAD
pr_commit "PR SIDE"; main_commit edit_a "MAIN SIDE"
git_in checkout -q pr; git_in merge -q --no-edit main > /dev/null 2>&1
edit_a "RESOLVED BY HAND"; regenerate; git_in commit -q -a -m resolved; head=$(git_in rev-parse HEAD)
git_in cat-file -p "$head" | grep -c '^parent ' | grep -qx 2 || fail "conflict: the fixture's head is not a merge"
prove "$reviewed" "$head" --repository unused
expect hand-resolved-conflict 1 "diff --cc"
contains hand-resolved-conflict "diff --cc src/a.txt"
contains hand-resolved-conflict "++RESOLVED BY HAND"
contains hand-resolved-conflict "RESOLVED BY HAND"
grep -q '^OK\|^NOT OK' "$TMP/out" && fail "conflict: a verdict was printed"
[ ! -s "$TMP/err" ] || fail "conflict: wrote to stderr"

# 4. a stale bootstrap/c: main changed src and did not regenerate, so the clean merge is stale
start; git_in update-ref refs/remotes/origin/main HEAD
pr_commit "PR CHANGE"
git_in checkout -q main; edit_b "MAIN CHANGE"; git_in commit -q -a -m "main, not regenerated"; git_in update-ref refs/remotes/origin/main HEAD
git_in checkout -q pr; git_in merge -q --no-edit main > /dev/null; head=$(git_in rev-parse HEAD)
prove "$reviewed" "$head" --repository unused
expect stale-bootstrap 1 "NOT OK: bootstrap/c is stale"
contains stale-bootstrap "bootstrap/c/generated"

# 5. a third parent
start; git_in update-ref refs/remotes/origin/main HEAD
pr_commit "PR CHANGE"
git_in checkout -q -b side1 main; echo one > "$TMP/repo/one.txt"; git_in add -A; git_in commit -q -m one
git_in checkout -q -b side2 main; echo two > "$TMP/repo/two.txt"; git_in add -A; git_in commit -q -m two
git_in checkout -q main; git_in merge -q --ff-only side2; git_in merge -q --no-edit side1 > /dev/null 2>&1
git_in update-ref refs/remotes/origin/main HEAD
git_in checkout -q pr; git_in merge -q --no-edit side1 side2 > /dev/null 2>&1; head=$(git_in rev-parse HEAD)
git_in cat-file -p "$head" | grep -c '^parent ' | grep -qx 3 || fail "third-parent: the fixture's head has not three parents"
prove "$reviewed" "$head" --repository unused
expect third-parent 1 "NOT OK: the head has a third parent"

# the head is no merge
start; git_in update-ref refs/remotes/origin/main HEAD
pr_commit "PR CHANGE"; head=$(git_in rev-parse HEAD)
prove "$reviewed" "$head" --repository unused
expect not-a-merge 1 "NOT OK: the head is not a merge"

# the second parent is a side branch, not main
start; git_in update-ref refs/remotes/origin/main HEAD
pr_commit "PR CHANGE"
git_in checkout -q -b side main; echo one > "$TMP/repo/one.txt"; git_in add -A; git_in commit -q -m one
git_in checkout -q pr; git_in merge -q --no-edit side; head=$(git_in rev-parse HEAD)
prove "$reviewed" "$head" --repository unused
expect parent-not-main 1 "NOT OK: the other parent of the head is not a commit of main"

# neither parent is the reviewed head
start; git_in update-ref refs/remotes/origin/main HEAD
pr_commit "PR CHANGE"; first=$reviewed
echo again >> "$TMP/repo/src/a.txt"; regenerate; git_in commit -q -a -m again
main_commit edit_b "MAIN CHANGE"
git_in checkout -q pr; git_in merge -q --no-edit main > /dev/null; head=$(git_in rev-parse HEAD)
prove "$first" "$head" --repository unused
expect reviewed-not-a-parent 1 "NOT OK: neither parent of the head is the reviewed head"

# the checkout is not the head
start; git_in update-ref refs/remotes/origin/main HEAD
pr_commit "PR CHANGE"; main_commit edit_b "MAIN CHANGE"
git_in checkout -q pr; git_in merge -q --no-edit main > /dev/null; head=$(git_in rev-parse HEAD)
git_in checkout -q main
(cd "$TMP/repo" && "$BATS" merge-proof "$reviewed" "$head" --repository unused) > "$TMP/out" 2> "$TMP/err"; status=$?
expect checkout-not-head 1 "NOT OK: the working tree is not at the head"

# a revision git does not know
(cd "$TMP/repo" && "$BATS" merge-proof 0000000000000000000000000000000000000001 "$head" --repository unused) > "$TMP/out" 2> "$TMP/err"; status=$?
[ "$status" -eq 2 ] || fail "unknown revision: status $status, wanted 2"
[ ! -s "$TMP/out" ] || fail "unknown revision: stdout"
echo "ok   unknown-revision (status 2)"

# the arguments
usage() { # <name> <arguments...>
  local name=$1; shift
  (cd "$TMP/repo" && "$BATS" merge-proof "$@") > "$TMP/out" 2> "$TMP/err"; status=$?
  [ "$status" -eq 2 ] || fail "$name: status $status, wanted 2"
  [ ! -s "$TMP/out" ] || fail "$name: printed a verdict"
  grep -q '^usage: bats merge-proof' "$TMP/err" || fail "$name: no usage"
  echo "ok   $name (usage, status 2)"
}
usage no-arguments
usage one-argument "$head"
usage option-as-revision --abbrev "$head"
usage three-arguments "$reviewed" "$head" extra
usage flag-without-directory "$reviewed" "$head" --repository
usage other-flag "$reviewed" "$head" --other x
