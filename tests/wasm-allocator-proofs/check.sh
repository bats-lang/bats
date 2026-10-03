#!/bin/sh
# The wasm runtime's allocator is proven (src/allocator.bats,
# bats-lang/bats#241): the source a wasm build writes out checks as a
# module of an unsafe package, and each of these, made from that very
# source, does not:
# - a walk of a free list without its length as the metric;
# - a freed block put on two lists;
# - a block freed twice inside the allocator.
# Each faulty variant has a control, the same code doing it once, that
# checks, so what is rejected is the fault alone.
# usage: tests/wasm-allocator-proofs/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# The allocator's source, as a wasm build writes it out
mkdir -p "$TMP/w/src/bin"
printf '[package]\nname = "aw"\nkind = "bin"\n' > "$TMP/w/bats.toml"
printf '#target wasm binary\n\nimplement main0 () = ()\n' > "$TMP/w/src/bin/web.bats"
(cd "$TMP/w" && "$BATS" build --only debug) > "$TMP/build.log" 2>&1 || { echo "FAIL: wasm build"; cat "$TMP/build.log"; exit 1; }
SOURCE=$TMP/w/build/_bats_wasm_allocator.bats
[ -s "$SOURCE" ] || { echo "FAIL: no allocator source in build/"; exit 1; }
n=0
package() { # <source file>: a package whose module is that source
  n=$((n + 1)); d=$TMP/p$n
  mkdir -p "$d/src"
  printf '[package]\nname = "ap%s"\nkind = "lib"\nunsafe = true\n' "$n" > "$d/bats.toml"
  cp "$1" "$d/src/lib.bats"
}
accepted() { # <what> <source file>
  package "$2"
  (cd "$d" && "$BATS" check) > "$d/log" 2>&1 || { echo "FAIL: rejected: $1"; cat "$d/log"; exit 1; }
}
rejected() { # <what> <expected message part> <source file>
  package "$3"
  if (cd "$d" && "$BATS" check) > "$d/log" 2>&1; then echo "FAIL: accepted: $1"; exit 1; fi
  grep -qF -- "$2" "$d/log" || { echo "FAIL: $1 rejected, but not with '$2':"; cat "$d/log"; exit 1; }
}
appended() { # <code> <out>: the source with the code after it
  cp "$SOURCE" "$2"
  printf '\n%s\n' "$1" >> "$2"
}
accepted "the allocator" "$SOURCE"

# The region walk without its metric
grep -q '^fun region_take .*\.<count>\.$' "$SOURCE" || { echo "FAIL: no region_take with its metric"; exit 1; }
sed 's/^\(fun region_take .*\) \.<count>\.$/\1/' "$SOURCE" > "$TMP/no_metric.bats"
rejected "a walk without its metric" "without termination metric is not allowed outside" "$TMP/no_metric.bats"

# A freed block of 64 bytes put on bucket 32's list, then on the regions'
once='fn freed_once {l:agz} (block: block_v(l, 64) | p: ptr l): void = let
  val (pf_heads | heads) = heads_take()
  val () = heads_push(pf_heads, BUCKET_32(), block | heads, 0, 0, p)
  prval () = heads_give(pf_heads)
in end'
appended "$once" "$TMP/once.bats"
accepted "a block put on one list" "$TMP/once.bats"
appended "fn on_two_lists {l:agz} (block: block_v(l, 64) | p: ptr l): void = let
  val (pf_heads | heads) = heads_take()
  val () = heads_push(pf_heads, BUCKET_32(), block | heads, 0, 0, p)
  prval () = heads_give(pf_heads)
  val () = free_region(block | p, 64)
in end" "$TMP/two_lists.bats"
rejected "a block put on two lists" "the linear dynamic variable [block" "$TMP/two_lists.bats"

# The same block pushed twice on bucket 32's list
appended "fn freed_twice {l:agz} (block: block_v(l, 64) | p: ptr l): void = let
  val (pf_heads | heads) = heads_take()
  val () = heads_push(pf_heads, BUCKET_32(), block | heads, 0, 0, p)
  val () = heads_push(pf_heads, BUCKET_32(), block | heads, 0, 0, p)
  prval () = heads_give(pf_heads)
in end" "$TMP/twice.bats"
rejected "a block freed twice" "the linear dynamic variable [block" "$TMP/twice.bats"
echo "wasm-allocator-proofs: ok"
