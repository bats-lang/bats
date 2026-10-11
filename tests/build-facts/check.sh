#!/bin/sh
# A module that staloads "_bats_facts.sats" gets the commit the build is
# made from (bats-lang/bats#250): its committer time, that time in UTC as
# YEAR.MONTH.DAY.SECONDS, its short and full SHA. They are the commit's,
# never the build's: the same under any TZ, BATS_COMMIT names another
# commit, and a new commit compiles the facts module again and nothing
# else (its .sats never changes). Outside a git repository it is an
# error that says so.
# usage: tests/build-facts/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_COMMIT
# with the cache, a module bats takes for stale only because its C was
# written in the same second as its .dats (mtimes are whole seconds) is
# a hit, so what runs patsopt is what changed
export BATS_CACHE_DIR="$TMP/cache"
P=$TMP/p
mkdir -p "$P/src/bin"
printf '[package]\nname = "facts"\nkind = "bin"\n' > "$P/bats.toml"
printf 'build/\ndist/\n' > "$P/.gitignore"
printf '#include "share/atspre_staload.hats"\n\n#pub fn h (): int\n\nimplement h () = 1\n' > "$P/src/other.bats"
printf '#include "share/atspre_staload.hats"\nstaload F = "_bats_facts.sats"\nstaload "other.sats"\nimplement main0 () = let\n  val () = println! ($F.bats_commit_time ())\n  val () = println! ($F.bats_commit_version ())\n  val () = println! ($F.bats_commit_short ())\n  val () = println! ($F.bats_commit_sha ())\nin println! (h ()) end\n' > "$P/src/bin/facts.bats"
cd "$P"
git init -q -b main .
commit() { # <committer date> <message>
  git add -A && GIT_COMMITTER_DATE="$1" git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$2"
}
# 2026-10-02 17:02:53 UTC: 1790960573, 61373 seconds after midnight
commit "2026-10-02T17:02:53Z" first
build() { # <log>
  "$BATS" -v build --only debug --only native > "$1" 2>&1 || { echo "FAIL: build"; cat "$1"; exit 1; }
}
expect() { # <time> <version> <sha>
  printf '%s\n%s\n%s\n%s\n1\n' "$1" "$2" "$(printf '%s' "$3" | cut -c1-7)" "$3" > "$TMP/want"
  ./dist/debug/facts > "$TMP/got"
  diff -u "$TMP/want" "$TMP/got" || { echo "FAIL: the facts are not the commit's"; exit 1; }
}
build "$TMP/1.log"
first=$(git rev-parse HEAD)
expect 1790960573 2026.10.2.61373 "$first"
# the same under another clock's zone, from scratch
rm -rf build dist
TZ=Pacific/Kiritimati "$BATS" build --only debug --only native > "$TMP/tz.log" 2>&1 || { echo "FAIL: build under TZ"; cat "$TMP/tz.log"; exit 1; }
expect 1790960573 2026.10.2.61373 "$first"
# a new commit: only the facts module is compiled again
sleep 1
commit "2026-10-03T00:00:07Z" second
build "$TMP/2.log"
expect 1790985607 2026.10.3.7 "$(git rev-parse HEAD)"
ran=$(grep -a -- '+ patsopt' "$TMP/2.log" | grep -av '(cached)' | sed -e 's/.*-d //' -e 's/[^a-zA-Z0-9_./].*//' | sort | tr '\n' ' ')
[ "$ran" = "build/src/_bats_facts.dats " ] || { echo "FAIL: a new commit ran patsopt on: $ran"; cat "$TMP/2.log"; exit 1; }
# BATS_COMMIT names another commit
BATS_COMMIT="$first" "$BATS" build --only debug --only native > "$TMP/3.log" 2>&1 || { echo "FAIL: build with BATS_COMMIT"; cat "$TMP/3.log"; exit 1; }
expect 1790960573 2026.10.2.61373 "$first"
if BATS_COMMIT=no-such-commit "$BATS" build --only debug --only native > "$TMP/4.log" 2>&1; then
  echo "FAIL: an unknown BATS_COMMIT built"; exit 1
fi
grep -q "names no commit" "$TMP/4.log" || { echo "FAIL: an unknown BATS_COMMIT did not say why"; cat "$TMP/4.log"; exit 1; }
# outside a git repository: an error that says so
Q=$TMP/q
mkdir -p "$Q"
cp -R "$P/bats.toml" "$P/src" "$Q/"
cd "$Q"
if GIT_CEILING_DIRECTORIES="$TMP" "$BATS" build --only debug --only native > "$TMP/5.log" 2>&1; then
  echo "FAIL: a build outside git made facts"; exit 1
fi
grep -q "names no commit" "$TMP/5.log" || { echo "FAIL: outside git it did not say why"; cat "$TMP/5.log"; exit 1; }
# a project that does not name them gets none
rm "$Q/src/bin/facts.bats"
printf 'implement main0 () = ()\n' > "$Q/src/bin/facts.bats"
GIT_CEILING_DIRECTORIES="$TMP" "$BATS" build --only debug --only native > "$TMP/6.log" 2>&1 || { echo "FAIL: a build without facts outside git"; cat "$TMP/6.log"; exit 1; }
[ ! -e "$Q/build/src/_bats_facts.dats" ] || { echo "FAIL: facts written for a project that does not name them"; exit 1; }
echo "build-facts: ok"
