staload "./lib.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
(* builder -- append-only byte string builder *)
(* Fixed-capacity buffer (512KB). Indexed type tracks position. *)
(* No runtime checks: callers prove capacity and byte ranges via constraints. *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"

(* ============================================================
   Constants
   ============================================================ *)



macdef _BUILDER_CAP = 524288

(* ============================================================
   Types
   ============================================================ *)







(* ============================================================
   API
   ============================================================ *)






















(* Decimal digits of num, with a leading '-' when negative: at most 11
   bytes (an int is 32 bits: 10 digits and the sign). *)






(* ============================================================
   Rope: text of any length, in builder-sized chunks
   ============================================================ *)

(* k chunks, each an array of BUILDER_CAP bytes whose first n hold text *)





(* Text of any length: the chunks already filled (newest first) and the
   one being filled. Each chunk is one BUILDER_CAP allocation, so no
   allocation grows with the text. *)





(* Appends the byte v *)


(* Appends s *)


(* Appends src[start, stop) *)



(* Appends b's text *)


(* The rope's chunks, oldest first: its text is their texts in order *)


(* Frees a list of chunks *)


(* ============================================================
   Implementations
   ============================================================ *)

implement create() = let
  val buf = $A.alloc<byte>(_BUILDER_CAP)
in Builder(buf, 0) end

implement length(b) = let
  val+ @Builder(_, pos) = b
  val p = pos
  prval () = fold@(b)
in p end

implement to_arr(b) = let
  val+ ~Builder(buf, pos) = b
in @(buf, pos) end

implement builder_free(b) = let
  val+ ~Builder(buf, _) = b
in $A.free<byte>(buf) end

implement put_byte(b, v) = let
  val+ @Builder(buf, pos) = b
  val () = $A.set<byte>(buf, pos, int2byte0(v))
  val () = pos := pos + 1
  prval () = fold@(b)
in end

implement put_char(b, v) = put_byte(b, v)

implement put_newline(b) = put_byte(b, 10)

(* |num| is written as head digits then one last digit, and is never
   computed itself: for the minimum int it does not fit in an int. For
   num < 0, ~(num + 1) = |num| - 1 always fits, and adding the 1 back
   carries into head when its last digit is 9. head = |num| / 10 is
   below 10^9, so it has at most nine digits. *)
implement put_int(b, num) = let
  (* The digits of u in its k lowest decimal places, without leading
     zeros: the higher places first, then this place's digit when u (this
     digit and the higher ones) is not 0. low_byte gives the digit's byte
     value its bound; it is the identity on 48 .. 57. *)
  fun head_digits {n:nat}{k:nat | n + k <= BUILDER_CAP} .<k>.
    (b: !builder(n) >> [m:nat | n <= m; m <= n + k] builder(m), u: int, k: int k): void =
    if k = 0 then ()
    else let
      val () = head_digits(b, u / 10, k - 1)
    in
      if u > 0 then put_byte(b, $AR.low_byte(u mod 10 + 48)) else ()
    end
  (* head's digits, then the last digit *)
  fn digits {n:nat | n + 10 <= BUILDER_CAP}
    (b: !builder(n) >> [m:nat | n < m; m <= n + 10] builder(m), head: int, last: int): void = let
    val () = head_digits(b, head, 9)
  in put_byte(b, $AR.low_byte(last + 48)) end
in
  if num < 0 then let
    val () = put_byte(b, 45)
    val m = ~(num + 1)
    val r = m mod 10
  in
    if r = 9 then digits(b, m / 10 + 1, 0) else digits(b, m / 10, r + 1)
  end
  else digits(b, num / 10, num mod 10)
end

implement bput(b, s) = let
  fun loop {sn:nat}{i:nat | i <= sn}{p:nat | p + sn - i <= BUILDER_CAP} .<sn - i>.
    (b: !builder(p) >> builder(p + sn - i),
     s: string sn, slen: int sn, i: int i): void =
    if i >= slen then ()
    else let
      val () = put_byte(b, $AR.byte_of_char(string_get_at(s, i)))
    in loop(b, s, slen, i + 1) end
  val slen = g1u2i(string1_length(s))
in loop(b, s, slen, 0) end

implement rope_create () = Rope(rope_nil(), create())

implement rope_put (r, v) = let
  val+ @Rope(cs, cur) = r
  val n = length(cur)
in
  if n < _BUILDER_CAP then let
    val () = put_byte(cur, v)
    prval () = fold@(r)
  in end
  else let
    val @(arr, len) = to_arr(cur)
    val () = cs := rope_cons(arr, len, cs)
    val () = cur := create()
    val () = put_byte(cur, v)
    prval () = fold@(r)
  in end
end

implement rope_bput (r, s) = let
  fun loop {sn:nat}{i:nat | i <= sn} .<sn - i>.
    (r: !rope, s: string sn, slen: int sn, i: int i): void =
    if i >= slen then ()
    else let
      val () = rope_put(r, $AR.byte_of_char(string_get_at(s, i)))
    in loop(r, s, slen, i + 1) end
in loop(r, s, g1u2i(string1_length(s)), 0) end

implement rope_copy {l}{n}{i,j} (r, src, start, stop) = let
  fun loop {k:nat | i <= k; k <= j} .<j - k>.
    (r: !rope, src: !$A.borrow(byte, l, n), k: int k): void =
    if k >= stop then ()
    else let
      val () = rope_put(r, $AR.low_byte(byte2int0($A.read<byte>(src, k))))
    in loop(r, src, k + 1) end
in loop(r, src, start) end

implement rope_append (r, b) = let
  val @(arr, len) = to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(arr)
  val () = rope_copy(r, bv, 0, len)
  val () = $A.drop<byte>(fz, bv)
in $A.free<byte>($A.thaw<byte>(fz)) end

implement rope_chunks (r) = let
  val+ ~Rope(cs, cur) = r
  val @(arr, len) = to_arr(cur)
  (* cs is newest first: reversed onto acc, it comes out oldest first *)
  fun rev {a,b:nat} .<a>. (cs: rope_list(a), acc: rope_list(b)): rope_list(a + b) =
    case+ cs of
    | ~rope_nil() => acc
    | ~rope_cons(x, n, tl) => rev(tl, rope_cons(x, n, acc))
in rev(rope_cons(arr, len, cs), rope_nil()) end

implement rope_list_free (cs) = let
  fun loop {k:nat} .<k>. (cs: rope_list(k)): void =
    case+ cs of
    | ~rope_nil() => ()
    | ~rope_cons(x, _, tl) => let val () = $A.free<byte>(x) in loop(tl) end
in loop(cs) end

(* ============================================================
   Static tests
   ============================================================ *)

fn _check_byte {l:agz}{idx:nat | idx < BUILDER_CAP}
  (arr: !$A.arr(byte, l, BUILDER_CAP), idx: int idx, expected: int): bool =
  $AR.eq_int_int(byte2int0($A.get<byte>(arr, idx)), expected)

fn _test_create_free(): bool = let
  val b = create()
  val () = builder_free(b)
in true end

fn _test_put_byte(): bool = let
  val b = create()
  val () = put_byte(b, 65)
  val () = put_byte(b, 66)
  val l = length(b)
  val @(arr, len) = to_arr(b)
  val c0 = _check_byte(arr, 0, char2int0('A'))
  val c1 = _check_byte(arr, 1, char2int0('B'))
  val ok = l = 2 && len = 2 && c0 && c1
  val () = $A.free<byte>(arr)
in ok end

fn _test_put_int(): bool = let
  val b = create()
  val () = put_int(b, 42)
  val l1 = length(b)
  val @(arr, _) = to_arr(b)
  val c0 = _check_byte(arr, 0, char2int0('4'))
  val c1 = _check_byte(arr, 1, char2int0('2'))
  val ok = l1 = 2 && c0 && c1
  val () = $A.free<byte>(arr)
in ok end

fn _test_put_int_zero(): bool = let
  val b = create()
  val () = put_int(b, 0)
  val @(arr, len) = to_arr(b)
  val c0 = _check_byte(arr, 0, char2int0('0'))
  val ok = len = 1 && c0
  val () = $A.free<byte>(arr)
in ok end

fn _test_put_int_negative(): bool = let
  val b = create()
  val () = put_int(b, ~1)
  val @(arr, len) = to_arr(b)
  val c0 = _check_byte(arr, 0, char2int0('-'))
  val c1 = _check_byte(arr, 1, char2int0('1'))
  val ok = len = 2 && c0 && c1
  val () = $A.free<byte>(arr)
in ok end

fn _test_put_newline(): bool = let
  val b = create()
  val () = put_newline(b)
  val @(arr, len) = to_arr(b)
  val c0 = _check_byte(arr, 0, char2int0('\n'))
  val ok = len = 1 && c0
  val () = $A.free<byte>(arr)
in ok end

fn _test_bput(): bool = let
  val b = create()
  val () = bput(b, "hi")
  val @(arr, len) = to_arr(b)
  val c0 = _check_byte(arr, 0, char2int0('h'))
  val c1 = _check_byte(arr, 1, char2int0('i'))
  val ok = len = 2 && c0 && c1
  val () = $A.free<byte>(arr)
in ok end
