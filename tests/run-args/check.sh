#!/bin/sh
# `bats run -- <args>` passes <args> to the program, empty ones
# included; they used to be dropped. The program exits 0 only when its
# arguments are exactly x, "" and "y z"; bats run exits with its status.
# usage: tests/run-args/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$(cd "$2" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "runargs"\nkind = "bin"\n\n[dependencies]\n"array" = ""\n"env" = ""\n"result" = ""\n' > "$TMP/p/bats.toml"
cat > "$TMP/p/src/bin/runargs.bats" <<'B'
#include "share/atspre_staload.hats"
#use array as A
#use env as E
#use result as R

(* The position after argv[0]'s NUL in b[0, k), or k. *)
fun skip0 {l:agz}{k:nat | k <= 256}{i:nat | i <= k} .<k - i>.
  (b: !$A.arr(byte, l, 256), k: int k, i: int i): [j:nat | j <= k] int j =
  if i >= k then i
  else if byte2int0($A.get<byte>(b, i)) = 0 then i + 1
  else skip0(b, k, i + 1)

(* b[s, k) = w[0, n) *)
fun same {l:agz}{k:nat | k <= 256}{n:nat}{s:nat}{i:nat | i <= n} .<n - i>.
  (b: !$A.arr(byte, l, 256), k: int k, s: int s,
   w: &(@[char][n]), n: int n, i: int i): bool =
  if i >= n then s + n = k
  else if s + i >= k then false
  else if byte2int0($A.get<byte>(b, s + i)) <> char2int0(w.[i]) then false
  else same(b, k, s, w, n, i + 1)

implement main0 () = let
  val b = $A.alloc<byte>(256)
  val k = (case+ $E.args_read(b, 256) of | ~$R.some(k) => k | ~$R.none() => 0): [k:nat | k <= 256] int k
  val s = skip0(b, k, 0)
  var w = @[char][7]('x', '\000', '\000', 'y', ' ', 'z', '\000')
  val ok = same(b, k, s, w, 7, 0)
  val () = $A.free<byte>(b)
in if ok then () else exit_void (1) end
B
cd "$TMP/p"
"$BATS" lock --repository "$REPO" > lock.log 2>&1 || { echo "FAIL: lock"; cat lock.log; exit 1; }
rc=0; "$BATS" run --repository "$REPO" -- x "" "y z" > run.log 2>&1 || rc=$?
grep -q "built: dist/debug/runargs" run.log || { echo "FAIL: build"; cat run.log; exit 1; }
[ "$rc" = 0 ] || { echo "FAIL: the program did not get x, \"\", \"y z\""; cat run.log; exit 1; }
echo "run-args: ok"
