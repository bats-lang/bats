#!/bin/sh
# `bats check` fails when a lambda whose kind is a plain function (FUN)
# captures a variable: patsopt emits ATSERRORnotenvless for it, which
# only cc would reject. The message points to the .bats line. A plain
# function that captures nothing, and a linear closure that captures,
# pass (freeing the closure takes $UNSAFE, as in promise).
# usage: tests/capturing-function/check.sh <bats-binary>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
n=0
lib() { # <body> [unsafe]
  n=$((n + 1)); d=$TMP/p$n
  mkdir -p "$d/src"
  printf '[package]\nname = "cf%s"\nkind = "lib"\nunsafe = %s\n' "$n" "${2:-false}" > "$d/bats.toml"
  printf '#include "share/atspre_staload.hats"\n%s\n' "$1" > "$d/src/lib.bats"
}
reject() { # <line> <body>
  lib "$2"
  if (cd "$d" && "$BATS" check) > "$d/log" 2>&1; then
    echo "FAIL: check passed a capturing plain function: $2"; exit 1
  fi
  grep -qF "captures a variable, which a plain function cannot carry" "$d/log" ||
    { echo "FAIL: not rejected as a capturing function: $2"; cat "$d/log"; exit 1; }
  grep -qF "(line=$1, " "$d/log" ||
    { echo "FAIL: the message does not point to line $1: $2"; cat "$d/log"; exit 1; }
}
accept() { # <body> [unsafe]
  lib "$1" "${2:-false}"
  (cd "$d" && "$BATS" check) > "$d/log" 2>&1 || { echo "FAIL: rejected: $1"; cat "$d/log"; exit 1; }
}
reject 4 '#pub fn add (k: int): int
implement add (k) = let
  val f = lam (x: int): int =<fun1> x + k
in f(1) end'
reject 4 'fn apply (f: (int) -<fun1> int): int = f(1)
#pub fn add (k: int): int
implement add (k) = apply(lam (x: int): int =<fun1> x + k)'
accept 'fn apply (f: (int) -<fun1> int): int = f(1)
#pub fn add_one (): int
implement add_one () = apply(lam (x: int): int =<fun1> x + 1)'
accept 'fn apply (f: (int) -<lincloptr1> int): int = let
  val r = f(1)
  val () = cloptr_free($UNSAFE begin $UNSAFE.castvwtp0{cloptr0}(f) end)
in r end
#pub fn add (k: int): int
implement add (k) = apply(llam (x) => x + k)' true
echo "capturing-function: ok"
