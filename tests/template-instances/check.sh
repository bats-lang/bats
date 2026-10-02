#!/bin/sh
# `bats check` fails when patsopt leaves a template instance with no
# implementation (PMVtmpltcstmat in the C it emits), which only cc
# would reject: the message names the template and the .bats line that
# uses it. The same instance passes once the template is implemented
# for it, and a template implemented generically passes too.
# usage: tests/template-instances/check.sh <bats-binary>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
n=0
lib() { # <body>
  n=$((n + 1)); d=$TMP/p$n
  mkdir -p "$d/src"
  printf '[package]\nname = "ti%s"\nkind = "lib"\nunsafe = false\n' "$n" > "$d/bats.toml"
  printf '#include "share/atspre_staload.hats"\n%s\n' "$1" > "$d/src/lib.bats"
}
lib '#pub fn{a:t@ype} dispose (x: a): void
#pub fn use_dispose (x: int): void
implement use_dispose (x) = dispose<int>(x)'
if (cd "$d" && "$BATS" check) > "$d/log" 2>&1; then
  echo "FAIL: check passed with an unimplemented template instance"; exit 1
fi
grep -qF "error: template 'dispose' has no implementation for the instance dispose<" "$d/log" ||
  { echo "FAIL: the message does not name the template"; cat "$d/log"; exit 1; }
grep -qF "src/lib.bats: " "$d/log" && grep -qF "(line=4, " "$d/log" ||
  { echo "FAIL: the message does not point to the .bats line"; cat "$d/log"; exit 1; }
# Not taken for fresh on the next run: it fails again
if (cd "$d" && "$BATS" check) > "$d/log2" 2>&1; then
  echo "FAIL: a second check passed"; exit 1
fi
lib '#pub fn{a:t@ype} dispose (x: a): void
implement dispose<int> (x) = ()
#pub fn use_dispose (x: int): void
implement use_dispose (x) = dispose<int>(x)'
(cd "$d" && "$BATS" check) > "$d/log" 2>&1 || { echo "FAIL: rejected an implemented instance"; cat "$d/log"; exit 1; }
lib '#pub fn{a:t@ype} dispose (x: a): void
implement{a} dispose (x) = ()
#pub fn use_dispose (x: int): void
implement use_dispose (x) = dispose<int>(x)'
(cd "$d" && "$BATS" check) > "$d/log" 2>&1 || { echo "FAIL: rejected a generic implementation"; cat "$d/log"; exit 1; }
echo "template-instances: ok"
