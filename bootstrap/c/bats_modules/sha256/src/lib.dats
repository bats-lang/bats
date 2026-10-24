staload "./lib.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
(* sha256 -- SHA-256 and SHA-1 (FIPS 180-4) in Bats
   No C code, no $UNSAFE, no praxi. Two implementations of SHA-256 sit side
   by side. hash, init, update and finish (below) are the fast one: 32-bit
   words are uint, and C unsigned arithmetic wraps modulo 2^32 by definition,
   so no operation overflows (signed int arithmetic would); it assumes a
   32-bit unsigned int, as on every bats target (LP64 and ILP32 native,
   wasm32); it is tested, not proved. proved_hash, proved_init, proved_update
   and proved_finish, and sha1_digest, run the proved code: a 32-bit word is
   arith's word32, one machine word at run time and its two 16-bit halves in
   the types (arith's ROTR, SHR, ADD32), and the digest is the one the proofs
   are about (sha256#29). The proved code is about 8 times slower than the
   fast one in a release build (452 instructions a byte against 52; it was 30
   times slower with a word as two ints, sha256#34, #40, #48), so the fast API
   is not replaced by it yet. *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"

(* ============================================================
   Public API
   ============================================================ *)

(* The SHA-256 of data[0, data_len) as 64 lowercase hex digits in out. *)





(* An incremental SHA-256: init, update with each piece of the input in
   order, then finish. For input that does not fit one array, such as a
   file read in chunks. *)











(* Hashes data[0, len) after everything given so far. *)




(* The SHA-256 of everything given, as 64 lowercase hex digits in out. *)


(* ============================================================
   Word functions (FIPS 180-4, section 4.1.2)
   ============================================================ *)

(* One round of FIPS 180-4, section 6.2.2, step 3, without the shift of the
   eight working variables, which the caller does by naming them in another
   order: the new e, d + T1, and the new a, T1 + T2, where kw is K_t + W_t.
   Ch(e, f, g) is written g xor (e and (f xor g)) and Maj(a, b, c) as
   (a and b) or (c and (a or b)), the same functions with fewer operations;
   a rotation by n is (x >> n) or (x << (32 - n)), written with its amount
   and in the form a C compiler turns into a rotate. The code is not proved (the proved SHA-256
   is proved_hash) and is written for a build without optimisation, where
   every operation is a call: rotations by their amounts, no function of a
   sigma, the rounds one after another (scripts/gen-fast-compress.py). *)
fn _round (a: uint, b: uint, c: uint, d: uint, e: uint, f: uint, g: uint, h: uint,
           kw: uint): @(uint, uint) = let
  val t1 = h
    + (((e >> 6) lor (e << 26)) lxor ((e >> 11) lor (e << 21)) lxor ((e >> 25) lor (e << 7)))
    + (g lxor (e land (f lxor g))) + kw
  val t2 = (((a >> 2) lor (a << 30)) lxor ((a >> 13) lor (a << 19)) lxor ((a >> 22) lor (a << 10)))
    + ((a land b) lor (c land (a lor b)))
in @(d + t1, t1 + t2) end

(* W_t of a block from the words before it: sigma1(W_t-2) + W_t-7 +
   sigma0(W_t-15) + W_t-16; the arguments are those, in that order *)
fn _schedule (w2: uint, w7: uint, w15: uint, w16: uint): uint =
  (((w2 >> 17) lor (w2 << 15)) lxor ((w2 >> 19) lor (w2 << 13)) lxor (w2 >> 10)) + w7
  + (((w15 >> 7) lor (w15 << 25)) lxor ((w15 >> 18) lor (w15 << 14)) lxor (w15 >> 3)) + w16

(* The big-endian word of data[at, at + 4) *)
fn _word {ld:agz}{nd:pos}{at:nat | at + 4 <= nd}
  (data: !$A.arr(byte, ld, nd), at: int at): uint =
  (g0int2uint_int_uint(byte2int0($A.get<byte>(data, at))) << 24)
  lor (g0int2uint_int_uint(byte2int0($A.get<byte>(data, at + 1))) << 16)
  lor (g0int2uint_int_uint(byte2int0($A.get<byte>(data, at + 2))) << 8)
  lor g0int2uint_int_uint(byte2int0($A.get<byte>(data, at + 3)))

fn _u (x: int): uint = g0int2uint_int_uint(x)

(* ============================================================
   The word functions, proved (FIPS 180-4, section 4.1.2)

   A word is arith's word32(high, low): one unsigned int at run time, and
   in the types its two 16-bit halves (arith's ROTR, SHR, ADD32: the solver
   of an int build is 32-bit, so no proof names 2 to the 32). Each relation below is the
   standard's definition of the function, composed from arith's
   specifications of the bit operations; each function returns the proof
   that its result is related to its arguments (sha256#29).
   ============================================================ *)

(* CH(xh, xl, yh, yl, zh, zl, rh, rl): r is Ch(x, y, z) = (x and y) xor
   ((not x) and z) *)








(* MAJ(xh, xl, yh, yl, zh, zl, rh, rl): r is Maj(x, y, z) = (x and y) xor
   (x and z) xor (y and z) *)









(* BIG_SIGMA_0(xh, xl, rh, rl): r is the upper case sigma 0 of x,
   ROTR 2 xor ROTR 13 xor ROTR 22; BIG_SIGMA_1: ROTR 6, 11, 25 *)














(* SMALL_SIGMA_0(xh, xl, rh, rl): r is the lower case sigma 0 of x, ROTR 7
   xor ROTR 18 xor SHR 3; SMALL_SIGMA_1: ROTR 17 xor ROTR 19 xor SHR 10 *)


















implement word_ch_w32 (x, y, z) = let
  val (pah, pal | a) = $AR.word32_and(x, y)
  val (pnot | n) = $AR.word32_not(x)
  val (pbh, pbl | b) = $AR.word32_and(n, z)
  val (prh, prl | r) = $AR.word32_xor(a, b)
in (CH_mk(pah, pal, pnot, pbh, pbl, prh, prl) | r) end

(* Deprecated (sha256#48): word_ch is kept as published, with the two 16-bit halves as ints; use word_ch_w32. It is removed in a later version, after one published version with both. *)




implement word_ch (xh, xl, yh, yl, zh, zl) = let
  val (pah, pal | @(ah, al)) = $AR.and32(xh, xl, yh, yl)
  val (pnot | @(nh, nl)) = $AR.not32(xh, xl)
  val (pbh, pbl | @(bh, bl)) = $AR.and32(nh, nl, zh, zl)
  val (prh, prl | @(rh, rl)) = $AR.xor32(ah, al, bh, bl)
in (CH_mk(pah, pal, pnot, pbh, pbl, prh, prl) | @(rh, rl)) end





implement word_maj_w32 (x, y, z) = let
  val (pah, pal | a) = $AR.word32_and(x, y)
  val (pbh, pbl | b) = $AR.word32_and(x, z)
  val (pch, pcl | c) = $AR.word32_and(y, z)
  val (psh, psl | s) = $AR.word32_xor(a, b)
  val (prh, prl | r) = $AR.word32_xor(s, c)
in (MAJ_mk(pah, pal, pbh, pbl, pch, pcl, psh, psl, prh, prl) | r) end

(* Deprecated (sha256#48): word_maj is kept as published, with the two 16-bit halves as ints; use word_maj_w32. It is removed in a later version, after one published version with both. *)




implement word_maj (xh, xl, yh, yl, zh, zl) = let
  val (pah, pal | @(ah, al)) = $AR.and32(xh, xl, yh, yl)
  val (pbh, pbl | @(bh, bl)) = $AR.and32(xh, xl, zh, zl)
  val (pch, pcl | @(ch, cl)) = $AR.and32(yh, yl, zh, zl)
  val (psh, psl | @(sh, sl)) = $AR.xor32(ah, al, bh, bl)
  val (prh, prl | @(rh, rl)) = $AR.xor32(sh, sl, ch, cl)
in (MAJ_mk(pah, pal, pbh, pbl, pch, pcl, psh, psl, prh, prl) | @(rh, rl)) end




implement big_sigma_0_w32 (x) = let
  val (pa | a) = $AR.word32_rotr_inline(x, 2)
  val (pb | b) = $AR.word32_rotr_inline(x, 13)
  val (pc | c) = $AR.word32_rotr_inline(x, 22)
  val (psh, psl | s) = $AR.word32_xor(a, b)
  val (prh, prl | r) = $AR.word32_xor(s, c)
in (BIG_SIGMA_0_mk(pa, pb, pc, psh, psl, prh, prl) | r) end

(* Deprecated (sha256#48): big_sigma_0 is kept as published, with the two 16-bit halves as ints; use big_sigma_0_w32. It is removed in a later version, after one published version with both. *)



implement big_sigma_0 (xh, xl) = let
  val (pa | @(ah, al)) = $AR.rotr_fast(2, xh, xl)
  val (pb | @(bh, bl)) = $AR.rotr_fast(13, xh, xl)
  val (pc | @(ch, cl)) = $AR.rotr_fast(22, xh, xl)
  val (psh, psl | @(sh, sl)) = $AR.xor32(ah, al, bh, bl)
  val (prh, prl | @(rh, rl)) = $AR.xor32(sh, sl, ch, cl)
in (BIG_SIGMA_0_mk(pa, pb, pc, psh, psl, prh, prl) | @(rh, rl)) end




implement big_sigma_1_w32 (x) = let
  val (pa | a) = $AR.word32_rotr_inline(x, 6)
  val (pb | b) = $AR.word32_rotr_inline(x, 11)
  val (pc | c) = $AR.word32_rotr_inline(x, 25)
  val (psh, psl | s) = $AR.word32_xor(a, b)
  val (prh, prl | r) = $AR.word32_xor(s, c)
in (BIG_SIGMA_1_mk(pa, pb, pc, psh, psl, prh, prl) | r) end

(* Deprecated (sha256#48): big_sigma_1 is kept as published, with the two 16-bit halves as ints; use big_sigma_1_w32. It is removed in a later version, after one published version with both. *)



implement big_sigma_1 (xh, xl) = let
  val (pa | @(ah, al)) = $AR.rotr_fast(6, xh, xl)
  val (pb | @(bh, bl)) = $AR.rotr_fast(11, xh, xl)
  val (pc | @(ch, cl)) = $AR.rotr_fast(25, xh, xl)
  val (psh, psl | @(sh, sl)) = $AR.xor32(ah, al, bh, bl)
  val (prh, prl | @(rh, rl)) = $AR.xor32(sh, sl, ch, cl)
in (BIG_SIGMA_1_mk(pa, pb, pc, psh, psl, prh, prl) | @(rh, rl)) end




implement small_sigma_0_w32 (x) = let
  val (pa | a) = $AR.word32_rotr_inline(x, 7)
  val (pb | b) = $AR.word32_rotr_inline(x, 18)
  val (pc | c) = $AR.word32_shr(x, 3)
  val (psh, psl | s) = $AR.word32_xor(a, b)
  val (prh, prl | r) = $AR.word32_xor(s, c)
in (SMALL_SIGMA_0_mk(pa, pb, pc, psh, psl, prh, prl) | r) end

(* Deprecated (sha256#48): small_sigma_0 is kept as published, with the two 16-bit halves as ints; use small_sigma_0_w32. It is removed in a later version, after one published version with both. *)



implement small_sigma_0 (xh, xl) = let
  val (pa | @(ah, al)) = $AR.rotr_fast(7, xh, xl)
  val (pb | @(bh, bl)) = $AR.rotr_fast(18, xh, xl)
  val (pc | @(ch, cl)) = $AR.shr(3, xh, xl)
  val (psh, psl | @(sh, sl)) = $AR.xor32(ah, al, bh, bl)
  val (prh, prl | @(rh, rl)) = $AR.xor32(sh, sl, ch, cl)
in (SMALL_SIGMA_0_mk(pa, pb, pc, psh, psl, prh, prl) | @(rh, rl)) end




implement small_sigma_1_w32 (x) = let
  val (pa | a) = $AR.word32_rotr_inline(x, 17)
  val (pb | b) = $AR.word32_rotr_inline(x, 19)
  val (pc | c) = $AR.word32_shr(x, 10)
  val (psh, psl | s) = $AR.word32_xor(a, b)
  val (prh, prl | r) = $AR.word32_xor(s, c)
in (SMALL_SIGMA_1_mk(pa, pb, pc, psh, psl, prh, prl) | r) end

(* Deprecated (sha256#48): small_sigma_1 is kept as published, with the two 16-bit halves as ints; use small_sigma_1_w32. It is removed in a later version, after one published version with both. *)



implement small_sigma_1 (xh, xl) = let
  val (pa | @(ah, al)) = $AR.rotr_fast(17, xh, xl)
  val (pb | @(bh, bl)) = $AR.rotr_fast(19, xh, xl)
  val (pc | @(ch, cl)) = $AR.shr(10, xh, xl)
  val (psh, psl | @(sh, sl)) = $AR.xor32(ah, al, bh, bl)
  val (prh, prl | @(rh, rl)) = $AR.xor32(sh, sl, ch, cl)
in (SMALL_SIGMA_1_mk(pa, pb, pc, psh, psl, prh, prl) | @(rh, rl)) end

(* ============================================================
   Words in an array, and the message schedules, proved
   (FIPS 180-4, sections 6.1.2 and 6.2.2, step 1)

   The cells of a byte array are known to the types (array's barr). A
   word of an array is four of its cells, the most significant byte
   first, so a word needs no array of its own and a message block's words
   are read from the bytes the block is: WORD_AT(cells, at, high, low) says
   that the four cells from `at` are the word high:low (high = 256 * b0 +
   b1, low = 256 * b2 + b3), and WORD_SET that setting four cells made the
   word. The words of the schedule are stored at 4 * t.
   ============================================================ *)

(* WORD_AT(cs, at, high, low): the cells at, at + 1, at + 2 and at + 3 of
   cs are the word high:low, big endian *)






(* WORD_SET(cs, at, high, low, cs2): cs2 is cs with the four cells from
   `at` set to the word high:low, one after the other *)






(* The word at `at`, with the proof that it is *)




implement word_get_w32 {l}{n,at}{cs} (cells, at) = let
  val (first, second, third, fourth | @(b0, b1, b2, b3)) = $A.barr_get_be32_inline(cells, at)
  val word_value = $AR.word32_pack_inline(b0, b1, b2, b3)
in (WORD_AT_mk(first, second, third, fourth) | word_value) end

(* Deprecated (sha256#48): word_get is kept as published, with the two 16-bit halves as ints; use word_get_w32. It is removed in a later version, after one published version with both. *)




implement word_get {l}{n,at}{cs} (cells, at) = let
  val (first | b0) = $A.barr_get_inline(cells, at)
  val (second | b1) = $A.barr_get_inline(cells, at + 1)
  val (third | b2) = $A.barr_get_inline(cells, at + 2)
  val (fourth | b3) = $A.barr_get_inline(cells, at + 3)
in (WORD_AT_mk(first, second, third, fourth) | @(256 * b0 + b1, 256 * b2 + b3)) end

(* The four cells from `at` set to the word, with the proof that they are *)




implement word_set_w32 {l}{n,at}{cs}{high,low} (cells, at, word_value) = let
  val (byte0 | b0) = $AR.word32_byte_inline(word_value, 0)
  val (byte1 | b1) = $AR.word32_byte_inline(word_value, 1)
  val (byte2 | b2) = $AR.word32_byte_inline(word_value, 2)
  val (byte3 | b3) = $AR.word32_byte_inline(word_value, 3)
  prval $AR.WORD_BYTE_0() = byte0
  prval $AR.WORD_BYTE_1() = byte1
  prval $AR.WORD_BYTE_2() = byte2
  prval $AR.WORD_BYTE_3() = byte3
  val (first | cells) = $A.barr_set_inline(cells, at, b0)
  val (second | cells) = $A.barr_set_inline(cells, at + 1, b1)
  val (third | cells) = $A.barr_set_inline(cells, at + 2, b2)
  val (fourth | cells) = $A.barr_set_inline(cells, at + 3, b3)
in (WORD_SET_mk(first, second, third, fourth) | cells) end

(* Deprecated (sha256#48): word_set is kept as published, with the two 16-bit halves as ints; use word_set_w32. It is removed in a later version, after one published version with both. *)




implement word_set {l}{n,at}{cs}{high,low} (cells, at, high, low) = let
  val b0 = high / 256
  val b1 = high - 256 * b0
  val b2 = low / 256
  val b3 = low - 256 * b2
  val (first | cells) = $A.barr_set_inline(cells, at, b0)
  val (second | cells) = $A.barr_set_inline(cells, at + 1, b1)
  val (third | cells) = $A.barr_set_inline(cells, at + 2, b2)
  val (fourth | cells) = $A.barr_set_inline(cells, at + 3, b3)
in (WORD_SET_mk(first, second, third, fourth) | cells) end

(* What was set is the word that is read there afterwards *)



primplement word_set_at {cs,cs2}{at,high,low} (set) = let
  prval WORD_SET_mk(s0, s1, s2, s3) = set
  prval n3 = $A.setc_nth_same(s3)
  prval n2 = $A.setc_nth_other(s3, $A.setc_nth_same(s2))
  prval n1 = $A.setc_nth_other(s3, $A.setc_nth_other(s2, $A.setc_nth_same(s1)))
  prval n0 = $A.setc_nth_other(s3, $A.setc_nth_other(s2, $A.setc_nth_other(s1, $A.setc_nth_same(s0))))
in WORD_AT_mk(n0, n1, n2, n3) end

(* A word whose cells are not the four set is as it was *)




primplement word_set_other {cs,cs2}{at,high,low,other,other_high,other_low} (set, word) = let
  prval WORD_SET_mk(s0, s1, s2, s3) = set
  prval WORD_AT_mk(n0, n1, n2, n3) = word
  prfn through {c0,c1,c2,c3,c4:$A.cells}{b0,b1,b2,b3:nat}{index,value:nat | index + 1 <= at || at + 4 <= index}
    (s0: $A.SETC(c0, at, b0, c1), s1: $A.SETC(c1, at + 1, b1, c2), s2: $A.SETC(c2, at + 2, b2, c3),
     s3: $A.SETC(c3, at + 3, b3, c4), n: $A.NTH(c0, index, value)): $A.NTH(c4, index, value) =
    $A.setc_nth_other(s3, $A.setc_nth_other(s2, $A.setc_nth_other(s1, $A.setc_nth_other(s0, n))))
in WORD_AT_mk(through(s0, s1, s2, s3, n0), through(s0, s1, s2, s3, n1),
              through(s0, s1, s2, s3, n2), through(s0, s1, s2, s3, n3)) end

(* A word is one word: the cells are one value *)



primplement word_at_functional {cs}{at,high,low,high2,low2} (first, second) = let
  prval WORD_AT_mk(a0, a1, a2, a3) = first
  prval WORD_AT_mk(b0, b1, b2, b3) = second
  prval () = $A.nth_functional(a0, b0)
  prval () = $A.nth_functional(a1, b1)
  prval () = $A.nth_functional(a2, b2)
  prval () = $A.nth_functional(a3, b3)
in end

(* ============================================================
   The schedule words of the standard

   SCHEDULE(kind, msg, at, t, high, low): W_t of the block that is the 64
   bytes from `at` of the cells msg is the word high:low, by the standard's
   definition and nothing of any array: for t under 16 the t-th word of the
   block (section 6.1.2 step 1, 6.2.2 step 1), and above:
     SHA-256: W_t = sigma1(W_t-2) + W_t-7 + sigma0(W_t-15) + W_t-16,
       added in that order, each modulo 2 to the 32 (ADD32)
     SHA-1: W_t = ROTL 1 (W_t-3 xor W_t-8 xor W_t-14 xor W_t-16), the
       rotation left by one being the rotation right by 31
   ============================================================ *)


































(* SCHEDULE_ARRAY(kind, words, msg, at, count): the first count words of
   the array whose cells are `words`, at 4 * t, are W_0 to W_count-1 of
   the block *)









(* Word i of the first count words of the array, and what the standard
   says it is *)




primplement schedule_array_get {kind}{words,msg}{at,count,i} (listed) =
  case+ listed of
  | SCHEDULE_ARRAY_cons(rest, word, specified) =>
      sif i == count - 1 then (word, specified)
      else schedule_array_get{kind}{words,msg}{at,count-1,i}(rest)

(* Setting a word beyond the first count leaves the first count as they were *)




primplement schedule_array_frame {kind}{words,words2,msg}{at,count,set_at,high,low} (set, listed) =
  case+ listed of
  | SCHEDULE_ARRAY_nil() => SCHEDULE_ARRAY_nil()
  | SCHEDULE_ARRAY_cons(rest, word, specified) =>
      SCHEDULE_ARRAY_cons(schedule_array_frame{kind}{words,words2,msg}{at,count-1,set_at,high,low}(set, rest),
                          word_set_other(set, word), specified)

(* Words 0 to 15 of the array are the block's own words *)
fun _schedule_load {kind:schedule_kind}{lm:agz}{nm:nat}{msg:$A.cells}{at:nat | at + 64 <= nm}
  {lw:agz}{nw:nat | 64 <= nw}{words:$A.cells}{t:nat | t <= 16} .<16 - t>.
  (message: !$A.barr(lm, nm, msg), at: int at, array: $A.barr(lw, nw, words), t: int t,
   loaded: SCHEDULE_ARRAY(kind, words, msg, at, t))
  : [words2:$A.cells] (SCHEDULE_ARRAY(kind, words2, msg, at, 16) | $A.barr(lw, nw, words2)) =
  if t >= 16 then (loaded | array)
  else let
    val (read | word_value) = word_get_w32(message, at + 4 * t)
    val (set | array) = word_set_w32(array, 4 * t, word_value)
    prval kept = schedule_array_frame(set, loaded)
  in _schedule_load(message, at, array, t + 1,
       SCHEDULE_ARRAY_cons(kept, word_set_at(set), SCHEDULE_message(read))) end

(* Word i of the array read and tied to the standard's W_i *)
fn _scheduled {kind:schedule_kind}{lw:agz}{nw:nat}{words,msg:$A.cells}{at,count,i:nat | i < count; 4*i + 3 < nw}
  (array: !$A.barr(lw, nw, words), listed: SCHEDULE_ARRAY(kind, words, msg, at, count), i: int i)
  : [high,low:nat | high < 65536; low < 65536] (SCHEDULE(kind, msg, at, i, high, low) | $AR.word32(high, low)) = let
  val (read | word_value) = word_get_w32(array, 4 * i)
  prval @(known, specified) = schedule_array_get{kind}{words,msg}{at,count,i}(listed)
  prval () = word_at_functional(read, known)
in (specified | word_value) end

(* W_t for t from 16 to 63 of SHA-256, each from the earlier ones *)
fun _schedule_sha256_expand {lw:agz}{words:$A.cells}{msg:$A.cells}{at:nat}{t:nat | 16 <= t; t <= 64} .<64 - t>.
  (array: $A.barr(lw, 256, words), t: int t,
   listed: SCHEDULE_ARRAY(sha256_kind(), words, msg, at, t))
  : [words2:$A.cells] (SCHEDULE_ARRAY(sha256_kind(), words2, msg, at, 64) | $A.barr(lw, 256, words2)) =
  if t >= 64 then (listed | array)
  else let
    val (back2 | back2_word) = _scheduled(array, listed, t - 2)
    val (back7 | back7_word) = _scheduled(array, listed, t - 7)
    val (back15 | back15_word) = _scheduled(array, listed, t - 15)
    val (back16 | back16_word) = _scheduled(array, listed, t - 16)
    val (sigma1 | s1_word) = small_sigma_1_w32(back2_word)
    val (sigma0 | s0_word) = small_sigma_0_w32(back15_word)
    val (add1 | sum1_word) = $AR.word32_add(s1_word, back7_word)
    val (add2 | sum2_word) = $AR.word32_add(sum1_word, s0_word)
    val (add3 | word_value) = $AR.word32_add(sum2_word, back16_word)
    val (set | array) = word_set_w32(array, 4 * t, word_value)
    prval kept = schedule_array_frame(set, listed)
    prval specified = SCHEDULE_sha256(back2, back7, back15, back16, sigma1, sigma0, add1, add2, add3)
  in _schedule_sha256_expand(array, t + 1,
       SCHEDULE_ARRAY_cons(kept, word_set_at(set), specified)) end

(* W_t for t from 16 to 79 of SHA-1, each from the earlier ones *)
fun _schedule_sha1_expand {lw:agz}{words:$A.cells}{msg:$A.cells}{at:nat}{t:nat | 16 <= t; t <= 80} .<80 - t>.
  (array: $A.barr(lw, 320, words), t: int t,
   listed: SCHEDULE_ARRAY(sha1_kind(), words, msg, at, t))
  : [words2:$A.cells] (SCHEDULE_ARRAY(sha1_kind(), words2, msg, at, 80) | $A.barr(lw, 320, words2)) =
  if t >= 80 then (listed | array)
  else let
    val (back3 | back3_word) = _scheduled(array, listed, t - 3)
    val (back8 | back8_word) = _scheduled(array, listed, t - 8)
    val (back14 | back14_word) = _scheduled(array, listed, t - 14)
    val (back16 | back16_word) = _scheduled(array, listed, t - 16)
    val (xor1_high, xor1_low | x1_word) = $AR.word32_xor(back3_word, back8_word)
    val (xor2_high, xor2_low | x2_word) = $AR.word32_xor(x1_word, back14_word)
    val (xor3_high, xor3_low | x3_word) = $AR.word32_xor(x2_word, back16_word)
    val (turned | word_value) = $AR.word32_rotr_inline(x3_word, 31)
    val (set | array) = word_set_w32(array, 4 * t, word_value)
    prval kept = schedule_array_frame(set, listed)
    prval specified = SCHEDULE_sha1(back3, back8, back14, back16, xor1_high, xor1_low, xor2_high, xor2_low, xor3_high, xor3_low, turned)
  in _schedule_sha1_expand(array, t + 1,
       SCHEDULE_ARRAY_cons(kept, word_set_at(set), specified)) end

(* The 64 words of SHA-256's message schedule of the block of 64 bytes
   from `at` of the message, in the array at 4 * t, with the proof that
   each is the standard's W_t *)




implement schedule_sha256 {lm}{nm}{msg}{at}{lw}{words} (message, at, array) = let
  val (loaded | array) = _schedule_load{sha256_kind()}(message, at, array, 0, SCHEDULE_ARRAY_nil())
in _schedule_sha256_expand(array, 16, loaded) end

(* The 80 words of SHA-1's message schedule, likewise *)




implement schedule_sha1 {lm}{nm}{msg}{at}{lw}{words} (message, at, array) = let
  val (loaded | array) = _schedule_load{sha1_kind()}(message, at, array, 0, SCHEDULE_ARRAY_nil())
in _schedule_sha1_expand(array, 16, loaded) end

(* ============================================================
   The round constants, the rounds and the block's chaining add
   (FIPS 180-4, sections 4.2.2, 5.3.3 and 6.2.2 steps 2 to 4 for SHA-256;
   4.1.1, 4.2.1, 5.3.1 and 6.1.2 steps 2 to 4 for SHA-1), proved against
   the standard (bats-lang/sha256#29, stage C)

   The state of the rounds is eight words (SHA-1: five), each an arith word32
   whose two 16-bit halves are in its type. `word` is the sort of a word, w32(high, low), and
   `eight_words` and `five_words` those of the states, so a relation between
   states names every word of both, and the register shifts of a round are
   in the indices: the state after a round of SHA-256 is
   eight(new a, a, b, c, new e, e, f, g).
   ============================================================ *)








(* The words of a state in an array: EIGHT_AT(cs, at, s) says the 32 cells
   from `at` of cs are the eight words of s, in order, big endian (the
   chaining value H of SHA-256 is kept so); FIVE_AT the 20 cells of SHA-1's *)





















(* The 8 words of a state at `at`, read from the array; the proof says what
   they are, and the values returned are those the proof names *)





implement eight_get_w32 {lc}{n,at}{cs}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low,h5_high,h5_low,h6_high,h6_low,h7_high,h7_low} (cells, at, have) = let
  prval EIGHT_AT_mk(known0, known1, known2, known3, known4, known5, known6, known7) = have
  val (read0 | read0_word) = word_get_w32(cells, at + 0)
  prval () = word_at_functional(read0, known0)
  val (read1 | read1_word) = word_get_w32(cells, at + 4)
  prval () = word_at_functional(read1, known1)
  val (read2 | read2_word) = word_get_w32(cells, at + 8)
  prval () = word_at_functional(read2, known2)
  val (read3 | read3_word) = word_get_w32(cells, at + 12)
  prval () = word_at_functional(read3, known3)
  val (read4 | read4_word) = word_get_w32(cells, at + 16)
  prval () = word_at_functional(read4, known4)
  val (read5 | read5_word) = word_get_w32(cells, at + 20)
  prval () = word_at_functional(read5, known5)
  val (read6 | read6_word) = word_get_w32(cells, at + 24)
  prval () = word_at_functional(read6, known6)
  val (read7 | read7_word) = word_get_w32(cells, at + 28)
  prval () = word_at_functional(read7, known7)
in @(read0_word, read1_word, read2_word, read3_word, read4_word, read5_word, read6_word, read7_word) end

(* Deprecated (sha256#48): eight_get is kept as published, with the two 16-bit halves as ints; use eight_get_w32. It is removed in a later version, after one published version with both. *)





implement eight_get {lc}{n,at}{cs}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low,h5_high,h5_low,h6_high,h6_low,h7_high,h7_low} (cells, at, have) = let
  prval EIGHT_AT_mk(known0, known1, known2, known3, known4, known5, known6, known7) = have
  val (read0 | @(read0_high, read0_low)) = word_get(cells, at + 0)
  prval () = word_at_functional(read0, known0)
  val (read1 | @(read1_high, read1_low)) = word_get(cells, at + 4)
  prval () = word_at_functional(read1, known1)
  val (read2 | @(read2_high, read2_low)) = word_get(cells, at + 8)
  prval () = word_at_functional(read2, known2)
  val (read3 | @(read3_high, read3_low)) = word_get(cells, at + 12)
  prval () = word_at_functional(read3, known3)
  val (read4 | @(read4_high, read4_low)) = word_get(cells, at + 16)
  prval () = word_at_functional(read4, known4)
  val (read5 | @(read5_high, read5_low)) = word_get(cells, at + 20)
  prval () = word_at_functional(read5, known5)
  val (read6 | @(read6_high, read6_low)) = word_get(cells, at + 24)
  prval () = word_at_functional(read6, known6)
  val (read7 | @(read7_high, read7_low)) = word_get(cells, at + 28)
  prval () = word_at_functional(read7, known7)
in @(read0_high, read0_low, read1_high, read1_low, read2_high, read2_low, read3_high, read3_low, read4_high, read4_low, read5_high, read5_low, read6_high, read6_low, read7_high, read7_low) end

(* The 8 words written at `at`, with the proof that they are there *)




implement eight_set_w32 {lc}{n,at}{cs}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low,h5_high,h5_low,h6_high,h6_low,h7_high,h7_low} (cells, at, h0_word, h1_word, h2_word, h3_word, h4_word, h5_word, h6_word, h7_word) = let
  val (set0 | cells) = word_set_w32(cells, at + 0, h0_word)
  val (set1 | cells) = word_set_w32(cells, at + 4, h1_word)
  val (set2 | cells) = word_set_w32(cells, at + 8, h2_word)
  val (set3 | cells) = word_set_w32(cells, at + 12, h3_word)
  val (set4 | cells) = word_set_w32(cells, at + 16, h4_word)
  val (set5 | cells) = word_set_w32(cells, at + 20, h5_word)
  val (set6 | cells) = word_set_w32(cells, at + 24, h6_word)
  val (set7 | cells) = word_set_w32(cells, at + 28, h7_word)
  prval stored0 = word_set_other(set7, word_set_other(set6, word_set_other(set5, word_set_other(set4, word_set_other(set3, word_set_other(set2, word_set_other(set1, word_set_at(set0))))))))
  prval stored1 = word_set_other(set7, word_set_other(set6, word_set_other(set5, word_set_other(set4, word_set_other(set3, word_set_other(set2, word_set_at(set1)))))))
  prval stored2 = word_set_other(set7, word_set_other(set6, word_set_other(set5, word_set_other(set4, word_set_other(set3, word_set_at(set2))))))
  prval stored3 = word_set_other(set7, word_set_other(set6, word_set_other(set5, word_set_other(set4, word_set_at(set3)))))
  prval stored4 = word_set_other(set7, word_set_other(set6, word_set_other(set5, word_set_at(set4))))
  prval stored5 = word_set_other(set7, word_set_other(set6, word_set_at(set5)))
  prval stored6 = word_set_other(set7, word_set_at(set6))
  prval stored7 = word_set_at(set7)
in (EIGHT_AT_mk(stored0, stored1, stored2, stored3, stored4, stored5, stored6, stored7) | cells) end

(* Deprecated (sha256#48): eight_set is kept as published, with the two 16-bit halves as ints; use eight_set_w32. It is removed in a later version, after one published version with both. *)




implement eight_set {lc}{n,at}{cs}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low,h5_high,h5_low,h6_high,h6_low,h7_high,h7_low} (cells, at, h0_high, h0_low, h1_high, h1_low, h2_high, h2_low, h3_high, h3_low, h4_high, h4_low, h5_high, h5_low, h6_high, h6_low, h7_high, h7_low) = let
  val (set0 | cells) = word_set(cells, at + 0, h0_high, h0_low)
  val (set1 | cells) = word_set(cells, at + 4, h1_high, h1_low)
  val (set2 | cells) = word_set(cells, at + 8, h2_high, h2_low)
  val (set3 | cells) = word_set(cells, at + 12, h3_high, h3_low)
  val (set4 | cells) = word_set(cells, at + 16, h4_high, h4_low)
  val (set5 | cells) = word_set(cells, at + 20, h5_high, h5_low)
  val (set6 | cells) = word_set(cells, at + 24, h6_high, h6_low)
  val (set7 | cells) = word_set(cells, at + 28, h7_high, h7_low)
  prval stored0 = word_set_other(set7, word_set_other(set6, word_set_other(set5, word_set_other(set4, word_set_other(set3, word_set_other(set2, word_set_other(set1, word_set_at(set0))))))))
  prval stored1 = word_set_other(set7, word_set_other(set6, word_set_other(set5, word_set_other(set4, word_set_other(set3, word_set_other(set2, word_set_at(set1)))))))
  prval stored2 = word_set_other(set7, word_set_other(set6, word_set_other(set5, word_set_other(set4, word_set_other(set3, word_set_at(set2))))))
  prval stored3 = word_set_other(set7, word_set_other(set6, word_set_other(set5, word_set_other(set4, word_set_at(set3)))))
  prval stored4 = word_set_other(set7, word_set_other(set6, word_set_other(set5, word_set_at(set4))))
  prval stored5 = word_set_other(set7, word_set_other(set6, word_set_at(set5)))
  prval stored6 = word_set_other(set7, word_set_at(set6))
  prval stored7 = word_set_at(set7)
in (EIGHT_AT_mk(stored0, stored1, stored2, stored3, stored4, stored5, stored6, stored7) | cells) end

(* The 5 words of a state at `at`, read from the array; the proof says what
   they are, and the values returned are those the proof names *)





implement five_get_w32 {lc}{n,at}{cs}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low} (cells, at, have) = let
  prval FIVE_AT_mk(known0, known1, known2, known3, known4) = have
  val (read0 | read0_word) = word_get_w32(cells, at + 0)
  prval () = word_at_functional(read0, known0)
  val (read1 | read1_word) = word_get_w32(cells, at + 4)
  prval () = word_at_functional(read1, known1)
  val (read2 | read2_word) = word_get_w32(cells, at + 8)
  prval () = word_at_functional(read2, known2)
  val (read3 | read3_word) = word_get_w32(cells, at + 12)
  prval () = word_at_functional(read3, known3)
  val (read4 | read4_word) = word_get_w32(cells, at + 16)
  prval () = word_at_functional(read4, known4)
in @(read0_word, read1_word, read2_word, read3_word, read4_word) end

(* Deprecated (sha256#48): five_get is kept as published, with the two 16-bit halves as ints; use five_get_w32. It is removed in a later version, after one published version with both. *)





implement five_get {lc}{n,at}{cs}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low} (cells, at, have) = let
  prval FIVE_AT_mk(known0, known1, known2, known3, known4) = have
  val (read0 | @(read0_high, read0_low)) = word_get(cells, at + 0)
  prval () = word_at_functional(read0, known0)
  val (read1 | @(read1_high, read1_low)) = word_get(cells, at + 4)
  prval () = word_at_functional(read1, known1)
  val (read2 | @(read2_high, read2_low)) = word_get(cells, at + 8)
  prval () = word_at_functional(read2, known2)
  val (read3 | @(read3_high, read3_low)) = word_get(cells, at + 12)
  prval () = word_at_functional(read3, known3)
  val (read4 | @(read4_high, read4_low)) = word_get(cells, at + 16)
  prval () = word_at_functional(read4, known4)
in @(read0_high, read0_low, read1_high, read1_low, read2_high, read2_low, read3_high, read3_low, read4_high, read4_low) end

(* The 5 words written at `at`, with the proof that they are there *)




implement five_set_w32 {lc}{n,at}{cs}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low} (cells, at, h0_word, h1_word, h2_word, h3_word, h4_word) = let
  val (set0 | cells) = word_set_w32(cells, at + 0, h0_word)
  val (set1 | cells) = word_set_w32(cells, at + 4, h1_word)
  val (set2 | cells) = word_set_w32(cells, at + 8, h2_word)
  val (set3 | cells) = word_set_w32(cells, at + 12, h3_word)
  val (set4 | cells) = word_set_w32(cells, at + 16, h4_word)
  prval stored0 = word_set_other(set4, word_set_other(set3, word_set_other(set2, word_set_other(set1, word_set_at(set0)))))
  prval stored1 = word_set_other(set4, word_set_other(set3, word_set_other(set2, word_set_at(set1))))
  prval stored2 = word_set_other(set4, word_set_other(set3, word_set_at(set2)))
  prval stored3 = word_set_other(set4, word_set_at(set3))
  prval stored4 = word_set_at(set4)
in (FIVE_AT_mk(stored0, stored1, stored2, stored3, stored4) | cells) end

(* Deprecated (sha256#48): five_set is kept as published, with the two 16-bit halves as ints; use five_set_w32. It is removed in a later version, after one published version with both. *)




implement five_set {lc}{n,at}{cs}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low} (cells, at, h0_high, h0_low, h1_high, h1_low, h2_high, h2_low, h3_high, h3_low, h4_high, h4_low) = let
  val (set0 | cells) = word_set(cells, at + 0, h0_high, h0_low)
  val (set1 | cells) = word_set(cells, at + 4, h1_high, h1_low)
  val (set2 | cells) = word_set(cells, at + 8, h2_high, h2_low)
  val (set3 | cells) = word_set(cells, at + 12, h3_high, h3_low)
  val (set4 | cells) = word_set(cells, at + 16, h4_high, h4_low)
  prval stored0 = word_set_other(set4, word_set_other(set3, word_set_other(set2, word_set_other(set1, word_set_at(set0)))))
  prval stored1 = word_set_other(set4, word_set_other(set3, word_set_other(set2, word_set_at(set1))))
  prval stored2 = word_set_other(set4, word_set_other(set3, word_set_at(set2)))
  prval stored3 = word_set_other(set4, word_set_at(set3))
  prval stored4 = word_set_at(set4)
in (FIVE_AT_mk(stored0, stored1, stored2, stored3, stored4) | cells) end

(* cube_fraction_le/gt (i, high, low, p): with x = i * 2^32 + 65536 * high +
   low, x^3 <= p * 2^96 < (x + 1)^3, that is x = floor(cbrt(p) * 2^32): i is
   the integer part of the cube root of p and high:low the first 32 bits of
   its fractional part (FIPS 180-4, section 4.2.2). Integers of 2^105, held by
   the gmp solver (arith's CLAUDE.md, the infinite-precision solver);
   keyword: round-constants (sha256#31). *)








(* SHA256_K(t, high, low): the constant K_t of SHA-256 (section 4.2.2) is
   the word high:low: the first 32 bits of the fractional part of the cube
   root of the (t+1)-th prime. Each constructor states that definition as its
   guard (the prime p and the integer part i of its root are literals), so a
   word that is not floor(cbrt(p) * 2^32) mod 2^32 does not type-check
   (tests/static/reject, the sha256-k fixtures). That p is the (t+1)-th prime is not
   proved: sha256#78. Keyword: round-constants. *)


































































(* The constant of round t, with the proof that it is the table's *)



implement sha256_k_w32 {t} (t) =
  if $AR.eq_g1(t, 0) then
    (SHA256_K_0() | $AR.word32_pack_inline(0x42, 0x8a, 0x2f, 0x98))
  else
  if $AR.eq_g1(t, 1) then
    (SHA256_K_1() | $AR.word32_pack_inline(0x71, 0x37, 0x44, 0x91))
  else
  if $AR.eq_g1(t, 2) then
    (SHA256_K_2() | $AR.word32_pack_inline(0xb5, 0xc0, 0xfb, 0xcf))
  else
  if $AR.eq_g1(t, 3) then
    (SHA256_K_3() | $AR.word32_pack_inline(0xe9, 0xb5, 0xdb, 0xa5))
  else
  if $AR.eq_g1(t, 4) then
    (SHA256_K_4() | $AR.word32_pack_inline(0x39, 0x56, 0xc2, 0x5b))
  else
  if $AR.eq_g1(t, 5) then
    (SHA256_K_5() | $AR.word32_pack_inline(0x59, 0xf1, 0x11, 0xf1))
  else
  if $AR.eq_g1(t, 6) then
    (SHA256_K_6() | $AR.word32_pack_inline(0x92, 0x3f, 0x82, 0xa4))
  else
  if $AR.eq_g1(t, 7) then
    (SHA256_K_7() | $AR.word32_pack_inline(0xab, 0x1c, 0x5e, 0xd5))
  else
  if $AR.eq_g1(t, 8) then
    (SHA256_K_8() | $AR.word32_pack_inline(0xd8, 0x07, 0xaa, 0x98))
  else
  if $AR.eq_g1(t, 9) then
    (SHA256_K_9() | $AR.word32_pack_inline(0x12, 0x83, 0x5b, 0x01))
  else
  if $AR.eq_g1(t, 10) then
    (SHA256_K_10() | $AR.word32_pack_inline(0x24, 0x31, 0x85, 0xbe))
  else
  if $AR.eq_g1(t, 11) then
    (SHA256_K_11() | $AR.word32_pack_inline(0x55, 0x0c, 0x7d, 0xc3))
  else
  if $AR.eq_g1(t, 12) then
    (SHA256_K_12() | $AR.word32_pack_inline(0x72, 0xbe, 0x5d, 0x74))
  else
  if $AR.eq_g1(t, 13) then
    (SHA256_K_13() | $AR.word32_pack_inline(0x80, 0xde, 0xb1, 0xfe))
  else
  if $AR.eq_g1(t, 14) then
    (SHA256_K_14() | $AR.word32_pack_inline(0x9b, 0xdc, 0x06, 0xa7))
  else
  if $AR.eq_g1(t, 15) then
    (SHA256_K_15() | $AR.word32_pack_inline(0xc1, 0x9b, 0xf1, 0x74))
  else
  if $AR.eq_g1(t, 16) then
    (SHA256_K_16() | $AR.word32_pack_inline(0xe4, 0x9b, 0x69, 0xc1))
  else
  if $AR.eq_g1(t, 17) then
    (SHA256_K_17() | $AR.word32_pack_inline(0xef, 0xbe, 0x47, 0x86))
  else
  if $AR.eq_g1(t, 18) then
    (SHA256_K_18() | $AR.word32_pack_inline(0x0f, 0xc1, 0x9d, 0xc6))
  else
  if $AR.eq_g1(t, 19) then
    (SHA256_K_19() | $AR.word32_pack_inline(0x24, 0x0c, 0xa1, 0xcc))
  else
  if $AR.eq_g1(t, 20) then
    (SHA256_K_20() | $AR.word32_pack_inline(0x2d, 0xe9, 0x2c, 0x6f))
  else
  if $AR.eq_g1(t, 21) then
    (SHA256_K_21() | $AR.word32_pack_inline(0x4a, 0x74, 0x84, 0xaa))
  else
  if $AR.eq_g1(t, 22) then
    (SHA256_K_22() | $AR.word32_pack_inline(0x5c, 0xb0, 0xa9, 0xdc))
  else
  if $AR.eq_g1(t, 23) then
    (SHA256_K_23() | $AR.word32_pack_inline(0x76, 0xf9, 0x88, 0xda))
  else
  if $AR.eq_g1(t, 24) then
    (SHA256_K_24() | $AR.word32_pack_inline(0x98, 0x3e, 0x51, 0x52))
  else
  if $AR.eq_g1(t, 25) then
    (SHA256_K_25() | $AR.word32_pack_inline(0xa8, 0x31, 0xc6, 0x6d))
  else
  if $AR.eq_g1(t, 26) then
    (SHA256_K_26() | $AR.word32_pack_inline(0xb0, 0x03, 0x27, 0xc8))
  else
  if $AR.eq_g1(t, 27) then
    (SHA256_K_27() | $AR.word32_pack_inline(0xbf, 0x59, 0x7f, 0xc7))
  else
  if $AR.eq_g1(t, 28) then
    (SHA256_K_28() | $AR.word32_pack_inline(0xc6, 0xe0, 0x0b, 0xf3))
  else
  if $AR.eq_g1(t, 29) then
    (SHA256_K_29() | $AR.word32_pack_inline(0xd5, 0xa7, 0x91, 0x47))
  else
  if $AR.eq_g1(t, 30) then
    (SHA256_K_30() | $AR.word32_pack_inline(0x06, 0xca, 0x63, 0x51))
  else
  if $AR.eq_g1(t, 31) then
    (SHA256_K_31() | $AR.word32_pack_inline(0x14, 0x29, 0x29, 0x67))
  else
  if $AR.eq_g1(t, 32) then
    (SHA256_K_32() | $AR.word32_pack_inline(0x27, 0xb7, 0x0a, 0x85))
  else
  if $AR.eq_g1(t, 33) then
    (SHA256_K_33() | $AR.word32_pack_inline(0x2e, 0x1b, 0x21, 0x38))
  else
  if $AR.eq_g1(t, 34) then
    (SHA256_K_34() | $AR.word32_pack_inline(0x4d, 0x2c, 0x6d, 0xfc))
  else
  if $AR.eq_g1(t, 35) then
    (SHA256_K_35() | $AR.word32_pack_inline(0x53, 0x38, 0x0d, 0x13))
  else
  if $AR.eq_g1(t, 36) then
    (SHA256_K_36() | $AR.word32_pack_inline(0x65, 0x0a, 0x73, 0x54))
  else
  if $AR.eq_g1(t, 37) then
    (SHA256_K_37() | $AR.word32_pack_inline(0x76, 0x6a, 0x0a, 0xbb))
  else
  if $AR.eq_g1(t, 38) then
    (SHA256_K_38() | $AR.word32_pack_inline(0x81, 0xc2, 0xc9, 0x2e))
  else
  if $AR.eq_g1(t, 39) then
    (SHA256_K_39() | $AR.word32_pack_inline(0x92, 0x72, 0x2c, 0x85))
  else
  if $AR.eq_g1(t, 40) then
    (SHA256_K_40() | $AR.word32_pack_inline(0xa2, 0xbf, 0xe8, 0xa1))
  else
  if $AR.eq_g1(t, 41) then
    (SHA256_K_41() | $AR.word32_pack_inline(0xa8, 0x1a, 0x66, 0x4b))
  else
  if $AR.eq_g1(t, 42) then
    (SHA256_K_42() | $AR.word32_pack_inline(0xc2, 0x4b, 0x8b, 0x70))
  else
  if $AR.eq_g1(t, 43) then
    (SHA256_K_43() | $AR.word32_pack_inline(0xc7, 0x6c, 0x51, 0xa3))
  else
  if $AR.eq_g1(t, 44) then
    (SHA256_K_44() | $AR.word32_pack_inline(0xd1, 0x92, 0xe8, 0x19))
  else
  if $AR.eq_g1(t, 45) then
    (SHA256_K_45() | $AR.word32_pack_inline(0xd6, 0x99, 0x06, 0x24))
  else
  if $AR.eq_g1(t, 46) then
    (SHA256_K_46() | $AR.word32_pack_inline(0xf4, 0x0e, 0x35, 0x85))
  else
  if $AR.eq_g1(t, 47) then
    (SHA256_K_47() | $AR.word32_pack_inline(0x10, 0x6a, 0xa0, 0x70))
  else
  if $AR.eq_g1(t, 48) then
    (SHA256_K_48() | $AR.word32_pack_inline(0x19, 0xa4, 0xc1, 0x16))
  else
  if $AR.eq_g1(t, 49) then
    (SHA256_K_49() | $AR.word32_pack_inline(0x1e, 0x37, 0x6c, 0x08))
  else
  if $AR.eq_g1(t, 50) then
    (SHA256_K_50() | $AR.word32_pack_inline(0x27, 0x48, 0x77, 0x4c))
  else
  if $AR.eq_g1(t, 51) then
    (SHA256_K_51() | $AR.word32_pack_inline(0x34, 0xb0, 0xbc, 0xb5))
  else
  if $AR.eq_g1(t, 52) then
    (SHA256_K_52() | $AR.word32_pack_inline(0x39, 0x1c, 0x0c, 0xb3))
  else
  if $AR.eq_g1(t, 53) then
    (SHA256_K_53() | $AR.word32_pack_inline(0x4e, 0xd8, 0xaa, 0x4a))
  else
  if $AR.eq_g1(t, 54) then
    (SHA256_K_54() | $AR.word32_pack_inline(0x5b, 0x9c, 0xca, 0x4f))
  else
  if $AR.eq_g1(t, 55) then
    (SHA256_K_55() | $AR.word32_pack_inline(0x68, 0x2e, 0x6f, 0xf3))
  else
  if $AR.eq_g1(t, 56) then
    (SHA256_K_56() | $AR.word32_pack_inline(0x74, 0x8f, 0x82, 0xee))
  else
  if $AR.eq_g1(t, 57) then
    (SHA256_K_57() | $AR.word32_pack_inline(0x78, 0xa5, 0x63, 0x6f))
  else
  if $AR.eq_g1(t, 58) then
    (SHA256_K_58() | $AR.word32_pack_inline(0x84, 0xc8, 0x78, 0x14))
  else
  if $AR.eq_g1(t, 59) then
    (SHA256_K_59() | $AR.word32_pack_inline(0x8c, 0xc7, 0x02, 0x08))
  else
  if $AR.eq_g1(t, 60) then
    (SHA256_K_60() | $AR.word32_pack_inline(0x90, 0xbe, 0xff, 0xfa))
  else
  if $AR.eq_g1(t, 61) then
    (SHA256_K_61() | $AR.word32_pack_inline(0xa4, 0x50, 0x6c, 0xeb))
  else
  if $AR.eq_g1(t, 62) then
    (SHA256_K_62() | $AR.word32_pack_inline(0xbe, 0xf9, 0xa3, 0xf7))
  else
  (SHA256_K_63() | $AR.word32_pack_inline(0xc6, 0x71, 0x78, 0xf2))

(* Deprecated (sha256#48): sha256_k is kept as published, with the two 16-bit halves as ints; use sha256_k_w32. It is removed in a later version, after one published version with both. *)



implement sha256_k {t} (t) =
  if $AR.lt_g1(t, 32) then
    if $AR.lt_g1(t, 16) then
      if $AR.lt_g1(t, 8) then
        if $AR.lt_g1(t, 4) then
          if $AR.lt_g1(t, 2) then
            if $AR.lt_g1(t, 1) then
              (SHA256_K_0() | @(0x428a, 0x2f98))
            else
              (SHA256_K_1() | @(0x7137, 0x4491))
          else
            if $AR.lt_g1(t, 3) then
              (SHA256_K_2() | @(0xb5c0, 0xfbcf))
            else
              (SHA256_K_3() | @(0xe9b5, 0xdba5))
        else
          if $AR.lt_g1(t, 6) then
            if $AR.lt_g1(t, 5) then
              (SHA256_K_4() | @(0x3956, 0xc25b))
            else
              (SHA256_K_5() | @(0x59f1, 0x11f1))
          else
            if $AR.lt_g1(t, 7) then
              (SHA256_K_6() | @(0x923f, 0x82a4))
            else
              (SHA256_K_7() | @(0xab1c, 0x5ed5))
      else
        if $AR.lt_g1(t, 12) then
          if $AR.lt_g1(t, 10) then
            if $AR.lt_g1(t, 9) then
              (SHA256_K_8() | @(0xd807, 0xaa98))
            else
              (SHA256_K_9() | @(0x1283, 0x5b01))
          else
            if $AR.lt_g1(t, 11) then
              (SHA256_K_10() | @(0x2431, 0x85be))
            else
              (SHA256_K_11() | @(0x550c, 0x7dc3))
        else
          if $AR.lt_g1(t, 14) then
            if $AR.lt_g1(t, 13) then
              (SHA256_K_12() | @(0x72be, 0x5d74))
            else
              (SHA256_K_13() | @(0x80de, 0xb1fe))
          else
            if $AR.lt_g1(t, 15) then
              (SHA256_K_14() | @(0x9bdc, 0x06a7))
            else
              (SHA256_K_15() | @(0xc19b, 0xf174))
    else
      if $AR.lt_g1(t, 24) then
        if $AR.lt_g1(t, 20) then
          if $AR.lt_g1(t, 18) then
            if $AR.lt_g1(t, 17) then
              (SHA256_K_16() | @(0xe49b, 0x69c1))
            else
              (SHA256_K_17() | @(0xefbe, 0x4786))
          else
            if $AR.lt_g1(t, 19) then
              (SHA256_K_18() | @(0x0fc1, 0x9dc6))
            else
              (SHA256_K_19() | @(0x240c, 0xa1cc))
        else
          if $AR.lt_g1(t, 22) then
            if $AR.lt_g1(t, 21) then
              (SHA256_K_20() | @(0x2de9, 0x2c6f))
            else
              (SHA256_K_21() | @(0x4a74, 0x84aa))
          else
            if $AR.lt_g1(t, 23) then
              (SHA256_K_22() | @(0x5cb0, 0xa9dc))
            else
              (SHA256_K_23() | @(0x76f9, 0x88da))
      else
        if $AR.lt_g1(t, 28) then
          if $AR.lt_g1(t, 26) then
            if $AR.lt_g1(t, 25) then
              (SHA256_K_24() | @(0x983e, 0x5152))
            else
              (SHA256_K_25() | @(0xa831, 0xc66d))
          else
            if $AR.lt_g1(t, 27) then
              (SHA256_K_26() | @(0xb003, 0x27c8))
            else
              (SHA256_K_27() | @(0xbf59, 0x7fc7))
        else
          if $AR.lt_g1(t, 30) then
            if $AR.lt_g1(t, 29) then
              (SHA256_K_28() | @(0xc6e0, 0x0bf3))
            else
              (SHA256_K_29() | @(0xd5a7, 0x9147))
          else
            if $AR.lt_g1(t, 31) then
              (SHA256_K_30() | @(0x06ca, 0x6351))
            else
              (SHA256_K_31() | @(0x1429, 0x2967))
  else
    if $AR.lt_g1(t, 48) then
      if $AR.lt_g1(t, 40) then
        if $AR.lt_g1(t, 36) then
          if $AR.lt_g1(t, 34) then
            if $AR.lt_g1(t, 33) then
              (SHA256_K_32() | @(0x27b7, 0x0a85))
            else
              (SHA256_K_33() | @(0x2e1b, 0x2138))
          else
            if $AR.lt_g1(t, 35) then
              (SHA256_K_34() | @(0x4d2c, 0x6dfc))
            else
              (SHA256_K_35() | @(0x5338, 0x0d13))
        else
          if $AR.lt_g1(t, 38) then
            if $AR.lt_g1(t, 37) then
              (SHA256_K_36() | @(0x650a, 0x7354))
            else
              (SHA256_K_37() | @(0x766a, 0x0abb))
          else
            if $AR.lt_g1(t, 39) then
              (SHA256_K_38() | @(0x81c2, 0xc92e))
            else
              (SHA256_K_39() | @(0x9272, 0x2c85))
      else
        if $AR.lt_g1(t, 44) then
          if $AR.lt_g1(t, 42) then
            if $AR.lt_g1(t, 41) then
              (SHA256_K_40() | @(0xa2bf, 0xe8a1))
            else
              (SHA256_K_41() | @(0xa81a, 0x664b))
          else
            if $AR.lt_g1(t, 43) then
              (SHA256_K_42() | @(0xc24b, 0x8b70))
            else
              (SHA256_K_43() | @(0xc76c, 0x51a3))
        else
          if $AR.lt_g1(t, 46) then
            if $AR.lt_g1(t, 45) then
              (SHA256_K_44() | @(0xd192, 0xe819))
            else
              (SHA256_K_45() | @(0xd699, 0x0624))
          else
            if $AR.lt_g1(t, 47) then
              (SHA256_K_46() | @(0xf40e, 0x3585))
            else
              (SHA256_K_47() | @(0x106a, 0xa070))
    else
      if $AR.lt_g1(t, 56) then
        if $AR.lt_g1(t, 52) then
          if $AR.lt_g1(t, 50) then
            if $AR.lt_g1(t, 49) then
              (SHA256_K_48() | @(0x19a4, 0xc116))
            else
              (SHA256_K_49() | @(0x1e37, 0x6c08))
          else
            if $AR.lt_g1(t, 51) then
              (SHA256_K_50() | @(0x2748, 0x774c))
            else
              (SHA256_K_51() | @(0x34b0, 0xbcb5))
        else
          if $AR.lt_g1(t, 54) then
            if $AR.lt_g1(t, 53) then
              (SHA256_K_52() | @(0x391c, 0x0cb3))
            else
              (SHA256_K_53() | @(0x4ed8, 0xaa4a))
          else
            if $AR.lt_g1(t, 55) then
              (SHA256_K_54() | @(0x5b9c, 0xca4f))
            else
              (SHA256_K_55() | @(0x682e, 0x6ff3))
      else
        if $AR.lt_g1(t, 60) then
          if $AR.lt_g1(t, 58) then
            if $AR.lt_g1(t, 57) then
              (SHA256_K_56() | @(0x748f, 0x82ee))
            else
              (SHA256_K_57() | @(0x78a5, 0x636f))
          else
            if $AR.lt_g1(t, 59) then
              (SHA256_K_58() | @(0x84c8, 0x7814))
            else
              (SHA256_K_59() | @(0x8cc7, 0x0208))
        else
          if $AR.lt_g1(t, 62) then
            if $AR.lt_g1(t, 61) then
              (SHA256_K_60() | @(0x90be, 0xfffa))
            else
              (SHA256_K_61() | @(0xa450, 0x6ceb))
          else
            if $AR.lt_g1(t, 63) then
              (SHA256_K_62() | @(0xbef9, 0xa3f7))
            else
              (SHA256_K_63() | @(0xc671, 0x78f2))

(* SHA256_ROUND(a, b, c, d, e, f, g, h, k, w, new_a, new_e): one round of
   SHA-256 (section 6.2.2 step 3) from the working variables a to h, the
   constant k and the schedule word w:
     T1 = h + BIG_SIGMA_1(e) + Ch(e, f, g) + k + w
     T2 = BIG_SIGMA_0(a) + Maj(a, b, c)
   each sum modulo 2 to the 32, in that order; the new a is T1 + T2 and the
   new e is d + T1. The other variables shift (h = g, g = f, f = e, d = c,
   c = b, b = a), which SHA256_ROUNDS puts in its indices. *)















(* One round, with the proof that its results are the standard's *)





implement sha256_round_w32 (a_word, b_word, c_word, d_word, e_word, f_word, g_word, h_word, k_word, w_word) = let
  val (big1 | big1_word) = big_sigma_1_w32(e_word)
  val (choice | ch_word) = word_ch_w32(e_word, f_word, g_word)
  val (add1 | sum1_word) = $AR.word32_add(h_word, big1_word)
  val (add2 | sum2_word) = $AR.word32_add(sum1_word, ch_word)
  val (add3 | sum3_word) = $AR.word32_add(sum2_word, k_word)
  val (add4 | t1_word) = $AR.word32_add(sum3_word, w_word)
  val (big0 | big0_word) = big_sigma_0_w32(a_word)
  val (majority | maj_word) = word_maj_w32(a_word, b_word, c_word)
  val (add5 | t2_word) = $AR.word32_add(big0_word, maj_word)
  val (add6 | new_a_word) = $AR.word32_add(t1_word, t2_word)
  val (add7 | new_e_word) = $AR.word32_add(d_word, t1_word)
in (SHA256_ROUND_mk(big1, choice, add1, add2, add3, add4, big0, majority, add5, add6, add7)
    | @(new_a_word, new_e_word)) end

(* Deprecated (sha256#48): sha256_round is kept as published, with the two 16-bit halves as ints; use sha256_round_w32. It is removed in a later version, after one published version with both. *)





implement sha256_round (a_high, a_low, b_high, b_low, c_high, c_low, d_high, d_low, e_high, e_low, f_high, f_low, g_high, g_low, h_high, h_low, k_high, k_low, w_high, w_low) = let
  val (big1 | @(big1_high, big1_low)) = big_sigma_1(e_high, e_low)
  val (choice | @(ch_high, ch_low)) = word_ch(e_high, e_low, f_high, f_low, g_high, g_low)
  val (add1 | @(sum1_high, sum1_low)) = $AR.add32(h_high, h_low, big1_high, big1_low)
  val (add2 | @(sum2_high, sum2_low)) = $AR.add32(sum1_high, sum1_low, ch_high, ch_low)
  val (add3 | @(sum3_high, sum3_low)) = $AR.add32(sum2_high, sum2_low, k_high, k_low)
  val (add4 | @(t1_high, t1_low)) = $AR.add32(sum3_high, sum3_low, w_high, w_low)
  val (big0 | @(big0_high, big0_low)) = big_sigma_0(a_high, a_low)
  val (majority | @(maj_high, maj_low)) = word_maj(a_high, a_low, b_high, b_low, c_high, c_low)
  val (add5 | @(t2_high, t2_low)) = $AR.add32(big0_high, big0_low, maj_high, maj_low)
  val (add6 | @(new_a_high, new_a_low)) = $AR.add32(t1_high, t1_low, t2_high, t2_low)
  val (add7 | @(new_e_high, new_e_low)) = $AR.add32(d_high, d_low, t1_high, t1_low)
in (SHA256_ROUND_mk(big1, choice, add1, add2, add3, add4, big0, majority, add5, add6, add7)
    | @(new_a_high, new_a_low, new_e_high, new_e_low)) end

(* SHA256_ROUNDS(msg, at, t, init, state): after t rounds of the block of 64
   bytes from `at` of the cells msg, begun with the working variables init,
   the working variables are state. Round t uses K_t and the schedule word
   W_t of that block (SCHEDULE), and ends in the state of SHA256_ROUND with
   its registers shifted. *)













(* SHA256_BLOCK(msg, at, before, after): the block of 64 bytes from `at` of
   msg, hashed onto the chaining value `before` (section 6.2.2), makes the
   chaining value `after`: the 64 rounds begun with the working variables
   a to h set to `before`, and the new chaining value is each working
   variable at the end added (modulo 2 to the 32) to the same word of
   `before` (step 4) *)













(* The 64 rounds, each with the proof that it is the standard's, from the
   working variables a to h after t rounds *)
fun _rounds256 {lw:agz}{words,msg:$A.cells}{at:nat}{init:eight_words}{t:nat | t <= 64}
  {a_high,a_low,b_high,b_low,c_high,c_low,d_high,d_low,e_high,e_low,f_high,f_low,g_high,g_low,h_high,h_low:nat | a_high < 65536; a_low < 65536; b_high < 65536; b_low < 65536; c_high < 65536; c_low < 65536; d_high < 65536; d_low < 65536; e_high < 65536; e_low < 65536; f_high < 65536; f_low < 65536; g_high < 65536; g_low < 65536; h_high < 65536; h_low < 65536} .<64 - t>.
  (schedule: !$A.barr(lw, 256, words), listed: SCHEDULE_ARRAY(sha256_kind(), words, msg, at, 64), t: int t,
   a_word: $AR.word32(a_high, a_low), b_word: $AR.word32(b_high, b_low), c_word: $AR.word32(c_high, c_low), d_word: $AR.word32(d_high, d_low), e_word: $AR.word32(e_high, e_low), f_word: $AR.word32(f_high, f_low), g_word: $AR.word32(g_high, g_low), h_word: $AR.word32(h_high, h_low),
   done: SHA256_ROUNDS(msg, at, t, init, eight(w32(a_high, a_low), w32(b_high, b_low), w32(c_high, c_low), w32(d_high, d_low), w32(e_high, e_low), w32(f_high, f_low), w32(g_high, g_low), w32(h_high, h_low))))
  : [end_a_high,end_a_low,end_b_high,end_b_low,end_c_high,end_c_low,end_d_high,end_d_low,end_e_high,end_e_low,end_f_high,end_f_low,end_g_high,end_g_low,end_h_high,end_h_low:nat | end_a_high < 65536; end_a_low < 65536; end_b_high < 65536; end_b_low < 65536; end_c_high < 65536; end_c_low < 65536; end_d_high < 65536; end_d_low < 65536; end_e_high < 65536; end_e_low < 65536; end_f_high < 65536; end_f_low < 65536; end_g_high < 65536; end_g_low < 65536; end_h_high < 65536; end_h_low < 65536]
    (SHA256_ROUNDS(msg, at, 64, init, eight(w32(end_a_high, end_a_low), w32(end_b_high, end_b_low), w32(end_c_high, end_c_low), w32(end_d_high, end_d_low), w32(end_e_high, end_e_low), w32(end_f_high, end_f_low), w32(end_g_high, end_g_low), w32(end_h_high, end_h_low))) | @($AR.word32(end_a_high, end_a_low), $AR.word32(end_b_high, end_b_low), $AR.word32(end_c_high, end_c_low), $AR.word32(end_d_high, end_d_low), $AR.word32(end_e_high, end_e_low), $AR.word32(end_f_high, end_f_low), $AR.word32(end_g_high, end_g_low), $AR.word32(end_h_high, end_h_low))) =
  if t >= 64 then (done | @(a_word, b_word, c_word, d_word, e_word, f_word, g_word, h_word))
  else let
    val (constant | k_word) = sha256_k_w32(t)
    val (word | w_word) = _scheduled(schedule, listed, t)
    val (step | @(new_a_word, new_e_word)) =
      sha256_round_w32(a_word, b_word, c_word, d_word, e_word, f_word, g_word, h_word, k_word, w_word)
  in _rounds256(schedule, listed, t + 1,
       new_a_word, a_word, b_word, c_word,
       new_e_word, e_word, f_word, g_word,
       SHA256_ROUNDS_next(done, constant, word, step)) end

(* The block of 64 bytes from `at` of the message hashed onto the chaining
   value in the array (32 bytes, eight words, at 0) and the new chaining value
   written there, with the proof that it is the standard's. The array
   `schedule` is scratch space for the 64 words of the message schedule. *)










implement sha256_compress {lm}{nm}{msg}{at}{lw}{words}{lc}{chain}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low,h5_high,h5_low,h6_high,h6_low,h7_high,h7_low}
  (message, at, schedule, chaining, have) = let
  val (listed | schedule) = schedule_sha256(message, at, schedule)
  val @(h0_word, h1_word, h2_word, h3_word, h4_word, h5_word, h6_word, h7_word) = eight_get_w32(chaining, 0, have)
  val (rounds | @(end_a_word, end_b_word, end_c_word, end_d_word, end_e_word, end_f_word, end_g_word, end_h_word)) = _rounds256(schedule, listed, 0,
    h0_word, h1_word, h2_word, h3_word, h4_word, h5_word, h6_word, h7_word, SHA256_ROUNDS_zero())
  val (add0 | next_h0_word) = $AR.word32_add(h0_word, end_a_word)
  val (add1 | next_h1_word) = $AR.word32_add(h1_word, end_b_word)
  val (add2 | next_h2_word) = $AR.word32_add(h2_word, end_c_word)
  val (add3 | next_h3_word) = $AR.word32_add(h3_word, end_d_word)
  val (add4 | next_h4_word) = $AR.word32_add(h4_word, end_e_word)
  val (add5 | next_h5_word) = $AR.word32_add(h5_word, end_f_word)
  val (add6 | next_h6_word) = $AR.word32_add(h6_word, end_g_word)
  val (add7 | next_h7_word) = $AR.word32_add(h7_word, end_h_word)
  val (written | chaining) = eight_set_w32(chaining, 0, next_h0_word, next_h1_word, next_h2_word, next_h3_word, next_h4_word, next_h5_word, next_h6_word, next_h7_word)
in (SHA256_BLOCK_mk(rounds, add0, add1, add2, add3, add4, add5, add6, add7), written | @(schedule, chaining)) end

(* ============================================================
   SHA-1's rounds (FIPS 180-4, sections 4.1.1, 4.2.1, 5.3.1, 6.1.2)
   ============================================================ *)

(* PARITY(x, y, z, r): r is Parity(x, y, z) = x xor y xor z (section 4.1.1) *)






(* SHA1_F(t, b, c, d, f): f is f_t(b, c, d) (section 4.1.1): Ch for t from 0
   to 19, Parity from 20 to 39, Maj from 40 to 59, Parity from 60 to 79 *)










(* Parity of three words, with the proof that it is *)




implement word_parity_w32 (x, y, z) = let
  val (pah, pal | a) = $AR.word32_xor(x, y)
  val (prh, prl | r) = $AR.word32_xor(a, z)
in (PARITY_mk(pah, pal, prh, prl) | r) end

(* Deprecated (sha256#48): word_parity is kept as published, with the two 16-bit halves as ints; use word_parity_w32. It is removed in a later version, after one published version with both. *)




implement word_parity (xh, xl, yh, yl, zh, zl) = let
  val (pah, pal | @(ah, al)) = $AR.xor32(xh, xl, yh, yl)
  val (prh, prl | @(rh, rl)) = $AR.xor32(ah, al, zh, zl)
in (PARITY_mk(pah, pal, prh, prl) | @(rh, rl)) end

(* f_t(b, c, d), with the proof that it is *)




implement sha1_f_w32 {t}{bh,bl,ch,cl,dh,dl} (t, b, c, d) =
  if $AR.lt_g1(t, 20) then let
    val (pf | f) = word_ch_w32(b, c, d)
  in (SHA1_F_choose(pf) | f) end
  else if $AR.lt_g1(t, 40) then let
    val (pf | f) = word_parity_w32(b, c, d)
  in (SHA1_F_parity_first(pf) | f) end
  else if $AR.lt_g1(t, 60) then let
    val (pf | f) = word_maj_w32(b, c, d)
  in (SHA1_F_majority(pf) | f) end
  else let
    val (pf | f) = word_parity_w32(b, c, d)
  in (SHA1_F_parity_second(pf) | f) end

(* Deprecated (sha256#48): sha1_f is kept as published, with the two 16-bit halves as ints; use sha1_f_w32. It is removed in a later version, after one published version with both. *)




implement sha1_f {t}{bh,bl,ch,cl,dh,dl} (t, bh, bl, ch, cl, dh, dl) =
  if $AR.lt_g1(t, 20) then let
    val (pf | @(fh, fl)) = word_ch(bh, bl, ch, cl, dh, dl)
  in (SHA1_F_choose(pf) | @(fh, fl)) end
  else if $AR.lt_g1(t, 40) then let
    val (pf | @(fh, fl)) = word_parity(bh, bl, ch, cl, dh, dl)
  in (SHA1_F_parity_first(pf) | @(fh, fl)) end
  else if $AR.lt_g1(t, 60) then let
    val (pf | @(fh, fl)) = word_maj(bh, bl, ch, cl, dh, dl)
  in (SHA1_F_majority(pf) | @(fh, fl)) end
  else let
    val (pf | @(fh, fl)) = word_parity(bh, bl, ch, cl, dh, dl)
  in (SHA1_F_parity_second(pf) | @(fh, fl)) end

(* sqrt_fraction_le/gt (high, low, n): with x = 65536 * high + low,
   x^2 <= n * 2^60 < (x + 1)^2, that is x = floor(sqrt(n) * 2^30): the integer
   part of 2 to the 30 times the square root of n (FIPS 180-4, section 4.2.1).
   Integers of 2^64, held by the gmp solver (arith's CLAUDE.md, the
   infinite-precision solver); keyword: round-constants (sha256#31). *)






(* SHA1_K(t, high, low): the constant K_t of SHA-1 (section 4.2.1) is the word
   high:low: the integer part of 2 to the 30 times the square root of 2 for t
   from 0 to 19, of 3 from 20 to 39, of 5 from 40 to 59 and of 10 from 60 to
   79 (5a827999, 6ed9eba1, 8f1bbcdc, ca62c1d6). Each constructor states that
   definition as its guard (n is a literal; the word is free, as SHA256_K's),
   so a word that is not floor(sqrt(n) * 2^30) does not type-check
   (tests/static/reject, the sha1-k fixtures). Keyword: round-constants. *)






(* The constant of round t, with the proof that it is the table's *)



implement sha1_k_w32 {t} (t) =
  if $AR.lt_g1(t, 20) then (SHA1_K_0_to_19() | $AR.word32_pack_inline(0x5a, 0x82, 0x79, 0x99))
  else if $AR.lt_g1(t, 40) then (SHA1_K_20_to_39() | $AR.word32_pack_inline(0x6e, 0xd9, 0xeb, 0xa1))
  else if $AR.lt_g1(t, 60) then (SHA1_K_40_to_59() | $AR.word32_pack_inline(0x8f, 0x1b, 0xbc, 0xdc))
  else (SHA1_K_60_to_79() | $AR.word32_pack_inline(0xca, 0x62, 0xc1, 0xd6))

(* Deprecated (sha256#48): sha1_k is kept as published, with the two 16-bit halves as ints; use sha1_k_w32. It is removed in a later version, after one published version with both. *)



implement sha1_k {t} (t) =
  if $AR.lt_g1(t, 20) then (SHA1_K_0_to_19() | @(0x5a82, 0x7999))
  else if $AR.lt_g1(t, 40) then (SHA1_K_20_to_39() | @(0x6ed9, 0xeba1))
  else if $AR.lt_g1(t, 60) then (SHA1_K_40_to_59() | @(0x8f1b, 0xbcdc))
  else (SHA1_K_60_to_79() | @(0xca62, 0xc1d6))

(* SHA1_ROUND(t, a, b, c, d, e, k, w, new_a, new_c): round t of SHA-1
   (section 6.1.2 step 3) from the working variables a to e, the constant k
   and the schedule word w:
     T = ROTL 5 (a) + f_t(b, c, d) + e + k + w
   each sum modulo 2 to the 32, in that order; ROTL 5 is ROTR 27 and ROTL 30
   is ROTR 2 (arith has no left rotation; ROTL n = ROTR (32 - n) by the
   standard's definitions of the two). The new a is T and the new c is ROTL 30
   (b); the others shift (e = d, d = c, b = a), which SHA1_ROUNDS puts in its
   indices. *)











(* Round t, with the proof that its results are the standard's *)





implement sha1_round_w32 (t, a_word, b_word, c_word, d_word, e_word, k_word, w_word) = let
  val (turn | turn5_word) = $AR.word32_rotr_inline(a_word, 27)
  val (function | f_word) = sha1_f_w32(t, b_word, c_word, d_word)
  val (add1 | sum1_word) = $AR.word32_add(turn5_word, f_word)
  val (add2 | sum2_word) = $AR.word32_add(sum1_word, e_word)
  val (add3 | sum3_word) = $AR.word32_add(sum2_word, k_word)
  val (add4 | new_a_word) = $AR.word32_add(sum3_word, w_word)
  val (turn30 | new_c_word) = $AR.word32_rotr_inline(b_word, 2)
in (SHA1_ROUND_mk(turn, function, add1, add2, add3, add4, turn30)
    | @(new_a_word, new_c_word)) end

(* Deprecated (sha256#48): sha1_round is kept as published, with the two 16-bit halves as ints; use sha1_round_w32. It is removed in a later version, after one published version with both. *)





implement sha1_round (t, a_high, a_low, b_high, b_low, c_high, c_low, d_high, d_low, e_high, e_low, k_high, k_low, w_high, w_low) = let
  val (turn | @(turn5_high, turn5_low)) = $AR.rotr_fast(27, a_high, a_low)
  val (function | @(f_high, f_low)) = sha1_f(t, b_high, b_low, c_high, c_low, d_high, d_low)
  val (add1 | @(sum1_high, sum1_low)) = $AR.add32(turn5_high, turn5_low, f_high, f_low)
  val (add2 | @(sum2_high, sum2_low)) = $AR.add32(sum1_high, sum1_low, e_high, e_low)
  val (add3 | @(sum3_high, sum3_low)) = $AR.add32(sum2_high, sum2_low, k_high, k_low)
  val (add4 | @(new_a_high, new_a_low)) = $AR.add32(sum3_high, sum3_low, w_high, w_low)
  val (turn30 | @(new_c_high, new_c_low)) = $AR.rotr_fast(2, b_high, b_low)
in (SHA1_ROUND_mk(turn, function, add1, add2, add3, add4, turn30)
    | @(new_a_high, new_a_low, new_c_high, new_c_low)) end

(* SHA1_ROUNDS(msg, at, t, init, state): after t rounds of the block of 64
   bytes from `at` of the cells msg, begun with the working variables init,
   the working variables are state (section 6.1.2 step 3) *)













(* SHA1_BLOCK(msg, at, before, after): the block of 64 bytes from `at` of msg,
   hashed onto the chaining value `before` (section 6.1.2), makes `after`: the
   80 rounds begun with the working variables a to e set to `before`, and
   each working variable at the end added (modulo 2 to the 32) to the same
   word of `before` (step 4) *)










(* The 80 rounds, each with the proof that it is the standard's *)
fun _rounds1 {lw:agz}{words,msg:$A.cells}{at:nat}{init:five_words}{t:nat | t <= 80}
  {a_high,a_low,b_high,b_low,c_high,c_low,d_high,d_low,e_high,e_low:nat | a_high < 65536; a_low < 65536; b_high < 65536; b_low < 65536; c_high < 65536; c_low < 65536; d_high < 65536; d_low < 65536; e_high < 65536; e_low < 65536} .<80 - t>.
  (schedule: !$A.barr(lw, 320, words), listed: SCHEDULE_ARRAY(sha1_kind(), words, msg, at, 80), t: int t,
   a_word: $AR.word32(a_high, a_low), b_word: $AR.word32(b_high, b_low), c_word: $AR.word32(c_high, c_low), d_word: $AR.word32(d_high, d_low), e_word: $AR.word32(e_high, e_low),
   done: SHA1_ROUNDS(msg, at, t, init, five(w32(a_high, a_low), w32(b_high, b_low), w32(c_high, c_low), w32(d_high, d_low), w32(e_high, e_low))))
  : [end_a_high,end_a_low,end_b_high,end_b_low,end_c_high,end_c_low,end_d_high,end_d_low,end_e_high,end_e_low:nat | end_a_high < 65536; end_a_low < 65536; end_b_high < 65536; end_b_low < 65536; end_c_high < 65536; end_c_low < 65536; end_d_high < 65536; end_d_low < 65536; end_e_high < 65536; end_e_low < 65536]
    (SHA1_ROUNDS(msg, at, 80, init, five(w32(end_a_high, end_a_low), w32(end_b_high, end_b_low), w32(end_c_high, end_c_low), w32(end_d_high, end_d_low), w32(end_e_high, end_e_low))) | @($AR.word32(end_a_high, end_a_low), $AR.word32(end_b_high, end_b_low), $AR.word32(end_c_high, end_c_low), $AR.word32(end_d_high, end_d_low), $AR.word32(end_e_high, end_e_low))) =
  if t >= 80 then (done | @(a_word, b_word, c_word, d_word, e_word))
  else let
    val (constant | k_word) = sha1_k_w32(t)
    val (word | w_word) = _scheduled(schedule, listed, t)
    val (step | @(new_a_word, new_c_word)) =
      sha1_round_w32(t, a_word, b_word, c_word, d_word, e_word, k_word, w_word)
  in _rounds1(schedule, listed, t + 1,
       new_a_word, a_word, new_c_word, c_word, d_word,
       SHA1_ROUNDS_next(done, constant, word, step)) end

(* The block of 64 bytes from `at` of the message hashed onto the chaining
   value in the array (20 bytes, five words, at 0), the new chaining value
   written there, with the proof that it is the standard's *)










implement sha1_compress {lm}{nm}{msg}{at}{lw}{words}{lc}{chain}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low}
  (message, at, schedule, chaining, have) = let
  val (listed | schedule) = schedule_sha1(message, at, schedule)
  val @(h0_word, h1_word, h2_word, h3_word, h4_word) = five_get_w32(chaining, 0, have)
  val (rounds | @(end_a_word, end_b_word, end_c_word, end_d_word, end_e_word)) = _rounds1(schedule, listed, 0,
    h0_word, h1_word, h2_word, h3_word, h4_word, SHA1_ROUNDS_zero())
  val (add0 | next_h0_word) = $AR.word32_add(h0_word, end_a_word)
  val (add1 | next_h1_word) = $AR.word32_add(h1_word, end_b_word)
  val (add2 | next_h2_word) = $AR.word32_add(h2_word, end_c_word)
  val (add3 | next_h3_word) = $AR.word32_add(h3_word, end_d_word)
  val (add4 | next_h4_word) = $AR.word32_add(h4_word, end_e_word)
  val (written | chaining) = five_set_w32(chaining, 0, next_h0_word, next_h1_word, next_h2_word, next_h3_word, next_h4_word)
in (SHA1_BLOCK_mk(rounds, add0, add1, add2, add3, add4), written | @(schedule, chaining)) end

(* ============================================================
   Messages as sequences of bytes, and the padding (FIPS 180-4,
   sections 5.1.1 and 5.1.2), proved (bats-lang/sha256#29, stage D)

   A message is a sequence of cells (array's `cells`, whose cell values
   are the bytes). `SNOC(message, value, message_after)` says message_after is
   message with the byte `value` after it. `HELD(base, cells, n, message)`
   says message is `base` followed, one byte at a time, by the first n cells
   of `cells`: it is how bytes reach a message from an array (a piece given
   to update, the block being filled), and it names no array but the cells it
   reads. `LIST(message)` says message is a finite sequence, which is what
   lets a byte be put after it.
   ============================================================ *)












(* the empty message is a sequence *)


primplement empty_is_a_list () = LIST_mk(LISTN_nil())






(* A byte can be put after any message *)


prfun _snoc_list {message:$A.cells}{value:int}{size:nat} .<size>.
  (listed: LISTN(message, size)): [message_after:$A.cells] (SNOC(message, value, message_after), LISTN(message_after, size + 1)) =
  case+ listed of
  | LISTN_nil() => (SNOC_nil(), LISTN_cons(LISTN_nil()))
  | LISTN_cons(rest) => let
      prval (snoc, longer) = _snoc_list{..}{value}(rest)
    in (SNOC_cons(snoc), LISTN_cons(longer)) end

primplement snoc_list {message}{value} (list) = let
  prval LIST_mk(listed) = list
  prval (snoc, longer) = _snoc_list{message}{value}(listed)
in (snoc, LIST_mk(longer)) end

(* Setting a cell the held bytes do not reach leaves them as they were *)



prfun _held_frame {base,cells,cells_after,message:$A.cells}{n,i:nat | n <= i}{value:int} .<n>.
  (held: HELD(base, cells, n, message), set: $A.SETC(cells, i, value, cells_after)): HELD(base, cells_after, n, message) =
  case+ held of
  | HELD_zero() => HELD_zero()
  | HELD_next(before, cell, snoc) =>
      HELD_next(_held_frame(before, set), $A.setc_nth_other(set, cell), snoc)

primplement held_frame {base,cells,cells_after,message}{n,i}{value} (held, set) = _held_frame(held, set)

(* ============================================================
   The length of a message, in digits, and the padding

   The solver is 32-bit, so a message's length is not one integer: it is
   (count_top, count_high, count_blocks, fill) for n = 2 to the 32 *
   count_top + 2 to the 16 * count_high + 64 * count_blocks + fill, with
   fill the bytes in the block being filled (fill = 64 while that block is
   full and not yet hashed, then it is counted anew by NORM), count_blocks
   under 1024 (so 64 * count_blocks + fill is the low 16 bits), count_high
   under 65536 and count_top under 8192: a message of under 2 to the 45
   bytes, whose length in bits is under 2 to the 48, so the 64-bit length of
   the padding has its top two bytes zero.
   ============================================================ *)

(* NORM: a full block (fill = 64) is hashed, and the count carries into the
   next digit: the blocks, then count_high, then count_top *)





(* COUNTED(message, count_top, count_high, count_blocks, fill): message has
   2^32 * count_top + 2^16 * count_high + 64 * count_blocks + fill bytes, by
   its bytes one at a time (COUNTED_byte), and a full block hashed (COUNTED_norm) *)







(* The length in bits is 8 * n, and n = 2^32 * count_top + 2^16 * count_high +
   64 * count_blocks + fill, so 8 * n is three 16-bit limbs: each limb is two
   bytes and hands a carry (under 8) to the next. The three relations are
   small because the solver is 32-bit: each limb is its own, with its own few
   variables, and the carries are what they share.

   BITLEN_LOW(count_blocks, fill, carry_low, byte6, byte7): 8 * (64 *
   count_blocks + fill) = 65536 * carry_low + 256 * byte6 + byte7, the low limb
   and the carry out of it, with count_blocks = 128 * carry_low + blocks_rest
   BITLEN_MID(count_high, carry_low, carry_mid, byte4, byte5): 8 * count_high +
   carry_low = 65536 * carry_mid + 256 * byte4 + byte5, with count_high = 8192 *
   carry_mid + high_rest
   BITLEN_HIGH(count_top, carry_mid, byte2, byte3): 8 * count_top + carry_mid =
   256 * byte2 + byte3 (under 65536 since count_top is under 8192) *)












(* BITLEN(count_top, count_high, count_blocks, fill, byte0, ..., byte7): the
   8 bytes, most significant first, of 8 * n, the length in bits (the top two
   are 0: the length is under 2^48) *)





(* ZCOUNT(fill, zeros): `zeros` is the number of zero bytes after the 0x80 of
   a message whose length is `fill` modulo 64: the smallest number with fill +
   1 + zeros + 8 a multiple of 64 (5.1.1: the smallest k with l + 1 + k = 448
   modulo 512, here in bytes) *)




(* ZSNOC(start, zeros, longer): longer is start with `zeros` zero bytes after it *)




(* LENSNOC(start, byte0, ..., byte7, grown8): grown8 is start with the bytes
   byte0 to byte7 after it, one at a time *)






(* PAD(message, count_top, count_high, count_blocks, fill, padded): padded is
   the message, of that length, padded (FIPS 180-4, section 5.1.1 of SHA-256
   and of SHA-1): the byte 128 (the bit 1 and seven zeros), `zeros` zero bytes
   (ZCOUNT) and the 64-bit big-endian length in bits (BITLEN). padded is a
   multiple of 64 bytes long. *)







(* The 8 bytes of the length in bits (the top two are 0), with the proof that
   they are *)





fn _split128 {number:nat} (number: int number): [quotient,remainder:nat | number == 128*quotient + remainder; remainder < 128] @(int quotient, int remainder) = let
  val quotient = number / 128
in @(quotient, number - 128 * quotient) end

fn _split256 {number:nat} (number: int number): [quotient,remainder:nat | number == 256*quotient + remainder; remainder < 256] @(int quotient, int remainder) = let
  val quotient = number / 256
in @(quotient, number - 256 * quotient) end

fn _split8192 {number:nat} (number: int number): [quotient,remainder:nat | number == 8192*quotient + remainder; remainder < 8192] @(int quotient, int remainder) = let
  val quotient = number / 8192
in @(quotient, number - 8192 * quotient) end

(* The low limb of 8 * n, and the carry out of it *)



implement bitlen_low {count_blocks,fill} (count_blocks, fill) = let
  val [carry_low:int, blocks_rest:int] @(carry_low, blocks_rest) = _split128(count_blocks)
  val [byte6:int, byte7:int] @(byte6, byte7) = _split256(512 * blocks_rest + 8 * fill)
in (BITLEN_LOW_mk{count_blocks,fill,carry_low,blocks_rest,byte6,byte7}() | @(carry_low, byte6, byte7)) end

(* The middle limb, with the carry from below, and the carry out of it *)



implement bitlen_mid {count_high,carry_low} (count_high, carry_low) = let
  val [carry_mid:int, high_rest:int] @(carry_mid, high_rest) = _split8192(count_high)
  val [byte4:int, byte5:int] @(byte4, byte5) = _split256(8 * high_rest + carry_low)
in (BITLEN_MID_mk{count_high,carry_low,carry_mid,high_rest,byte4,byte5}() | @(carry_mid, byte4, byte5)) end

(* The high limb, with the carry from below *)



implement bitlen_high {count_top,carry_mid} (count_top, carry_mid) = let
  val [byte2:int, byte3:int] @(byte2, byte3) = _split256(8 * count_top + carry_mid)
in (BITLEN_HIGH_mk{count_top,carry_mid,byte2,byte3}() | @(byte2, byte3)) end

implement bitlen_bytes {count_top,count_high,count_blocks,fill} (count_top, count_high, count_blocks, fill) = let
  val (low | @(carry_low, byte6, byte7)) = bitlen_low(count_blocks, fill)
  val (mid | @(carry_mid, byte4, byte5)) = bitlen_mid(count_high, carry_low)
  val (high | @(byte2, byte3)) = bitlen_high(count_top, carry_mid)
in (BITLEN_mk(low, mid, high) | @(byte2, byte3, byte4, byte5, byte6, byte7)) end

(* ============================================================
   Writing the padding in place in the block being filled
   ============================================================ *)

(* The byte `value` put at cell i of the block, after the i bytes held *)
fn _emit {block_loc:agz}{block_cells,base,message:$A.cells}{i:nat | i < 64}{value:nat | value < 256}
  (block_array: $A.barr(block_loc, 64, block_cells), i: int i, value: int value, held: HELD(base, block_cells, i, message), list: LIST(message))
  : [block_cells_after,message_after:$A.cells] (HELD(base, block_cells_after, i + 1, message_after), LIST(message_after), SNOC(message, value, message_after) | $A.barr(block_loc, 64, block_cells_after)) = let
  val (set | block_array) = $A.barr_set_inline(block_array, i, value)
  prval kept = held_frame(held, set)
  prval (snoc, listed) = snoc_list{message}{value}(list)
in (HELD_next(kept, $A.setc_nth_same(set), snoc), listed, snoc | block_array) end

(* `remaining` zero bytes put from cell i, after `zeros_so_far` zeros *)
fun _emit_zeros {block_loc:agz}{block_cells,base,marked,message:$A.cells}{zeros_so_far:nat}{i,remaining:nat | i + remaining <= 64} .<remaining>.
  (block_array: $A.barr(block_loc, 64, block_cells), i: int i, remaining: int remaining,
   held: HELD(base, block_cells, i, message), list: LIST(message), zeros: ZSNOC(marked, zeros_so_far, message))
  : [block_cells_after,message_after:$A.cells] (HELD(base, block_cells_after, i + remaining, message_after), LIST(message_after), ZSNOC(marked, zeros_so_far + remaining, message_after) | $A.barr(block_loc, 64, block_cells_after)) =
  if remaining = 0 then (held, list, zeros | block_array)
  else let
    val (held_next, list_next, snoc | block_array) = _emit(block_array, i, 0, held, list)
  in _emit_zeros(block_array, i + 1, remaining - 1, held_next, list_next, ZSNOC_next(zeros, snoc)) end

(* The 8 bytes of the length at cells 56 to 63 *)
fn _emit_length {block_loc:agz}{block_cells,base,zeroed:$A.cells}{byte2,byte3,byte4,byte5,byte6,byte7:nat | byte2 < 256; byte3 < 256; byte4 < 256; byte5 < 256; byte6 < 256; byte7 < 256}
  (block_array: $A.barr(block_loc, 64, block_cells), held: HELD(base, block_cells, 56, zeroed), list: LIST(zeroed),
   byte2: int byte2, byte3: int byte3, byte4: int byte4, byte5: int byte5, byte6: int byte6, byte7: int byte7)
  : [block_cells_after,padded:$A.cells] (HELD(base, block_cells_after, 64, padded), LENSNOC(zeroed, 0, 0, byte2, byte3, byte4, byte5, byte6, byte7, padded) | $A.barr(block_loc, 64, block_cells_after)) = let
  val (held0, listed0, snoc0 | block_array) = _emit(block_array, 56, 0, held, list)
  val (held1, listed1, snoc1 | block_array) = _emit(block_array, 57, 0, held0, listed0)
  val (held2, listed2, snoc2 | block_array) = _emit(block_array, 58, byte2, held1, listed1)
  val (held3, listed3, snoc3 | block_array) = _emit(block_array, 59, byte3, held2, listed2)
  val (held4, listed4, snoc4 | block_array) = _emit(block_array, 60, byte4, held3, listed3)
  val (held5, listed5, snoc5 | block_array) = _emit(block_array, 61, byte5, held4, listed4)
  val (held6, listed6, snoc6 | block_array) = _emit(block_array, 62, byte6, held5, listed5)
  val (held7, listed7, snoc7 | block_array) = _emit(block_array, 63, byte7, held6, listed6)
in (held7, LENSNOC_mk(snoc0, snoc1, snoc2, snoc3, snoc4, snoc5, snoc6, snoc7) | block_array) end

(* A message of fill <= 55 bytes in the block being filled: the padding makes
   the block whole (128, zeros, the length) *)





implement pad_short {block_loc}{block_cells,hashed_bytes,message}{count_top,count_high,count_blocks,fill} (block_array, count_top, count_high, count_blocks, fill, held, list, counted) = let
  val (held1, list1, snoc128 | block_array) = _emit(block_array, fill, 128, held, list)
  val (held2, list2, zeros | block_array) = _emit_zeros(block_array, fill + 1, 55 - fill, held1, list1, ZSNOC_zero())
  val (lengths | @(byte2, byte3, byte4, byte5, byte6, byte7)) = bitlen_bytes(count_top, count_high, count_blocks, fill)
  val (held3, written | block_array) = _emit_length(block_array, held2, list2, byte2, byte3, byte4, byte5, byte6, byte7)
in (held3, PAD_mk(counted, ZCOUNT_short(), lengths, snoc128, zeros, written) | block_array) end

(* A message of 56 to 63 bytes in the block being filled: the first padding
   block is whole with the 128 and zeros; the second (pad_long_second, once
   the first is hashed) is the rest *)





implement pad_long_first {block_loc}{block_cells,hashed_bytes,message}{fill} (block_array, fill, held, list) = let
  val (held1, list1, snoc128 | block_array) = _emit(block_array, fill, 128, held, list)
  val (held2, list2, zeros | block_array) = _emit_zeros(block_array, fill + 1, 63 - fill, held1, list1, ZSNOC_zero())
in (held2, list2, snoc128, zeros | block_array) end






implement pad_long_second {block_loc}{block_cells,message,marked,first_padded}{count_top,count_high,count_blocks,fill} (block_array, count_top, count_high, count_blocks, fill, list, counted, snoc128, zeros) = let
  val (held1, list1, more | block_array) = _emit_zeros(block_array, 0, 56, HELD_zero(), list, zeros)
  val (lengths | @(byte2, byte3, byte4, byte5, byte6, byte7)) = bitlen_bytes(count_top, count_high, count_blocks, fill)
  val (held2, written | block_array) = _emit_length(block_array, held1, list1, byte2, byte3, byte4, byte5, byte6, byte7)
in (held2, PAD_mk(counted, ZCOUNT_long(), lengths, snoc128, more, written) | block_array) end

(* ============================================================
   The hash of a sequence of whole blocks, and the digest
   ============================================================ *)

(* SHA256_IV(chaining): the initial hash value H(0) of SHA-256 (FIPS 180-4, section
   5.3.3): the first 32 bits of the fractional parts of the square roots of
   the first eight primes. Stated, and tested against the definition, not
   proved (needs integers of 2 to the 64: sha256 issue 31) *)




(* SHA1_IV(chaining): the initial hash value H(0) of SHA-1 (section 5.3.1), five
   constants the standard gives as they are *)



(* The initial value, with the proof that it is the table's. The words are in
   the type, so the values returned are the ones the proof states. *)





implement sha256_iv_w32 () = (SHA256_IV_mk() | @($AR.word32_pack_inline(0x6a, 0x09, 0xe6, 0x67), $AR.word32_pack_inline(0xbb, 0x67, 0xae, 0x85), $AR.word32_pack_inline(0x3c, 0x6e, 0xf3, 0x72), $AR.word32_pack_inline(0xa5, 0x4f, 0xf5, 0x3a), $AR.word32_pack_inline(0x51, 0x0e, 0x52, 0x7f), $AR.word32_pack_inline(0x9b, 0x05, 0x68, 0x8c), $AR.word32_pack_inline(0x1f, 0x83, 0xd9, 0xab), $AR.word32_pack_inline(0x5b, 0xe0, 0xcd, 0x19)))

(* Deprecated (sha256#48): sha256_iv is kept as published, with the two 16-bit halves as ints; use sha256_iv_w32. It is removed in a later version, after one published version with both. *)






implement sha256_iv () = (SHA256_IV_mk() | @(0x6a09, 0xe667, 0xbb67, 0xae85, 0x3c6e, 0xf372, 0xa54f, 0xf53a,
                                              0x510e, 0x527f, 0x9b05, 0x688c, 0x1f83, 0xd9ab, 0x5be0, 0xcd19))





implement sha1_iv_w32 () = (SHA1_IV_mk() | @($AR.word32_pack_inline(0x67, 0x45, 0x23, 0x01), $AR.word32_pack_inline(0xef, 0xcd, 0xab, 0x89), $AR.word32_pack_inline(0x98, 0xba, 0xdc, 0xfe), $AR.word32_pack_inline(0x10, 0x32, 0x54, 0x76), $AR.word32_pack_inline(0xc3, 0xd2, 0xe1, 0xf0)))

(* Deprecated (sha256#48): sha1_iv is kept as published, with the two 16-bit halves as ints; use sha1_iv_w32. It is removed in a later version, after one published version with both. *)




implement sha1_iv () = (SHA1_IV_mk() | @(0x6745, 0x2301, 0xefcd, 0xab89, 0x98ba, 0xdcfe, 0x1032, 0x5476, 0xc3d2, 0xe1f0))

(* HASHED256(hashed_bytes, chaining): the SHA-256 chaining value after the
   sequence hashed_bytes, a whole number of 64-byte blocks, is `chaining`: the
   initial value, and then each block, which is 64 bytes put after the ones
   before (HELD) and is compressed (SHA256_BLOCK) onto the value the ones
   before made. The block's bytes are the first 64 cells of an array's cells,
   at 0. HASHED1 is the same for SHA-1. *)










(* DIGEST256(message, chaining): the SHA-256 of the message is `chaining`:
   the message padded (PAD), and the padded message hashed block by block from
   the initial value (HASHED256). DIGEST1 is the same for SHA-1. *)









(* The halves of a word of an array are under 2 to the 16 (bound lemmas: what
   the compression's preconditions need of the words an array holds) *)


primplement word_at_bound {cells}{at,high,low} (word) = let
  prval WORD_AT_mk(case0, case1, case2, case3) = word
in end





primplement eight_at_bound {cells}{at,h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low,h5_high,h5_low,h6_high,h6_low,h7_high,h7_low} (have) = let
  prval EIGHT_AT_mk(word0, word1, word2, word3, word4, word5, word6, word7) = have
  prval () = word_at_bound(word0)
  prval () = word_at_bound(word1)
  prval () = word_at_bound(word2)
  prval () = word_at_bound(word3)
  prval () = word_at_bound(word4)
  prval () = word_at_bound(word5)
  prval () = word_at_bound(word6)
  prval () = word_at_bound(word7)
in end

(* One block hashed onto the chaining value: the block is the 64 bytes held
   in the block array, put after the bytes already hashed *)
fn _compress256 {chain_loc,schedule_loc,block_loc:agz}{chain_cells,schedule_cells,block_cells,hashed_bytes,message:$A.cells}{chaining:eight_words}
  (block_array: !$A.barr(block_loc, 64, block_cells), schedule_array: $A.barr(schedule_loc, 256, schedule_cells), chain_array: $A.barr(chain_loc, 32, chain_cells),
   have: EIGHT_AT(chain_cells, 0, chaining), hashed: HASHED256(hashed_bytes, chaining), held: HELD(hashed_bytes, block_cells, 64, message))
  : [schedule_cells_after,chain_cells_after:$A.cells][chaining_after:eight_words]
    (HASHED256(message, chaining_after), EIGHT_AT(chain_cells_after, 0, chaining_after) | @($A.barr(schedule_loc, 256, schedule_cells_after), $A.barr(chain_loc, 32, chain_cells_after))) = let
  prval EIGHT_AT_mk(word0, word1, word2, word3, word4, word5, word6, word7) = have
  prval opened = EIGHT_AT_mk(word0, word1, word2, word3, word4, word5, word6, word7)
  prval () = eight_at_bound(opened)
  val (block, written | @(schedule_array, chain_array)) = sha256_compress(block_array, 0, schedule_array, chain_array, opened)
in (HASHED256_block(hashed, block, held), written | @(schedule_array, chain_array)) end







(* The parts of a hash of the empty message: the proofs and the three arrays *)
fn _init256 ()
  : [chain_cells,schedule_cells,block_cells:$A.cells][chain_loc,schedule_loc,block_loc:agz][chaining:eight_words]
    (HASHED256($A.cnil(), chaining), EIGHT_AT(chain_cells, 0, chaining), HELD($A.cnil(), block_cells, 0, $A.cnil()), LIST($A.cnil()),
     COUNTED($A.cnil(), 0, 0, 0, 0) | @($A.barr(chain_loc, 32, chain_cells), $A.barr(schedule_loc, 256, schedule_cells), $A.barr(block_loc, 64, block_cells))) = let
  val (_ | chain_array) = $A.barr_alloc(32)
  val (_ | schedule_array) = $A.barr_alloc(256)
  val (_ | block_array) = $A.barr_alloc(64)
  val (initial | @(h0_word, h1_word, h2_word, h3_word, h4_word, h5_word, h6_word, h7_word)) = sha256_iv_w32()
  val (have | chain_array) = eight_set_w32(chain_array, 0, h0_word, h1_word, h2_word, h3_word,
                                       h4_word, h5_word, h6_word, h7_word)
in (HASHED256_start(initial), have, HELD_zero(), empty_is_a_list(), COUNTED_nil() | @(chain_array, schedule_array, block_array)) end

(* A hash of the empty message: the context of everything fed to it so far,
   indexed by that message. Its chaining value (HASHED256), the bytes of the
   block being filled (HELD), their count (COUNTED) and the arrays are held
   in it, and none of them is given out. *)


implement init256_proved () = let
  val (hashed, have, block_held, list, counted | @(chain_array, schedule_array, block_array)) = _init256()
in ctx256_mk(hashed, have, block_held, list, counted | chain_array, schedule_array, block_array, 0, 0, 0, 0) end

(* Bytes of data from i put in the block until the data ends or the block is
   full: each is read from the data, put at the next cell and counted *)
fun _feed {block_loc,data_loc:agz}{n:nat}{data_cells,message_before,block_cells,hashed_bytes,message:$A.cells}{length:nat | length <= n}{i:nat | i <= length}{count_top,count_high,count_blocks,fill:nat | fill <= 64} .<length - i>.
  (block_array: $A.barr(block_loc, 64, block_cells), data: !$A.barr(data_loc, n, data_cells), length: int length, i: int i, fill: int fill,
   data_held: HELD(message_before, data_cells, i, message), block_held: HELD(hashed_bytes, block_cells, fill, message), list: LIST(message), counted: COUNTED(message, count_top, count_high, count_blocks, fill))
  : [block_cells_after,message_after:$A.cells][index_after,fill_after:nat | i <= index_after; index_after <= length; fill <= fill_after; fill_after <= 64; fill_after - fill == index_after - i; index_after == length || fill_after == 64]
    (HELD(message_before, data_cells, index_after, message_after), HELD(hashed_bytes, block_cells_after, fill_after, message_after), LIST(message_after), COUNTED(message_after, count_top, count_high, count_blocks, fill_after)
     | @($A.barr(block_loc, 64, block_cells_after), int index_after, int fill_after)) =
  if i >= length then (data_held, block_held, list, counted | @(block_array, i, fill))
  else if fill >= 64 then (data_held, block_held, list, counted | @(block_array, i, fill))
  else let
    val [value:int] (cell | value) = $A.barr_get_inline(data, i)
    val (set | block_array) = $A.barr_set_inline(block_array, fill, value)
    prval kept = held_frame(block_held, set)
    prval (snoc, list_after) = snoc_list{message}{value}(list)
  in _feed(block_array, data, length, i + 1, fill + 1,
       HELD_next(data_held, cell, snoc), HELD_next(kept, $A.setc_nth_same(set), snoc), list_after, COUNTED_byte(counted, snoc)) end

(* The count once a full block is hashed: carried into the next digit (the
   top digit is under 8190, so it cannot pass its end) *)
fn _normalize {count_top,count_high,count_blocks:nat | count_top < 8190; count_high < 65536; count_blocks < 1024} (count_top: int count_top, count_high: int count_high, count_blocks: int count_blocks)
  : [count_top_after,count_high_after,count_blocks_after:nat | count_top_after < 8191; count_high_after < 65536; count_blocks_after < 1024]
    (NORM(count_top, count_high, count_blocks, 64, count_top_after, count_high_after, count_blocks_after, 0) | @(int count_top_after, int count_high_after, int count_blocks_after)) =
  if count_blocks < 1023 then (NORM_block() | @(count_top, count_high, count_blocks + 1))
  else if count_high < 65535 then (NORM_carry() | @(count_top, count_high + 1, 0))
  else (NORM_carry2() | @(count_top + 1, 0, 0))

(* What update256_proved did: all `length` bytes were put after the message
   (Updated256: message_after is the message and the first `length` cells of
   the data, one after the other), or the message reached its largest length
   (about 2 to the 45 bytes) first and the bytes from the i-th on were not put
   (Stopped256: only the first i were). The comparable streaming API of HACL*
   answers a length over its maximum with an error code, as this does. *)






fun _update256 {chain_loc,schedule_loc,block_loc,data_loc:agz}{n:nat}{data_cells,message_before:$A.cells}{length:nat | length <= n}{i:nat | i <= length}
  {chain_cells,schedule_cells,block_cells,hashed_bytes,message:$A.cells}{chaining:eight_words}{count_top,count_high,count_blocks,fill:nat | count_top < 8191; count_high < 65536; count_blocks < 1024; fill < 64} .<length - i>.
  (chain_array: $A.barr(chain_loc, 32, chain_cells), schedule_array: $A.barr(schedule_loc, 256, schedule_cells), block_array: $A.barr(block_loc, 64, block_cells),
   data: !$A.barr(data_loc, n, data_cells), length: int length, i: int i, count_top: int count_top, count_high: int count_high, count_blocks: int count_blocks, fill: int fill,
   hashed: HASHED256(hashed_bytes, chaining), have: EIGHT_AT(chain_cells, 0, chaining), block_held: HELD(hashed_bytes, block_cells, fill, message), list: LIST(message),
   counted: COUNTED(message, count_top, count_high, count_blocks, fill), data_held: HELD(message_before, data_cells, i, message))
  : update256_result(message_before, data_cells, length) =
  if i >= length then Updated256(data_held | ctx256_mk(hashed, have, block_held, list, counted | chain_array, schedule_array, block_array, count_top, count_high, count_blocks, fill))
  else if count_top >= 8190 then Stopped256(data_held | ctx256_mk(hashed, have, block_held, list, counted | chain_array, schedule_array, block_array, count_top, count_high, count_blocks, fill))
  else let
    val (data_held_after, block_held_after, list_after, counted_after | @(block_array, index_after, fill_after)) = _feed(block_array, data, length, i, fill, data_held, block_held, list, counted)
  in
    if fill_after >= 64 then let
      val (hashed_after, have_after | @(schedule_array, chain_array)) = _compress256(block_array, schedule_array, chain_array, have, hashed, block_held_after)
      val (norm | @(count_top_after, count_high_after, count_blocks_after)) = _normalize(count_top, count_high, count_blocks)
    in _update256(chain_array, schedule_array, block_array, data, length, index_after, count_top_after, count_high_after, count_blocks_after, 0,
         hashed_after, have_after, HELD_zero(), list_after, COUNTED_norm(counted_after, norm), data_held_after) end
    else Updated256(data_held_after | ctx256_mk(hashed, have, block_held_after, list_after, counted_after | chain_array, schedule_array, block_array, count_top, count_high, count_blocks, fill_after))
  end

(* The bytes data[0, len) put after the message so far, one by one: the
   result's HELD proof is that message_after is the message followed by those
   cells. A block that fills is hashed (and the proof that it was, with the
   chaining value it made, is in the context). *)



implement update256_proved {message,data_cells}{l}{n}{length} (c, data, len) = let
  val+ ~ctx256_mk(hashed, have, block_held, list, counted | chain_array, schedule_array, block_array, count_top, count_high, count_blocks, fill) = c
in _update256(chain_array, schedule_array, block_array, data, len, 0, count_top, count_high, count_blocks, fill, hashed, have, block_held, list, counted, HELD_zero()) end

(* ============================================================
   The digest as 64 lowercase hex digits
   ============================================================ *)

(* HEX_DIGIT(digit, character): `character` is the ASCII character of the hex
   digit (a to f lower case) *)




(* HEXOF(out_cells, chain_cells, n): the first n bytes of chain_cells are
   written in out_cells as two hex digits each, the high digit first, from
   cell 0 *)







(* EIGHT_HEX(out_cells, chaining): out_cells holds the 64 hex digits of the 32
   bytes that are the eight words of `chaining`, big endian (the bytes are
   those of an array that held them: EIGHT_AT) *)



(* Setting a cell beyond the digits written leaves them as they were *)
prfun hexof_frame {out_cells,out_cells_after,chain_cells:$A.cells}{n,j:nat | 2*n <= j}{character:int} .<n>.
  (done: HEXOF(out_cells, chain_cells, n), set: $A.SETC(out_cells, j, character, out_cells_after)): HEXOF(out_cells_after, chain_cells, n) =
  case+ done of
  | HEXOF_zero() => HEXOF_zero()
  | HEXOF_next(before, nth, first, second, at_even, at_odd) =>
      HEXOF_next(hexof_frame(before, set), nth, first, second,
                 $A.setc_nth_other(set, at_even), $A.setc_nth_other(set, at_odd))

fn _split16 {number:nat | number < 256} (number: int number)
  : [quotient,remainder:nat | number == 16*quotient + remainder; quotient < 16; remainder < 16] @(int quotient, int remainder) = let
  val quotient = number / 16
in @(quotient, number - 16 * quotient) end

fn _hex_char {digit:nat | digit < 16} (digit: int digit): [character:nat | character < 256] (HEX_DIGIT(digit, character) | int character) =
  if digit < 10 then (HEX_DIGIT_decimal() | digit + 48) else (HEX_DIGIT_letter() | digit + 87)

fun _hex_bytes {chain_loc,out_loc:agz}{chain_cells,out_cells:$A.cells}{n:nat | n <= 32} .<32 - n>.
  (chain_array: !$A.barr(chain_loc, 32, chain_cells), out: $A.barr(out_loc, 64, out_cells), n: int n, done: HEXOF(out_cells, chain_cells, n))
  : [out_cells_after:$A.cells] (HEXOF(out_cells_after, chain_cells, 32) | $A.barr(out_loc, 64, out_cells_after)) =
  if n >= 32 then (done | out)
  else let
    val [value:int] (nth | value) = $A.barr_get_inline(chain_array, n)
    val [high_nibble:int, low_nibble:int] @(high_nibble, low_nibble) = _split16(value)
    val [first_char:int] (first | first_char) = _hex_char(high_nibble)
    val [second_char:int] (second | second_char) = _hex_char(low_nibble)
    val (set_even | out) = $A.barr_set_inline(out, 2 * n, first_char)
    val (set_odd | out) = $A.barr_set_inline(out, 2 * n + 1, second_char)
    prval kept = hexof_frame(hexof_frame(done, set_even), set_odd)
    prval at_even = $A.setc_nth_other(set_odd, $A.setc_nth_same(set_even))
    prval at_odd = $A.setc_nth_same(set_odd)
  in _hex_bytes(chain_array, out, n + 1, HEXOF_next(kept, nth, first, second, at_even, at_odd)) end

(* The hex digits of the chaining value, the array of it freed *)
fn _hex_out256 {chain_loc,out_loc:agz}{chain_cells,out_cells:$A.cells}{chaining:eight_words}
  (chain_array: $A.barr(chain_loc, 32, chain_cells), have: EIGHT_AT(chain_cells, 0, chaining), out: $A.barr(out_loc, 64, out_cells))
  : [out_cells_after:$A.cells] (EIGHT_HEX(out_cells_after, chaining) | $A.barr(out_loc, 64, out_cells_after)) = let
  val (written | out) = _hex_bytes(chain_array, out, 0, HEXOF_zero())
  val () = $A.barr_free(chain_array)
in (EIGHT_HEX_mk(have, written) | out) end

(* The padding of the message so far, the last block or two hashed, and the
   SHA-256 of the message as 64 lowercase hex digits in out, with the proof
   that it is (DIGEST256, EIGHT_HEX). The context is used up. *)



implement finish256_proved {message}{out_loc}{out_cells} (c, out) = let
  val+ ~ctx256_mk(hashed, have, block_held, list, counted | chain_array, schedule_array, block_array, count_top, count_high, count_blocks, fill) = c
in
  if fill <= 55 then let
    val (held, pad | block_array) = pad_short(block_array, count_top, count_high, count_blocks, fill, block_held, list, counted)
    val (hashed_after, have_after | @(schedule_array, chain_array)) = _compress256(block_array, schedule_array, chain_array, have, hashed, held)
    val () = $A.barr_free(block_array)
    val () = $A.barr_free(schedule_array)
    val (hex | out) = _hex_out256(chain_array, have_after, out)
  in (DIGEST256_mk(pad, hashed_after), hex | out) end
  else let
    val (held1, list_first, snoc, zeros | block_array) = pad_long_first(block_array, fill, block_held, list)
    val (hashed_after, have_after | @(schedule_array, chain_array)) = _compress256(block_array, schedule_array, chain_array, have, hashed, held1)
    val (held2, pad | block_array) = pad_long_second(block_array, count_top, count_high, count_blocks, fill, list_first, counted, snoc, zeros)
    val (hashed_last, have_last | @(schedule_array, chain_array)) = _compress256(block_array, schedule_array, chain_array, have_after, hashed_after, held2)
    val () = $A.barr_free(block_array)
    val () = $A.barr_free(schedule_array)
    val (hex | out) = _hex_out256(chain_array, have_last, out)
  in (DIGEST256_mk(pad, hashed_last), hex | out) end
end

(* ============================================================
   The digest of a whole array in one call
   ============================================================ *)

(* The same loop as _update256, for a message that starts empty and is under
   2 to the 16 bytes: 64 * count_blocks + fill = i bytes are in (so
   count_blocks is under 1024), the digits above stay 0, and the message never
   reaches its largest length. The count is not tied to anything bigger on
   purpose: the 32-bit solver accepted a false claim in a context that held
   1024 * count_high + count_blocks = j and 64 * j + fill = i together (65536 *
   count_high once j is gone) *)
fun _small256 {chain_loc,schedule_loc,block_loc,data_loc:agz}{n:nat}{data_cells,message_before:$A.cells}{length:nat | length <= n; length <= 65535}{i:nat | i <= length}
  {chain_cells,schedule_cells,block_cells,hashed_bytes,message:$A.cells}{chaining:eight_words}{count_blocks,fill:nat | count_blocks < 1024; fill < 64; 64*count_blocks + fill == i} .<length - i>.
  (chain_array: $A.barr(chain_loc, 32, chain_cells), schedule_array: $A.barr(schedule_loc, 256, schedule_cells), block_array: $A.barr(block_loc, 64, block_cells),
   data: !$A.barr(data_loc, n, data_cells), length: int length, i: int i, count_blocks: int count_blocks, fill: int fill,
   hashed: HASHED256(hashed_bytes, chaining), have: EIGHT_AT(chain_cells, 0, chaining), block_held: HELD(hashed_bytes, block_cells, fill, message), list: LIST(message),
   counted: COUNTED(message, 0, 0, count_blocks, fill), data_held: HELD(message_before, data_cells, i, message))
  : [message_after:$A.cells] (HELD(message_before, data_cells, length, message_after) | ctx256(message_after)) =
  if i >= length then (data_held | ctx256_mk(hashed, have, block_held, list, counted | chain_array, schedule_array, block_array, 0, 0, count_blocks, fill))
  else let
    val (data_held_after, block_held_after, list_after, counted_after | @(block_array, index_after, fill_after)) = _feed(block_array, data, length, i, fill, data_held, block_held, list, counted)
  in
    if fill_after >= 64 then let
      val (hashed_after, have_after | @(schedule_array, chain_array)) = _compress256(block_array, schedule_array, chain_array, have, hashed, block_held_after)
    in _small256(chain_array, schedule_array, block_array, data, length, index_after, count_blocks + 1, 0,
         hashed_after, have_after, HELD_zero(), list_after, COUNTED_norm(counted_after, NORM_block()), data_held_after) end
    else (data_held_after | ctx256_mk(hashed, have, block_held_after, list_after, counted_after | chain_array, schedule_array, block_array, 0, 0, count_blocks, fill_after))
  end

(* The SHA-256 of data[0, len), under 2 to the 16 bytes, as 64 lowercase hex
   digits in out: the message is the first len cells of the data, one after the
   other (HELD), its digest is the chaining value the padded message makes
   (DIGEST256), and the digits are that value's (EIGHT_HEX). For more bytes
   than that, the incremental API, in pieces. *)





implement sha256_digest_proved {l}{n}{data_cells}{length}{out_loc}{out_cells} (data, len, out) = let
  val (hashed, have, block_held, list, counted | @(chain_array, schedule_array, block_array)) = _init256()
  val (data_held | c) = _small256(chain_array, schedule_array, block_array, data, len, 0, 0, 0, hashed, have, block_held, list, counted, HELD_zero())
  val (digest, hex | out) = finish256_proved(c, out)
in (data_held, digest, hex | out) end

(* ============================================================
   SHA-1's digest (FIPS 180-4, section 6.1), the same padding and blocks
   ============================================================ *)





primplement five_at_bound {cells}{at,h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low} (have) = let
  prval FIVE_AT_mk(word0, word1, word2, word3, word4) = have
  prval () = word_at_bound(word0)
  prval () = word_at_bound(word1)
  prval () = word_at_bound(word2)
  prval () = word_at_bound(word3)
  prval () = word_at_bound(word4)
in end

fn _compress1 {chain_loc,schedule_loc,block_loc:agz}{chain_cells,schedule_cells,block_cells,hashed_bytes,message:$A.cells}{chaining:five_words}
  (block_array: !$A.barr(block_loc, 64, block_cells), schedule_array: $A.barr(schedule_loc, 320, schedule_cells), chain_array: $A.barr(chain_loc, 20, chain_cells),
   have: FIVE_AT(chain_cells, 0, chaining), hashed: HASHED1(hashed_bytes, chaining), held: HELD(hashed_bytes, block_cells, 64, message))
  : [schedule_cells_after,chain_cells_after:$A.cells][chaining_after:five_words]
    (HASHED1(message, chaining_after), FIVE_AT(chain_cells_after, 0, chaining_after) | @($A.barr(schedule_loc, 320, schedule_cells_after), $A.barr(chain_loc, 20, chain_cells_after))) = let
  prval FIVE_AT_mk(word0, word1, word2, word3, word4) = have
  prval opened = FIVE_AT_mk(word0, word1, word2, word3, word4)
  prval () = five_at_bound(opened)
  val (block, written | @(schedule_array, chain_array)) = sha1_compress(block_array, 0, schedule_array, chain_array, opened)
in (HASHED1_block(hashed, block, held), written | @(schedule_array, chain_array)) end

(* The padding and the last blocks of a SHA-1 message, and its 20 bytes
   written to out (the five words of the chaining value, big endian) *)
fn _finish1 {chain_loc,schedule_loc,block_loc,out_loc:agz}{chain_cells,schedule_cells,block_cells,hashed_bytes,message,out_cells:$A.cells}{chaining:five_words}{count_top,count_high,count_blocks,fill:nat | count_top < 8191; count_high < 65536; count_blocks < 1024; fill < 64}
  (chain_array: $A.barr(chain_loc, 20, chain_cells), schedule_array: $A.barr(schedule_loc, 320, schedule_cells), block_array: $A.barr(block_loc, 64, block_cells),
   count_top: int count_top, count_high: int count_high, count_blocks: int count_blocks, fill: int fill,
   hashed: HASHED1(hashed_bytes, chaining), have: FIVE_AT(chain_cells, 0, chaining), block_held: HELD(hashed_bytes, block_cells, fill, message), list: LIST(message),
   counted: COUNTED(message, count_top, count_high, count_blocks, fill), out: $A.barr(out_loc, 20, out_cells))
  : [out_cells_after:$A.cells][chaining_after:five_words] (DIGEST1(message, chaining_after), FIVE_AT(out_cells_after, 0, chaining_after) | $A.barr(out_loc, 20, out_cells_after)) = let
  fn written {chain_loc,out_loc:agz}{chain_cells,out_cells:$A.cells}{chaining:five_words}
    (chain_array: $A.barr(chain_loc, 20, chain_cells), have: FIVE_AT(chain_cells, 0, chaining), out: $A.barr(out_loc, 20, out_cells))
    : [out_cells_after:$A.cells] (FIVE_AT(out_cells_after, 0, chaining) | $A.barr(out_loc, 20, out_cells_after)) = let
    prval FIVE_AT_mk(word0, word1, word2, word3, word4) = have
    prval opened = FIVE_AT_mk(word0, word1, word2, word3, word4)
    prval () = five_at_bound(opened)
    val @(h0_word, h1_word, h2_word, h3_word, h4_word) = five_get_w32(chain_array, 0, opened)
    val () = $A.barr_free(chain_array)
  in five_set_w32(out, 0, h0_word, h1_word, h2_word, h3_word, h4_word) end
in
  if fill <= 55 then let
    val (held, pad | block_array) = pad_short(block_array, count_top, count_high, count_blocks, fill, block_held, list, counted)
    val (hashed_after, have_after | @(schedule_array, chain_array)) = _compress1(block_array, schedule_array, chain_array, have, hashed, held)
    val () = $A.barr_free(block_array)
    val () = $A.barr_free(schedule_array)
    val (placed | out) = written(chain_array, have_after, out)
  in (DIGEST1_mk(pad, hashed_after), placed | out) end
  else let
    val (held1, list_first, snoc, zeros | block_array) = pad_long_first(block_array, fill, block_held, list)
    val (hashed_after, have_after | @(schedule_array, chain_array)) = _compress1(block_array, schedule_array, chain_array, have, hashed, held1)
    val (held2, pad | block_array) = pad_long_second(block_array, count_top, count_high, count_blocks, fill, list_first, counted, snoc, zeros)
    val (hashed_last, have_last | @(schedule_array, chain_array)) = _compress1(block_array, schedule_array, chain_array, have_after, hashed_after, held2)
    val () = $A.barr_free(block_array)
    val () = $A.barr_free(schedule_array)
    val (placed | out) = written(chain_array, have_last, out)
  in (DIGEST1_mk(pad, hashed_last), placed | out) end
end

fn _init1 ()
  : [chain_cells,schedule_cells,block_cells:$A.cells][chain_loc,schedule_loc,block_loc:agz][chaining:five_words]
    (HASHED1($A.cnil(), chaining), FIVE_AT(chain_cells, 0, chaining), HELD($A.cnil(), block_cells, 0, $A.cnil()), LIST($A.cnil()),
     COUNTED($A.cnil(), 0, 0, 0, 0) | @($A.barr(chain_loc, 20, chain_cells), $A.barr(schedule_loc, 320, schedule_cells), $A.barr(block_loc, 64, block_cells))) = let
  val (_ | chain_array) = $A.barr_alloc(20)
  val (_ | schedule_array) = $A.barr_alloc(320)
  val (_ | block_array) = $A.barr_alloc(64)
  val (initial | @(h0_word, h1_word, h2_word, h3_word, h4_word)) = sha1_iv_w32()
  val (have | chain_array) = five_set_w32(chain_array, 0, h0_word, h1_word, h2_word, h3_word, h4_word)
in (HASHED1_start(initial), have, HELD_zero(), empty_is_a_list(), COUNTED_nil() | @(chain_array, schedule_array, block_array)) end

fun _small1 {chain_loc,schedule_loc,block_loc,data_loc,out_loc:agz}{n:nat}{data_cells,message_before,out_cells:$A.cells}{length:nat | length <= n; length <= 65535}{i:nat | i <= length}
  {chain_cells,schedule_cells,block_cells,hashed_bytes,message:$A.cells}{chaining:five_words}{count_blocks,fill:nat | count_blocks < 1024; fill < 64; 64*count_blocks + fill == i} .<length - i>.
  (chain_array: $A.barr(chain_loc, 20, chain_cells), schedule_array: $A.barr(schedule_loc, 320, schedule_cells), block_array: $A.barr(block_loc, 64, block_cells),
   data: !$A.barr(data_loc, n, data_cells), length: int length, i: int i, count_blocks: int count_blocks, fill: int fill,
   hashed: HASHED1(hashed_bytes, chaining), have: FIVE_AT(chain_cells, 0, chaining), block_held: HELD(hashed_bytes, block_cells, fill, message), list: LIST(message),
   counted: COUNTED(message, 0, 0, count_blocks, fill), data_held: HELD(message_before, data_cells, i, message), out: $A.barr(out_loc, 20, out_cells))
  : [message_after,out_cells_after:$A.cells][chaining_after:five_words]
    (HELD(message_before, data_cells, length, message_after), DIGEST1(message_after, chaining_after), FIVE_AT(out_cells_after, 0, chaining_after) | $A.barr(out_loc, 20, out_cells_after)) =
  if i >= length then let
    val (digest, placed | out) = _finish1(chain_array, schedule_array, block_array, 0, 0, count_blocks, fill, hashed, have, block_held, list, counted, out)
  in (data_held, digest, placed | out) end
  else let
    val (data_held_after, block_held_after, list_after, counted_after | @(block_array, index_after, fill_after)) = _feed(block_array, data, length, i, fill, data_held, block_held, list, counted)
  in
    if fill_after >= 64 then let
      val (hashed_after, have_after | @(schedule_array, chain_array)) = _compress1(block_array, schedule_array, chain_array, have, hashed, block_held_after)
    in _small1(chain_array, schedule_array, block_array, data, length, index_after, count_blocks + 1, 0,
         hashed_after, have_after, HELD_zero(), list_after, COUNTED_norm(counted_after, NORM_block()), data_held_after, out) end
    else let
      val (digest, placed | out) = _finish1(chain_array, schedule_array, block_array, 0, 0, count_blocks, fill_after, hashed, have, block_held_after, list_after, counted_after, out)
    in (data_held_after, digest, placed | out) end
  end

(* The SHA-1 of data[0, len), under 2 to the 16 bytes, as its 20 bytes in out,
   with the proof that the message is the data and the bytes are its digest
   (DIGEST1, FIVE_AT) *)





implement sha1_digest_proved {l}{n}{data_cells}{length}{out_loc}{out_cells} (data, len, out) = let
  val (hashed, have, block_held, list, counted | @(chain_array, schedule_array, block_array)) = _init1()
in _small1(chain_array, schedule_array, block_array, data, len, 0, 0, 0, hashed, have, block_held, list, counted, HELD_zero(), out) end

(* ============================================================
   SHA-1 incrementally (FIPS 180-4, section 6.1), the same way as SHA-256
   ============================================================ *)







(* A hash of the empty message *)


implement init1_proved () = let
  val (hashed, have, block_held, list, counted | @(chain_array, schedule_array, block_array)) = _init1()
in ctx1_mk(hashed, have, block_held, list, counted | chain_array, schedule_array, block_array, 0, 0, 0, 0) end

(* What update1_proved did: all `length` bytes were put after the message
   (Updated1: message_after is the message and the first `length` cells of
   the data, one after the other), or the message reached its largest length
   (about 2 to the 45 bytes) first and the bytes from the i-th on were not put
   (Stopped1: only the first i were). The comparable streaming API of HACL*
   answers a length over its maximum with an error code, as this does. *)






fun _update1 {chain_loc,schedule_loc,block_loc,data_loc:agz}{n:nat}{data_cells,message_before:$A.cells}{length:nat | length <= n}{i:nat | i <= length}
  {chain_cells,schedule_cells,block_cells,hashed_bytes,message:$A.cells}{chaining:five_words}{count_top,count_high,count_blocks,fill:nat | count_top < 8191; count_high < 65536; count_blocks < 1024; fill < 64} .<length - i>.
  (chain_array: $A.barr(chain_loc, 20, chain_cells), schedule_array: $A.barr(schedule_loc, 320, schedule_cells), block_array: $A.barr(block_loc, 64, block_cells),
   data: !$A.barr(data_loc, n, data_cells), length: int length, i: int i, count_top: int count_top, count_high: int count_high, count_blocks: int count_blocks, fill: int fill,
   hashed: HASHED1(hashed_bytes, chaining), have: FIVE_AT(chain_cells, 0, chaining), block_held: HELD(hashed_bytes, block_cells, fill, message), list: LIST(message),
   counted: COUNTED(message, count_top, count_high, count_blocks, fill), data_held: HELD(message_before, data_cells, i, message))
  : update1_result(message_before, data_cells, length) =
  if i >= length then Updated1(data_held | ctx1_mk(hashed, have, block_held, list, counted | chain_array, schedule_array, block_array, count_top, count_high, count_blocks, fill))
  else if count_top >= 8190 then Stopped1(data_held | ctx1_mk(hashed, have, block_held, list, counted | chain_array, schedule_array, block_array, count_top, count_high, count_blocks, fill))
  else let
    val (data_held_after, block_held_after, list_after, counted_after | @(block_array, index_after, fill_after)) = _feed(block_array, data, length, i, fill, data_held, block_held, list, counted)
  in
    if fill_after >= 64 then let
      val (hashed_after, have_after | @(schedule_array, chain_array)) = _compress1(block_array, schedule_array, chain_array, have, hashed, block_held_after)
      val (norm | @(count_top_after, count_high_after, count_blocks_after)) = _normalize(count_top, count_high, count_blocks)
    in _update1(chain_array, schedule_array, block_array, data, length, index_after, count_top_after, count_high_after, count_blocks_after, 0,
         hashed_after, have_after, HELD_zero(), list_after, COUNTED_norm(counted_after, norm), data_held_after) end
    else Updated1(data_held_after | ctx1_mk(hashed, have, block_held_after, list_after, counted_after | chain_array, schedule_array, block_array, count_top, count_high, count_blocks, fill_after))
  end

(* The bytes data[0, len) put after the message so far, one by one: the
   result's HELD proof is that message_after is the message followed by those
   cells. A block that fills is hashed (and the proof that it was, with the
   chaining value it made, is in the context). *)



implement update1_proved {message,data_cells}{l}{n}{length} (c, data, len) = let
  val+ ~ctx1_mk(hashed, have, block_held, list, counted | chain_array, schedule_array, block_array, count_top, count_high, count_blocks, fill) = c
in _update1(chain_array, schedule_array, block_array, data, len, 0, count_top, count_high, count_blocks, fill, hashed, have, block_held, list, counted, HELD_zero()) end

(* The padding of the message so far, the last block or two hashed, and the
   SHA-1 of the message as its 20 bytes in out, with the proof that they are
   (DIGEST1, FIVE_AT). The context is used up. *)



implement finish1_proved {message}{out_loc}{out_cells} (c, out) = let
  val+ ~ctx1_mk(hashed, have, block_held, list, counted | chain_array, schedule_array, block_array, count_top, count_high, count_blocks, fill) = c
in _finish1(chain_array, schedule_array, block_array, count_top, count_high, count_blocks, fill, hashed, have, block_held, list, counted, out) end

(* ============================================================
   Block compression (FIPS 180-4, section 6.2.2)
   ============================================================ *)

(* Processes data[bo, bo + 64) into h. The message schedule is not an array:
   the words are named (w is not used; it stays so that the context keeps its
   fields). *)
fn _compress {ld:agz}{nd:pos}{bo:nat | bo + 64 <= nd}{lw:agz}{lh:agz}
  (data: !$A.arr(byte, ld, nd), bo: int bo,
   w: !$A.arr(uint, lw, 64), h: !$A.arr(uint, lh, 8)): void = let
(* begin generated by scripts/gen-fast-compress.py *)
  (* the 16 words of the block *)
  val w0 = _word(data, bo + 0)
  val w1 = _word(data, bo + 4)
  val w2 = _word(data, bo + 8)
  val w3 = _word(data, bo + 12)
  val w4 = _word(data, bo + 16)
  val w5 = _word(data, bo + 20)
  val w6 = _word(data, bo + 24)
  val w7 = _word(data, bo + 28)
  val w8 = _word(data, bo + 32)
  val w9 = _word(data, bo + 36)
  val w10 = _word(data, bo + 40)
  val w11 = _word(data, bo + 44)
  val w12 = _word(data, bo + 48)
  val w13 = _word(data, bo + 52)
  val w14 = _word(data, bo + 56)
  val w15 = _word(data, bo + 60)
  (* the chaining value *)
  val h0 = $A.get<uint>(h, 0)
  val h1 = $A.get<uint>(h, 1)
  val h2 = $A.get<uint>(h, 2)
  val h3 = $A.get<uint>(h, 3)
  val h4 = $A.get<uint>(h, 4)
  val h5 = $A.get<uint>(h, 5)
  val h6 = $A.get<uint>(h, 6)
  val h7 = $A.get<uint>(h, 7)
  val @(e0, a0) = _round(h0, h1, h2, h3, h4, h5, h6, h7, 0x428a2f98u + w0)
  val @(e1, a1) = _round(a0, h0, h1, h2, e0, h4, h5, h6, 0x71374491u + w1)
  val @(e2, a2) = _round(a1, a0, h0, h1, e1, e0, h4, h5, 0xb5c0fbcfu + w2)
  val @(e3, a3) = _round(a2, a1, a0, h0, e2, e1, e0, h4, 0xe9b5dba5u + w3)
  val @(e4, a4) = _round(a3, a2, a1, a0, e3, e2, e1, e0, 0x3956c25bu + w4)
  val @(e5, a5) = _round(a4, a3, a2, a1, e4, e3, e2, e1, 0x59f111f1u + w5)
  val @(e6, a6) = _round(a5, a4, a3, a2, e5, e4, e3, e2, 0x923f82a4u + w6)
  val @(e7, a7) = _round(a6, a5, a4, a3, e6, e5, e4, e3, 0xab1c5ed5u + w7)
  val @(e8, a8) = _round(a7, a6, a5, a4, e7, e6, e5, e4, 0xd807aa98u + w8)
  val @(e9, a9) = _round(a8, a7, a6, a5, e8, e7, e6, e5, 0x12835b01u + w9)
  val @(e10, a10) = _round(a9, a8, a7, a6, e9, e8, e7, e6, 0x243185beu + w10)
  val @(e11, a11) = _round(a10, a9, a8, a7, e10, e9, e8, e7, 0x550c7dc3u + w11)
  val @(e12, a12) = _round(a11, a10, a9, a8, e11, e10, e9, e8, 0x72be5d74u + w12)
  val @(e13, a13) = _round(a12, a11, a10, a9, e12, e11, e10, e9, 0x80deb1feu + w13)
  val @(e14, a14) = _round(a13, a12, a11, a10, e13, e12, e11, e10, 0x9bdc06a7u + w14)
  val @(e15, a15) = _round(a14, a13, a12, a11, e14, e13, e12, e11, 0xc19bf174u + w15)
  val w16 = _schedule(w14, w9, w1, w0)
  val @(e16, a16) = _round(a15, a14, a13, a12, e15, e14, e13, e12, 0xe49b69c1u + w16)
  val w17 = _schedule(w15, w10, w2, w1)
  val @(e17, a17) = _round(a16, a15, a14, a13, e16, e15, e14, e13, 0xefbe4786u + w17)
  val w18 = _schedule(w16, w11, w3, w2)
  val @(e18, a18) = _round(a17, a16, a15, a14, e17, e16, e15, e14, 0x0fc19dc6u + w18)
  val w19 = _schedule(w17, w12, w4, w3)
  val @(e19, a19) = _round(a18, a17, a16, a15, e18, e17, e16, e15, 0x240ca1ccu + w19)
  val w20 = _schedule(w18, w13, w5, w4)
  val @(e20, a20) = _round(a19, a18, a17, a16, e19, e18, e17, e16, 0x2de92c6fu + w20)
  val w21 = _schedule(w19, w14, w6, w5)
  val @(e21, a21) = _round(a20, a19, a18, a17, e20, e19, e18, e17, 0x4a7484aau + w21)
  val w22 = _schedule(w20, w15, w7, w6)
  val @(e22, a22) = _round(a21, a20, a19, a18, e21, e20, e19, e18, 0x5cb0a9dcu + w22)
  val w23 = _schedule(w21, w16, w8, w7)
  val @(e23, a23) = _round(a22, a21, a20, a19, e22, e21, e20, e19, 0x76f988dau + w23)
  val w24 = _schedule(w22, w17, w9, w8)
  val @(e24, a24) = _round(a23, a22, a21, a20, e23, e22, e21, e20, 0x983e5152u + w24)
  val w25 = _schedule(w23, w18, w10, w9)
  val @(e25, a25) = _round(a24, a23, a22, a21, e24, e23, e22, e21, 0xa831c66du + w25)
  val w26 = _schedule(w24, w19, w11, w10)
  val @(e26, a26) = _round(a25, a24, a23, a22, e25, e24, e23, e22, 0xb00327c8u + w26)
  val w27 = _schedule(w25, w20, w12, w11)
  val @(e27, a27) = _round(a26, a25, a24, a23, e26, e25, e24, e23, 0xbf597fc7u + w27)
  val w28 = _schedule(w26, w21, w13, w12)
  val @(e28, a28) = _round(a27, a26, a25, a24, e27, e26, e25, e24, 0xc6e00bf3u + w28)
  val w29 = _schedule(w27, w22, w14, w13)
  val @(e29, a29) = _round(a28, a27, a26, a25, e28, e27, e26, e25, 0xd5a79147u + w29)
  val w30 = _schedule(w28, w23, w15, w14)
  val @(e30, a30) = _round(a29, a28, a27, a26, e29, e28, e27, e26, 0x06ca6351u + w30)
  val w31 = _schedule(w29, w24, w16, w15)
  val @(e31, a31) = _round(a30, a29, a28, a27, e30, e29, e28, e27, 0x14292967u + w31)
  val w32 = _schedule(w30, w25, w17, w16)
  val @(e32, a32) = _round(a31, a30, a29, a28, e31, e30, e29, e28, 0x27b70a85u + w32)
  val w33 = _schedule(w31, w26, w18, w17)
  val @(e33, a33) = _round(a32, a31, a30, a29, e32, e31, e30, e29, 0x2e1b2138u + w33)
  val w34 = _schedule(w32, w27, w19, w18)
  val @(e34, a34) = _round(a33, a32, a31, a30, e33, e32, e31, e30, 0x4d2c6dfcu + w34)
  val w35 = _schedule(w33, w28, w20, w19)
  val @(e35, a35) = _round(a34, a33, a32, a31, e34, e33, e32, e31, 0x53380d13u + w35)
  val w36 = _schedule(w34, w29, w21, w20)
  val @(e36, a36) = _round(a35, a34, a33, a32, e35, e34, e33, e32, 0x650a7354u + w36)
  val w37 = _schedule(w35, w30, w22, w21)
  val @(e37, a37) = _round(a36, a35, a34, a33, e36, e35, e34, e33, 0x766a0abbu + w37)
  val w38 = _schedule(w36, w31, w23, w22)
  val @(e38, a38) = _round(a37, a36, a35, a34, e37, e36, e35, e34, 0x81c2c92eu + w38)
  val w39 = _schedule(w37, w32, w24, w23)
  val @(e39, a39) = _round(a38, a37, a36, a35, e38, e37, e36, e35, 0x92722c85u + w39)
  val w40 = _schedule(w38, w33, w25, w24)
  val @(e40, a40) = _round(a39, a38, a37, a36, e39, e38, e37, e36, 0xa2bfe8a1u + w40)
  val w41 = _schedule(w39, w34, w26, w25)
  val @(e41, a41) = _round(a40, a39, a38, a37, e40, e39, e38, e37, 0xa81a664bu + w41)
  val w42 = _schedule(w40, w35, w27, w26)
  val @(e42, a42) = _round(a41, a40, a39, a38, e41, e40, e39, e38, 0xc24b8b70u + w42)
  val w43 = _schedule(w41, w36, w28, w27)
  val @(e43, a43) = _round(a42, a41, a40, a39, e42, e41, e40, e39, 0xc76c51a3u + w43)
  val w44 = _schedule(w42, w37, w29, w28)
  val @(e44, a44) = _round(a43, a42, a41, a40, e43, e42, e41, e40, 0xd192e819u + w44)
  val w45 = _schedule(w43, w38, w30, w29)
  val @(e45, a45) = _round(a44, a43, a42, a41, e44, e43, e42, e41, 0xd6990624u + w45)
  val w46 = _schedule(w44, w39, w31, w30)
  val @(e46, a46) = _round(a45, a44, a43, a42, e45, e44, e43, e42, 0xf40e3585u + w46)
  val w47 = _schedule(w45, w40, w32, w31)
  val @(e47, a47) = _round(a46, a45, a44, a43, e46, e45, e44, e43, 0x106aa070u + w47)
  val w48 = _schedule(w46, w41, w33, w32)
  val @(e48, a48) = _round(a47, a46, a45, a44, e47, e46, e45, e44, 0x19a4c116u + w48)
  val w49 = _schedule(w47, w42, w34, w33)
  val @(e49, a49) = _round(a48, a47, a46, a45, e48, e47, e46, e45, 0x1e376c08u + w49)
  val w50 = _schedule(w48, w43, w35, w34)
  val @(e50, a50) = _round(a49, a48, a47, a46, e49, e48, e47, e46, 0x2748774cu + w50)
  val w51 = _schedule(w49, w44, w36, w35)
  val @(e51, a51) = _round(a50, a49, a48, a47, e50, e49, e48, e47, 0x34b0bcb5u + w51)
  val w52 = _schedule(w50, w45, w37, w36)
  val @(e52, a52) = _round(a51, a50, a49, a48, e51, e50, e49, e48, 0x391c0cb3u + w52)
  val w53 = _schedule(w51, w46, w38, w37)
  val @(e53, a53) = _round(a52, a51, a50, a49, e52, e51, e50, e49, 0x4ed8aa4au + w53)
  val w54 = _schedule(w52, w47, w39, w38)
  val @(e54, a54) = _round(a53, a52, a51, a50, e53, e52, e51, e50, 0x5b9cca4fu + w54)
  val w55 = _schedule(w53, w48, w40, w39)
  val @(e55, a55) = _round(a54, a53, a52, a51, e54, e53, e52, e51, 0x682e6ff3u + w55)
  val w56 = _schedule(w54, w49, w41, w40)
  val @(e56, a56) = _round(a55, a54, a53, a52, e55, e54, e53, e52, 0x748f82eeu + w56)
  val w57 = _schedule(w55, w50, w42, w41)
  val @(e57, a57) = _round(a56, a55, a54, a53, e56, e55, e54, e53, 0x78a5636fu + w57)
  val w58 = _schedule(w56, w51, w43, w42)
  val @(e58, a58) = _round(a57, a56, a55, a54, e57, e56, e55, e54, 0x84c87814u + w58)
  val w59 = _schedule(w57, w52, w44, w43)
  val @(e59, a59) = _round(a58, a57, a56, a55, e58, e57, e56, e55, 0x8cc70208u + w59)
  val w60 = _schedule(w58, w53, w45, w44)
  val @(e60, a60) = _round(a59, a58, a57, a56, e59, e58, e57, e56, 0x90befffau + w60)
  val w61 = _schedule(w59, w54, w46, w45)
  val @(e61, a61) = _round(a60, a59, a58, a57, e60, e59, e58, e57, 0xa4506cebu + w61)
  val w62 = _schedule(w60, w55, w47, w46)
  val @(e62, a62) = _round(a61, a60, a59, a58, e61, e60, e59, e58, 0xbef9a3f7u + w62)
  val w63 = _schedule(w61, w56, w48, w47)
  val @(e63, a63) = _round(a62, a61, a60, a59, e62, e61, e60, e59, 0xc67178f2u + w63)
  val () = $A.set<uint>(h, 0, h0 + a63)
  val () = $A.set<uint>(h, 1, h1 + a62)
  val () = $A.set<uint>(h, 2, h2 + a61)
  val () = $A.set<uint>(h, 3, h3 + a60)
  val () = $A.set<uint>(h, 4, h4 + e63)
  val () = $A.set<uint>(h, 5, h5 + e62)
  val () = $A.set<uint>(h, 6, h6 + e61)
  val () = $A.set<uint>(h, 7, h7 + e60)
(* end generated by scripts/gen-fast-compress.py *)
in end

(* The one or two padding blocks in pad[0, last). *)
fn _compress_pad {lp,lw,lh:agz}{e:int | e == 64 || e == 128}
  (pad: !$A.arr(byte, lp, 128), last: int e,
   w: !$A.arr(uint, lw, 64), h: !$A.arr(uint, lh, 8)): void = let
  val () = _compress(pad, 0, w, h)
in if last = 128 then _compress(pad, 64, w, h) else () end

(* ============================================================
   Output
   ============================================================ *)

(* The low byte of x. *)
fn _byte (x: uint): [v:nat | v < 256] int v =
  $AR.low_byte(g0uint2int_uint_int(x land 0xffu))

(* The hex digit of d < 16. *)
fn _hex {d:nat | d < 16} (d: int d): [c:nat | c < 256] int c =
  if d < 10 then d + 48 else d + 87

(* Writes x as 8 hex digits at out[p, p + 8). *)
fn _put_word {lo:agz}{p:nat | p + 8 <= 64}
  (out: !$A.arr(byte, lo, 64), p: int p, x: uint): void = let
  fun loop {i:nat | i <= 8} .<8 - i>.
    (out: !$A.arr(byte, lo, 64), i: int i): void =
    if i >= 8 then ()
    else let
      val v = _byte(x >> (28 - 4 * i))
      val hi = v / 16
      val () = $A.set<byte>(out, p + i, $A.int2byte(_hex(v - 16 * hi)))
    in loop(out, i + 1) end
in loop(out, 0) end

(* ============================================================
   Incremental hash
   ============================================================ *)

implement init () = let
  val h = $A.alloc<uint>(8)
  val () = $A.set<uint>(h, 0, 0x6a09e667u)
  val () = $A.set<uint>(h, 1, 0xbb67ae85u)
  val () = $A.set<uint>(h, 2, 0x3c6ef372u)
  val () = $A.set<uint>(h, 3, 0xa54ff53au)
  val () = $A.set<uint>(h, 4, 0x510e527fu)
  val () = $A.set<uint>(h, 5, 0x9b05688cu)
  val () = $A.set<uint>(h, 6, 0x1f83d9abu)
  val () = $A.set<uint>(h, 7, 0x5be0cd19u)
in ctx_mk(h, $A.alloc<uint>(64), $A.alloc<byte>(64), 0, 0u, 0u) end

(* data[i, k) appended to the block in buf[0, b), compressing each block
   as it fills; the bytes left in the block. With the block empty, a whole
   block of data is compressed where it lies, with no copy. *)
fun _fill {lh,lw,lb,ld:agz}{n:pos}{k:nat | k <= n}{i:nat | i <= k}{b:nat | b < 64}
  .<k - i>.
  (h: !$A.arr(uint, lh, 8), w: !$A.arr(uint, lw, 64), buf: !$A.arr(byte, lb, 64),
   data: !$A.arr(byte, ld, n), k: int k, i: int i, b: int b)
  : [b2:nat | b2 < 64] int b2 =
  if i >= k then b
  else if b = 0 then
    (if i + 64 > k then let
       val () = $A.set<byte>(buf, 0, $A.get<byte>(data, i))
     in _fill(h, w, buf, data, k, i + 1, 1) end
     else let
       val () = _compress(data, i, w, h)
     in _fill(h, w, buf, data, k, i + 64, 0) end)
  else let
    val () = $A.set<byte>(buf, b, $A.get<byte>(data, i))
  in
    if b + 1 >= 64 then let
      val () = _compress(buf, 0, w, h)
    in _fill(h, w, buf, data, k, i + 1, 0) end
    else _fill(h, w, buf, data, k, i + 1, b + 1)
  end

implement update {l}{n}{k} (c, data, len) = let
  val+ @ctx_mk(h, w, buf, b, hi, lo) = c
  val () = b := _fill(h, w, buf, data, len, 0, b)
  val nlo = lo + _u(len)
  val () = (if nlo < lo then hi := hi + 1u else ())
  val () = lo := nlo
  prval () = fold@(c)
in end

implement finish {lo} (c, out) = let
  val+ ~ctx_mk(h, w, buf, tail, nhi, nlo) = c
  (* The tail, 0x80, zeros and the 64-bit big-endian bit length, in one
     or two blocks. alloc zeroes the buffer. *)
  val pad = $A.alloc<byte>(128)
  fun copy {lp,lb:agz}{t:nat | t < 64}{i:nat | i <= t} .<t - i>.
    (buf: !$A.arr(byte, lb, 64), pad: !$A.arr(byte, lp, 128), t: int t, i: int i): void =
    if i >= t then ()
    else let
      val () = $A.set<byte>(pad, i, $A.get<byte>(buf, i))
    in copy(buf, pad, t, i + 1) end
  val () = copy(buf, pad, tail, 0)
  val () = $A.set<byte>(pad, tail, $A.int2byte(128))
  val last = (if tail + 9 > 64 then 128 else 64): [e:int | e == 64 || e == 128] int e
  val bhi = (nhi << 3) lor (nlo >> 29)
  val blo = nlo << 3
  val () = $A.set<byte>(pad, last - 8, $A.int2byte(_byte(bhi >> 24)))
  val () = $A.set<byte>(pad, last - 7, $A.int2byte(_byte(bhi >> 16)))
  val () = $A.set<byte>(pad, last - 6, $A.int2byte(_byte(bhi >> 8)))
  val () = $A.set<byte>(pad, last - 5, $A.int2byte(_byte(bhi)))
  val () = $A.set<byte>(pad, last - 4, $A.int2byte(_byte(blo >> 24)))
  val () = $A.set<byte>(pad, last - 3, $A.int2byte(_byte(blo >> 16)))
  val () = $A.set<byte>(pad, last - 2, $A.int2byte(_byte(blo >> 8)))
  val () = $A.set<byte>(pad, last - 1, $A.int2byte(_byte(blo)))
  val () = _compress_pad(pad, last, w, h)
  fun put {lh:agz}{j:nat | j <= 8} .<8 - j>.
    (out: !$A.arr(byte, lo, 64), h: !$A.arr(uint, lh, 8), j: int j): void =
    if j >= 8 then ()
    else let val () = _put_word(out, 8 * j, $A.get<uint>(h, j)) in put(out, h, j + 1) end
  val () = put(out, h, 0)
  val () = $A.free<byte>(pad)
  val () = $A.free<byte>(buf)
  val () = $A.free<uint>(w)
  val () = $A.free<uint>(h)
in end

(* ============================================================
   Main hash
   ============================================================ *)

implement hash {l}{n}{lo} (data, data_len, out) = let
  val c = init()
  val () = update(c, data, data_len)
in finish(c, out) end

(* ============================================================
   The proved code through arrays: proved_hash, proved_init,
   proved_update, proved_finish and sha1_digest (sha256#29, stage E)

   The callers' arrays are array's `arr` (and `borrow`), whose cells the
   types know nothing of, and the proved functions read a `barr`, whose
   cells they do. So the bytes of a call are copied, a piece at a time, into
   a `barr` of the package's own (_copy_arr, _copy_borrow) and fed to the
   proved update (update256_proved, update1_proved); the digits and bytes
   the proved finish writes into a `barr` are copied to the caller's array
   (_copy_out). The copies are glue the types do not check, tested by
   tests/dynamic; everything between them (the padding, the blocks, the
   message schedule, the rounds, the chaining value, the digits) is the
   proved code, so the digest a caller gets is the one DIGEST256 and
   DIGEST1 are about. An input of any length is fed in pieces to the
   incremental proved API, so no input is limited to the 2 to the 16 bytes
   the one-shot sha256_digest_proved and sha1_digest_proved take (those are
   proved too and stay beside).

   hash, init, update and finish keep the fast code above: they are not
   changed, and the proved functions are new names beside them.
   ============================================================ *)

(* A byte as the integer it is, 0 to 255 *)
fn _octet (b: byte): [v:int | 0 <= v; v < 256] int v = let
  val x = g1ofg0(byte2int0(b))
in
  if x >= 0 then (if x < 256 then x else 0)
  else if x >= ~256 then x + 256 else 0
end

(* data[from, from + count) put in the cells of the piece from its j-th on *)
fun _copy_arr {ld,lb:agz}{nd:pos}{from,count:nat | from + count <= nd; count <= 4096}{j:nat | j <= count}{cs:$A.cells} .<count - j>.
  (piece: $A.barr(lb, 4096, cs), data: !$A.arr(byte, ld, nd), from: int from, count: int count, j: int j)
  : [cs2:$A.cells] $A.barr(lb, 4096, cs2) =
  if j >= count then piece
  else let
    val (_ | piece) = $A.barr_set_inline(piece, j, _octet($A.get<byte>(data, from + j)))
  in _copy_arr(piece, data, from, count, j + 1) end

fun _copy_borrow {ld,lb:agz}{nd:pos}{from,count:nat | from + count <= nd; count <= 4096}{j:nat | j <= count}{cs:$A.cells} .<count - j>.
  (piece: $A.barr(lb, 4096, cs), data: !$A.borrow(byte, ld, nd), from: int from, count: int count, j: int j)
  : [cs2:$A.cells] $A.barr(lb, 4096, cs2) =
  if j >= count then piece
  else let
    val (_ | piece) = $A.barr_set_inline(piece, j, _octet($A.read<byte>(data, from + j)))
  in _copy_borrow(piece, data, from, count, j + 1) end

(* The first count cells of a barr put in an array of the caller's *)
fun _copy_out {lt,lo:agz}{n:pos}{count:nat | count <= n}{j:nat | j <= count}{cs:$A.cells} .<count - j>.
  (source: !$A.barr(lt, n, cs), out: !$A.arr(byte, lo, n), count: int count, j: int j): void =
  if j >= count then ()
  else let
    val (_ | v) = $A.barr_get_inline(source, j)
    val () = $A.set<byte>(out, j, $A.int2byte(v))
  in _copy_out(source, out, count, j + 1) end

(* data[i, length) fed to the context in pieces of at most 4096 bytes; it stops
   (Stopped256) only when the message has reached its largest length, about
   2 to the 45 bytes *)
fun _pour256 {ld,lb:agz}{nd:pos}{message,cs:$A.cells}{length:nat | length <= nd}{i:nat | i <= length} .<length - i>.
  (c: ctx256(message), piece: $A.barr(lb, 4096, cs), data: !$A.arr(byte, ld, nd), length: int length, i: int i)
  : [message_after,cs2:$A.cells] @(ctx256(message_after), $A.barr(lb, 4096, cs2)) =
  if i >= length then @(c, piece)
  else let
    val rest = length - i
    val count = (if rest < 4096 then rest else 4096): [q:pos | q <= 4096; q <= length - i] int q
    val piece = _copy_arr(piece, data, i, count, 0)
  in
    case+ update256_proved(c, piece, count) of
    | ~Updated256(_ | c2) => _pour256(c2, piece, data, length, i + count)
    | ~Stopped256(_ | c2) => @(c2, piece)
  end

fun _pour1 {ld,lb:agz}{nd:pos}{message,cs:$A.cells}{length:nat | length <= nd}{i:nat | i <= length} .<length - i>.
  (c: ctx1(message), piece: $A.barr(lb, 4096, cs), data: !$A.borrow(byte, ld, nd), length: int length, i: int i)
  : [message_after,cs2:$A.cells] @(ctx1(message_after), $A.barr(lb, 4096, cs2)) =
  if i >= length then @(c, piece)
  else let
    val rest = length - i
    val count = (if rest < 4096 then rest else 4096): [q:pos | q <= 4096; q <= length - i] int q
    val piece = _copy_borrow(piece, data, i, count, 0)
  in
    case+ update1_proved(c, piece, count) of
    | ~Updated1(_ | c2) => _pour1(c2, piece, data, length, i + count)
    | ~Stopped1(_ | c2) => @(c2, piece)
  end

(* The proved incremental SHA-256: proved_init, proved_update with each piece
   of the input in order, then proved_finish; the same as init, update and
   finish but the proved code, and about 8 times slower. It holds a ctx256
   of some message. *)





implement proved_init () = proved_ctx_mk(init256_proved())

(* Hashes data[0, len) after everything given so far (the proved code). A message that has
   reached its largest length (about 2 to the 45 bytes) takes no more. *)




implement proved_update {l}{n}{k} (c, data, len) = let
  val+ @proved_ctx_mk(inner) = c
  val taken = inner
  val (_ | piece) = $A.barr_alloc(4096)
  val @(next, piece) = _pour256(taken, piece, data, len, 0)
  val () = $A.barr_free(piece)
  val () = inner := next
  prval () = fold@(c)
in end

(* The SHA-256 of everything given, as 64 lowercase hex digits in out (the
   proved code). *)


implement proved_finish {lo} (c, out) = let
  val+ ~proved_ctx_mk(inner) = c
  val (_ | digits) = $A.barr_alloc(64)
  val (_, _ | digits) = finish256_proved(inner, digits)
  val () = _copy_out(digits, out, 64, 0)
  val () = $A.barr_free(digits)
in end

(* The SHA-256 of data[0, data_len) as 64 lowercase hex digits in out (the
   proved code; hash is the fast one). *)





implement proved_hash {l}{n}{lo} (data, data_len, out) = let
  val c = proved_init()
  val () = proved_update(c, data, data_len)
in proved_finish(c, out) end

(* The SHA-1 of data[0, data_len) as its 20 bytes, in out. SHA-1 is not fit
   to keep anything secret; it is here for the one thing EPUB asks of it, the
   key of the IDPF font obfuscation (quire#562). *)



implement sha1_digest {l}{n}{data_len}{lo} (data, data_len, out) = let
  val (_ | piece) = $A.barr_alloc(4096)
  val @(c, piece) = _pour1(init1_proved(), piece, data, data_len, 0)
  val () = $A.barr_free(piece)
  val (_ | digits) = $A.barr_alloc(20)
  val (_, _ | digits) = finish1_proved(c, digits)
  val () = _copy_out(digits, out, 20, 0)
  val () = $A.barr_free(digits)
in end
