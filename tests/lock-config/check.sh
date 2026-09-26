#!/bin/sh
# bats lock reads bats.toml as the Rust bats's config::load does, and
# fails with its messages: a bats.toml it cannot read (with the OS error),
# an unknown [package] kind, or a path dependency in a lib package. A
# constraint that does not parse is reported before a path dependency.
# usage: tests/lock-config/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$(cd "$2" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
case_() { # <name> <bats.toml content, NONE, or DIR> <rc> <expected last stderr line>
  rm -rf "$TMP/p"; mkdir -p "$TMP/p/src"
  printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/p/src/lib.bats"
  case $2 in NONE) ;; DIR) mkdir "$TMP/p/bats.toml" ;; *) printf "$2" > "$TMP/p/bats.toml" ;; esac
  rc=0
  (cd "$TMP/p" && "$BATS" lock --repository "$REPO") > /dev/null 2> "$TMP/err" || rc=$?
  got=$(tail -1 "$TMP/err")
  [ "$rc" = "$3" ] && [ "$got" = "$4" ] || { echo "FAIL: $1: rc $rc, got: $got"; exit 1; }
}
case_ "no bats.toml" NONE 1 "error: cannot read './bats.toml': No such file or directory (os error 2)"
case_ "a directory" DIR 1 "error: cannot read './bats.toml': Is a directory (os error 21)"
case_ "unknown kind" '[package]\nname = "x"\nkind = "exe"\n' 1 "error: unknown package kind: 'exe'"
case_ "bin" '[package]\nname = "x"\nkind = "bin"\n' 0 "wrote bats.lock (no dependencies)"
case_ "path dependency in a lib" '[package]\nname = "x"\n[dependencies]\n"y" = { path = "../y" }\n' 1 \
  'error: path dependencies are only supported in binary packages (kind = "bin")'
case_ "a bad constraint first" '[package]\nname = "x"\n[dependencies]\n"y" = { path = "../y" }\n"z" = "< 1"\n' 1 \
  "error: in [dependencies] 'z': invalid constraint '< 1': must start with >= or !="
echo "lock-config: ok"
