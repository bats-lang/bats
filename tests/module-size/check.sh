#!/bin/sh
# A module is read into 524288 bytes and its .dats is written from a
# builder of 524288 bytes. A module larger than that, or one whose .dats
# would be, is an error, not a build of its first 524288 bytes.
# usage: tests/module-size/check.sh <bats-binary>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0

# A package whose src/bin/main.bats is main0 and then a string of $1
# bytes of x (a string, which the emitter copies, not a comment, which
# it blanks)
make_pkg() {
  rm -rf "$TMP/p" && mkdir -p "$TMP/p/src/bin"
  printf '[package]\nname = "p"\nkind = "bin"\n' > "$TMP/p/bats.toml"
  {
    printf 'implement main0 () = println! ("hi")\nval big = "'
    head -c "$1" /dev/zero | tr '\0' x
    printf '"\n'
  } > "$TMP/p/src/bin/main.bats"
}

# Larger than a module can be read into
make_pkg 600000
if (cd "$TMP/p" && "$BATS" check) > "$TMP/out" 2>&1; then
  echo "FAIL: a 600 KB module passed bats check"; fail=1
elif ! grep -q "src/bin/main.bats is larger than 524288 bytes" "$TMP/out"; then
  echo "FAIL: no size error for a 600 KB module:"; head -5 "$TMP/out"; fail=1
fi

# Read whole, but its .dats (the module and what the emitter adds) is
# larger than the builder holds
make_pkg 524230
if (cd "$TMP/p" && "$BATS" check) > "$TMP/out" 2>&1; then
  echo "FAIL: a module whose .dats is over 524288 bytes passed bats check"; fail=1
elif ! grep -q "is larger than 524288 bytes, the most bats can write" "$TMP/out"; then
  echo "FAIL: no output size error:"; head -5 "$TMP/out"; fail=1
fi

# Well under both: builds and runs
make_pkg 1000
if ! (cd "$TMP/p" && "$BATS" build --only debug --only native && ./dist/debug/main) > "$TMP/out" 2>&1; then
  echo "FAIL: a small module did not build:"; tail -5 "$TMP/out"; fail=1
elif ! grep -qx "hi" "$TMP/out"; then
  echo "FAIL: the small module printed:"; cat "$TMP/out"; fail=1
fi

[ $fail -eq 0 ] && echo "module-size: ok"
exit $fail
