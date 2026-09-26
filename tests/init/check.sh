#!/bin/sh
# bats init as the Rust bats did it: the project is named after the
# current directory; bats.toml, the source file and .gitignore have the
# Rust contents; existing files are listed and left alone; only
# binary/bin/library/lib are kinds. It used to name every project "."
# (via a /tmp placeholder) and accept any word starting with b or l.
# usage: tests/init/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

mkdir -p "$TMP/myproj" && cd "$TMP/myproj"
"$BATS" init binary 2> err.log || fail "init binary exited $?"
[ "$(cat bats.toml)" = "$(printf '[package]\nname = "myproj"\nkind = "bin"')" ] || fail "bats.toml: $(cat bats.toml)"
[ "$(cat src/bin/myproj.bats)" = 'implement main0 () = println! ("hello, world!")' ] || fail "source: $(cat src/bin/myproj.bats)"
[ "$(cat .gitignore)" = "$(printf 'build/\ndist/\ndocs/\nbats_modules/')" ] || fail ".gitignore: $(cat .gitignore)"
grep -qx "created binary project 'myproj'" err.log || fail "message: $(cat err.log)"

rc=0; "$BATS" init bin 2> err2.log || rc=$?
[ "$rc" = 1 ] || fail "second init exited $rc"
[ "$(cat err2.log)" = "$(printf 'error: refusing to overwrite existing files:\n  bats.toml\n  src/bin/myproj.bats\n  .gitignore')" ] || fail "conflicts: $(cat err2.log)"

mkdir -p "$TMP/mylib" && cd "$TMP/mylib"
"$BATS" init lib 2> err.log || fail "init lib exited $?"
[ "$(cat bats.toml)" = "$(printf '[package]\nname = "mylib"\nkind = "lib"')" ] || fail "lib bats.toml: $(cat bats.toml)"
[ -f src/lib.bats ] || fail "no src/lib.bats"
grep -qx "created lib project 'mylib'" err.log || fail "lib message: $(cat err.log)"

mkdir -p "$TMP/other" && cd "$TMP/other"
rc=0; "$BATS" init banana 2> err.log || rc=$?
[ "$rc" = 1 ] || fail "init banana exited $rc"
grep -qx "error: unknown project kind 'banana', use 'binary' or 'library'" err.log || fail "banana: $(cat err.log)"
[ ! -f bats.toml ] || fail "init banana wrote bats.toml"
echo "init: ok"
