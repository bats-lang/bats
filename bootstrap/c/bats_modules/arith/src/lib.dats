staload "./lib.sats"
(* arith -- freestanding arithmetic for ATS2 *)
(* g0/g1 arithmetic, comparisons, bitwise, type coercion *)

#include "share/atspre_staload.hats"

(* ========== g0 Arithmetic ========== *)











(* ========== g0 Comparison ========== *)













(* ========== g1 Dependent Comparison ========== *)





(* ========== Bitwise ========== *)









(* ========== g1 Dependent Arithmetic ========== *)







(* ========== g1 Dependent Comparisons ========== *)











(* ========== g1 Dependent Bitwise ========== *)



(* ========== Exclusive or, with its proof ========== *)

(* XOR(a, b, c): c is a xor b. The specification, bit by bit from the
   least significant: each case says what the bit makes of the number *)







(* AND(a, b, c) and OR(a, b, c): c is a and b, a or b, by the same bit
   by bit specification *)














(* a and b, a or b, with the proofs that they are. The C operators are
   trusted to be the ones AND and OR describe (as band_g1 is trusted for
   its bound); that they are is tested for every pair of 16-bit numbers
   (tests/dynamic/xor, which checks the exclusive or made of them) *)




(* a xor b is a or b less a and b: the bits both have are counted twice
   by the or, once too many *)
prfun _xor_or_and {a,b,o,n:nat} .<a+b>. (po: OR(a, b, o), pn: AND(a, b, n)): [n <= o] XOR(a, b, o - n) =
  case+ po of
  | OR_nil() => (case+ pn of AND_nil() => XOR_nil())
  | OR_00(po1) => (case+ pn of AND_00(pn1) => XOR_00(_xor_or_and(po1, pn1)))
  | OR_01(po1) => (case+ pn of AND_01(pn1) => XOR_01(_xor_or_and(po1, pn1)))
  | OR_10(po1) => (case+ pn of AND_10(pn1) => XOR_10(_xor_or_and(po1, pn1)))
  | OR_11(po1) => (case+ pn of AND_11(pn1) => XOR_11(_xor_or_and(po1, pn1)))

(* a xor b, with the proof that it is: the number is made of an and and an
   or, whose proofs make the one XOR describes. (The wasm runtime has no
   exclusive or of its own.) *)


implement xor_g1 (a, b) = let
  val (po | o) = or_proved(a, b)
  val (pn | n) = and_proved(a, b)
  prval px = _xor_or_and(po, pn)
in (px | sub_g1(o, n)) end

(* a xor b is one number *)


prfun _xor_functional {a,b,c1,c2:nat} .<a+b>. (p: XOR(a, b, c1), q: XOR(a, b, c2)): [c1 == c2] void =
  case+ p of
  | XOR_nil() => (case+ q of XOR_nil() => ())
  | XOR_00(p1) => (case+ q of XOR_00(q1) => _xor_functional(p1, q1))
  | XOR_01(p1) => (case+ q of XOR_01(q1) => _xor_functional(p1, q1))
  | XOR_10(p1) => (case+ q of XOR_10(q1) => _xor_functional(p1, q1))
  | XOR_11(p1) => (case+ q of XOR_11(q1) => _xor_functional(p1, q1))

primplement xor_functional {a,b,c1,c2} (p, q) = _xor_functional(p, q)

(* POW2(k, p): p is 2 to the k *)




(* a xor b of numbers under 2 to the k is under 2 to the k *)


prfun _xor_bound {k,p,a,b,c:nat | a < p; b < p} .<k>. (w: POW2(k, p), x: XOR(a, b, c)): [c < p] void =
  case+ x of
  | XOR_nil() => ()
  | XOR_00(x1) => (case+ w of POW2_succ(w1) => _xor_bound(w1, x1))
  | XOR_01(x1) => (case+ w of POW2_succ(w1) => _xor_bound(w1, x1))
  | XOR_10(x1) => (case+ w of POW2_succ(w1) => _xor_bound(w1, x1))
  | XOR_11(x1) => (case+ w of POW2_succ(w1) => _xor_bound(w1, x1))

primplement xor_bound {k,p,a,b,c} (w, x) = _xor_bound(w, x)

(* ========== Bytes ========== *)

(* The low 8 bits of x as an int proven in [0, 256). Rebuilt from its
   bits: each term is a literal or 0, so the bound needs no cast. *)


implement low_byte(x) = let
  fn bit {w:nat | w < 256} (x: int, w: int w): [y:nat | y <= w] int y =
    if band_int_int(x, w) = 0 then 0 else w
in
  bit(x, 128) + bit(x, 64) + bit(x, 32) + bit(x, 16)
    + bit(x, 8) + bit(x, 4) + bit(x, 2) + bit(x, 1)
end



implement byte_of_char(c) = low_byte(char2int0(c))

