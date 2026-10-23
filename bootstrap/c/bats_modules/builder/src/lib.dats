staload "./lib.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
(* builder -- append-only byte string builder *)
(* Append-only buffer of at most BUILDER_CAP (512KB) bytes. The indexed type
   tracks the length. The array inside starts at INITIAL_CAP bytes and is
   made twice as large when a byte does not fit, so its capacity is not in
   the type of builder: a builder of a few bytes costs a few bytes (#43). *)
(* No runtime checks: callers prove capacity and byte ranges via constraints. *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"

(* ============================================================
   Constants
   ============================================================ *)



macdef _BUILDER_CAP = 524288

(* The array of a new builder: 64 bytes (Go's bytes.Buffer smallBufferSize).
   64 * 8192 = BUILDER_CAP, so doubling reaches BUILDER_CAP exactly. *)


(* ============================================================
   Types
   ============================================================ *)

(* The bytes of a builder holding m of them: an array of cap >= m bytes, of
   which the first m are written. cap is existential, so what the array
   holds in all is not in builder's type. It is public only because a
   datavtype cannot be abstract without `assume`, which a safe package may
   not write: nothing outside this package makes or takes apart a store. *)










(* ============================================================
   API
   ============================================================ *)




(* The text as an array of BUILDER_CAP bytes whose first n hold it, the rest
   zero: made by copying, so a consumer typed arr(byte, l, BUILDER_CAP) is
   unchanged. into_arr does not copy. *)



(* The text as the builder's own array, of cap >= n bytes whose first n hold
   it, the rest zero. No copy. *)


















(* Decimal digits of num, with a leading '-' when negative: at most 11
   bytes (an int is 32 bits: 10 digits and the sign). *)






(* ============================================================
   Rope: text of any length, in builder-sized chunks
   ============================================================ *)

(* k chunks, each an array of BUILDER_CAP bytes whose first n hold text. The
   published form, kept as it is until builder#56 removes it. *)





(* Text of any length: the chunks already filled (newest first) and the
   one being filled. Each chunk is one BUILDER_CAP allocation, so no
   allocation grows with the text. *)





(* Appends the byte v *)


(* Appends s *)


(* Appends src[start, stop) *)



(* Appends b's text *)


(* The rope's chunks, oldest first: its text is their texts in order *)


(* Frees a list of chunks *)


(* ------------------------------------------------------------
   The sized rope (#51): a chunk is the builder's own array. It is a new
   type beside the rope above, which stays as published (builder#56
   removes that one), so nothing a dependent matches on changes.
   ------------------------------------------------------------ *)

(* k chunks, newest first. A chunk is a builder's own array (into_arr), of
   cap bytes whose first n hold text: n <= cap <= BUILDER_CAP. The rule for
   cap (#51): a builder's array starts at INITIAL_CAP and doubles when a
   byte does not fit, so a chunk is INITIAL_CAP bytes or fewer than twice
   the bytes it holds. A chunk of a few bytes is 64 bytes, not BUILDER_CAP;
   only a chunk that holds that much is BUILDER_CAP bytes. The rule is in
   the comment, not the type: builder hides its capacity. *)





(* Text of any length: the chunks already filled (newest first) and the
   one being filled. Each chunk is one builder's array, so the allocation
   of a chunk is what its text needs, and no allocation grows with the
   text. *)





(* Appends the byte v *)


(* Appends s *)


(* Appends src[start, stop) *)



(* Appends b's text *)


(* The rope's chunks, oldest first: its text is their texts in order *)


(* Frees a list of sized chunks *)


(* ============================================================
   Implementations
   ============================================================ *)

(* The bytes [0, k) of src, into dst at the same places. Both arrays are
   proved to hold them: k <= n, and n is no more than either capacity. *)
fun copy_bytes {l,m:agz}{n,cap,new_cap,k:nat | n <= cap; n <= new_cap; k <= n} .<n - k>.
  (src: !$A.arr(byte, l, cap), dst: !$A.arr(byte, m, new_cap), n: int n, k: int k): void =
  if k >= n then ()
  else let
    val () = $A.set<byte>(dst, k, $A.get<byte>(src, k))
  in copy_bytes(src, dst, n, k + 1) end

(* A new capacity for a store of capacity cap holding n bytes, with room
   for one more and at most BUILDER_CAP: twice cap, or n + 1 when that is
   more. Doubling makes the cost of a byte amortised constant. *)
fn grown_cap {n,cap:nat | n < BUILDER_CAP; n <= cap; cap <= BUILDER_CAP}
  (n: int n, cap: int cap): [new_cap:pos | n + 1 <= new_cap; new_cap <= BUILDER_CAP] int(new_cap) =
  if cap + cap < n + 1 then n + 1
  else if cap + cap <= _BUILDER_CAP then cap + cap
  else _BUILDER_CAP

(* The byte put in an array made larger: the old one is copied and freed.
   Only the n bytes written are copied; the rest of the new array is zero. *)
fn store_grow {n:nat | n < BUILDER_CAP}{v:nat | v < 256}
  (st: builder_store(n), pos: int n, v: int v): builder_store(n + 1) = let
  val+ ~BuilderStore(buf, old_cap) = st
  val new_cap = grown_cap(pos, old_cap)
  val grown = $A.alloc<byte>(new_cap)
  val () = copy_bytes(buf, grown, pos, 0)
  val () = $A.set<byte>(grown, pos, int2byte0(v))
  val () = $A.free<byte>(buf)
in BuilderStore(grown, new_cap) end

(* Where the array has room the byte is written in place; else the array is
   made larger first. The store's length is the builder's, so pos is the
   first free place and pos <= cap. *)
fn store_put {n:nat | n < BUILDER_CAP}{v:nat | v < 256}
  (st: builder_store(n), pos: int n, v: int v): builder_store(n + 1) = let
  val+ @BuilderStore(buf, cap) = st
in
  if pos < cap then let
    val () = $A.set<byte>(buf, pos, int2byte0(v))
    prval () = fold@(st)
  in st end
  else let
    prval () = fold@(st)
  in store_grow(st, pos, v) end
end

implement create() = let
  (* 64 is INITIAL_CAP; a literal, so that its type is int(64) *)
  val buf = $A.alloc<byte>(64)
in Builder(BuilderStore(buf, 64), 0) end

implement length(b) = let
  val+ @Builder(_, pos) = b
  val p = pos
  prval () = fold@(b)
in p end

implement into_arr(b) = let
  val+ ~Builder(st, pos) = b
  val+ ~BuilderStore(buf, _) = st
in @(buf, pos) end

implement to_arr(b) = let
  val @(small, pos) = into_arr(b)
  val big = $A.alloc<byte>(_BUILDER_CAP)
  val () = copy_bytes(small, big, pos, 0)
  val () = $A.free<byte>(small)
in @(big, pos) end

implement builder_free(b) = let
  val+ ~Builder(st, _) = b
  val+ ~BuilderStore(buf, _) = st
in $A.free<byte>(buf) end

(* The store is taken out of the builder and put back one longer: the field
   is unfolded (@), not consumed, because consuming a builder passed by !
   and assigning it compiles to C that clang refuses (bats#327). *)
implement put_byte(b, v) = let
  val+ @Builder(st, pos) = b
  val p = pos
  val s = st
  val () = st := store_put(s, p, v)
  val () = pos := p + 1
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
  val @(arr, len) = into_arr(b)
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

implement sized_rope_create () = SizedRope(rope_sized_nil(), create())

implement sized_rope_put (r, v) = let
  val+ @SizedRope(cs, cur) = r
  val n = length(cur)
in
  if n < _BUILDER_CAP then let
    val () = put_byte(cur, v)
    prval () = fold@(r)
  in end
  else let
    val @(arr, len) = into_arr(cur)
    val () = cs := rope_sized_cons(arr, len, cs)
    val () = cur := create()
    val () = put_byte(cur, v)
    prval () = fold@(r)
  in end
end

implement sized_rope_bput (r, s) = let
  fun loop {sn:nat}{i:nat | i <= sn} .<sn - i>.
    (r: !sized_rope, s: string sn, slen: int sn, i: int i): void =
    if i >= slen then ()
    else let
      val () = sized_rope_put(r, $AR.byte_of_char(string_get_at(s, i)))
    in loop(r, s, slen, i + 1) end
in loop(r, s, g1u2i(string1_length(s)), 0) end

implement sized_rope_copy {l}{n}{i,j} (r, src, start, stop) = let
  fun loop {k:nat | i <= k; k <= j} .<j - k>.
    (r: !sized_rope, src: !$A.borrow(byte, l, n), k: int k): void =
    if k >= stop then ()
    else let
      val () = sized_rope_put(r, $AR.low_byte(byte2int0($A.read<byte>(src, k))))
    in loop(r, src, k + 1) end
in loop(r, src, start) end

implement sized_rope_append (r, b) = let
  val @(arr, len) = into_arr(b)
  val @(fz, bv) = $A.freeze<byte>(arr)
  val () = sized_rope_copy(r, bv, 0, len)
  val () = $A.drop<byte>(fz, bv)
in $A.free<byte>($A.thaw<byte>(fz)) end

implement sized_rope_chunks (r) = let
  val+ ~SizedRope(cs, cur) = r
  val @(arr, len) = into_arr(cur)
  (* cs is newest first: reversed onto acc, it comes out oldest first *)
  fun rev {a,b:nat} .<a>. (cs: rope_sized_list(a), acc: rope_sized_list(b)): rope_sized_list(a + b) =
    case+ cs of
    | ~rope_sized_nil() => acc
    | ~rope_sized_cons(x, n, tl) => rev(tl, rope_sized_cons(x, n, acc))
in rev(rope_sized_cons(arr, len, cs), rope_sized_nil()) end

implement rope_sized_list_free (cs) = let
  fun loop {k:nat} .<k>. (cs: rope_sized_list(k)): void =
    case+ cs of
    | ~rope_sized_nil() => ()
    | ~rope_sized_cons(x, _, tl) => let val () = $A.free<byte>(x) in loop(tl) end
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
