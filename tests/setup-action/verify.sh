#!/bin/sh
# What the setup action (.github/actions/setup) leaves behind, checked on a
# runner after it ran (bats-lang/bats#274): the GMP build of ATS2, lld, the
# caps, the package repository at its pinned commit, the compiler built
# from the commit it was given, and BATS_COMMIT naming the commit the
# version is the date of (a pull request's head, never the merge).
# usage: tests/setup-action/verify.sh <expected BATS_COMMIT> <repository-version> <bats-version> <project>
# run in the checkout, in a step after the action, so the environment it
# wrote to GITHUB_ENV is in this process's.
set -eu
expected=$1 repository_version=$2 bats_version=$3 project=$4
fail() { echo "FAIL: $1"; exit 1; }

# The GMP build: the symlink names it, and patsopt is linked to libgmp
# (the -int build computes in C int and accepts false statements, quire#594)
target=$(readlink ~/.bats/ats2) || fail "~/.bats/ats2 is not a link"
case $target in *ATS2-Postiats-gmp-*) ;; *) fail "~/.bats/ats2 is $target, not the GMP build" ;; esac
ldd ~/.bats/ats2/bin/patsopt | grep -q 'libgmp' || fail "patsopt is not linked to libgmp"
dpkg -s libgmp-dev > /dev/null 2>&1 || fail "libgmp-dev is not installed"
command -v wasm-ld > /dev/null || fail "lld (wasm-ld) is not installed"

# The caps, as the action's defaults give them
[ "${BATS_PATSOPT_TIMEOUT_S:-}" = 600 ] || fail "BATS_PATSOPT_TIMEOUT_S is '${BATS_PATSOPT_TIMEOUT_S:-}', not 600"
[ "${BATS_PATSOPT_MEM_MB:-}" = 4096 ] || fail "BATS_PATSOPT_MEM_MB is '${BATS_PATSOPT_MEM_MB:-}', not 4096"

# The repository: a clone at the pinned commit, and bats is told of it
[ "$(git -C ~/repository rev-parse HEAD)" = "$repository_version" ] || fail "~/repository is not at $repository_version"
[ "${BATS_REPOSITORY:-}" = "$HOME/repository" ] || fail "BATS_REPOSITORY is '${BATS_REPOSITORY:-}'"

# The version names the commit, and on a pull request that is the head,
# the merge's second parent, not the merge the checkout is at
[ "${BATS_COMMIT:-}" = "$expected" ] || fail "BATS_COMMIT is '${BATS_COMMIT:-}', not $expected"
if [ "$(git rev-parse HEAD)" != "$expected" ]; then
  [ "$(git rev-parse 'HEAD^2')" = "$expected" ] || fail "$expected is neither HEAD nor the merge's second parent"
  echo "BATS_COMMIT is the head $expected, not the merge $(git rev-parse HEAD)"
fi

# The compiler on the PATH builds a project, and the facts it writes name
# BATS_COMMIT: the whole chain, from the bootstrap C to the version
command -v bats > /dev/null || fail "bats is not on the PATH"
cd "$project"
bats build --only debug --only native > "${RUNNER_TEMP:-/tmp}/setup-fixture.log" 2>&1 || { cat "${RUNNER_TEMP:-/tmp}/setup-fixture.log"; fail "the fixture does not build"; }
printed=$(./dist/debug/facts)
[ "$printed" = "$expected" ] || fail "the facts name $printed, not $expected"
echo "ok: GMP ATS2, lld, caps, repository $repository_version, compiler $bats_version, version names $expected"
