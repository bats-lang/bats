#!/bin/sh
# bats upload reports on stderr with the Rust bats' messages and leaves
# stdout empty: "uploaded <name> v<version> to <repository>" on success,
# and its errors for a missing --repository and a binary package. It used
# to print "uploaded successfully" and its errors on stdout.
# usage: tests/upload-messages/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo" "$TMP/lib/src" "$TMP/app/src/bin"
printf '[package]\nname = "msgs"\nversion = "1.0.0"\nkind = "lib"\n' > "$TMP/lib/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/lib/src/lib.bats"
printf '[package]\nname = "msgsapp"\nversion = "1.0.0"\nkind = "bin"\n' > "$TMP/app/bats.toml"
printf 'implement main0 () = ()\n' > "$TMP/app/src/bin/msgsapp.bats"
expect() { # <dir> <want stderr line> <upload args...>
  d=$1; want=$2; shift 2
  (cd "$d" && "$BATS" upload "$@") > "$TMP/out" 2> "$TMP/err" || true
  [ ! -s "$TMP/out" ] || { echo "FAIL: stdout not empty:"; cat "$TMP/out"; exit 1; }
  grep -qxF -- "$want" "$TMP/err" || { echo "FAIL: want on stderr: $want"; cat "$TMP/err"; exit 1; }
}
expect "$TMP/lib" "uploaded msgs v1.0.0 to $TMP/repo" --repository "$TMP/repo"
expect "$TMP/lib" "error: 'bats upload' requires --repository <dir>"
expect "$TMP/app" "error: 'bats upload' is only for library packages (kind = \"lib\")" --repository "$TMP/repo"
if (cd "$TMP/lib" && "$BATS" upload) > /dev/null 2>&1; then echo "FAIL: upload without --repository succeeded"; exit 1; fi
echo "upload-messages: ok"
