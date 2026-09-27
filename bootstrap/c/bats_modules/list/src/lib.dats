staload "./lib.sats"
(* list -- singly-linked linear lists *)

#include "share/atspre_staload.hats"

(* ============================================================
   Type

   A list is linear: bats has no GC, so every cell is freed by
   whoever holds the list last (free, or a consuming ~ pattern).
   Operations that walk a list borrow it (!); operations that
   rebuild one (reverse, append, tail) consume it and reuse or free
   its cells.
   ============================================================ *)







(* ============================================================
   Construction and freeing
   ============================================================ *)






(* Frees every cell. The elements are values (t@ype); a list of
   linear elements is consumed with ~ patterns instead. *)



implement {a} nil () = list_vt_nil()

implement {a} cons (x, xs) = list_vt_cons(x, xs)

implement {a} free {n} (xs) = let
  fun loop {i:nat} .<i>.
    (xs: list_vt(a, i)): void =
    case+ xs of
    | ~list_vt_nil() => ()
    | ~list_vt_cons(_, tl) => loop(tl)
in loop(xs) end

(* ============================================================
   Length and is_nil
   ============================================================ *)







implement {a} length {n} (xs) = let
  fun loop {i:nat}{k:nat} .<i>.
    (xs: !list_vt(a, i), k: int(k)): int(i+k) =
    case+ xs of
    | list_vt_nil() => k
    | list_vt_cons(_, tl) => loop(tl, k + 1)
in loop(xs, 0) end

implement {a} is_nil (xs) =
  case+ xs of
  | list_vt_nil() => true
  | list_vt_cons(_, _) => false

(* ============================================================
   Reverse (in place: the cells are reused)
   ============================================================ *)




implement {a} reverse (xs) = let
  fun loop {i:nat}{j:nat} .<j>.
    (acc: list_vt(a, i), rest: list_vt(a, j)): list_vt(a, i+j) =
    case+ rest of
    | ~list_vt_nil() => acc
    | @list_vt_cons(_, tl) => let
        val next = tl
        val () = tl := acc
        prval () = fold@(rest)
      in loop(rest, next) end
in loop(list_vt_nil(), xs) end

(* ============================================================
   Head and tail
   ============================================================ *)




(* Frees the first cell. *)



implement {a} head (xs) =
  case+ xs of list_vt_cons(x, _) => x

implement {a} tail (xs) =
  case+ xs of ~list_vt_cons(_, tl) => tl

(* ============================================================
   Map and fold

   The function is a closure on the caller's stack, passed by
   reference, so nothing is allocated for it:
     var f = lam@ (x: int): int =<clo1> x * 10
     val ys = map<int><int>(xs, f)
   ============================================================ *)







implement {a}{b} map {n} (xs, f) = let
  fun loop {i:nat} .<i>.
    (xs: !list_vt(a, i), f: &(a) -<clo1> b): list_vt(b, i) =
    case+ xs of
    | list_vt_nil() => list_vt_nil()
    | list_vt_cons(x, tl) => let
        val y = f(x)
      in list_vt_cons(y, loop(tl, f)) end
in loop(xs, f) end

implement {a}{b} foldl {n} (xs, init, f) = let
  fun loop {i:nat} .<i>.
    (xs: !list_vt(a, i), acc: b, f: &(b, a) -<clo1> b): b =
    case+ xs of
    | list_vt_nil() => acc
    | list_vt_cons(x, tl) => loop(tl, f(acc, x), f)
in loop(xs, init, f) end

(* ============================================================
   Append (consumes both lists; the cells of xs are reused)
   ============================================================ *)




implement {a} append {m}{n} (xs, ys) = let
  fun loop {i:nat} .<i>.
    (xs: list_vt(a, i), ys: list_vt(a, n)): list_vt(a, i+n) =
    case+ xs of
    | ~list_vt_nil() => ys
    | @list_vt_cons(_, tl) => let
        val () = tl := loop(tl, ys)
        prval () = fold@(xs)
      in xs end
in loop(xs, ys) end

(* ============================================================
   Tests (bats test)
   ============================================================ *)


































































