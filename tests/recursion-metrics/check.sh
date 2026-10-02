#!/bin/sh
# Every recursion needs a termination metric outside $UNSAFE, as a fun
# does: fnx, a fun group's and members, fix lambdas, and val rec (which
# cannot carry one) are rejected without it. The Rust bats checked only
# the fun keyword, so these recursed with no termination proof. The
# same forms with metrics, and the and of datatype and val groups, stay
# allowed.
# usage: tests/recursion-metrics/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
n=0
lib() { # <body>: a scratch library in $TMP/p$n
  n=$((n + 1)); d=$TMP/p$n
  mkdir -p "$d/src"
  printf '[package]\nname = "rm%s"\nkind = "lib"\n' "$n" > "$d/bats.toml"
  printf '#include "share/atspre_staload.hats"\n\n%s\n' "$1" > "$d/src/lib.bats"
}
reject() { # <message> <body>
  lib "$2"
  if (cd "$d" && "$BATS" check) > "$d/log" 2>&1; then
    echo "FAIL: accepted: $2"; exit 1
  fi
  grep -qF "$1" "$d/log" || { echo "FAIL: rejected, but not with \"$1\": $2"; grep error "$d/log" | head -3; exit 1; }
}
accept() { # <body>
  lib "$1"
  (cd "$d" && "$BATS" check) > "$d/log" 2>&1 || { echo "FAIL: rejected: $1"; grep error "$d/log" | head -3; exit 1; }
}
reject "'fnx' without termination metric" 'fnx spin (x: int): int = spin(x + 1)'
reject "'and' without termination metric" 'fun f {n:nat} .<n>. (x: int n): int = if x = 0 then g(0) else f(x - 1)
and g (x: int): int = g(x + 1)'
reject "'and' without termination metric" 'fn outer (): int = let
  fun f {n:nat} .<n>. (x: int n): int = if x = 0 then g(0) else f(x - 1)
  and g (x: int): int = g(x + 1)
in f(3) end'
reject "'fix' without termination metric" 'val h = fix loop (x: int): int => loop(x + 1)'
reject "'val rec' is not allowed" 'val rec r: int -<cloref1> int = lam (x) => r(x + 1)'
accept 'fnx f {n:nat} .<n>. (x: int n): int = if x = 0 then 0 else f(x - 1)'
accept 'fun f {n:nat} .<n, 0>. (x: int n): int = if x = 0 then 0 else g(x - 1)
and g {n:nat} .<n, 1>. (x: int n): int = f(x)'
accept 'val h = fix loop {n:nat} .<n>. (x: int n): int => if x = 0 then 0 else loop(x - 1)'
accept 'datavtype tree = Leaf of () | Node of (tree, forest)
and forest = FNil of () | FCons of (tree, forest)'
accept 'val a = 1
and b = 2'
echo "recursion-metrics: ok"
