staload "./lib.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
(* str -- byte array operations *)
(* Pure computation on borrowed byte arrays. No $UNSAFE, no assume. *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"

(* ============================================================
   Option type for returning optional int values
   ============================================================ *)





(* ============================================================
   compare -- lexicographic comparison, returns -1/0/1
   ============================================================ *)






(* ============================================================
   eq -- equality check
   ============================================================ *)






(* ============================================================
   index_of -- first occurrence of a byte
   ============================================================ *)






(* ============================================================
   starts_with -- test whether s begins with pfx
   ============================================================ *)






(* ============================================================
   ends_with -- test whether s ends with suffix
   ============================================================ *)






(* ============================================================
   contains -- test whether s contains a given byte value
   ============================================================ *)






(* ============================================================
   trim_left -- returns new start offset (skips spaces/tabs/newlines)
   ============================================================ *)





(* ============================================================
   trim_right -- returns new end position
   ============================================================ *)





(* ============================================================
   to_upper_byte -- single byte a-z -> A-Z
   ============================================================ *)



(* ============================================================
   to_lower_byte -- single byte A-Z -> a-z
   ============================================================ *)



(* ============================================================
   int_to_str -- write decimal representation into buffer, return new pos
   ============================================================ *)

(* Writes value's decimal digits, with a leading '-' when negative, at
   buf[pos, r) and returns r: at most 11 bytes (an int is 32 bits: 10
   digits and the sign), which must fit. *)





(* ============================================================
   str_to_int -- parse decimal integer from byte array
   ============================================================ *)





(* ============================================================
   from_char_array -- create arr(byte) from a flat char array literal
   ============================================================ *)





(* ============================================================
   text_of_chars -- create text(n) from a flat char array literal
   ============================================================ *)





(* ============================================================
   has_suffix -- check if name ends with a borrow suffix
   ============================================================ *)






(* ============================================================
   name_eq -- check if name exactly matches a borrow
   ============================================================ *)






(* ============================================================
   Whitespace helper
   ============================================================ *)

fn _is_whitespace(c: int): bool =
  if $AR.eq_int_int(c, 32) then true
  else if $AR.eq_int_int(c, 9) then true
  else if $AR.eq_int_int(c, 10) then true
  else if $AR.eq_int_int(c, 13) then true
  else false

(* ============================================================
   Implementations
   ============================================================ *)

(* -- compare -- *)

implement compare {la}{na}{lb}{nb} (a, a_len, b, b_len) = let
  (* i stays within both buffers; the metric bounds the recursion. *)
  fun loop {i:nat | i <= na; i <= nb} .<na - i>.
    (a: !$A.borrow(byte, la, na), a_len: int na,
     b: !$A.borrow(byte, lb, nb), b_len: int nb, i: int i)
    : [r:int | ~1 <= r; r <= 1] int r =
    if i >= a_len then (if i < b_len then ~1 else 0)
    else if i >= b_len then 1
    else let
      val ca = byte2int0($A.read<byte>(a, i))
      val cb = byte2int0($A.read<byte>(b, i))
    in
      if ca < cb then ~1
      else if ca > cb then 1
      else loop(a, a_len, b, b_len, i + 1)
    end
in loop(a, a_len, b, b_len, 0) end

(* -- eq -- *)

implement eq {la}{na}{lb}{nb} (a, a_len, b, b_len) = let
  (* Only reached when the lengths are equal, so i indexes both. *)
  fun loop {i:nat | i <= na; na == nb} .<na - i>.
    (a: !$A.borrow(byte, la, na), a_len: int na,
     b: !$A.borrow(byte, lb, nb), i: int i): bool =
    if i >= a_len then true
    else if byte2int0($A.read<byte>(a, i)) != byte2int0($A.read<byte>(b, i)) then false
    else loop(a, a_len, b, i + 1)
in
  if a_len != b_len then false
  else loop(a, a_len, b, 0)
end

(* -- index_of -- *)

(* The index found is proven in range, so callers can use it directly. *)
implement index_of {la}{na} (haystack, h_len, needle_byte) = let
  fun loop {i:nat | i <= na} .<na - i>.
    (h: !$A.borrow(byte, la, na), h_len: int na, needle: int, i: int i)
    : str_option([j:nat | j < na] int j) =
    if i >= h_len then str_none()
    else if byte2int0($A.read<byte>(h, i)) = needle then str_some(i)
    else loop(h, h_len, needle, i + 1)
in loop(haystack, h_len, needle_byte, 0) end

(* -- starts_with -- *)

(* When the prefix is not longer than s, it provably fits at 0. *)
implement starts_with (s, s_len, pfx, p_len) =
  if p_len > s_len then false
  else match_at(s, 0, pfx, p_len)

(* -- ends_with -- *)

(* When the suffix is not longer than s, it provably fits at
   s_len - sf_len. *)
implement ends_with (s, s_len, suffix, sf_len) =
  if sf_len > s_len then false
  else match_at(s, s_len - sf_len, suffix, sf_len)

(* -- contains -- *)

implement contains {la}{na} (s, s_len, byte_val) = let
  fun loop {i:nat | i <= na} .<na - i>.
    (s: !$A.borrow(byte, la, na), s_len: int na, bv: int, i: int i): bool =
    if i >= s_len then false
    else if byte2int0($A.read<byte>(s, i)) = bv then true
    else loop(s, s_len, bv, i + 1)
in loop(s, s_len, byte_val, 0) end

(* -- trim_left -- *)

(* Start of the first non-whitespace byte, in [0, na]. *)
implement trim_left {la}{na} (s, s_len) = let
  fun loop {i:nat | i <= na} .<na - i>.
    (s: !$A.borrow(byte, la, na), s_len: int na, i: int i)
    : [r:nat | r <= na] int r =
    if i >= s_len then i
    else if _is_whitespace(byte2int0($A.read<byte>(s, i))) then loop(s, s_len, i + 1)
    else i
in loop(s, s_len, 0) end

(* -- trim_right -- *)

(* End of the last non-whitespace byte, in [0, na]. *)
implement trim_right {la}{na} (s, s_len) = let
  fun loop {p:nat | p <= na} .<p>.
    (s: !$A.borrow(byte, la, na), p: int p): [r:nat | r <= na] int r =
    if p <= 0 then 0
    else if _is_whitespace(byte2int0($A.read<byte>(s, p - 1))) then loop(s, p - 1)
    else p
in loop(s, s_len) end

(* -- to_upper_byte -- *)

implement to_upper_byte(b) =
  if $AR.gte_int_int(b, 97) then
    if $AR.lte_int_int(b, 122) then $AR.sub_int_int(b, 32)
    else b
  else b

(* -- to_lower_byte -- *)

implement to_lower_byte(b) =
  if $AR.gte_int_int(b, 65) then
    if $AR.lte_int_int(b, 90) then $AR.add_int_int(b, 32)
    else b
  else b

(* -- int_to_str -- *)

(* Writes the decimal form of value at buf[pos..] and returns the
   position after it. Every index and every digit byte is proven in
   range: the caller's p + 11 <= n bounds the positions, and nmod bounds
   each digit to [0, 10). head = |value| / 10 is below 10^9, so its
   digits are those of its nine lowest decimal places.

   |value| is written as head digits then one last digit, and is never
   computed itself: for the minimum int it does not fit in an int. For
   value < 0, ~(value + 1) = |value| - 1 always fits, and adding the 1
   back carries into head when its last digit is 9. *)
implement int_to_str {l}{n}{p}{v} (buf, pos, max_len, value) = let
  (* Number of digits of u in its k lowest decimal places *)
  fun places {u:nat}{k:nat} .<k>. (u: int u, k: int k): [d:nat | d <= k] int d =
    if k = 0 then 0 else if u = 0 then 0 else 1 + places(ndiv(u, 10), k - 1)
  (* Digits of u into buf[lo..w], least significant at w. *)
  fun write {u:nat}{lo,w:int | lo >= 0; lo - 1 <= w; w < n} .<w - lo + 1>.
    (buf: !$A.arr(byte, l, n), lo: int lo, w: int w, u: int u): void =
    if w < lo then ()
    else let
      val () = $A.set<byte>(buf, w, $A.int2byte(nmod(u, 10) + 48))
    in write(buf, lo, w - 1, ndiv(u, 10)) end
  val @(head, last) = (if value < 0 then let
      val m = ~(value + 1)
      val r = nmod(m, 10)
    in
      if r = 9 then @(ndiv(m, 10) + 1, 0) else @(ndiv(m, 10), r + 1)
    end
    else @(ndiv(value, 10), nmod(value, 10))
  ): [h:nat][d:nat | d < 10] @(int h, int d)
  val sign = (if value < 0 then 1 else 0): [s:nat | s <= 1] int s
  val hd = places(head, 9)
  val total = sign + hd + 1
  val () = (if sign > 0 then $A.set<byte>(buf, pos, $A.int2byte(45)) else ())
  val () = write(buf, pos + sign, pos + sign + hd - 1, head)
  val () = $A.set<byte>(buf, pos + sign + hd, $A.int2byte(last + 48))
in pos + total end

(* -- str_to_int -- *)

(* Parses an optional '-' followed by one or more decimal digits,
   filling the whole buffer. The loop index is bounded by n.

   The value is accumulated as -|value|, because the minimum int has no
   positive counterpart. A digit that would take it below the minimum
   int gives none, and so does a positive value one past the maximum. *)
implement str_to_int {lb}{n} (s, len) = let
  val neg = (byte2int0($A.read<byte>(s, 0)) = 45)
  val start = (if neg then 1 else 0): [st:nat | st <= 1] int st
  fun loop {i:nat | i <= n} .<n - i>.
    (s: !$A.borrow(byte, lb, n), len: int n, i: int i, acc: int): str_option(int) =
    if i >= len then str_some(acc)
    else let
      val c = byte2int0($A.read<byte>(s, i))
    in
      if c < 48 then str_none()
      else if c > 57 then str_none()
      (* acc * 10 - d must stay >= -2147483648 *)
      else if acc < ~214748364 then str_none()
      else if acc = ~214748364 && c - 48 > 8 then str_none()
      else loop(s, len, i + 1, acc * 10 - (c - 48))
    end
in
  if start >= len then str_none()
  else (case+ loop(s, len, start, 0) of
    | ~str_some(v) =>
      if neg then str_some(v)
      else if v < ~2147483647 then str_none()
      else str_some(~v)
    | ~str_none() => str_none())
end

(* -- from_char_array -- *)

implement from_char_array {n} (src, n) = let
  val arr = $A.alloc<byte>(n)
  fun copy_loop {l:agz}{n:pos}{k:nat | k <= n} .<n - k>.
    (arr: !$A.arr(byte, l, n), src: &(@[char][n]),
     i: int k, n: int n): void =
    if i >= n then ()
    else let
      val () = $A.set<byte>(arr, i, $A.int2byte(
        $AR.byte_of_char(src.[i])))
    in copy_loop(arr, src, i + 1, n) end
  val () = copy_loop(arr, src, 0, n)
in arr end

(* -- text_of_chars -- *)

fn _putc
  {n:pos}{i:nat | i < n}{v:nat | v < 256}
  (b: $A.text_builder(n, i), i: int i, c: int v)
  : $A.text_builder(n, i + 1) =
  $A.text_putc(b, i, c)

fun _text_from_chars {n:pos}{k:nat | k <= n} .<n-k>.
  (b: $A.text_builder(n, k), src: &(@[char][n]),
   i: int k, n: int n): $A.text_builder(n, n) =
  if i >= n then b
  else let
    val cb = $AR.byte_of_char(src.[i])
  in _text_from_chars(_putc(b, i, cb), src, i + 1, n) end

implement text_of_chars {n} (src, n) =
  $A.text_done(_text_from_chars($A.text_build(n), src, 0, n))

(* -- has_suffix -- *)

(* len <= n is in the type, so after len >= slen the suffix
   ent[len - slen .. len) provably lies inside the buffer. *)
implement has_suffix {l}{n}{k}{lp}{np}
  (ent, len, max, suf, slen) =
  if len < slen then false
  else match_at_arr(ent, len - slen, suf, slen)

(* -- name_eq -- *)

(* len <= n is in the type, so after len = slen the whole name
   provably fits in the buffer. *)
implement name_eq {l}{n}{k}{lp}{np}
  (ent, len, max, s, slen) =
  if len != slen then false
  else match_at_arr(ent, 0, s, slen)

(* ============================================================
   Byte reading and null scanning
   ============================================================ *)

(* True when pat[0..np) equals src[p..p+np). The pattern must fit:
   p + np <= n is part of the type, so there is no runtime range check.
   A caller that does not know whether it fits tests p + np <= n first.
*)




implement match_at {l}{n}{lp}{np}{p} (src, p, pat, np) = let
  fun loop {i:nat | i <= np} .<np - i>.
    (src: !$A.borrow(byte, l, n), p: int p,
     pat: !$A.borrow(byte, lp, np), np: int np, i: int i): bool =
    if i >= np then true
    else if byte2int0($A.read<byte>(src, p + i)) != byte2int0($A.read<byte>(pat, i)) then false
    else loop(src, p, pat, np, i + 1)
in loop(src, p, pat, np, 0) end

(* match_at for an array source. Replaces the former chars_match, which read
   ent[p + pi] with no bounds check at all. *)




implement match_at_arr {l}{n}{lp}{np}{p} (src, p, pat, np) = let
  fun loop {i:nat | i <= np} .<np - i>.
    (src: !$A.arr(byte, l, n), p: int p,
     pat: !$A.borrow(byte, lp, np), np: int np, i: int i): bool =
    if i >= np then true
    else if byte2int0($A.get<byte>(src, p + i)) != byte2int0($A.read<byte>(pat, i)) then false
    else loop(src, p, pat, np, i + 1)
in loop(src, p, pat, np, 0) end
(* Byte at a proven index p < n. *)



implement byte_at (src, p) = byte2int0($A.read<byte>(src, p))

(* Index of the first NUL byte at or after p, or n if there is none.
   The bound on p is proven by the caller, so there is no runtime range
   check and no fuel: the recursion is bounded by n - p. *)




implement find_null_at {l}{n}{p} (buf, p, n) = let
  fun loop {i:nat | p <= i; i <= n} .<n - i>.
    (buf: !$A.arr(byte, l, n), i: int i, n: int n)
    : [r:int | p <= r; r <= n] int r =
    if i >= n then i
    else if $AR.eq_int_int(byte2int0($A.get<byte>(buf, i)), 0) then i
    else loop(buf, i + 1, n)
in loop(buf, p, n) end

(* find_null_at for a borrow. *)




implement find_null_bv_at {l}{n}{p} (bv, p, n) = let
  fun loop {i:nat | p <= i; i <= n} .<n - i>.
    (bv: !$A.borrow(byte, l, n), i: int i, n: int n)
    : [r:int | p <= r; r <= n] int r =
    if i >= n then i
    else if $AR.eq_int_int(byte2int0($A.read<byte>(bv, i)), 0) then i
    else loop(bv, i + 1, n)
in loop(bv, p, n) end

(* ============================================================
   copy_from_borrow -- copy bytes from a borrow into an array
   ============================================================ *)







(* ============================================================
   copy_arr_region -- copy a region from one array into another
   ============================================================ *)







(* ============================================================
   borrow_region_eq -- compare two regions within the same borrow
   ============================================================ *)






(* ============================================================
   String to array conversion
   ============================================================ *)

(* Copies src[i, nb) to arr[i, nb); src must fit in arr. *)




implement fill_exact {l}{n}{lb}{nb}{i} (arr, src, n, slen, i) = let
  fun loop {j:nat | j <= nb} .<nb - j>.
    (arr: !$A.arr(byte, l, n), src: !$A.borrow(byte, lb, nb),
     n: int n, slen: int nb, j: int j): void =
    if j >= slen then ()
    else let
      val () = $A.set<byte>(arr, j, $A.read<byte>(src, j))
    in loop(arr, src, n, slen, j + 1) end
in loop(arr, src, n, slen, i) end

(* -- copy_from_borrow -- *)

implement copy_from_borrow {lb}{nb}{la}{na}{so}{do_}{c} (src, src_off, src_max, dst, dst_off, dst_max, count) = let
  fun loop {s,d,k:nat | s + k <= nb; d + k <= na} .<k>.
    (src: !$A.borrow(byte, lb, nb), s: int s, dst: !$A.arr(byte, la, na), d: int d, k: int k): void =
    if k <= 0 then ()
    else let
      val () = $A.set<byte>(dst, d, $A.read<byte>(src, s))
    in loop(src, s + 1, dst, d + 1, k - 1) end
in loop(src, src_off, dst, dst_off, count) end

(* -- copy_arr_region -- *)

implement copy_arr_region(src, src_off, src_max, dst, dst_max, count) = let
  val @(frozen, borrow) = $A.freeze<byte>(src)
  val () = copy_from_borrow(borrow, src_off, src_max,
                            dst, 0, dst_max, count)
  val () = $A.drop<byte>(frozen, borrow)
in $A.thaw<byte>(frozen) end

(* -- borrow_region_eq -- *)

implement borrow_region_eq {lb}{n}{oa}{ob}{c} (data, len, off_a, off_b, count) = let
  fun loop {a,b,k:nat | a + k <= n; b + k <= n} .<k>.
    (data: !$A.borrow(byte, lb, n), a: int a, b: int b, k: int k): bool =
    if k <= 0 then true
    else if $AR.neq_int_int(byte2int0($A.read<byte>(data, a)), byte2int0($A.read<byte>(data, b))) then false
    else loop(data, a + 1, b + 1, k - 1)
in loop(data, off_a, off_b, count) end

