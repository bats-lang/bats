#!/bin/bash
# bats check-push [--repository <dir>] (bats-lang/bats#575): the three first-minute checks of a push, in
# order, stopping at the first failure, each failure naming its check and its fix:
#   1 locks     every bats.lock of the tree resolves against the package repository at the commit of
#               .github/repository-version (read from that commit, not from the clone's files)
#   2 compiler  the bats that runs is built from the commit of .github/bats-version (a fact of its build:
#               src/built.bats, keyword: built-commit)
#   3 memory    BATS_PATSOPT_MEM_MB is 4096, what the setup action sets for CI
# A fixture for each class, each failing in its own, and the all-good case passing. Detail:
# .claude/rules/check-push.md.
# usage: tests/check-push/check.sh <bats-binary> <repository-dir>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPOSITORY=$2
. "$(dirname "$0")/../keep-on-fail.sh"
PROJECT=$(cd "$(dirname "$0")/../.." && pwd)
unset BATS_COMMIT BATS_REPOSITORY BATS_PATSOPT_MEM_MB
fail() { echo "FAIL: $*" >&2; echo "--- stdout" >&2; cat "$TMP/out" >&2; echo "--- stderr" >&2; cat "$TMP/err" >&2; exit 1; }

git_in() { local d=$1; shift; git -C "$d" -c user.name=t -c user.email=t@example.com "$@"; }

# ---- the compilers: one built without BATS_COMMIT, one built from a commit of its own (the facts of a build)
SRC=$TMP/bats-src
mkdir -p "$SRC"
cp -R "$PROJECT/bats.toml" "$PROJECT/bats.lock" "$PROJECT/src" "$SRC/"
for d in build bats_modules; do [ -d "$PROJECT/$d" ] && cp -R "$PROJECT/$d" "$SRC/$d"; done
printf 'build/\ndist/\nbats_modules/\n' > "$SRC/.gitignore"
git -C "$SRC" init -q -b main
git_in "$SRC" add -A
git_in "$SRC" commit -q -m source
build_in_src() { (cd "$SRC" && "$BATS" build --only debug --only native --repository "$REPOSITORY") > "$TMP/out" 2> "$TMP/err" || fail "build of the compiler fixture"; }
build_in_src
UNNAMED=$TMP/bats-unnamed
cp "$SRC/dist/debug/bats" "$UNNAMED"
NAMED_COMMIT=$(git -C "$SRC" rev-parse HEAD)
(cd "$SRC" && BATS_COMMIT="$NAMED_COMMIT" "$BATS" build --only debug --only native --repository "$REPOSITORY") > "$TMP/out" 2> "$TMP/err" || fail "build of the named compiler"
NAMED=$TMP/bats-named
cp "$SRC/dist/debug/bats" "$NAMED"
# a BATS_COMMIT git does not know is an error that says so
if (cd "$SRC" && BATS_COMMIT=no-such-commit "$BATS" build --only debug --only native --repository "$REPOSITORY") > "$TMP/out" 2> "$TMP/err"; then
  fail "a BATS_COMMIT git does not know built"
fi
grep -qF "git names no commit for BATS_COMMIT" "$TMP/err" || fail "an unknown BATS_COMMIT did not say why"
echo "ok   the compilers: unnamed, named, an unknown commit refused"

# ---- the package repository: a commit R1 holding two versions, then R2 holding a third
PKG=$TMP/package-repository
mkdir -p "$PKG/arith" "$PKG/wasm.bats-packages.dev/dom"
git -C "$PKG" init -q -b main
h() { printf '%064d' "$1" | tr '0' "$2"; }   # a 64-digit hex string of one digit
printf '%s  arith_2026.1.1.1.bats\n' "$(h 1 a)" > "$PKG/arith/arith_2026.1.1.1.bats.sha256"
printf '%s  wasm.bats-packages.dev_dom_2026.1.1.2.bats\n' "$(h 1 b)" > "$PKG/wasm.bats-packages.dev/dom/wasm.bats-packages.dev_dom_2026.1.1.2.bats.sha256"
git_in "$PKG" add -A
git_in "$PKG" commit -q -m one
PIN=$(git -C "$PKG" rev-parse HEAD)
printf '%s  arith_2026.2.2.2.bats\n' "$(h 1 c)" > "$PKG/arith/arith_2026.2.2.2.bats.sha256"
git_in "$PKG" add -A
git_in "$PKG" commit -q -m two

# ---- the app: pins, a lock at the root and one deeper, all good
APP=$TMP/app
good_app() {
  rm -rf "$APP"
  mkdir -p "$APP/.github" "$APP/tests/deep"
  git -C "$APP" init -q -b main
  printf '%s\n' "$PIN" > "$APP/.github/repository-version"
  printf '%s\n' "$NAMED_COMMIT" > "$APP/.github/bats-version"
  printf 'arith 2026.1.1.1 %s\nwasm.bats-packages.dev/dom 2026.1.1.2 %s\n' "$(h 1 a)" "$(h 1 b)" > "$APP/bats.lock"
  printf 'arith 2026.1.1.1 %s\n' "$(h 1 a)" > "$APP/tests/deep/bats.lock"
  printf 'ignored/\n' > "$APP/.gitignore"
  git_in "$APP" add -A
  git_in "$APP" commit -q -m app
}
# runs bats check-push in the app: <bats> [MEM=value] -- arguments
check() { # <binary> <memory or ->  [arguments]
  local bin=$1 mem=$2; shift 2
  if [ "$mem" = - ]; then
    (cd "$APP" && "$bin" check-push "$@") > "$TMP/out" 2> "$TMP/err"
  else
    (cd "$APP" && BATS_PATSOPT_MEM_MB="$mem" "$bin" check-push "$@") > "$TMP/out" 2> "$TMP/err"
  fi
  status=$?
}
passes() { # <name> <binary> <memory> [arguments]
  local name=$1; shift
  check "$@"
  [ "$status" -eq 0 ] || fail "$name: status $status, wanted 0"
  [ "$(cat "$TMP/out")" = "bats check-push: ok (locks, compiler, memory)" ] || fail "$name: stdout is not the all-good line"
  [ ! -s "$TMP/err" ] || fail "$name: wrote stderr"
  echo "ok   $name"
}
fails() { # <name> <check line starts> <what it says> <binary> <memory> [arguments]
  local name=$1 prefix=$2 what=$3; shift 3
  check "$@"
  [ "$status" -eq 1 ] || fail "$name: status $status, wanted 1"
  [ ! -s "$TMP/out" ] || fail "$name: wrote stdout"
  grep -qF -- "bats check-push: check $prefix failed: " "$TMP/err" || fail "$name: stderr lacks the check line '$prefix'"
  grep -qF -- "$what" "$TMP/err" || fail "$name: stderr lacks '$what'"
  [ "$(grep -c '^fix: ' "$TMP/err")" = 1 ] || fail "$name: not exactly one fix line"
  [ "$(grep -c 'failed: ' "$TMP/err")" -ge 1 ] || fail "$name: no failure line"
  echo "ok   $name"
}

good_app
passes "all good" "$NAMED" 4096 --repository "$PKG"
BATS_REPOSITORY=$PKG passes "repository from the environment" "$NAMED" 4096
# the clone's files are at R2, the pin is R1: a lock that names a version only R2 holds is not in the pin
printf 'arith 2026.2.2.2 %s\n' "$(h 1 c)" > "$APP/bats.lock"
fails "version only after the pin" "1 (locks)" "bats.lock:1: arith 2026.2.2.2 is not in the package repository at the commit of .github/repository-version" "$NAMED" 4096 --repository "$PKG"
# locks, each class
good_app
printf 'arith 2026.1.1.1 %s\n' "$(h 1 d)" > "$APP/bats.lock"
fails "sha256 differs" "1 (locks)" "bats.lock:1: arith 2026.1.1.1 has another sha256" "$NAMED" 4096 --repository "$PKG"
good_app
printf 'arith 2026.1.1.1 %s\nwasm.bats-packages.dev/dom 2026.1.1.2 %s\n' "$(h 1 a)" "$(h 1 d)" > "$APP/bats.lock"
fails "second line differs (namespaced package)" "1 (locks)" "bats.lock:2: wasm.bats-packages.dev/dom 2026.1.1.2 has another sha256" "$NAMED" 4096 --repository "$PKG"
good_app
printf 'arith 2026.9.9.9 %s\n' "$(h 1 a)" > "$APP/bats.lock"
fails "version missing" "1 (locks)" "bats.lock:1: arith 2026.9.9.9 is not in the package repository" "$NAMED" 4096 --repository "$PKG"
good_app
printf 'nosuch 2026.1.1.1 %s\n' "$(h 1 a)" > "$APP/tests/deep/bats.lock"
fails "package missing, in a lock deeper in the tree" "1 (locks)" "tests/deep/bats.lock:1: nosuch 2026.1.1.1 is not in the package repository" "$NAMED" 4096 --repository "$PKG"
good_app
printf 'arith 2026.1.1.1\n' > "$APP/bats.lock"
fails "line with two fields" "1 (locks)" "bats.lock:1: is not a line" "$NAMED" 4096 --repository "$PKG"
good_app
printf 'arith 2026.1.1.1 %s\n' "$(h 1 A)" > "$APP/bats.lock"
fails "sha256 in capitals" "1 (locks)" "bats.lock:1: is not a line" "$NAMED" 4096 --repository "$PKG"
good_app
printf 'arith 2026.1.1.1 %s extra\n' "$(h 1 a)" > "$APP/bats.lock"
fails "line with four fields" "1 (locks)" "bats.lock:1: is not a line" "$NAMED" 4096 --repository "$PKG"
good_app
printf '\narith 2026.1.1.1 %s\n\nwasm.bats-packages.dev/dom 2026.1.1.2 %s' "$(h 1 a)" "$(h 1 b)" > "$APP/bats.lock"
passes "blank lines and no final newline" "$NAMED" 4096 --repository "$PKG"
good_app
mkdir -p "$APP/untracked"
printf 'arith 2026.1.1.1 %s\n' "$(h 1 d)" > "$APP/untracked/bats.lock"
fails "an untracked lock" "1 (locks)" "untracked/bats.lock:1: arith 2026.1.1.1 has another sha256" "$NAMED" 4096 --repository "$PKG"
good_app
mkdir -p "$APP/ignored"
printf 'arith 2026.1.1.1 %s\n' "$(h 1 d)" > "$APP/ignored/bats.lock"
passes "an ignored lock is not read" "$NAMED" 4096 --repository "$PKG"
good_app
rm "$APP/.github/repository-version"
fails "no repository-version" "1 (locks)" ".github/repository-version cannot be read" "$NAMED" 4096 --repository "$PKG"
good_app
printf 'main\n' > "$APP/.github/repository-version"
fails "repository-version is a branch" "1 (locks)" ".github/repository-version is not a full lowercase commit" "$NAMED" 4096 --repository "$PKG"
good_app
printf '%s\n' "$(h 0 f | cut -c1-40)" > "$APP/.github/repository-version"
fails "the repository lacks the pinned commit" "1 (locks)" "does not have the commit of .github/repository-version" "$NAMED" 4096 --repository "$PKG"
good_app
fails "no repository named" "1 (locks)" "no package repository is named" "$NAMED" 4096
# the flag wins over the environment
BATS_REPOSITORY=$TMP/nothing-here fails "the flag wins over the environment" "1 (locks)" "does not have the commit" "$NAMED" 4096 --repository "$TMP/app"
# compiler, each class
good_app
fails "compiler built without a commit" "2 (compiler)" "built without BATS_COMMIT" "$UNNAMED" 4096 --repository "$PKG"
printf '%s\n' "$(h 0 e | cut -c1-40)" > "$APP/.github/bats-version"
fails "compiler built from another commit" "2 (compiler)" "this bats is built from $NAMED_COMMIT, .github/bats-version is $(h 0 e | cut -c1-40)" "$NAMED" 4096 --repository "$PKG"
rm "$APP/.github/bats-version"
fails "no bats-version" "2 (compiler)" ".github/bats-version cannot be read" "$NAMED" 4096 --repository "$PKG"
printf 'HEAD\n' > "$APP/.github/bats-version"
fails "bats-version is not a commit" "2 (compiler)" ".github/bats-version is not a full lowercase commit" "$NAMED" 4096 --repository "$PKG"
# memory, each class
good_app
fails "memory unset" "3 (memory)" "BATS_PATSOPT_MEM_MB is not set, CI runs with 4096" "$NAMED" - --repository "$PKG"
fails "memory another value" "3 (memory)" "BATS_PATSOPT_MEM_MB is 8192, CI runs with 4096" "$NAMED" 8192 --repository "$PKG"
fails "memory with a longer value" "3 (memory)" "BATS_PATSOPT_MEM_MB is 40960, CI runs with 4096" "$NAMED" 40960 --repository "$PKG"
# the order: the first failure is the only one reported
printf 'arith 2026.1.1.1 %s\n' "$(h 1 d)" > "$APP/bats.lock"
fails "locks come before the compiler and the memory" "1 (locks)" "has another sha256" "$UNNAMED" - --repository "$PKG"
[ "$(grep -c 'failed: ' "$TMP/err")" = 1 ] || fail "more than one check reported"
printf 'arith 2026.1.1.1 %s\n' "$(h 1 a)" > "$APP/bats.lock"
fails "the compiler comes before the memory" "2 (compiler)" "built without BATS_COMMIT" "$UNNAMED" - --repository "$PKG"
[ "$(grep -c 'failed: ' "$TMP/err")" = 1 ] || fail "more than one check reported"
fails "memory is last" "3 (memory)" "is not set" "$NAMED" - --repository "$PKG"
# arguments
check "$NAMED" 4096 --nonsense
[ "$status" -eq 2 ] || fail "an unknown flag: status $status, wanted 2"
grep -qF "usage: bats check-push [--repository <dir>]" "$TMP/err" || fail "an unknown flag: no usage"
check "$NAMED" 4096 --repository
[ "$status" -eq 2 ] || fail "a flag without a directory: status $status, wanted 2"
check "$NAMED" 4096 --repository "$PKG" extra
[ "$status" -eq 2 ] || fail "an extra argument: status $status, wanted 2"
echo "ok   arguments"
