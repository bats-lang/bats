#!/bin/bash
# bats pins-check <base> <head> (bats-lang/bats#427): OK only for a diff that touches pin files alone, whose pins
# are 40 hex digits that exist in their repository's checkout, ahead of the old ones, whose new lock lines move
# forward with the sha256 of the sidecar, and (with --require-contains) whose pins contain a given fix.
# Detail: .claude/rules/pins-check.md. The fixtures plant git repositories with git, as tests/merge-proof does:
# a compiler checkout (c1 < c2 < c3, and a side commit), a package repository (r1 < r2, whose r2 has a second
# version of the package), and an app whose pull request branches are made from its main.
# usage: tests/pins-check/check.sh <bats-binary> <repository-dir>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
. "$(dirname "$0")/../keep-on-fail.sh"
fail() { echo "FAIL: $*" >&2; echo "--- stdout" >&2; cat "$TMP/out" >&2; echo "--- stderr" >&2; cat "$TMP/err" >&2; exit 1; }

git_in() { local d=$1; shift; git -C "$TMP/$d" -c user.name=t -c user.email=t@example.com "$@"; }
commit_in() { git_in "$1" add -A; git_in "$1" commit -q -m "$2"; git_in "$1" rev-parse HEAD; }

sum() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }

# the compiler checkout: c1 < c2 < c3 on main, and a side commit off c1
mkdir -p "$TMP/compiler"
git -C "$TMP/compiler" init -q -b main
echo 1 > "$TMP/compiler/f"; c1=$(commit_in compiler c1)
echo 2 > "$TMP/compiler/f"; c2=$(commit_in compiler c2)
echo 3 > "$TMP/compiler/f"; c3=$(commit_in compiler c3)
git_in compiler checkout -q -b side "$c1"; echo side > "$TMP/compiler/g"; side=$(commit_in compiler side)
git_in compiler checkout -q main

# the package repository: r1 has pkg 1.0, r2 has pkg 1.0 and 2.0, and the namespaced package
mkdir -p "$TMP/repo/pkg" "$TMP/repo/wasm.bats-packages.dev/bridge"
git -C "$TMP/repo" init -q -b main
sha10=$(sum one); sha20=$(sum two); shab=$(sum bridge)
echo "$sha10  pkg_1.0.bats" > "$TMP/repo/pkg/pkg_1.0.bats.sha256"; r1=$(commit_in repo r1)
echo "$sha20  pkg_2.0.bats" > "$TMP/repo/pkg/pkg_2.0.bats.sha256"
echo "$shab  wasm.bats-packages.dev_bridge_2026.10.1.1.bats" > "$TMP/repo/wasm.bats-packages.dev/bridge/wasm.bats-packages.dev_bridge_2026.10.1.1.bats.sha256"
r2=$(commit_in repo r2)
nothing=0000000000000000000000000000000000000001

# the app: main has the pins at c1 and r1, a lock at pkg 1.0, a relock workflow at r1 and a source file
base_c=$c1; base_r=$r1; base_lock="pkg 1.0 $sha10"
start() {
  rm -rf "$TMP/app"; mkdir -p "$TMP/app/.github/workflows" "$TMP/app/src"
  git -C "$TMP/app" init -q -b main
  echo "$base_c" > "$TMP/app/.github/bats-version"
  echo "$base_r" > "$TMP/app/.github/repository-version"
  echo "$base_lock" > "$TMP/app/bats.lock"
  printf 'jobs:\n  relock:\n    uses: bats-lang/repository-prototype/.github/workflows/relock-pins.yml@%s # repository-prototype main %s\n' "$r1" "${r1:0:7}" > "$TMP/app/.github/workflows/relock.yml"
  echo code > "$TMP/app/src/a.txt"
  commit_in app base > /dev/null
  git_in app checkout -q -b pr
}
set_pins() { echo "$1" > "$TMP/app/.github/bats-version"; echo "$2" > "$TMP/app/.github/repository-version"; }
set_lock() { printf '%s\n' "$@" > "$TMP/app/bats.lock"; }
set_workflow() { # <commit>
  printf 'jobs:\n  relock:\n    uses: bats-lang/repository-prototype/.github/workflows/relock-pins.yml@%s # repository-prototype main %s\n' "$1" "${1:0:7}" > "$TMP/app/.github/workflows/relock.yml"
}
prove() { # [arguments]
  commit_in app change > /dev/null
  (cd "$TMP/app" && "$BATS" pins-check main pr --compiler "$TMP/compiler" --repository "$TMP/repo" "$@") > "$TMP/out" 2> "$TMP/err"
  status=$?
}
expect() { # <name> <status> <text the stdout holds>
  [ "$status" -eq "$2" ] || fail "$1: status $status, wanted $2"
  grep -qF -- "$3" "$TMP/out" || fail "$1: stdout lacks '$3'"
  echo "ok   $1"
}
expect_error() { # <name> <text stderr holds>
  [ "$status" -eq 2 ] || fail "$1: status $status, wanted 2"
  grep -qF -- "$2" "$TMP/err" || fail "$1: stderr lacks '$2'"
  ! grep -q '^OK\|^NOT OK' "$TMP/out" || fail "$1: a verdict was printed"
  echo "ok   $1"
}

# 1. a clean move of every kind of pin
start; set_pins "$c2" "$r2"; set_lock "pkg 2.0 $sha20"; set_workflow "$r2"
prove
expect clean-pin-move 0 "OK: main...pr changes only pins"
for f in .github/bats-version .github/repository-version bats.lock .github/workflows/relock.yml; do
  grep -qx "ok   $f" "$TMP/out" || fail "clean-pin-move: no ok line for $f"
done
[ ! -s "$TMP/err" ] || fail "clean-pin-move: wrote to stderr"

# a move of the lock alone, of the compiler pin alone
start; set_lock "pkg 2.0 $sha20"; echo "$r2" > "$TMP/app/.github/repository-version"
prove; expect lock-only 0 "OK: main...pr"
start; echo "$c3" > "$TMP/app/.github/bats-version"
prove; expect compiler-pin-only 0 "OK: main...pr"

# a namespaced package: its sidecar has the name with the slash as an underscore
start; echo "$r2" > "$TMP/app/.github/repository-version"
set_lock "pkg 1.0 $sha10" "wasm.bats-packages.dev/bridge 2026.10.1.1 $shab"
prove; expect namespaced-package 0 "OK: main...pr"

# 2. a pin that does not exist
start; set_pins "$nothing" "$r1"
prove
expect pin-does-not-exist 1 "NOT OK: .github/bats-version: the pin $nothing is not a commit of $TMP/compiler"
start; set_pins "$c1" "$nothing"
prove; expect repository-pin-does-not-exist 1 "NOT OK: .github/repository-version: the pin $nothing is not a commit of $TMP/repo"
start; set_workflow "$nothing"
prove; expect workflow-pin-does-not-exist 1 "NOT OK: .github/workflows/relock.yml: the pin $nothing is not a commit of $TMP/repo"

# 3. a pin behind
base_c=$c2; start; base_c=$c1
echo "$c1" > "$TMP/app/.github/bats-version"
prove
expect pin-behind 1 "NOT OK: .github/bats-version: the new pin $c1 is behind the old pin $c2"
# a pin on another branch than the old one is not ahead either
base_c=$c2; start; base_c=$c1
echo "$side" > "$TMP/app/.github/bats-version"
prove; expect pin-diverged-from-the-old 0 "note: .github/bats-version: the old pin $c2 is not an ancestor of the new pin $side (the two have diverged)"
grep -qx "OK: main...pr changes only pins" "$TMP/out" || fail "pin-diverged-from-the-old: no OK line"

# 4. a lock line backwards
base_lock="pkg 2.0 $sha20"; start; base_lock="pkg 1.0 $sha10"
set_lock "pkg 1.0 $sha10"
prove
expect lock-line-backwards 1 "NOT OK: bats.lock: pkg 1.0: the version moves backwards"

# 5. a sha256 that differs from the sidecar
start; echo "$r2" > "$TMP/app/.github/repository-version"; set_lock "pkg 2.0 $sha10"
prove; expect sha256-differs-from-sidecar 1 "NOT OK: bats.lock: pkg 2.0: has another sha256 than the sidecar"
start; echo "$r2" > "$TMP/app/.github/repository-version"; set_lock "pkg 3.0 $sha20"
prove; expect version-not-in-repository 1 "NOT OK: bats.lock: pkg 3.0: is not in the package repository"
start; set_lock "pkg 1.0 $sha20"
prove; expect same-version-other-sha256 1 "the version stayed and its sha256 changed"

# 6. an extra file in the diff
start; set_pins "$c2" "$r2"; echo more >> "$TMP/app/src/a.txt"
prove; expect extra-file 1 "NOT OK: the diff: src/a.txt is not a pin file"
start; echo new > "$TMP/app/bats.toml"
prove; expect new-file 1 "NOT OK: the diff: bats.toml is not a pin file"
start; echo "# a comment about the pin" >> "$TMP/app/.github/workflows/relock.yml"
prove; expect workflow-comment-line 0 "OK: main...pr changes only pins"
start; echo "$c2" > "$TMP/app/.github/bats-version"; echo extra >> "$TMP/app/.github/workflows/relock.yml"
prove; expect workflow-line-not-a-pin 1 "NOT OK: .github/workflows/relock.yml: a changed line holds no pin of 40 hex digits: +extra"

# a pin file that is not a pin, or holds more than one line, or is deleted
start; echo "main" > "$TMP/app/.github/bats-version"
prove; expect pin-not-hex 1 "NOT OK: .github/bats-version: the new line is not a pin of 40 hex digits"
start; echo "${c2:0:39}" > "$TMP/app/.github/bats-version"
prove; expect pin-39-digits 1 "the new line is not a pin of 40 hex digits"
start; echo "$c2" | tr a-f A-F > "$TMP/app/.github/bats-version"
prove; expect pin-uppercase 1 "NOT OK: .github/bats-version:"
start; printf '%s\n%s\n' "$c2" "$c3" > "$TMP/app/.github/bats-version"
prove; expect pin-two-lines 1 "the file does not end up holding exactly one line"
start; rm "$TMP/app/.github/bats-version"
prove; expect pin-deleted 1 "the file does not end up holding exactly one line"
start; rm "$TMP/app/.github/repository-version"
prove; expect repository-pin-deleted 1 "NOT OK: .github/repository-version:"

# nothing changed
start
git_in app commit -q --allow-empty -m empty
(cd "$TMP/app" && "$BATS" pins-check main pr --compiler "$TMP/compiler" --repository "$TMP/repo") > "$TMP/out" 2> "$TMP/err"; status=$?
expect no-change 1 "NOT OK: the diff: no file changed"

# 7. --require-contains: a pin that lacks a fix fails only when the fix is named
start; echo "$c2" > "$TMP/app/.github/bats-version"
prove --require-contains "$c3"
expect pin-lacks-required-fix 1 "NOT OK: .github/bats-version: the pin $c2 does not contain the required commit $c3"
start; echo "$c3" > "$TMP/app/.github/bats-version"
prove --require-contains "$c3"; expect pin-has-required-fix 0 "OK: main...pr"
start; echo "$c2" > "$TMP/app/.github/bats-version"
prove --require-contains "$c2"; expect pin-is-the-required-fix 0 "OK: main...pr"
start; echo "$c2" > "$TMP/app/.github/bats-version"
prove; expect pin-without-the-fix-named 0 "OK: main...pr"
start; echo "$r2" > "$TMP/app/.github/repository-version"
prove --require-contains "$c3"
expect required-fix-in-no-moved-pin 1 "NOT OK: --require-contains: no moved pin is in a checkout that has the required commit"
start; set_workflow "$r2"
prove --require-contains "$r2"; expect workflow-pin-has-required-fix 0 "OK: main...pr"
start; set_workflow "$r1"; echo "$r2" > "$TMP/app/.github/repository-version"
prove --require-contains "$r2"; expect repository-pin-has-required-fix 0 "OK: main...pr"

# the arguments
start; set_pins "$c2" "$r2"
commit_in app change > /dev/null
run() { (cd "$TMP/app" && "$BATS" pins-check "$@") > "$TMP/out" 2> "$TMP/err"; status=$?; }
run main pr --repository "$TMP/repo"
expect_error missing-compiler "--compiler <dir>"
run main pr --compiler "$TMP/compiler"
expect_error missing-repository "--repository <dir>"
run main
expect_error one-revision "usage: bats pins-check"
run main pr --require-contains abc --compiler "$TMP/compiler" --repository "$TMP/repo"
expect_error require-not-40-hex "usage: bats pins-check"
run main pr --compiler "$TMP/compiler" --compiler "$TMP/compiler" --repository "$TMP/repo"
expect_error flag-twice "usage: bats pins-check"
run main pr --nonsense x
expect_error unknown-flag "usage: bats pins-check"
run -x pr
expect_error revision-starts-with-dash "usage: bats pins-check"
run main nosuchbranch --compiler "$TMP/compiler" --repository "$TMP/repo"
expect_error unknown-revision "git did not answer"
(cd "$TMP/app" && env -u BATS_REPOSITORY "$BATS" pins-check main pr --compiler "$TMP/compiler") > "$TMP/out" 2> "$TMP/err"; status=$?
expect_error no-repository-in-environment "--repository <dir>"
(cd "$TMP/app" && BATS_REPOSITORY="$TMP/repo" "$BATS" pins-check main pr --compiler "$TMP/compiler") > "$TMP/out" 2> "$TMP/err"; status=$?
expect repository-from-environment 0 "OK: main...pr"

echo "pins-check: ok"
