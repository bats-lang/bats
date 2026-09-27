staload "./lib.sats"
(* result -- linear result and option types *)
(* Must pattern-match to consume. Errors cannot be ignored. *)

#include "share/atspre_staload.hats"

(* ============================================================
   Result -- ok(value) or err(error)
   Both type parameters are vt@ype (support linear types).
   ============================================================ *)





(* Unwrap ok value or return default. Consumes the result.
   Only works when both a and e are t@ype (copyable/droppable). *)



(* Is this an ok? Non-consuming check. *)



(* Is this an err? Non-consuming check. *)



(* Discard a result without extracting. Only for t@ype. *)



(* ============================================================
   Option -- some(value) or none (unchanged)
   ============================================================ *)

















(* ============================================================
   Implementations
   ============================================================ *)

implement{a}{e}
unwrap_or(r, default_val) =
  case+ r of
  | ~ok(v) => v
  | ~err(_) => default_val

implement{a}{e}
is_ok(r) = let
  val b = case+ r of | ok(_) => true | err(_) => false
in b end

implement{a}{e}
is_err(r) = let
  val b = case+ r of | ok(_) => false | err(_) => true
in b end

implement{a}{e}
discard(r) =
  case+ r of | ~ok(_) => () | ~err(_) => ()

implement{a}
option_unwrap_or(o, default_val) =
  case+ o of
  | ~some(v) => v
  | ~none() => default_val

implement{a}
is_some(o) = let
  val b = case+ o of | some(_) => true | none() => false
in b end

implement{a}
is_none(o) = let
  val b = case+ o of | some(_) => false | none() => true
in b end

implement{a}
option_discard(o) =
  case+ o of | ~some(_) => () | ~none() => ()

(* ============================================================
   Static tests
   ============================================================ *)

fn _test_result_ok(): void = let
  val r : result(int, int) = ok(42)
  val v = unwrap_or<int><int>(r, 0)
in () end

fn _test_result_err(): void = let
  val r : result(int, int) = err(~1)
  val v = unwrap_or<int><int>(r, 0)
in () end

fn _test_result_match(): void = let
  val r : result(int, int) = ok(42)
in
  case+ r of
  | ~ok(v) => ()
  | ~err(code) => ()
end

fn _test_option_some(): void = let
  val o : option(int) = some(99)
  val v = option_unwrap_or<int>(o, 0)
in () end

fn _test_option_none(): void = let
  val o : option(int) = none()
  val v = option_unwrap_or<int>(o, 0)
in () end

fn _test_is_ok(): void = let
  val r : result(int, int) = ok(1)
  val b = is_ok<int><int>(r)
  val () = discard<int><int>(r)
in () end

fn _test_is_some(): void = let
  val o : option(int) = some(1)
  val b = is_some<int>(o)
  val () = option_discard<int>(o)
in () end

(* ============================================================
   Tests (bats test)
   ============================================================ *)





































