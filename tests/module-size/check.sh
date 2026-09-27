#!/bin/sh
# A module of any size builds, as in the Rust bats: it is read whole (an
# arena piece sized to the file) and its .sats and .dats are written from
# ropes, not from 524288-byte buffers.
# usage: tests/module-size/check.sh <bats-binary>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0

# A package whose src/bin/main.bats is a string of $1 bytes of x (a
# string, which the emitter copies, not a comment, which it blanks) and a
# main0 that prints its length
make_pkg() {
  rm -rf "$TMP/p" && mkdir -p "$TMP/p/src/bin"
  printf '[package]\nname = "p"\nkind = "bin"\n' > "$TMP/p/bats.toml"
  {
    printf '#include "share/atspre_staload.hats"\nval big = "'
    head -c "$1" /dev/zero | tr '\0' x
    printf '"\nimplement main0 () = println! (length(big))\n'
  } > "$TMP/p/src/bin/main.bats"
}

# 1000: well under 524288. 524230: the module fits 524288 bytes but its
# .dats does not. 600000: the module does not either. 2000000: nor does
# it fit one alloc (1048576).
for n in 1000 524230 600000 2000000; do
  make_pkg $n
  if ! (cd "$TMP/p" && "$BATS" build --only debug --only native && ./dist/debug/main) > "$TMP/out" 2>&1; then
    echo "FAIL: a $n-byte string module did not build and run:"; tail -5 "$TMP/out"; fail=1
  elif ! grep -qx "$n" "$TMP/out"; then
    echo "FAIL: the $n-byte string module printed:"; tail -5 "$TMP/out"; fail=1
  fi
done

[ $fail -eq 0 ] && echo "module-size: ok"
exit $fail
