#!/bin/sh
# The end that closes $UNSAFE begin is found in code only: the word
# "end" in the C of a %{ ... %} block (here, in a comment) used to close
# the block early, so the C after it was checked as bats ("unsafe
# construct ... outside $UNSAFE block" for its while) and patsopt
# rejected the real end. (The Rust bats has the same bug; this is an
# allowed divergence.)
# usage: tests/unsafe-extcode-end/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src"
printf '[package]\nname = "extend"\nkind = "lib"\nunsafe = true\n' > "$TMP/p/bats.toml"
cat > "$TMP/p/src/lib.bats" <<'SRC'
#include "share/atspre_staload.hats"

$UNSAFE begin
%{
/* reads to the end; then stops */
static int _extend_sq(int x) {
  int i = 0;
  while (i < 1) { i++; }
  return x * x;
}
%}
end

#pub fun sq (x: int): int

implement sq (x) = x * x
SRC
cd "$TMP/p"
"$BATS" check > check.log 2>&1 || { echo "FAIL: check"; grep -E "error" check.log | head -5; exit 1; }
echo "unsafe-extcode-end: ok"
