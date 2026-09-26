#!/bin/sh
# `bats lock` resolves as the Rust bats does (lock::resolve_all): the
# packages come from the #use lines of src, the queue is taken from the
# end, a fetched package's own #use lines join the queue, and each fetch
# and the summary go to stderr. Without --repository it refuses.
# usage: tests/lock-order/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo" "$TMP/app/src"
publish() { # <name> <commit date> <#use line or empty>
  mkdir -p "$TMP/$1/src"
  printf '[package]\nname = "%s"\nkind = "lib"\n' "$1" > "$TMP/$1/bats.toml"
  printf '%s\n#pub fun f (): int\n\nimplement f () = 1\n' "$3" > "$TMP/$1/src/lib.bats"
  printf 'build/\ndist/\ndocs/\nbats_modules/\nbats.lock\n' > "$TMP/$1/.gitignore"
  (cd "$TMP/$1" && git init -q -b main . && git add -A &&
   GIT_COMMITTER_DATE="$2" git -c user.name=t -c user.email=t@t commit -q -m "$2" &&
   "$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1) || { echo "FAIL: upload $1"; cat "$TMP/up.log"; exit 1; }
}
publish lockc "2026-01-03T00:00:03Z" ""
publish locka "2026-01-01T00:00:01Z" "#use lockc as C"
publish lockb "2026-01-02T00:00:02Z" ""
printf '[package]\nname = "lockapp"\nkind = "lib"\n' > "$TMP/app/bats.toml"
printf '#use locka as A\n#use lockb as B\n\n#pub fun g (): int\n\nimplement g () = 2\n' > "$TMP/app/src/lib.bats"
cd "$TMP/app"
check() { # <run>
  cut -d' ' -f1,2 bats.lock > "$TMP/got.lock"
  printf 'lockb 2026.1.2.2\nlocka 2026.1.1.1\nlockc 2026.1.3.3\n' > "$TMP/want.lock"
  cmp -s "$TMP/got.lock" "$TMP/want.lock" || { echo "FAIL: run $1: bats.lock"; cat bats.lock; exit 1; }
  cmp -s "$TMP/err" "$TMP/want.err" || { echo "FAIL: run $1: stderr"; cat "$TMP/err"; exit 1; }
}
"$BATS" lock --repository "$TMP/repo" 2> "$TMP/err"
printf 'fetched lockb v2026.1.2.2\nfetched locka v2026.1.1.1\nfetched lockc v2026.1.3.3\nwrote bats.lock (3 dependencies)\n' > "$TMP/want.err"
check 1
"$BATS" lock --repository "$TMP/repo" 2> "$TMP/err"
printf 'wrote bats.lock (3 dependencies)\n' > "$TMP/want.err"
check 2
rm -f bats.lock
if "$BATS" lock 2> "$TMP/err"; then echo "FAIL: lock without --repository succeeded"; exit 1; fi
grep -q "'bats lock' requires --repository <dir>" "$TMP/err" || { echo "FAIL: no --repository message"; cat "$TMP/err"; exit 1; }
[ ! -e bats.lock ] || { echo "FAIL: lock without --repository wrote bats.lock"; exit 1; }
echo "lock-order: ok"
