staload "./lib.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
(* builder -- append-only byte string builder *)
(* Fixed-capacity buffer (512KB). Indexed type tracks position. *)
(* No runtime bounds checks -- callers prove safety via constraints. *)

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

implement put_newline(b) = put_byte(b, char2int0('\n'))

implement put_int(b, num) = let
  fun _put_digits {n:nat}{fuel:nat | n + fuel <= BUILDER_CAP} .<fuel>.
    (b: !builder(n) >> [m:nat | n <= m; m <= n + fuel] builder(m),
     v: int, fuel: int fuel): void =
    if fuel <= 0 then ()
    else if v < 10 then
      put_byte(b, v + char2int0('0'))
    else let
      val () = _put_digits(b, v / 10, fuel - 1)
    in
      put_byte(b, (v mod 10) + char2int0('0'))
    end
in
  if num < 0 then let
    val () = put_byte(b, char2int0('-'))
    val abs_num = ~num
  in
    if abs_num < 0 then
      put_byte(b, char2int0('0'))
    else
      _put_digits(b, abs_num, 20)
  end
  else if num = 0 then
    put_byte(b, char2int0('0'))
  else
    _put_digits(b, num, 20)
end

implement bput(b, s) = let
  fun loop {sn:nat}{i:nat | i <= sn}{fuel:nat}{n:nat | n + fuel <= BUILDER_CAP} .<fuel>.
    (b: !builder(n) >> [m:nat | n <= m; m <= n + fuel] builder(m),
     s: string sn, slen: int sn, i: int i, fuel: int fuel): void =
    if fuel <= 0 then ()
    else if i >= slen then ()
    else let
      val c = char2int0(string_get_at(s, i))
      val () = put_byte(b, c)
    in loop(b, s, slen, i + 1, fuel - 1) end
  val slen_sz = string1_length(s)
  val slen = g1u2i(slen_sz)
in loop(b, s, slen, 0, slen) end

implement bput_int(b, v) = let
  val digits = $A.alloc<byte>(16)
  fun fill {ld:agz}{pos:nat}{fuel:nat | pos + fuel <= 15} .<fuel>.
    (digits: !$A.arr(byte, ld, 16), v: int, pos: int pos, fuel: int fuel): [r:nat | r <= 16] int r =
    if fuel <= 0 then pos
    else if v < 10 then let
      val () = $A.set<byte>(digits, pos, int2byte0(char2int0('0') + v))
    in pos + 1 end
    else let
      val () = $A.set<byte>(digits, pos, int2byte0(char2int0('0') + $AR.mod_int_int(v, 10)))
    in fill(digits, $AR.div_int_int(v, 10), pos + 1, fuel - 1) end
  fun emit {ld:agz}{n:nat}{fuel:nat | n + fuel <= BUILDER_CAP}{pos:int | pos < 16} .<fuel>.
    (digits: !$A.arr(byte, ld, 16), b: !builder(n) >> [m:nat | n <= m; m <= n + fuel] builder(m),
     pos: int pos, fuel: int fuel): void =
    if fuel <= 0 then ()
    else if pos < 0 then ()
    else let
      val () = put_byte(b, byte2int0($A.get<byte>(digits, pos)))
    in emit(digits, b, pos - 1, fuel - 1) end
in
  if v < 0 then let
    val abs_v = ~v
  in
    if abs_v < 0 then let
      val () = put_byte(b, char2int0('0'))
    in $A.free<byte>(digits) end
    else let
      val ndigits = fill(digits, abs_v, 0, 15)
      val () = put_byte(b, char2int0('-'))
      val () = emit(digits, b, ndigits - 1, 15)
    in $A.free<byte>(digits) end
  end
  else let
    val ndigits = fill(digits, v, 0, 15)
    val () = emit(digits, b, ndigits - 1, 15)
  in $A.free<byte>(digits) end
end

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
  val () = put_byte(b, char2int0('A'))
  val () = put_byte(b, char2int0('B'))
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

fn _test_bput_int(): bool = let
  val b = create()
  val () = bput_int(b, 123)
  val @(arr, len) = to_arr(b)
  val c0 = _check_byte(arr, 0, char2int0('1'))
  val c1 = _check_byte(arr, 1, char2int0('2'))
  val c2 = _check_byte(arr, 2, char2int0('3'))
  val ok = len = 3 && c0 && c1 && c2
  val () = $A.free<byte>(arr)
in ok end
