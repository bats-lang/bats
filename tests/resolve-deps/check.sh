#!/bin/sh
# check, build, run and test first make sure every #use package of src/
# is in bats_modules, as the Rust bats's build::resolve_deps does: without
# --repository a missing one is an error; with it, it is fetched (the
# newest version that meets the project's constraints). A path
# dependency is never fetched.
# usage: tests/resolve-deps/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo"
publish() { # <name> <commit date>
  rm -rf "$TMP/p"; mkdir -p "$TMP/p/src"
  printf '[package]\nname = "%s"\nkind = "lib"\n' "$1" > "$TMP/p/bats.toml"
  printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/p/src/lib.bats"
  printf 'build/\ndist/\ndocs/\nbats_modules/\nbats.lock\n' > "$TMP/p/.gitignore"
  (cd "$TMP/p" && git init -q -b main . && git add -A &&
   GIT_COMMITTER_DATE="$2" git -c user.name=t -c user.email=t@t commit -q -m "$2" &&
   "$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1) || { echo "FAIL: upload $1"; cat "$TMP/up.log"; exit 1; }
}
publish ra "2026-01-01T00:00:01Z"
publish ra "2026-01-02T00:00:02Z"
publish rb "2026-01-03T00:00:03Z"
app() { # <[dependencies] lines>
  rm -rf "$TMP/app"; mkdir -p "$TMP/app/src"
  printf '[package]\nname = "rapp"\nkind = "lib"\n%s' "$1" > "$TMP/app/bats.toml"
  printf '#use ra as A\n#use rb as B\n\n#pub fun g (): int\n\nimplement g () = 2\n' > "$TMP/app/src/lib.bats"
}
app ""
rc=0; (cd "$TMP/app" && "$BATS" check) > /dev/null 2> "$TMP/err" || rc=$?
[ "$rc" != 0 ] && grep -qx "error: missing dependencies: ra, rb. Use --repository <dir> to fetch them." "$TMP/err" ||
  { echo "FAIL: no --repository"; cat "$TMP/err"; exit 1; }
(cd "$TMP/app" && "$BATS" check --repository "$TMP/repo") > /dev/null 2> "$TMP/err" || { echo "FAIL: fetch"; cat "$TMP/err"; exit 1; }
head -2 "$TMP/err" | tr '\n' '|' | grep -qx "fetched ra v2026.1.2.2|fetched rb v2026.1.3.3|" || { echo "FAIL: fetch messages"; cat "$TMP/err"; exit 1; }
app '[dependencies]
"ra" = "!= 2026.1.2.2"
'
(cd "$TMP/app" && "$BATS" check --repository "$TMP/repo") > /dev/null 2> "$TMP/err" || { echo "FAIL: constraint"; cat "$TMP/err"; exit 1; }
head -1 "$TMP/err" | grep -qx "fetched ra v2026.1.1.1" || { echo "FAIL: constraint not honored"; cat "$TMP/err"; exit 1; }
echo "resolve-deps: ok"
