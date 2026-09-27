staload "./lib.sats"
(* list -- singly-linked linear lists *)

#include "share/atspre_staload.hats"

(* ============================================================
   Types
   ============================================================ *)







(* ============================================================
   Construction
   ============================================================ *)






implement {a} nil () = list_nil()

implement {a} cons (x, xs) = list_cons(x, xs)

(* ============================================================
   Length
   ============================================================ *)




implement {a} length {n} (xs) = let
  fun loop {i:nat} .<i>.
    (xs: list_t(a, i)): int(i) =
    case+ xs of
    | list_nil() => 0
    | list_cons(_, tl) => 1 + loop(tl)
in loop(xs) end

(* ============================================================
   Reverse
   ============================================================ *)




implement {a} reverse (xs) = let
  fun loop {i:nat}{j:nat} .<j>.
    (acc: list_t(a, i), rest: list_t(a, j)): list_t(a, i+j) =
    case+ rest of
    | list_nil() => acc
    | list_cons(x, tl) => loop(list_cons(x, acc), tl)
in loop(list_nil(), xs) end

(* ============================================================
   Head and tail
   ============================================================ *)







implement {a} head (xs) =
  case+ xs of list_cons(x, _) => x

implement {a} tail (xs) =
  case+ xs of list_cons(_, tl) => tl

(* ============================================================
   Map and fold
   ============================================================ *)




implement {a}{b} map {n} (xs, f) = let
  fun loop {i:nat} .<i>.
    (xs: list_t(a, i), f: (a) -<cloref1> b): list_t(b, i) =
    case+ xs of
    | list_nil() => list_nil()
    | list_cons(x, tl) => list_cons(f(x), loop(tl, f))
in loop(xs, f) end




implement {a}{b} foldl {n} (xs, init, f) = let
  fun loop {i:nat} .<i>.
    (xs: list_t(a, i), acc: b, f: (b, a) -<cloref1> b): b =
    case+ xs of
    | list_nil() => acc
    | list_cons(x, tl) => loop(tl, f(acc, x), f)
in loop(xs, init, f) end

(* ============================================================
   Append
   ============================================================ *)




implement {a} append {m}{n} (xs, ys) = let
  fun loop {i:nat} .<i>.
    (xs: list_t(a, i), ys: list_t(a, n)): list_t(a, i+n) =
    case+ xs of
    | list_nil() => ys
    | list_cons(x, tl) => list_cons(x, loop(tl, ys))
in loop(xs, ys) end

(* ============================================================
   Is_nil
   ============================================================ *)




implement {a} is_nil (xs) =
  case+ xs of
  | list_nil() => true
  | list_cons(_, _) => false

(* ============================================================
   Linear list (for holding linear values like arrays)
   ============================================================ *)







(* ============================================================
   Tests (bats test)
   ============================================================ *)































