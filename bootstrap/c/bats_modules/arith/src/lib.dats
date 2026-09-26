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

