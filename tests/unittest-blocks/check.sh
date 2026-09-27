#!/bin/sh
# $UNITTEST blocks are code, lexed and checked as any other code:
#  * an unsafe construct in one is rejected as anywhere else (the Rust
#    bats copied a block's text verbatim, unchecked);
#  * bats check type-checks what is in them, as the Rust bats's check
#    (preprocess_all with check_mode) does, while bats build leaves them
#    out;
#  * a block closes at its own end, not at the first end of a let inside
#    it (the Rust bats closed it there), and a keyword in a comment or a
#    string, or at the end of a name (book_begin), is not one;
#  * a bad $UNITTEST.run target list, or a block with no end, is an
#    error with Rust's message.
# A nested #target block keeps its code (it was dropped).
# usage: tests/unittest-blocks/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
n=0
lib() { # <body>: a scratch library in $TMP/p$n
  n=$((n + 1)); d=$TMP/p$n
  mkdir -p "$d/src"
  printf '[package]\nname = "ut%s"\nkind = "lib"\n' "$n" > "$d/bats.toml"
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
  (cd "$d" && "$BATS" check) > "$d/log" 2>&1 || { echo "FAIL: rejected: $1"; grep error "$d/log" | head -5; exit 1; }
}
reject "'castfn' is not allowed outside" '$UNITTEST.run begin
castfn cheat (x: int): bool
end'
reject "'fun' without termination metric" '$UNITTEST begin
fun spin (x: int): int = spin(x + 1)
end'
# a type error in a test is a check error
reject "the symbol [=] cannot be resolved" '#pub fn one (): int
implement one () = 1
$UNITTEST.run begin
fn test_bad (): bool = one() = "one"
end'
# a let inside the block does not close it
accept '#pub fn one (): int
implement one () = 1
$UNITTEST.run(native, wasm) begin
fn test_one (): bool = let
  val x = one()
in x = 1 end
fn test_two (): bool = one() + one() = 2
end'
# a let or begin in a comment, an end in a string, a '"' char, do not count
body=$(cat <<'B'
$UNITTEST.run begin
(* a let, and a begin, in a comment *)
// begin
fn test_s (): bool = let val s = "the end" in true end
fn test_c (): bool = '"' = '"'
end
B
)
accept "$body"
# a name that ends in begin, let or local (book_begin) is not the keyword:
# it opens nothing, so the block still closes at its own end
accept '#pub fn book_begin (): int
implement book_begin () = 1
#target native begin
fn outlet (): int = book_begin() + 1
fn nonlocal (): int = outlet()
end
$UNITTEST.run begin
fn test_b (): bool = book_begin() = 1
end'
reject "empty target list in \$UNITTEST.run()" '$UNITTEST.run() begin
fn test_x (): bool = true
end'
reject "unknown test target 'arm'; expected 'native' or 'wasm'" '$UNITTEST.run(native, arm) begin
fn test_x (): bool = true
end'
reject "unterminated \$UNITTEST.run begin...end block" '$UNITTEST.run begin
fn test_x (): bool = true'
# build leaves a block out: a binary whose test does not type-check builds
d=$TMP/bin; mkdir -p "$d/src/bin"
printf '[package]\nname = "utbin"\nkind = "bin"\n' > "$d/bats.toml"
cat > "$d/src/bin/utbin.bats" <<'B'
#include "share/atspre_staload.hats"

$UNITTEST.run begin
fn test_bad (): bool = 1 = "one"
end

implement main0 () = println! ("built")
B
(cd "$d" && "$BATS" build --only debug --only native) > "$d/log" 2>&1 || { echo "FAIL: build did not leave the test out"; grep error "$d/log" | head -3; exit 1; }
[ "$("$d/dist/debug/utbin")" = built ] || { echo "FAIL: binary"; exit 1; }
# a #target block inside a #target block keeps its code
cat > "$d/src/bin/utbin.bats" <<'B'
#include "share/atspre_staload.hats"

#target native begin
#target native begin
fn msg (): string = "nested"
end
end

implement main0 () = println! (msg())
B
(cd "$d" && "$BATS" build --only debug --only native) > "$d/log" 2>&1 || { echo "FAIL: nested #target"; grep error "$d/log" | head -3; exit 1; }
[ "$("$d/dist/debug/utbin")" = nested ] || { echo "FAIL: nested #target binary"; exit 1; }
echo "unittest-blocks: ok"
