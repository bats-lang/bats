#!/bin/sh
# bats lock treats a { path = "<dir>" } dependency as the Rust bats does
# (lock::resolve_all): it is not locked or fetched, even where another
# package uses it; the #use packages of <dir>/src are resolved in its
# place, under the constraints of <dir>/bats.toml.
# usage: tests/lock-path-deps/check.sh <bats-binary> <repository-dir>
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
publish pc "2026-01-03T00:00:03Z" ""
publish pc "2026-01-04T00:00:04Z" ""
publish pb "2026-01-02T00:00:02Z" "#use pmine as M"
case_() { # <name> <pmine [dependencies] lines> <expected lock "pkg ver;...">
  rm -rf "$TMP/w"; mkdir -p "$TMP/w/app/src/bin" "$TMP/w/pmine/src"
  printf '[package]\nname = "pmine"\nkind = "lib"\n%s' "$2" > "$TMP/w/pmine/bats.toml"
  printf '#use pc as C\n#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/w/pmine/src/lib.bats"
  printf '[package]\nname = "papp"\nkind = "bin"\n\n[dependencies]\n"pmine" = { path = "../pmine" }\n' > "$TMP/w/app/bats.toml"
  printf '#use pmine as M\n#use pb as B\n\nimplement main0 () = ()\n' > "$TMP/w/app/src/bin/papp.bats"
  (cd "$TMP/w/app" && "$BATS" lock --repository "$TMP/repo") > /dev/null 2> "$TMP/err" || { echo "FAIL: $1: lock"; cat "$TMP/err"; exit 1; }
  got=$(cut -d' ' -f1,2 "$TMP/w/app/bats.lock" | tr '\n' ';')
  [ "$got" = "$3" ] || { echo "FAIL: $1: got $got"; exit 1; }
  [ ! -e "$TMP/w/app/bats_modules/pmine" ] || { echo "FAIL: $1: fetched the path dependency"; exit 1; }
}
case_ "its #use packages" "" "pc 2026.1.4.4;pb 2026.1.2.2;"
case_ "its constraints" '[dependencies]
"pc" = "!= 2026.1.4.4"
' "pc 2026.1.3.3;pb 2026.1.2.2;"
echo "lock-path-deps: ok"
