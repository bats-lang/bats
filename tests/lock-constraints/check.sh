#!/bin/sh
# `bats lock` honors the >= and != constraints of [dependencies], as the
# Rust bats does (config::parse_constraints, lock::resolve_all): the
# project's own and, for packages resolved after it, those of each
# fetched dependency's bats.toml. != compares part for part, so
# "!= 2026.1.5.5.0" does not exclude 2026.1.5.5. The expected output is
# the Rust bats's.
# usage: tests/lock-constraints/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo"
publish() { # <name> <commit date> <#use line or empty> <[dependencies] or empty>
  rm -rf "$TMP/p"; mkdir -p "$TMP/p/src"
  printf '[package]\nname = "%s"\nkind = "lib"\n%s' "$1" "$4" > "$TMP/p/bats.toml"
  printf '%s\n#pub fun f (): int\n\nimplement f () = 1\n' "$3" > "$TMP/p/src/lib.bats"
  printf 'build/\ndist/\ndocs/\nbats_modules/\nbats.lock\n' > "$TMP/p/.gitignore"
  (cd "$TMP/p" && git init -q -b main . && git add -A &&
   GIT_COMMITTER_DATE="$2" git -c user.name=t -c user.email=t@t commit -q -m "$2" &&
   "$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1) || { echo "FAIL: upload $1"; cat "$TMP/up.log"; exit 1; }
}
publish cc "2026-01-03T00:00:03Z" "" ""
publish cc "2026-01-04T00:00:04Z" "" ""
publish cb "2026-01-02T00:00:02Z" "" ""
publish cb "2026-01-05T00:00:05Z" "" ""
publish ca "2026-01-01T00:00:01Z" "#use cc as C" '
[dependencies]
"cc" = "!= 2026.1.4.4"
'
# case <name> <[dependencies] value of cb, or of cc when it starts with cc:> <rc> <expected>
# expected: the versions locked ("cb v;ca v;cc v") or the last stderr line
case_() {
  rm -rf "$TMP/app"; mkdir -p "$TMP/app/src"
  pkg=cb; val=$2
  case $2 in cc:*) pkg=cc; val=${2#cc:};; esac
  printf '[package]\nname = "capp"\nkind = "lib"\n\n[dependencies]\n"%s" = "%s"\n' "$pkg" "$val" > "$TMP/app/bats.toml"
  printf '#use ca as A\n#use cb as B\n\n#pub fun g (): int\n\nimplement g () = 2\n' > "$TMP/app/src/lib.bats"
  rc=0
  (cd "$TMP/app" && "$BATS" lock --repository "$TMP/repo") > /dev/null 2> "$TMP/err" || rc=$?
  if [ "$rc" = 0 ]; then got=$(cut -d' ' -f1,2 "$TMP/app/bats.lock" | tr '\n' ';'); else got=$(tail -1 "$TMP/err"); fi
  [ "$rc" = "$3" ] && [ "$got" = "$4" ] || { echo "FAIL: $1: rc $rc, got: $got"; cat "$TMP/err"; exit 1; }
}
case_ "no constraint" "" 0 "cb 2026.1.5.5;ca 2026.1.1.1;cc 2026.1.3.3;"
case_ ">= met" ">= 2026.1.2" 0 "cb 2026.1.5.5;ca 2026.1.1.1;cc 2026.1.3.3;"
case_ "!= the latest" "!= 2026.1.5.5" 0 "cb 2026.1.2.2;ca 2026.1.1.1;cc 2026.1.3.3;"
case_ "!= more parts" "!= 2026.1.5.5.0" 0 "cb 2026.1.5.5;ca 2026.1.1.1;cc 2026.1.3.3;"
case_ "!= unnormalized" "!= 2026.01.+5.5" 0 "cb 2026.1.2.2;ca 2026.1.1.1;cc 2026.1.3.3;"
case_ "spaces and empty parts" "  ,>=2026.1.2 ,  , !=  2026.1.2.2  ," 0 "cb 2026.1.5.5;ca 2026.1.1.1;cc 2026.1.3.3;"
case_ ">= unmet" ">= 2026.1.6" 1 "error: no version of 'cb' satisfies all constraints: >= 2026.1.6 (from capp)"
case_ "conflict" ">= 2026.1.5, != 2026.1.5.5" 1 "error: no version of 'cb' satisfies all constraints: >= 2026.1.5 (from capp), != 2026.1.5.5 (from capp)"
case_ "a dependency's constraint" "cc:>= 2026.1.4" 1 "error: no version of 'cc' satisfies all constraints: >= 2026.1.4 (from capp), != 2026.1.4.4 (from ca)"
case_ "bad operator" "< 2026" 1 "error: in [dependencies] 'cb': invalid constraint '< 2026': must start with >= or !="
case_ "bad part" ">= 2026.x.1" 1 "error: in [dependencies] 'cb': invalid version part 'x' in '2026.x.1'"
case_ "no version" ">=" 1 "error: in [dependencies] 'cb': invalid version part '' in ''"
echo "lock-constraints: ok"
