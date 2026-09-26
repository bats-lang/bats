#!/bin/sh
# build and run first load bats.toml as Rust's config::load does, then
# refuse a package that is not kind = "bin", before resolving any
# dependency (Rust: cmd_build, build::build).
# usage: tests/build-kind/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
case_() { # <name> <command> <bats.toml, or NONE> <expected stderr line>
  rm -rf "$TMP/p"; mkdir -p "$TMP/p/src/bin"
  printf '#use arith as AR\nimplement main0 () = ()\n' > "$TMP/p/src/bin/x.bats"
  [ "$3" = NONE ] || printf "$3" > "$TMP/p/bats.toml"
  rc=0
  (cd "$TMP/p" && "$BATS" $2) > /dev/null 2> "$TMP/err" || rc=$?
  [ "$rc" = 1 ] && [ "$(cat "$TMP/err")" = "$4" ] || { echo "FAIL: $1: rc $rc"; cat "$TMP/err"; exit 1; }
}
case_ "build a lib" build '[package]\nname = "x"\nkind = "lib"\n' "error: 'bats build' is only for binary packages (kind = \"bin\")"
case_ "run a lib" run '[package]\nname = "x"\n' "error: 'bats build' is only for binary packages (kind = \"bin\")"
case_ "no bats.toml" build NONE "error: cannot read './bats.toml': No such file or directory (os error 2)"
case_ "unknown kind" run '[package]\nname = "x"\nkind = "exe"\n' "error: unknown package kind: 'exe'"
case_ "a bin, then its dependencies" build '[package]\nname = "x"\nkind = "bin"\n' \
  "error: missing dependencies: arith. Use --repository <dir> to fetch them."
echo "build-kind: ok"
