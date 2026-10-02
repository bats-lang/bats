#!/bin/sh
# What allocates must be linear, so its consumer frees it (there is no
# garbage collector): outside $UNSAFE, a datatype with a constructor that
# carries data, a boxed tuple, record or list ('(, '{, '[, $tup, $rec,
# $list), a non-linear closure (cloref, cloptr) and a ref made inside a
# function are rejected, as is a lam whose arrow leaves its kind to the
# context: given to a cloref parameter (the prelude's
# list_mergesort_cloref, say) it is a cloref1 closure, allocated. A
# nullary-only datatype, a datavtype, a flat @( ) or @{ },
# $tup_vt/$rec_vt/$list_vt, lincloptr1, llam, lam@, a lam whose arrow
# is =<fun1> or =<lincloptr1> and a top-level ref stay allowed;
# comments and strings are not code.
# usage: tests/linear-heap/check.sh <bats-binary>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
n=0
lib() { # <unsafe> <body>
  n=$((n + 1)); d=$TMP/p$n
  mkdir -p "$d/src"
  printf '[package]\nname = "lh%s"\nkind = "lib"\nunsafe = %s\n' "$n" "$1" > "$d/bats.toml"
  printf '#include "share/atspre_staload.hats"\n%s\n' "$2" > "$d/src/lib.bats"
}
reject() { # <expected message part> <body>
  lib false "$2"
  if (cd "$d" && "$BATS" check) > "$d/log" 2>&1; then
    echo "FAIL: accepted: $2"; exit 1
  fi
  grep -qF -- "$1" "$d/log" || { echo "FAIL: rejected, but not with '$1': $2"; grep error "$d/log" | head -3; exit 1; }
}
accept() { # <unsafe> <body>
  lib "$1" "$2"
  (cd "$d" && "$BATS" check) > "$d/log" 2>&1 || { echo "FAIL: rejected: $2"; grep error "$d/log" | head -3; exit 1; }
}
reject "'datatype' with a constructor that carries data" 'datatype reading = Known of int | Unknown'
reject "'datatype' with a constructor that carries data" 'datatype reading =
  | Known of int
  | Unknown'
reject "'datatype' with a constructor that carries data" '#pub datatype reading =
  | Unknown
  | {n:nat | n <= 100} Known of int n'
reject "'datatype' with a constructor that carries data" 'datatype a = A | B
and b = C of int'
reject "a boxed tuple, record or list" 'val p = '"'"'(1, 2)'
reject "a boxed tuple, record or list" 'typedef r = '"'"'{x= int, y= int}'
reject "a boxed tuple, record or list" 'val xs = '"'"'[1, 2, 3]'
reject "'\$tup' is not allowed" 'val p = $tup(1, 2)'
reject "'\$list_t' is not allowed" 'val xs = $list_t{int}(1, 2)'
reject "'cloref1' is not allowed" 'fn apply (f: (int) -<cloref1> int): int = f(1)'
reject "'cloptr1' is not allowed" 'fn apply (f: (int) -<cloptr1> int): int = f(1)'
reject "'cloref1' is not allowed" '#pub fn listen (callback: (int) -<cloref1> void): void'
reject "'datatype' with a constructor that carries data" '#pub datatype shelf = Reading | Trash of int'
reject "'cloref' is not allowed" 'val f = lam (x: int): int =<cloref> x'
reject "'lam' is not allowed" 'fn add (k: int): int = let
  val f = lam (x: int): int => x + k
in f(1) end'
reject "'lam' is not allowed" 'fn sorted (k: int): void = let
  val ys = list_mergesort_cloref<int>(list_nil{int}(), lam (a, b) => a - b - k)
in list_vt_free<int>(ys) end'
reject "use 'llam'" 'fn sorted (): void = let
  val ys = list_mergesort_cloref<int>(list_nil{int}(), lam (a: int, b: int): int =<!wrt> a - b)
in list_vt_free<int>(ys) end'
reject "'ref' inside a function" 'fn count (): int = let
  val cell = ref<int>(0)
in !cell end'
accept false 'datatype shelf = Reading | Hidden | Archived | Trash
datatype tree = Leaf of () | Twig of ()
#pub fn with_linear (callback: (int) -<lincloptr1> void): (int) -<lincloptr1> void
implement with_linear (callback) = callback
#pub datatype outcome =
  | Locked
  | LockRefused
datavtype reading = Known of int | Unknown
fn free_reading (r: reading): void = case+ r of ~Known(_) => () | ~Unknown() => ()
typedef pair = @(int, int)
typedef point = @{x= int, y= int}
fn pass_on (f: (int) -<lincloptr1> int): (int) -<lincloptr1> int = f
fn make (): (int) -<lincloptr1> int = llam (x) => x + 1
fn sum (f: (int) -<fun1> int): int = f(1)
fn sum_one (): int = sum(lam (x: int): int =<fun1> x + 1)
fn flat (k: int): int = let
  var f = lam@ (x: int): int =<clo1> x + k
in f(1) end
fn made (): (int) -<lincloptr1> int = lam (x: int): int =<lincloptr1> x
fn spaced (): (int) -<lincloptr1> int = lam (x: int): int =< lincloptr1 > x
val lam_count = 0
val lambda = 1
val counter = ref<int>(0)
val t = $tup_vt(1, 2)
val xs = $list_vt{int}(1, 2)
(* datatype x = X of int, '"'"'(1, 2), cloref1, ref<int>(0), lam (x) => x in a comment *)
val s = "datatype x = X of int cloref1 '"'"'(1) ref<int>(0) lam (x) => x"
val c = '"'"'\('"'"'
val mydatatype = 1
fn in_datatypes (): int = 2'
accept true '$UNSAFE begin
datatype reading = Known of int | Unknown
val p = '"'"'(1, 2)
fn apply (f: (int) -<cloref1> int): int = f(1)
fn count (): int = let val cell = ref<int>(0) in !cell end
fn sorted (): void = let
  val ys = list_mergesort_cloref<int>(list_nil{int}(), lam (a, b) => a - b)
in list_vt_free<int>(ys) end
end'
echo "linear-heap: ok"
