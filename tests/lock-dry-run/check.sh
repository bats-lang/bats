#!/bin/sh
# `bats lock --dry-run` compares what it resolves with bats.lock instead
# of writing it, as the Rust bats does (lock::generate, print_diff,
# read_lockfile): "  + " for a new package, "  ~ " for a new version,
# "  - " for a package no longer used, else "no changes"; a change fails
# with "lockfile is stale". Hashes are not compared, and a line without
# a space is malformed. The expected output is the Rust bats's.
# usage: tests/lock-dry-run/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo"
publish() { # <name> <commit date> <#use line or empty>
  rm -rf "$TMP/p"; mkdir -p "$TMP/p/src"
  printf '[package]\nname = "%s"\nkind = "lib"\n' "$1" > "$TMP/p/bats.toml"
  printf '%s\n#pub fun f (): int\n\nimplement f () = 1\n' "$3" > "$TMP/p/src/lib.bats"
  printf 'build/\ndist/\ndocs/\nbats_modules/\nbats.lock\n' > "$TMP/p/.gitignore"
  (cd "$TMP/p" && git init -q -b main . && git add -A &&
   GIT_COMMITTER_DATE="$2" git -c user.name=t -c user.email=t@t commit -q -m "$2" &&
   "$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1) || { echo "FAIL: upload $1"; cat "$TMP/up.log"; exit 1; }
}
publish dc "2026-01-03T00:00:03Z" ""
publish da "2026-01-01T00:00:01Z" "#use dc as C"
publish db "2026-01-05T00:00:05Z" ""
mkdir -p "$TMP/app/src"
printf '[package]\nname = "dapp"\nkind = "lib"\n' > "$TMP/app/bats.toml"
printf '#use da as A\n#use db as B\n\n#pub fun g (): int\n\nimplement g () = 2\n' > "$TMP/app/src/lib.bats"
F='fetched db v2026.1.5.5
fetched da v2026.1.1.1
fetched dc v2026.1.3.3
'
case_() { # <name> <old bats.lock, or NONE> <rc> <expected stderr>
  rm -rf "$TMP/app/bats_modules" "$TMP/app/bats.lock"
  [ "$2" = NONE ] || printf "$2" > "$TMP/app/bats.lock"
  cp "$TMP/app/bats.lock" "$TMP/before" 2>/dev/null || rm -f "$TMP/before"
  rc=0
  (cd "$TMP/app" && "$BATS" lock --dry-run --repository "$TMP/repo") 2> "$TMP/err" || rc=$?
  printf '%s' "$4" > "$TMP/want"
  [ "$rc" = "$3" ] && cmp -s "$TMP/err" "$TMP/want" || { echo "FAIL: $1: rc $rc"; cat "$TMP/err"; exit 1; }
  if [ -e "$TMP/before" ]; then cmp -s "$TMP/before" "$TMP/app/bats.lock"; else [ ! -e "$TMP/app/bats.lock" ]; fi ||
    { echo "FAIL: $1: --dry-run changed bats.lock"; exit 1; }
}
case_ "no bats.lock" NONE 1 "$F  + db v2026.1.5.5
  + da v2026.1.1.1
  + dc v2026.1.3.3
error: lockfile is stale
"
case_ "up to date, reordered, other hashes" "\n  dc 2026.1.3.3 x\r\n\tda 2026.1.1.1\ndb 2026.1.5.5 y z\n" 0 "${F}no changes
"
case_ "changed and removed" "zz 1.0 h\ndb 2026.1.2.2 h\nda 2026.1.1.1 h\n" 1 "$F  ~ db v2026.1.2.2 -> v2026.1.5.5
  + dc v2026.1.3.3
  - zz v1.0
error: lockfile is stale
"
case_ "malformed" "db 2026.1.5.5 h\n  justname  \n" 1 "${F}error: malformed lockfile line: justname
"
echo "lock-dry-run: ok"
