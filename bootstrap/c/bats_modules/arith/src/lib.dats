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

(* ========== The algebra of exclusive or ========== *)

(* What a table-driven checksum needs of XOR: it is commutative and
   associative, 0 is its identity, a number is its own inverse, and
   halving (dropping the low bit) goes through it. Each is proved from
   the bit by bit specification, so none is trusted. *)

(* 2a xor 2b is 2c where a xor b is c; XOR_00 alone needs a + b > 0, so
   this form is the one to build with *)


primplement xor_double {a,b,c} (p) =
  case+ p of
  | XOR_nil() => XOR_nil()
  | XOR_00(p1) => XOR_00(xor_double(p1))
  | XOR_01(p1) => XOR_00(p)
  | XOR_10(p1) => XOR_00(p)
  | XOR_11(p1) => XOR_00(p)

(* a xor 0 and 0 xor a are a *)


primplement xor_zero_right {a} () = let
  prfun go {a:nat} .<a>. (): XOR(a, 0, a) =
    sif a == 0 then XOR_nil()
    else sif a == 2*(a/2) then xor_double(go{a/2}())
    else XOR_10(go{a/2}())
in go{a}() end



primplement xor_zero_left {a} () = let
  prfun go {a:nat} .<a>. (): XOR(0, a, a) =
    sif a == 0 then XOR_nil()
    else sif a == 2*(a/2) then xor_double(go{a/2}())
    else XOR_01(go{a/2}())
in go{a}() end

(* a xor b is b xor a *)


primplement xor_comm {a,b,c} (p) =
  case+ p of
  | XOR_nil() => XOR_nil()
  | XOR_00(p1) => XOR_00(xor_comm(p1))
  | XOR_01(p1) => XOR_10(xor_comm(p1))
  | XOR_10(p1) => XOR_01(xor_comm(p1))
  | XOR_11(p1) => XOR_11(xor_comm(p1))

(* a xor a is 0 *)


primplement xor_self {a} () = let
  prfun go {a:nat} .<a>. (): XOR(a, a, 0) =
    sif a == 0 then XOR_nil()
    else sif a == 2*(a/2) then xor_double(go{a/2}())
    else XOR_11(go{a/2}())
in go{a}() end

(* Halving goes through xor: (a xor b) / 2 is a / 2 xor b / 2. (The low
   bit is in the constructors: matching on a XOR says it) *)


primplement xor_half {a,b,c} (p) =
  case+ p of
  | XOR_nil() => XOR_nil()
  | XOR_00(p1) => p1
  | XOR_01(p1) => p1
  | XOR_10(p1) => p1
  | XOR_11(p1) => p1

(* a xor b is 0 only for a equal to b *)


primplement xor_zero_equal {a,b} (p) = let
  prfun go {a,b:nat} .<a+b>. (p: XOR(a, b, 0)): [a == b] void =
    case+ p of
    | XOR_nil() => ()
    | XOR_00(p1) => go(p1)
    | XOR_11(p1) => go(p1)
in go(p) end

(* (a xor b) xor c is a xor (b xor c). The cases where the second
   argument of one of the xors is 0 come first, as the XOR_00 of a
   zero has no recursion to carry the proof *)



prfn _assoc_rnil {a,ab,abc:nat} (p: XOR(a, 0, ab), q: XOR(ab, 0, abc)): XOR(a, 0, abc) = let
  prval () = xor_functional(p, xor_zero_right{a}())
  prval () = xor_functional(q, xor_zero_right{ab}())
in xor_zero_right{a}() end

prfn _assoc_qnil {a,b,bc:nat} (p: XOR(a, b, 0), r: XOR(b, 0, bc)): XOR(a, bc, 0) = let
  prval () = xor_zero_equal(p)
  prval () = xor_functional(r, xor_zero_right{b}())
in xor_self{a}() end

prfun _xor_assoc {a,b,c,ab,bc,abc:nat} .<a+b+c>.
  (p: XOR(a, b, ab), q: XOR(ab, c, abc), r: XOR(b, c, bc)): XOR(a, bc, abc) =
  case+ p of
  | XOR_nil() => let
      prval () = xor_functional(r, q)
    in xor_zero_left() end
  | XOR_00(p1) => (case+ r of
    | XOR_nil() => _assoc_rnil(p, q)
    | XOR_00(r1) => (case+ q of XOR_nil() => _assoc_qnil(p, r) | XOR_00(q1) => xor_double(_xor_assoc(p1, q1, r1)))
    | XOR_01(r1) => (case+ q of XOR_01(q1) => XOR_01(_xor_assoc(p1, q1, r1))))
  | XOR_01(p1) => (case+ r of
    | XOR_10(r1) => (case+ q of XOR_10(q1) => XOR_01(_xor_assoc(p1, q1, r1)))
    | XOR_11(r1) => (case+ q of XOR_11(q1) => xor_double(_xor_assoc(p1, q1, r1))))
  | XOR_10(p1) => (case+ r of
    | XOR_nil() => _assoc_rnil(p, q)
    | XOR_00(r1) => (case+ q of XOR_10(q1) => XOR_10(_xor_assoc(p1, q1, r1)))
    | XOR_01(r1) => (case+ q of XOR_11(q1) => XOR_11(_xor_assoc(p1, q1, r1))))
  | XOR_11(p1) => (case+ r of
    | XOR_10(r1) => (case+ q of XOR_nil() => _assoc_qnil(p, r) | XOR_00(q1) => XOR_11(_xor_assoc(p1, q1, r1)))
    | XOR_11(r1) => (case+ q of XOR_01(q1) => XOR_10(_xor_assoc(p1, q1, r1))))

primplement xor_assoc (p, q, r) = _xor_assoc(p, q, r)

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


(* ========== 32-bit words, as two 16-bit halves ========== *)

(* A word is its high and low halves, each a number under 65536. The
   halves, not the number, are what the specification is indexed by: the
   solver is 32-bit, a constant or a coefficient of 2 to the 30 or more
   in a hypothesis makes its context contradictory, so no proof here
   names 2 to the 32. The word is h * 65536 + l.

   The specifications are the standard's own definitions, one bit at a
   time: rotating right by n bits is n rotations by one bit, shifting
   right by n bits is n shifts by one bit, and an addition is modulo
   2 to the 32 by its carries (FIPS 180-4, sections 2.2.2, 3.2 and 4.1) *)

(* ROTR1(h, l, h2, l2): the word h:l rotated right by one bit is h2:l2.
   Each half is its upper bits and its lowest bit (h = 2a + s, l = 2b + t):
   the lowest bit of the word, t, becomes the highest, and the lowest bit
   of the high half, s, becomes the highest of the low half. *)




(* ROTR(n, h, l, h2, l2): h:l rotated right by n bits is h2:l2 *)





(* SHR1(h, l, h2, l2) and SHR(n, h, l, h2, l2): shifted right by one bit
   and by n bits; the bits shifted out are lost and zeros come in at the top *)









(* ADD32(h1, l1, h2, l2, h3, l3): h1:l1 plus h2:l2 modulo 2 to the 32 is
   h3:l3. The low halves add to l3 and a carry c into the high halves,
   which add with it to h3 and a carry d that is dropped: the modulus *)





(* NOT32(h, l, h2, l2): h2:l2 is h:l with every bit flipped *)



(* x as 2a + s, a half and the bit that is left *)
fn half_split {x:nat | x < 65536} (x: int x): [a,s:nat | x == 2*a + s; a < 32768; s < 2] @(int a, int s) = let
  val a = x / 2
in @(a, sub_g1(x, mul_g1(2, a))) end

(* The word h:l rotated right by one bit, with the proof that it is *)



implement rotr1 {h,l} (h, l) = let
  val [a:int, s:int] @(a, s) = half_split(h)
  val [b:int, t:int] @(b, t) = half_split(l)
in (ROTR1_mk{a,b}{s,t}() | @(add_g1(a, mul_g1(32768, t)), add_g1(b, mul_g1(32768, s)))) end

(* The word shifted right by one bit, with the proof that it is *)



implement shr1 {h,l} (h, l) = let
  val [a:int, s:int] @(a, s) = half_split(h)
  val [b:int, t:int] @(b, t) = half_split(l)
in (SHR1_mk{a,b}{s,t}() | @(a, add_g1(b, mul_g1(32768, s)))) end

(* The word h:l rotated right by n bits, with the proof that it is: n
   rotations by one bit *)



implement rotr {n,h,l} (n, h, l) = let
  fun loop {n,h,l:nat | h < 65536; l < 65536} .<n>. (n: int n, h: int h, l: int l)
    : [h2,l2:nat | h2 < 65536; l2 < 65536] (ROTR(n, h, l, h2, l2) | @(int h2, int l2)) =
    if n = 0 then (ROTR_zero() | @(h, l))
    else let
      val (once | @(h1, l1)) = rotr1(h, l)
      val (rest | @(h2, l2)) = loop(sub_g1(n, 1), h1, l1)
    in (ROTR_succ(once, rest) | @(h2, l2)) end
in loop(n, h, l) end

(* The word h:l shifted right by n bits, with the proof that it is *)



implement shr {n,h,l} (n, h, l) = let
  fun loop {n,h,l:nat | h < 65536; l < 65536} .<n>. (n: int n, h: int h, l: int l)
    : [h2,l2:nat | h2 < 65536; l2 < 65536] (SHR(n, h, l, h2, l2) | @(int h2, int l2)) =
    if n = 0 then (SHR_zero() | @(h, l))
    else let
      val (once | @(h1, l1)) = shr1(h, l)
      val (rest | @(h2, l2)) = loop(sub_g1(n, 1), h1, l1)
    in (SHR_succ(once, rest) | @(h2, l2)) end
in loop(n, h, l) end

(* The sum modulo 2 to the 32 of two words, with the proof that it is *)




implement add32 {h1,l1,h2,l2} (h1, l1, h2, l2) = let
  val low = add_g1(l1, l2)
in
  if gte_g1(low, 65536) then let
    val l3 = sub_g1(low, 65536)
    val high = add_g1(add_g1(h1, h2), 1)
  in
    if gte_g1(high, 65536) then (ADD32_mk{h1,l1,h2,l2,h1+h2+1-65536,l1+l2-65536}{1,1}() | @(sub_g1(high, 65536), l3))
    else (ADD32_mk{h1,l1,h2,l2,h1+h2+1,l1+l2-65536}{1,0}() | @(high, l3))
  end
  else let
    val high = add_g1(h1, h2)
  in
    if gte_g1(high, 65536) then (ADD32_mk{h1,l1,h2,l2,h1+h2-65536,l1+l2}{0,1}() | @(sub_g1(high, 65536), low))
    else (ADD32_mk{h1,l1,h2,l2,h1+h2,l1+l2}{0,0}() | @(high, low))
  end
end

(* The word with every bit flipped, with the proof that it is *)



implement not32 {h,l} (h, l) = (NOT32_mk() | @(sub_g1(65535, h), sub_g1(65535, l)))

(* a and b, a or b of numbers under 2 to the k are under 2 to the k *)


prfun _and_bound {k,p,a,b,c:nat | a < p; b < p} .<k>. (w: POW2(k, p), x: AND(a, b, c)): [c < p] void =
  case+ x of
  | AND_nil() => (case+ w of POW2_zero() => () | POW2_succ(_) => ())
  | AND_00(x1) => (case+ w of POW2_succ(w1) => _and_bound(w1, x1))
  | AND_01(x1) => (case+ w of POW2_succ(w1) => _and_bound(w1, x1))
  | AND_10(x1) => (case+ w of POW2_succ(w1) => _and_bound(w1, x1))
  | AND_11(x1) => (case+ w of POW2_succ(w1) => _and_bound(w1, x1))

primplement and_bound {k,p,a,b,c} (w, x) = _and_bound(w, x)



prfun _or_bound {k,p,a,b,c:nat | a < p; b < p} .<k>. (w: POW2(k, p), x: OR(a, b, c)): [c < p] void =
  case+ x of
  | OR_nil() => (case+ w of POW2_zero() => () | POW2_succ(_) => ())
  | OR_00(x1) => (case+ w of POW2_succ(w1) => _or_bound(w1, x1))
  | OR_01(x1) => (case+ w of POW2_succ(w1) => _or_bound(w1, x1))
  | OR_10(x1) => (case+ w of POW2_succ(w1) => _or_bound(w1, x1))
  | OR_11(x1) => (case+ w of POW2_succ(w1) => _or_bound(w1, x1))

primplement or_bound {k,p,a,b,c} (w, x) = _or_bound(w, x)

(* 2 to the 16, the size of a half *)


primplement pow2_half () =
  POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(
  POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(POW2_succ(
  POW2_zero()))))))))))))))))

(* The bitwise operations on words, each half by its own proof: the
   exclusive or, and and or of h1:l1 and h2:l2 are h3:l3 where the high
   halves and the low halves are each related by XOR, AND or OR *)




implement xor32 {h1,l1,h2,l2} (h1, l1, h2, l2) = let
  val (high | h3) = xor_g1(h1, h2)
  val (low | l3) = xor_g1(l1, l2)
  prval () = xor_bound(pow2_half(), high)
  prval () = xor_bound(pow2_half(), low)
in (high, low | @(h3, l3)) end





implement and32 {h1,l1,h2,l2} (h1, l1, h2, l2) = let
  val (high | h3) = and_proved(h1, h2)
  val (low | l3) = and_proved(l1, l2)
  prval () = and_bound(pow2_half(), high)
  prval () = and_bound(pow2_half(), low)
in (high, low | @(h3, l3)) end





implement or32 {h1,l1,h2,l2} (h1, l1, h2, l2) = let
  val (high | h3) = or_proved(h1, h2)
  val (low | l3) = or_proved(l1, l2)
  prval () = or_bound(pow2_half(), high)
  prval () = or_bound(pow2_half(), low)
in (high, low | @(h3, l3)) end

(* Each operation of a word gives one word *)


(* A number is its half and its lowest bit in one way only. With the
   digits split off like this (the same lemma for both halves) the proof
   is honest under both solvers: stated whole, the 32-bit one accepts
   false variants of it (its context is contradictory) *)
prfn _digit2 {a,s,a2,s2:nat | s < 2; s2 < 2; 2*a + s == 2*a2 + s2} (): [a == a2; s == s2] void = ()

primplement rotr1_functional {h,l,h2,l2,h3,l3} (p, q) =
  case+ p of ROTR1_mk{a,b}{s,t}() => (case+ q of ROTR1_mk{a2,b2}{s2,t2}() => let
    prval () = _digit2{a,s,a2,s2}()
    prval () = _digit2{b,t,b2,t2}()
  in end)



prfun _rotr_functional {n,h,l,h2,l2,h3,l3:nat} .<n>. (p: ROTR(n, h, l, h2, l2), q: ROTR(n, h, l, h3, l3)): [h2 == h3; l2 == l3] void =
  case+ p of
  | ROTR_zero() => (case+ q of ROTR_zero() => ())
  | ROTR_succ(p1, p2) => (case+ q of
    | ROTR_succ(q1, q2) => let
        prval () = rotr1_functional(p1, q1)
      in _rotr_functional(p2, q2) end)

primplement rotr_functional {n,h,l,h2,l2,h3,l3} (p, q) = _rotr_functional(p, q)



primplement shr1_functional {h,l,h2,l2,h3,l3} (p, q) =
  case+ p of SHR1_mk{a,b}{s,t}() => (case+ q of SHR1_mk{a2,b2}{s2,t2}() => let
    prval () = _digit2{a,s,a2,s2}()
    prval () = _digit2{b,t,b2,t2}()
  in end)



prfun _shr_functional {n,h,l,h2,l2,h3,l3:nat} .<n>. (p: SHR(n, h, l, h2, l2), q: SHR(n, h, l, h3, l3)): [h2 == h3; l2 == l3] void =
  case+ p of
  | SHR_zero() => (case+ q of SHR_zero() => ())
  | SHR_succ(p1, p2) => (case+ q of
    | SHR_succ(q1, q2) => let
        prval () = shr1_functional(p1, q1)
      in _shr_functional(p2, q2) end)

primplement shr_functional {n,h,l,h2,l2,h3,l3} (p, q) = _shr_functional(p, q)




(* The two halves are proved apart: the low halves and then the high
   halves, each an equation of one sum in two ways. Stated as one lemma
   (the carries c, d of both proofs and all eight halves in one context)
   the infinite-precision solver does not answer; the two small ones it
   does at once. *)
prfn _add32_low {l1,l2,l3,l4,c,c2:nat | l1 < 65536; l2 < 65536; l3 < 65536; l4 < 65536; c < 2; c2 < 2;
  l1 + l2 == l3 + 65536*c; l1 + l2 == l4 + 65536*c2} (): [c == c2; l3 == l4] void = ()

prfn _add32_high {h1,h2,h3,h4,c,d,d2:nat | h1 < 65536; h2 < 65536; h3 < 65536; h4 < 65536; c < 2; d < 2; d2 < 2;
  h1 + h2 + c == h3 + 65536*d; h1 + h2 + c == h4 + 65536*d2} (): [h3 == h4] void = ()

primplement add32_functional {h1,l1,h2,l2,h3,l3,h4,l4} (p, q) =
  case+ p of ADD32_mk{..}{c,d}() => (case+ q of ADD32_mk{..}{c2,d2}() => let
    prval () = _add32_low{l1,l2,l3,l4,c,c2}()
    prval () = _add32_high{h1,h2,h3,h4,c,d,d2}()
  in end)

(* ===== Fast rotations (sha256#29, stage E) =====

   ROTR is n steps of one bit, which is the specification and too slow to
   compute with: a digest rotates about a million bits a block. Here a
   rotation by n < 32 is at most five constant-time steps on the halves
   (by 16, 8, 4, 2 and 1, one for each set bit of n), each proved against
   that same relation, and the steps compose: rotr_add says a rotation by
   a and then by b is one by a + b (by induction on a), so the proof of
   the rotation by n is the steps' proofs added.

   A step by k bits is stated on digits, never on divisions: with
   p = 2 to the k and q = 2 to the 16 - k, the halves are h = p*a + r
   and l = p*b + t (r and t are the k low bits), and h:l rotated right by
   k is (a + q*t):(b + q*r). The step by 2k is proved from the step by k
   twice (two digits of k bits make one of 2k, and q = p * q of 2k), the
   step by 1 from ROTR1, and the step by 16 from two of 8 on bytes (it
   swaps the halves). Every proof is an equation of linear terms whose
   coefficients are at most 2 to the 16, so the 32-bit solver is never
   near its limit; each is also tried by a false variant in
   tests/static/reject, which a solver with a contradictory context would
   accept. *)

(* a rotation by a and then by b is one by a + b *)


prfun _rotr_add {a,b,h,l,h1,l1,h2,l2:nat} .<a>. (p: ROTR(a, h, l, h1, l1), q: ROTR(b, h1, l1, h2, l2)): ROTR(a + b, h, l, h2, l2) =
  case+ p of
  | ROTR_zero() => q
  | ROTR_succ(once, rest) => ROTR_succ(once, _rotr_add(rest, q))

primplement rotr_add {a,b,h,l,h1,l1,h2,l2} (p, q) = _rotr_add(p, q)

(* the same for shifts: a shift by a and then by b is one by a + b *)


prfun _shr_add {a,b,h,l,h1,l1,h2,l2:nat} .<a>. (p: SHR(a, h, l, h1, l1), q: SHR(b, h1, l1, h2, l2)): SHR(a + b, h, l, h2, l2) =
  case+ p of
  | SHR_zero() => q
  | SHR_succ(once, rest) => SHR_succ(once, _shr_add(rest, q))

primplement shr_add {a,b,h,l,h1,l1,h2,l2} (p, q) = _shr_add(p, q)

(* the same rotation under equal halves *)
prfn rotr_cast {n,h,l,h2,l2,c,d,c2,d2:nat | h == c; l == d; h2 == c2; l2 == d2}
  (p: ROTR(n, h, l, h2, l2)): ROTR(n, c, d, c2, d2) = p

(* by 1 bit: h = 2a + r, l = 2b + t *)



primplement rotr_digits_1 {a,b,r,t} () = ROTR_succ(ROTR1_mk{a,b}{r,t}(), ROTR_zero())

(* by 2 bits: h = 4*A + R, l = 4*B + T, two steps of 1 *)



primplement rotr_digits_2 {a,b,r,t} () = let
  prval first = rotr_digits_1{2*a + r/2, 2*b + t/2, r - 2*(r/2), t - 2*(t/2)}()
  prval second = rotr_digits_1{a + 16384*(t - 2*(t/2)), b + 16384*(r - 2*(r/2)), r/2, t/2}()
in rotr_cast(rotr_add(first, second)) end

(* by 4 bits: h = 16*A + R, l = 16*B + T, two steps of 2 *)



primplement rotr_digits_4 {a,b,r,t} () = let
  prval first = rotr_digits_2{4*a + r/4, 4*b + t/4, r - 4*(r/4), t - 4*(t/4)}()
  prval second = rotr_digits_2{a + 4096*(t - 4*(t/4)), b + 4096*(r - 4*(r/4)), r/4, t/4}()
in rotr_cast(rotr_add(first, second)) end

(* by 8 bits: h = 256*A + R, l = 256*B + T, two steps of 4 *)



primplement rotr_digits_8 {a,b,r,t} () = let
  prval first = rotr_digits_4{16*a + r/16, 16*b + t/16, r - 16*(r/16), t - 16*(t/16)}()
  prval second = rotr_digits_4{a + 256*(t - 16*(t/16)), b + 256*(r - 16*(r/16)), r/16, t/16}()
in rotr_cast(rotr_add(first, second)) end

(* by 16 bits: the halves swap. h = 256*hh + hl, l = 256*lh + ll *)



primplement rotr_by_16 {h,l} () = let
  prval first = rotr_digits_8{h/256, l/256, h - 256*(h/256), l - 256*(l/256)}()
  prval second = rotr_digits_8{l - 256*(l/256), h - 256*(h/256), h/256, l/256}()
in rotr_cast(rotr_add(first, second)) end

(* A step by k bits on the halves, with the proof that it is one: the
   digits a, r of h and b, t of l by division by p = 2 to the k, and the
   result (a + q*t):(b + q*r), q = 2 to the 16 - k *)




implement rotr_step_1 {h,l} (h, l) = let
  val a = h / 2
  val b = l / 2
  val r = sub_g1(h, mul_g1(2, a))
  val t = sub_g1(l, mul_g1(2, b))
  prval pf = rotr_digits_1{h/2, l/2, h - 2*(h/2), l - 2*(l/2)}()
in (rotr_cast(pf) | @(add_g1(a, mul_g1(32768, t)), add_g1(b, mul_g1(32768, r)))) end




implement rotr_step_2 {h,l} (h, l) = let
  val a = h / 4
  val b = l / 4
  val r = sub_g1(h, mul_g1(4, a))
  val t = sub_g1(l, mul_g1(4, b))
  prval pf = rotr_digits_2{h/4, l/4, h - 4*(h/4), l - 4*(l/4)}()
in (rotr_cast(pf) | @(add_g1(a, mul_g1(16384, t)), add_g1(b, mul_g1(16384, r)))) end




implement rotr_step_4 {h,l} (h, l) = let
  val a = h / 16
  val b = l / 16
  val r = sub_g1(h, mul_g1(16, a))
  val t = sub_g1(l, mul_g1(16, b))
  prval pf = rotr_digits_4{h/16, l/16, h - 16*(h/16), l - 16*(l/16)}()
in (rotr_cast(pf) | @(add_g1(a, mul_g1(4096, t)), add_g1(b, mul_g1(4096, r)))) end




implement rotr_step_8 {h,l} (h, l) = let
  val a = h / 256
  val b = l / 256
  val r = sub_g1(h, mul_g1(256, a))
  val t = sub_g1(l, mul_g1(256, b))
  prval pf = rotr_digits_8{h/256, l/256, h - 256*(h/256), l - 256*(l/256)}()
in (rotr_cast(pf) | @(add_g1(a, mul_g1(256, t)), add_g1(b, mul_g1(256, r)))) end




implement rotr_step_16 {h,l} (h, l) = (rotr_by_16{h,l}() | @(l, h))

(* The word h:l rotated right by n < 32 bits, with the proof that it is,
   in at most five constant-time steps: the stage for k bits takes the
   step by k when n has that bit set and leaves the rest to the stages
   below it (rotr_add puts the proofs together) *)
fn _rotr_stage_1 {n,h,l:nat | n < 2; h < 65536; l < 65536} (n: int n, h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (ROTR(n, h, l, h2, l2) | @(int h2, int l2)) =
  if gte_g1(n, 1) then rotr_step_1(h, l) else (ROTR_zero() | @(h, l))

fn _rotr_stage_2 {n,h,l:nat | n < 4; h < 65536; l < 65536} (n: int n, h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (ROTR(n, h, l, h2, l2) | @(int h2, int l2)) =
  if gte_g1(n, 2) then let
    val (first | @(h1, l1)) = rotr_step_2(h, l)
    val (rest | @(h2, l2)) = _rotr_stage_1(sub_g1(n, 2), h1, l1)
  in (rotr_add(first, rest) | @(h2, l2)) end
  else _rotr_stage_1(n, h, l)

fn _rotr_stage_4 {n,h,l:nat | n < 8; h < 65536; l < 65536} (n: int n, h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (ROTR(n, h, l, h2, l2) | @(int h2, int l2)) =
  if gte_g1(n, 4) then let
    val (first | @(h1, l1)) = rotr_step_4(h, l)
    val (rest | @(h2, l2)) = _rotr_stage_2(sub_g1(n, 4), h1, l1)
  in (rotr_add(first, rest) | @(h2, l2)) end
  else _rotr_stage_2(n, h, l)

fn _rotr_stage_8 {n,h,l:nat | n < 16; h < 65536; l < 65536} (n: int n, h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (ROTR(n, h, l, h2, l2) | @(int h2, int l2)) =
  if gte_g1(n, 8) then let
    val (first | @(h1, l1)) = rotr_step_8(h, l)
    val (rest | @(h2, l2)) = _rotr_stage_4(sub_g1(n, 8), h1, l1)
  in (rotr_add(first, rest) | @(h2, l2)) end
  else _rotr_stage_4(n, h, l)

fn _rotr_stage_16 {n,h,l:nat | n < 32; h < 65536; l < 65536} (n: int n, h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (ROTR(n, h, l, h2, l2) | @(int h2, int l2)) =
  if gte_g1(n, 16) then let
    val (first | @(h1, l1)) = rotr_step_16(h, l)
    val (rest | @(h2, l2)) = _rotr_stage_8(sub_g1(n, 16), h1, l1)
  in (rotr_add(first, rest) | @(h2, l2)) end
  else _rotr_stage_8(n, h, l)




implement rotr_fast {n,h,l} (n, h, l) = _rotr_stage_16(n, h, l)

(* ===== Fast shifts (arith#36) =====

   The same decomposition for SHR: a shift by n < 32 is at most five
   constant-time steps (by 16, 8, 4, 2 and 1, one for each set bit of n),
   each proved against SHR, composed by shr_add. A step by k bits is stated
   on digits, as the rotations are: with p = 2 to the k and q = 2 to the
   16 - k, the halves are h = p*a + r and l = p*b + t (r and t are the k low
   bits), and h:l shifted right by k is a:(b + q*r): the high half loses its
   k low bits to the top of the low half, and the bits of the low half are
   lost. Coefficients are at most 2 to the 16, no division is nested. *)

(* the same shift under equal halves *)
prfn shr_cast {n,h,l,h2,l2,c,d,c2,d2:nat | h == c; l == d; h2 == c2; l2 == d2}
  (p: SHR(n, h, l, h2, l2)): SHR(n, c, d, c2, d2) = p

(* by 1 bit: h = 2a + r, l = 2b + t *)



primplement shr_digits_1 {a,b,r,t} () = SHR_succ(SHR1_mk{a,b}{r,t}(), SHR_zero())

(* by 2 bits: h = 4*A + R, l = 4*B + T, two steps of 1 *)



primplement shr_digits_2 {a,b,r,t} () = let
  prval first = shr_digits_1{2*a + r/2, 2*b + t/2, r - 2*(r/2), t - 2*(t/2)}()
  prval second = shr_digits_1{a, b + 16384*(r - 2*(r/2)), r/2, t/2}()
in shr_cast(shr_add(first, second)) end

(* by 4 bits: h = 16*A + R, l = 16*B + T, two steps of 2 *)



primplement shr_digits_4 {a,b,r,t} () = let
  prval first = shr_digits_2{4*a + r/4, 4*b + t/4, r - 4*(r/4), t - 4*(t/4)}()
  prval second = shr_digits_2{a, b + 4096*(r - 4*(r/4)), r/4, t/4}()
in shr_cast(shr_add(first, second)) end

(* by 8 bits: h = 256*A + R, l = 256*B + T, two steps of 4 *)



primplement shr_digits_8 {a,b,r,t} () = let
  prval first = shr_digits_4{16*a + r/16, 16*b + t/16, r - 16*(r/16), t - 16*(t/16)}()
  prval second = shr_digits_4{a, b + 256*(r - 16*(r/16)), r/16, t/16}()
in shr_cast(shr_add(first, second)) end

(* by 16 bits: the high half moves down and zero comes in. h = 256*hh + hl,
   l = 256*lh + ll *)



primplement shr_by_16 {h,l} () = let
  prval first = shr_digits_8{h/256, l/256, h - 256*(h/256), l - 256*(l/256)}()
  prval second = shr_digits_8{0, h - 256*(h/256), h/256, l/256}()
in shr_cast(shr_add(first, second)) end




implement shr_step_1 {h,l} (h, l) = let
  val a = h / 2
  val b = l / 2
  val r = sub_g1(h, mul_g1(2, a))
  prval pf = shr_digits_1{h/2, l/2, h - 2*(h/2), l - 2*(l/2)}()
in (shr_cast(pf) | @(a, add_g1(b, mul_g1(32768, r)))) end




implement shr_step_2 {h,l} (h, l) = let
  val a = h / 4
  val b = l / 4
  val r = sub_g1(h, mul_g1(4, a))
  prval pf = shr_digits_2{h/4, l/4, h - 4*(h/4), l - 4*(l/4)}()
in (shr_cast(pf) | @(a, add_g1(b, mul_g1(16384, r)))) end




implement shr_step_4 {h,l} (h, l) = let
  val a = h / 16
  val b = l / 16
  val r = sub_g1(h, mul_g1(16, a))
  prval pf = shr_digits_4{h/16, l/16, h - 16*(h/16), l - 16*(l/16)}()
in (shr_cast(pf) | @(a, add_g1(b, mul_g1(4096, r)))) end




implement shr_step_8 {h,l} (h, l) = let
  val a = h / 256
  val b = l / 256
  val r = sub_g1(h, mul_g1(256, a))
  prval pf = shr_digits_8{h/256, l/256, h - 256*(h/256), l - 256*(l/256)}()
in (shr_cast(pf) | @(a, add_g1(b, mul_g1(256, r)))) end




implement shr_step_16 {h,l} (h, l) = (shr_by_16{h,l}() | @(0, h))

fn _shr_stage_1 {n,h,l:nat | n < 2; h < 65536; l < 65536} (n: int n, h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (SHR(n, h, l, h2, l2) | @(int h2, int l2)) =
  if gte_g1(n, 1) then shr_step_1(h, l) else (SHR_zero() | @(h, l))

fn _shr_stage_2 {n,h,l:nat | n < 4; h < 65536; l < 65536} (n: int n, h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (SHR(n, h, l, h2, l2) | @(int h2, int l2)) =
  if gte_g1(n, 2) then let
    val (first | @(h1, l1)) = shr_step_2(h, l)
    val (rest | @(h2, l2)) = _shr_stage_1(sub_g1(n, 2), h1, l1)
  in (shr_add(first, rest) | @(h2, l2)) end
  else _shr_stage_1(n, h, l)

fn _shr_stage_4 {n,h,l:nat | n < 8; h < 65536; l < 65536} (n: int n, h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (SHR(n, h, l, h2, l2) | @(int h2, int l2)) =
  if gte_g1(n, 4) then let
    val (first | @(h1, l1)) = shr_step_4(h, l)
    val (rest | @(h2, l2)) = _shr_stage_2(sub_g1(n, 4), h1, l1)
  in (shr_add(first, rest) | @(h2, l2)) end
  else _shr_stage_2(n, h, l)

fn _shr_stage_8 {n,h,l:nat | n < 16; h < 65536; l < 65536} (n: int n, h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (SHR(n, h, l, h2, l2) | @(int h2, int l2)) =
  if gte_g1(n, 8) then let
    val (first | @(h1, l1)) = shr_step_8(h, l)
    val (rest | @(h2, l2)) = _shr_stage_4(sub_g1(n, 8), h1, l1)
  in (shr_add(first, rest) | @(h2, l2)) end
  else _shr_stage_4(n, h, l)

fn _shr_stage_16 {n,h,l:nat | n < 32; h < 65536; l < 65536} (n: int n, h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (SHR(n, h, l, h2, l2) | @(int h2, int l2)) =
  if gte_g1(n, 16) then let
    val (first | @(h1, l1)) = shr_step_16(h, l)
    val (rest | @(h2, l2)) = _shr_stage_8(sub_g1(n, 16), h1, l1)
  in (shr_add(first, rest) | @(h2, l2)) end
  else _shr_stage_8(n, h, l)

(* The word h:l shifted right by n < 32 bits, with the proof that it is,
   in at most five constant-time steps *)



implement shr_fast {n,h,l} (n, h, l) = _shr_stage_16(n, h, l)
