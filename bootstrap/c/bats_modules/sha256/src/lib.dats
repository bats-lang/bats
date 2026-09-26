staload "./lib.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
(* sha256 -- pure ATS2 SHA-256 implementation *)
(* No C code, no $UNSAFE. Uses arith for bitwise ops. *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"

(* ============================================================
   Public API
   ============================================================ *)






(* ============================================================
   Bitwise helpers
   ============================================================ *)

fn _bxor(a: int, b: int): int =
  $AR.sub_int_int($AR.bor_int_int(a, b), $AR.band_int_int(a, b))

fn _mask32_val(): int = $AR.sub_int_int(0, 1)

fn _ushr(x: int, n: int): int =
  $AR.band_int_int($AR.bsr_int_int(x, n),
    $AR.sub_int_int($AR.bsl_int_int(1, $AR.sub_int_int(32, n)), 1))

fn _rotr(x: int, n: int): int =
  $AR.bor_int_int(_ushr(x, n),
    $AR.band_int_int($AR.bsl_int_int(x, $AR.sub_int_int(32, n)), _mask32_val()))

fn _mask32(x: int): int = $AR.band_int_int(x, _mask32_val())

(* ============================================================
   SHA-256 round constants
   ============================================================ *)

fn _sha256_k {k:int} (i: int k): int =
  if $AR.eq_g1(i, 0) then 1116352408
  else if $AR.eq_g1(i, 1) then 1899447441
  else if $AR.eq_g1(i, 2) then $AR.sub_int_int(0, 1245643825)
  else if $AR.eq_g1(i, 3) then $AR.sub_int_int(0, 373957723)
  else if $AR.eq_g1(i, 4) then 961987163
  else if $AR.eq_g1(i, 5) then 1508970993
  else if $AR.eq_g1(i, 6) then $AR.sub_int_int(0, 1841331548)
  else if $AR.eq_g1(i, 7) then $AR.sub_int_int(0, 1424204075)
  else if $AR.eq_g1(i, 8) then $AR.sub_int_int(0, 670586216)
  else if $AR.eq_g1(i, 9) then 310598401
  else if $AR.eq_g1(i, 10) then 607225278
  else if $AR.eq_g1(i, 11) then 1426881987
  else if $AR.eq_g1(i, 12) then 1925078388
  else if $AR.eq_g1(i, 13) then $AR.sub_int_int(0, 2132889090)
  else if $AR.eq_g1(i, 14) then $AR.sub_int_int(0, 1680079193)
  else if $AR.eq_g1(i, 15) then $AR.sub_int_int(0, 1046744716)
  else if $AR.eq_g1(i, 16) then $AR.sub_int_int(0, 459576895)
  else if $AR.eq_g1(i, 17) then $AR.sub_int_int(0, 272742522)
  else if $AR.eq_g1(i, 18) then 264347078
  else if $AR.eq_g1(i, 19) then 604807628
  else if $AR.eq_g1(i, 20) then 770255983
  else if $AR.eq_g1(i, 21) then 1249150122
  else if $AR.eq_g1(i, 22) then 1555081692
  else if $AR.eq_g1(i, 23) then 1996064986
  else if $AR.eq_g1(i, 24) then $AR.sub_int_int(0, 1740746414)
  else if $AR.eq_g1(i, 25) then $AR.sub_int_int(0, 1473132947)
  else if $AR.eq_g1(i, 26) then $AR.sub_int_int(0, 1341970488)
  else if $AR.eq_g1(i, 27) then $AR.sub_int_int(0, 1084653625)
  else if $AR.eq_g1(i, 28) then $AR.sub_int_int(0, 958395405)
  else if $AR.eq_g1(i, 29) then $AR.sub_int_int(0, 710438585)
  else if $AR.eq_g1(i, 30) then 113926993
  else if $AR.eq_g1(i, 31) then 338241895
  else if $AR.eq_g1(i, 32) then 666307205
  else if $AR.eq_g1(i, 33) then 773529912
  else if $AR.eq_g1(i, 34) then 1294757372
  else if $AR.eq_g1(i, 35) then 1396182291
  else if $AR.eq_g1(i, 36) then 1695183700
  else if $AR.eq_g1(i, 37) then 1986661051
  else if $AR.eq_g1(i, 38) then $AR.sub_int_int(0, 2117940946)
  else if $AR.eq_g1(i, 39) then $AR.sub_int_int(0, 1838011235)
  else if $AR.eq_g1(i, 40) then $AR.sub_int_int(0, 1564481375)
  else if $AR.eq_g1(i, 41) then $AR.sub_int_int(0, 1474664885)
  else if $AR.eq_g1(i, 42) then $AR.sub_int_int(0, 1035236496)
  else if $AR.eq_g1(i, 43) then $AR.sub_int_int(0, 949202525)
  else if $AR.eq_g1(i, 44) then $AR.sub_int_int(0, 778901479)
  else if $AR.eq_g1(i, 45) then $AR.sub_int_int(0, 694614492)
  else if $AR.eq_g1(i, 46) then $AR.sub_int_int(0, 200395387)
  else if $AR.eq_g1(i, 47) then 275423344
  else if $AR.eq_g1(i, 48) then 430227734
  else if $AR.eq_g1(i, 49) then 506948616
  else if $AR.eq_g1(i, 50) then 659060556
  else if $AR.eq_g1(i, 51) then 883997877
  else if $AR.eq_g1(i, 52) then 958139571
  else if $AR.eq_g1(i, 53) then 1322822218
  else if $AR.eq_g1(i, 54) then 1537002063
  else if $AR.eq_g1(i, 55) then 1747873779
  else if $AR.eq_g1(i, 56) then 1955562222
  else if $AR.eq_g1(i, 57) then 2024104815
  else if $AR.eq_g1(i, 58) then $AR.sub_int_int(0, 2067236844)
  else if $AR.eq_g1(i, 59) then $AR.sub_int_int(0, 1933114872)
  else if $AR.eq_g1(i, 60) then $AR.sub_int_int(0, 1866530822)
  else if $AR.eq_g1(i, 61) then $AR.sub_int_int(0, 1538233109)
  else if $AR.eq_g1(i, 62) then $AR.sub_int_int(0, 1090935817)
  else $AR.sub_int_int(0, 965641998)

(* ============================================================
   SHA-256 functions
   ============================================================ *)

fn _sha256_ch(x: int, y: int, z: int): int =
  _bxor($AR.band_int_int(x, y),
       $AR.band_int_int(_bxor(x, _mask32_val()), z))

fn _sha256_maj(x: int, y: int, z: int): int =
  _bxor(_bxor($AR.band_int_int(x, y), $AR.band_int_int(x, z)),
       $AR.band_int_int(y, z))

fn _sha256_sigma0(x: int): int =
  _bxor(_bxor(_rotr(x, 2), _rotr(x, 13)), _rotr(x, 22))

fn _sha256_sigma1(x: int): int =
  _bxor(_bxor(_rotr(x, 6), _rotr(x, 11)), _rotr(x, 25))

fn _sha256_lsigma0(x: int): int =
  _bxor(_bxor(_rotr(x, 7), _rotr(x, 18)), _ushr(x, 3))

fn _sha256_lsigma1(x: int): int =
  _bxor(_bxor(_rotr(x, 17), _rotr(x, 19)), _ushr(x, 10))

(* ============================================================
   Array int helpers
   ============================================================ *)

fn _ai {l:agz}{n:pos}{off:nat | off < n}
  (a: !$A.arr(int, l, n), off: int off, cap: int n): int =
  $A.get<int>(a, off)

fn _wi {l:agz}{n:pos}{off:nat | off < n}
  (a: !$A.arr(int, l, n), off: int off, v: int, cap: int n): void =
  $A.set<int>(a, off, v)

(* ============================================================
   Block compression
   ============================================================ *)

fn _sha256_compress {ld:agz}{nd:pos}{bo:nat | bo + 64 <= nd}{lw:agz}{lh:agz}
  (data: !$A.arr(byte, ld, nd), data_cap: int nd, block_off: int(bo),
   w: !$A.arr(int, lw, 64), h: !$A.arr(int, lh, 8)): void = let

  fun read_words {ld:agz}{nd:pos}{lw:agz}{bo:nat | bo + 64 <= nd}{k:nat | k <= 16} .<16-k>.
    (data: !$A.arr(byte, ld, nd), w: !$A.arr(int, lw, 64),
     i: int(k), base: int(bo), dcap: int nd): void =
    if $AR.gte_g1(i, 16) then ()
    else let
      val off = $AR.add_g1(base, $AR.mul_g1(i, 4))
      val b0 = byte2int0($A.get<byte>(data, off))
      val b1 = byte2int0($A.get<byte>(data, $AR.add_g1(off, 1)))
      val b2 = byte2int0($A.get<byte>(data, $AR.add_g1(off, 2)))
      val b3 = byte2int0($A.get<byte>(data, $AR.add_g1(off, 3)))
      val word = $AR.bor_int_int($AR.bor_int_int($AR.bsl_int_int(b0, 24), $AR.bsl_int_int(b1, 16)),
                             $AR.bor_int_int($AR.bsl_int_int(b2, 8), b3))
      val () = _wi(w, i, word, 64)
    in read_words(data, w, $AR.add_g1(i, 1), base, dcap) end

  val () = read_words(data, w, 0, block_off, data_cap)

  fun expand {lw:agz}{k:int | k >= 16; k <= 64} .<64-k>.
    (w: !$A.arr(int, lw, 64), i: int(k)): void =
    if $AR.gte_g1(i, 64) then ()
    else let
      val s0 = _sha256_lsigma0(_ai(w, $AR.sub_g1(i, 15), 64))
      val s1 = _sha256_lsigma1(_ai(w, $AR.sub_g1(i, 2), 64))
      val v = _mask32(_mask32(_ai(w, $AR.sub_g1(i, 16), 64) + s0) + _mask32(_ai(w, $AR.sub_g1(i, 7), 64) + s1))
      val () = _wi(w, i, v, 64)
    in expand(w, $AR.add_g1(i, 1)) end

  val () = expand(w, 16)

  fun rounds {lw:agz}{lh:agz}{k:nat | k <= 64} .<64-k>.
    (w: !$A.arr(int, lw, 64), h: !$A.arr(int, lh, 8),
     i: int(k), a: int, b: int, c: int, d: int,
     e: int, f: int, g: int, hh: int): void =
    if $AR.gte_g1(i, 64) then let
      val () = _wi(h, 0, _mask32(_ai(h, 0, 8) + a), 8)
      val () = _wi(h, 1, _mask32(_ai(h, 1, 8) + b), 8)
      val () = _wi(h, 2, _mask32(_ai(h, 2, 8) + c), 8)
      val () = _wi(h, 3, _mask32(_ai(h, 3, 8) + d), 8)
      val () = _wi(h, 4, _mask32(_ai(h, 4, 8) + e), 8)
      val () = _wi(h, 5, _mask32(_ai(h, 5, 8) + f), 8)
      val () = _wi(h, 6, _mask32(_ai(h, 6, 8) + g), 8)
      val () = _wi(h, 7, _mask32(_ai(h, 7, 8) + hh), 8)
    in end
    else let
      val s1 = _sha256_sigma1(e)
      val ch = _sha256_ch(e, f, g)
      val temp1 = _mask32(_mask32(hh + s1) + _mask32(ch + _mask32(_sha256_k(i) + _ai(w, i, 64))))
      val s0 = _sha256_sigma0(a)
      val mj = _sha256_maj(a, b, c)
      val temp2 = _mask32(s0 + mj)
    in rounds(w, h, $AR.add_g1(i, 1),
        _mask32(temp1 + temp2), a, b, c,
        _mask32(d + temp1), e, f, g) end

  val a0 = _ai(h, 0, 8) val b0 = _ai(h, 1, 8)
  val c0 = _ai(h, 2, 8) val d0 = _ai(h, 3, 8)
  val e0 = _ai(h, 4, 8) val f0 = _ai(h, 5, 8)
  val g0_ = _ai(h, 6, 8) val h0 = _ai(h, 7, 8)

in rounds(w, h, 0, a0, b0, c0, d0, e0, f0, g0_, h0) end

(* ============================================================
   Safe g0-to-g1 nibble conversion via linear scan
   ============================================================ *)

fun _find_nibble {k:nat | k <= 16} .<16-k>.
  (target: int, k: int(k)): [r:nat | r < 16] int(r) =
  if $AR.gte_g1(k, 16) then 0
  else if $AR.eq_int_int(target, k) then k
  else _find_nibble(target, $AR.add_g1(k, 1))

fn _g1_byte(x: int): [v:nat | v < 256] int(v) = let
  val hi = _find_nibble($AR.band_int_int(_ushr(x, 4), 15), 0)
  val lo = _find_nibble($AR.band_int_int(x, 15), 0)
in $AR.add_g1($AR.mul_g1(hi, 16), lo) end

(* ============================================================
   Hex output
   ============================================================ *)

fn _write_hex_word {lo:agz}{p:nat | p + 8 <= 64}
  (out: !$A.arr(byte, lo, 64), pos: int(p), word: int): void = let
  fun loop {lo:agz}{k:nat | k <= 8} .<8-k>.
    (out: !$A.arr(byte, lo, 64), base: int(p), w: int, i: int(k)): void =
    if $AR.gte_g1(i, 8) then ()
    else let
      val shift = $AR.mul_g1($AR.sub_g1(7, i), 4)
      val nib = _find_nibble($AR.band_int_int(_ushr(w, shift), 15), 0)
      val idx = $AR.add_g1(base, i)
      val () = if $AR.lt_g1(nib, 10) then
        $A.set<byte>(out, idx, $A.int2byte($AR.add_g1(nib, 48)))
      else
        $A.set<byte>(out, idx, $A.int2byte($AR.add_g1(nib, 87)))
    in loop(out, base, w, $AR.add_g1(i, 1)) end
in loop(out, pos, word, 0) end

(* ============================================================
   Main hash
   ============================================================ *)

implement hash {l}{n}{lo} (data, data_len, out) = let
  val h = $A.alloc<int>(8)
  val () = _wi(h, 0, 1779033703, 8)
  val () = _wi(h, 1, $AR.sub_int_int(0, 1150833019), 8)
  val () = _wi(h, 2, 1013904242, 8)
  val () = _wi(h, 3, $AR.sub_int_int(0, 1521486534), 8)
  val () = _wi(h, 4, 1359893119, 8)
  val () = _wi(h, 5, $AR.sub_int_int(0, 1694144372), 8)
  val () = _wi(h, 6, 528734635, 8)
  val () = _wi(h, 7, 1541459225, 8)

  val w = $A.alloc<int>(64)

  fun proc_blocks {ld:agz}{nd:pos}{lw:agz}{lh:agz}{bo:nat | bo <= nd} .<nd - bo>.
    (data: !$A.arr(byte, ld, nd), dcap: int nd,
     w: !$A.arr(int, lw, 64), h: !$A.arr(int, lh, 8),
     boff: int(bo)): [td:nat | td <= nd; td + 64 > nd] int(td) =
    if $AR.gt_g1($AR.add_g1(boff, 64), dcap) then boff
    else let
      val () = _sha256_compress(data, dcap, boff, w, h)
    in proc_blocks(data, dcap, w, h, $AR.add_g1(boff, 64)) end

  val total_done = proc_blocks(data, data_len, w, h, 0)
  val tail_len = $AR.sub_g1(data_len, total_done)
  val pbuf = $A.alloc<byte>(128)

  fun zero_pb {lp:agz}{k:nat | k <= 128} .<128-k>.
    (pb: !$A.arr(byte, lp, 128), i: int(k)): void =
    if $AR.gte_g1(i, 128) then ()
    else let
      val () = $A.set<byte>(pb, i, $A.int2byte(0))
    in zero_pb(pb, $AR.add_g1(i, 1)) end
  val () = zero_pb(pbuf, 0)

  fun copy_tail {ld:agz}{nd:pos}{lp:agz}{base:nat}{k:nat}{nn:nat | k <= nn; nn < 64; base + nn <= nd} .<nn-k>.
    (data: !$A.arr(byte, ld, nd), pb: !$A.arr(byte, lp, 128),
     i: int(k), n: int(nn), dbase: int(base), dcap: int nd): void =
    if $AR.gte_g1(i, n) then ()
    else let
      val doff = $AR.add_g1(dbase, i)
      val () = $A.set<byte>(pb, i, $A.get<byte>(data, doff))
    in copy_tail(data, pb, $AR.add_g1(i, 1), n, dbase, dcap) end

  val () = copy_tail(data, pbuf, 0, tail_len, total_done, data_len)

  val () = $A.set<byte>(pbuf, tail_len, $A.int2byte(128))

  val need_two = $AR.gt_int_int(tail_len + 9, 64)
  val high_bits = _ushr(data_len, 29)
  val low_bits = _mask32($AR.bsl_int_int(data_len, 3))

  fn _wb_len {lp:agz}{p:nat | p + 8 <= 128}
    (pb: !$A.arr(byte, lp, 128), pos: int(p), hi: int, lo: int): void = let
    val () = $A.set<byte>(pb, pos, $A.int2byte(_g1_byte($AR.band_int_int(_ushr(hi, 24), 255))))
    val () = $A.set<byte>(pb, $AR.add_g1(pos, 1), $A.int2byte(_g1_byte($AR.band_int_int(_ushr(hi, 16), 255))))
    val () = $A.set<byte>(pb, $AR.add_g1(pos, 2), $A.int2byte(_g1_byte($AR.band_int_int(_ushr(hi, 8), 255))))
    val () = $A.set<byte>(pb, $AR.add_g1(pos, 3), $A.int2byte(_g1_byte($AR.band_int_int(hi, 255))))
    val () = $A.set<byte>(pb, $AR.add_g1(pos, 4), $A.int2byte(_g1_byte($AR.band_int_int(_ushr(lo, 24), 255))))
    val () = $A.set<byte>(pb, $AR.add_g1(pos, 5), $A.int2byte(_g1_byte($AR.band_int_int(_ushr(lo, 16), 255))))
    val () = $A.set<byte>(pb, $AR.add_g1(pos, 6), $A.int2byte(_g1_byte($AR.band_int_int(_ushr(lo, 8), 255))))
    val () = $A.set<byte>(pb, $AR.add_g1(pos, 7), $A.int2byte(_g1_byte($AR.band_int_int(lo, 255))))
  in end

  fn _write_bit_len {lp:agz}
    (pb: !$A.arr(byte, lp, 128), two: bool, hi: int, lo: int): void =
    if two then _wb_len(pb, 120, hi, lo)
    else _wb_len(pb, 56, hi, lo)
  val () = _write_bit_len(pbuf, need_two, high_bits, low_bits)

  fn _do_proc_pad {lp:agz}{lw:agz}{lh:agz}
    (pb: !$A.arr(byte, lp, 128), ww: !$A.arr(int, lw, 64),
     hh: !$A.arr(int, lh, 8), two: bool): void = let
    val () = _sha256_compress(pb, 128, 0, ww, hh)
    val () = if two then _sha256_compress(pb, 128, 64, ww, hh) else ()
  in end
  val () = _do_proc_pad(pbuf, w, h, need_two)

  fn _do_write_hex {lo:agz}{lh:agz}
    (out: !$A.arr(byte, lo, 64), h: !$A.arr(int, lh, 8)): void = let
    fun loop {lo:agz}{lh:agz}{k:nat | k <= 8} .<8-k>.
      (out: !$A.arr(byte, lo, 64), h: !$A.arr(int, lh, 8), i: int(k)): void =
      if $AR.gte_g1(i, 8) then ()
      else let
        val pos = $AR.mul_g1(i, 8)
        val () = _write_hex_word(out, pos, _ai(h, i, 8))
      in loop(out, h, $AR.add_g1(i, 1)) end
  in loop(out, h, 0) end

  val () = _do_write_hex(out, h)

  val () = $A.free<byte>(pbuf)
  val () = $A.free<int>(w)
  val () = $A.free<int>(h)

in end
