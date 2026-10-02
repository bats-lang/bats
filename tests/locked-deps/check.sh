#!/bin/sh
# With a bats.lock, check, build, run and test use exactly the versions
# it locks, transitive ones too, even when the repository has newer
# ones: bats_modules is made to hold them, each archive checked against
# the lock's sha256. A locked version the repository does not have, or
# an archive of another sha256, is an error, and so is a lock that does
# not match the project (a package used but not locked, one locked but
# not used, a version bats.toml rules out). Without the lock they
# fetched the newest version of each package src/ uses and never read
# bats.lock. `bats lock` replaces what bats_modules holds of another
# version, so a relock's transitive packages are read from the versions
# it locks.
# usage: tests/locked-deps/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo"
publish() { # <name> <commit date> [<used package>]
  rm -rf "$TMP/p"; mkdir -p "$TMP/p/src"
  printf '[package]\nname = "%s"\nkind = "lib"\n' "$1" > "$TMP/p/bats.toml"
  if [ $# -gt 2 ]; then
    printf '#use %s as U\n\n#pub fun f (): int\n\nimplement f () = $U.f()\n' "$3" > "$TMP/p/src/lib.bats"
  else
    printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/p/src/lib.bats"
  fi
  printf 'build/\ndist/\ndocs/\nbats_modules/\nbats.lock\n' > "$TMP/p/.gitignore"
  (cd "$TMP/p" && git init -q -b main . && git add -A &&
   GIT_COMMITTER_DATE="$2" git -c user.name=t -c user.email=t@t commit -q -m "$2" &&
   "$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1) || { echo "FAIL: upload $1"; cat "$TMP/up.log"; exit 1; }
}
version_of() { # <package>: the version bats_modules holds
  sed -n 's/^version = "\(.*\)"$/\1/p' "$TMP/app/bats_modules/$1/bats.toml"
}
fails_with() { # <what> <expected stderr line>
  rc=0; (cd "$TMP/app" && "$BATS" check --repository "$TMP/repo") > /dev/null 2> "$TMP/err" || rc=$?
  [ "$rc" != 0 ] && grep -qxF "$2" "$TMP/err" || { echo "FAIL: $1"; cat "$TMP/err"; exit 1; }
}
publish ld "2026-01-01T00:00:01Z"
publish lm "2026-01-02T00:00:02Z" ld
mkdir -p "$TMP/app/src/bin"
printf '[package]\nname = "lapp"\nkind = "bin"\n' > "$TMP/app/bats.toml"
printf '#use lm as M\n\nimplement main0 () = let val _ = $M.f() in () end\n' > "$TMP/app/src/bin/lapp.bats"
cd "$TMP/app"
"$BATS" lock --repository "$TMP/repo" > /dev/null 2>&1 || { echo "FAIL: first lock"; exit 1; }
cp bats.lock "$TMP/old.lock"
grep -q '^ld 2026.1.1.1 ' bats.lock && grep -q '^lm 2026.1.2.2 ' bats.lock || { echo "FAIL: first lock"; cat bats.lock; exit 1; }
# Newer versions are published; the lock still holds the old ones
publish ld "2026-01-03T00:00:03Z"
publish lm "2026-01-04T00:00:04Z" ld
rm -rf bats_modules
"$BATS" check --repository "$TMP/repo" > /dev/null 2> "$TMP/err" || { echo "FAIL: locked check"; cat "$TMP/err"; exit 1; }
[ "$(version_of ld)" = 2026.1.1.1 ] && [ "$(version_of lm)" = 2026.1.2.2 ] ||
  { echo "FAIL: check did not use the locked versions"; cat "$TMP/err"; exit 1; }
grep -qx "fetched lm v2026.1.2.2" "$TMP/err" && grep -qx "fetched ld v2026.1.1.1" "$TMP/err" ||
  { echo "FAIL: fetch messages"; cat "$TMP/err"; exit 1; }
cmp -s bats.lock "$TMP/old.lock" || { echo "FAIL: check changed bats.lock"; exit 1; }
# What bats_modules already holds at the locked version is kept
"$BATS" check --repository "$TMP/repo" > /dev/null 2> "$TMP/err" || { echo "FAIL: second check"; cat "$TMP/err"; exit 1; }
! grep -q "^fetched" "$TMP/err" || { echo "FAIL: refetched the locked versions"; cat "$TMP/err"; exit 1; }
# and another version is replaced by the locked one, by build too
rm -rf bats_modules/ld && mkdir -p bats_modules/ld && unzip -qo "$TMP/repo/ld/ld_2026.1.3.3.bats" -d bats_modules/ld
"$BATS" build --repository "$TMP/repo" > /dev/null 2> "$TMP/err" || { echo "FAIL: locked build"; cat "$TMP/err"; exit 1; }
[ "$(version_of ld)" = 2026.1.1.1 ] || { echo "FAIL: build kept another version"; cat "$TMP/err"; exit 1; }
# Without the repository, a locked version bats_modules lacks is an error
rm -rf bats_modules
rc=0; "$BATS" check > /dev/null 2> "$TMP/err" || rc=$?
[ "$rc" != 0 ] && grep -qx "error: bats.lock locks lm v2026.1.2.2, which is not in bats_modules. Use --repository <dir> to fetch it." "$TMP/err" ||
  { echo "FAIL: no repository"; cat "$TMP/err"; exit 1; }
# A locked version the repository does not have fails loudly
sed 's/^ld 2026.1.1.1 /ld 2025.1.1.1 /' "$TMP/old.lock" > bats.lock
fails_with "missing locked version" "error: bats.lock locks ld v2025.1.1.1, which is not in repository '$TMP/repo'"
# as does an archive whose sha256 is not the lock's
sed 's/^\(ld 2026.1.1.1\) .*/\1 0000/' "$TMP/old.lock" > bats.lock
fails_with "sha256" "error: bats.lock locks ld v2026.1.1.1, but its archive '$TMP/repo/ld/ld_2026.1.1.1.bats' does not have the sha256 bats.lock gives"
# A lock that does not match the project is stale
STALE="; bats.lock is stale: run 'bats lock --repository <dir>' and commit it"
grep -v '^ld ' "$TMP/old.lock" > bats.lock
fails_with "not locked" "error: ld is used but bats.lock does not lock it$STALE"
cp "$TMP/old.lock" bats.lock
printf 'lx 2026.1.1.1 00\n' >> bats.lock
fails_with "not used" "error: bats.lock locks lx, which nothing uses$STALE"
cp "$TMP/old.lock" bats.lock
printf '[package]\nname = "lapp"\nkind = "bin"\n\n[dependencies]\n"lm" = ">= 2026.1.4.4"\n' > bats.toml
fails_with "constraint" "error: bats.lock locks lm v2026.1.2.2, which does not meet >= 2026.1.4.4 (from lapp)$STALE"
printf '[package]\nname = "lapp"\nkind = "bin"\n' > bats.toml
# A relock moves to the newest versions and replaces bats_modules' copies
"$BATS" lock --repository "$TMP/repo" > /dev/null 2>&1 || { echo "FAIL: relock"; exit 1; }
grep -q '^ld 2026.1.3.3 ' bats.lock && grep -q '^lm 2026.1.4.4 ' bats.lock || { echo "FAIL: relock"; cat bats.lock; exit 1; }
[ "$(version_of ld)" = 2026.1.3.3 ] && [ "$(version_of lm)" = 2026.1.4.4 ] || { echo "FAIL: relock kept old copies"; exit 1; }
"$BATS" check --repository "$TMP/repo" > /dev/null 2> "$TMP/err" || { echo "FAIL: check after relock"; cat "$TMP/err"; exit 1; }
echo "locked-deps: ok"
