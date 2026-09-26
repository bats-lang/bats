#!/bin/sh
# mac#, ext#, while (but not while*), castfn, praxi, extern and assume are
# unsafe outside $UNSAFE begin...end, as in the Rust bats; they used to be
# accepted except castfn and friends, which were also wrongly flagged inside
# longer identifiers. #pub castfn/praxi/extern/assume are rejected too
# (the Rust bats let them through). Comments, strings and while* stay
# allowed.
# usage: tests/restricted-keywords/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
n=0
lib() { # <unsafe> <body>: a scratch library in $TMP/p$n
  n=$((n + 1)); d=$TMP/p$n
  mkdir -p "$d/src"
  printf '[package]\nname = "rk%s"\nkind = "lib"\nunsafe = %s\n' "$n" "$1" > "$d/bats.toml"
  printf '%s\n' "$2" > "$d/src/lib.bats"
}
reject() { # <body>
  lib false "$1"
  if (cd "$d" && "$BATS" check) > "$d/log" 2>&1; then
    echo "FAIL: accepted: $1"; exit 1
  fi
  grep -q 'not allowed outside' "$d/log" || { echo "FAIL: rejected, but not as an unsafe construct: $1"; grep error "$d/log" | head -3; exit 1; }
}
accept() { # <unsafe> <body>
  lib "$1" "$2"
  (cd "$d" && "$BATS" check) > "$d/log" 2>&1 || { echo "FAIL: rejected: $2"; grep error "$d/log" | head -3; exit 1; }
}
reject 'val x = mac#foo'
reject 'val x = ext#bar'
reject 'fn f (): void = while (false) ()'
reject 'castfn to_int (x: uint): int'
reject 'praxi lemma (): void'
reject 'extern fn foo (): void'
reject '#pub castfn to_int (x: uint): int'
reject '#pub praxi lemma (): void'
accept false 'fn count (): void = let
  var i: int = 3
  val () = while* {k:nat} .<k>. (i: int(k)) => (i > 0) (i := i - 1)
in end'
accept false '(* mac#foo ext#bar while castfn *)
// praxi extern assume
val s = "mac#foo while castfn"
val mycastfn = 1
val the_while = 2
val my_extern = 3
#pub fn castfn_like (): int
implement castfn_like () = 1'
accept true '$UNSAFE begin
val x = while (false) ()
end'
echo "restricted-keywords: ok"
