staload "./lib.sats"
staload "array/src/lib.dats"
staload "arith/src/lib.dats"
(* sha256 -- pure ATS2 SHA-256 implementation *)
(* No C code, no $UNSAFE. 32-bit words are uint: C unsigned arithmetic
   wraps modulo 2^32 by definition, so no operation overflows (signed
   int arithmetic would). Assumes a 32-bit unsigned int, as on every
   bats target (LP64 and ILP32 native, wasm32). *)

#include "share/atspre_staload.hats"

staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"

(* ============================================================
   Public API
   ============================================================ *)

(* The SHA-256 of data[0, data_len) as 64 lowercase hex digits in out. *)





(* ============================================================
   Word functions (FIPS 180-4, section 4.1.2)
   ============================================================ *)

fn _rotr {k:int | 0 < k; k < 32} (x: uint, k: int k): uint =
  (x >> k) lor (x << (32 - k))

fn _ch (x: uint, y: uint, z: uint): uint = (x land y) lxor ((lnot x) land z)

fn _maj (x: uint, y: uint, z: uint): uint =
  (x land y) lxor (x land z) lxor (y land z)

fn _bsig0 (x: uint): uint = _rotr(x, 2) lxor _rotr(x, 13) lxor _rotr(x, 22)
fn _bsig1 (x: uint): uint = _rotr(x, 6) lxor _rotr(x, 11) lxor _rotr(x, 25)
fn _ssig0 (x: uint): uint = _rotr(x, 7) lxor _rotr(x, 18) lxor (x >> 3)
fn _ssig1 (x: uint): uint = _rotr(x, 17) lxor _rotr(x, 19) lxor (x >> 10)

fn _u (x: int): uint = g0int2uint_int_uint(x)

(* ============================================================
   Round constants (FIPS 180-4, section 4.2.2)
   ============================================================ *)

fn _k {i:nat | i < 64} (i: int i): uint =
  if i < 8 then
    (if i = 0 then 0x428a2f98u else if i = 1 then 0x71374491u
     else if i = 2 then 0xb5c0fbcfu else if i = 3 then 0xe9b5dba5u
     else if i = 4 then 0x3956c25bu else if i = 5 then 0x59f111f1u
     else if i = 6 then 0x923f82a4u else 0xab1c5ed5u)
  else if i < 16 then
    (if i = 8 then 0xd807aa98u else if i = 9 then 0x12835b01u
     else if i = 10 then 0x243185beu else if i = 11 then 0x550c7dc3u
     else if i = 12 then 0x72be5d74u else if i = 13 then 0x80deb1feu
     else if i = 14 then 0x9bdc06a7u else 0xc19bf174u)
  else if i < 24 then
    (if i = 16 then 0xe49b69c1u else if i = 17 then 0xefbe4786u
     else if i = 18 then 0x0fc19dc6u else if i = 19 then 0x240ca1ccu
     else if i = 20 then 0x2de92c6fu else if i = 21 then 0x4a7484aau
     else if i = 22 then 0x5cb0a9dcu else 0x76f988dau)
  else if i < 32 then
    (if i = 24 then 0x983e5152u else if i = 25 then 0xa831c66du
     else if i = 26 then 0xb00327c8u else if i = 27 then 0xbf597fc7u
     else if i = 28 then 0xc6e00bf3u else if i = 29 then 0xd5a79147u
     else if i = 30 then 0x06ca6351u else 0x14292967u)
  else if i < 40 then
    (if i = 32 then 0x27b70a85u else if i = 33 then 0x2e1b2138u
     else if i = 34 then 0x4d2c6dfcu else if i = 35 then 0x53380d13u
     else if i = 36 then 0x650a7354u else if i = 37 then 0x766a0abbu
     else if i = 38 then 0x81c2c92eu else 0x92722c85u)
  else if i < 48 then
    (if i = 40 then 0xa2bfe8a1u else if i = 41 then 0xa81a664bu
     else if i = 42 then 0xc24b8b70u else if i = 43 then 0xc76c51a3u
     else if i = 44 then 0xd192e819u else if i = 45 then 0xd6990624u
     else if i = 46 then 0xf40e3585u else 0x106aa070u)
  else if i < 56 then
    (if i = 48 then 0x19a4c116u else if i = 49 then 0x1e376c08u
     else if i = 50 then 0x2748774cu else if i = 51 then 0x34b0bcb5u
     else if i = 52 then 0x391c0cb3u else if i = 53 then 0x4ed8aa4au
     else if i = 54 then 0x5b9cca4fu else 0x682e6ff3u)
  else
    (if i = 56 then 0x748f82eeu else if i = 57 then 0x78a5636fu
     else if i = 58 then 0x84c87814u else if i = 59 then 0x8cc70208u
     else if i = 60 then 0x90befffau else if i = 61 then 0xa4506cebu
     else if i = 62 then 0xbef9a3f7u else 0xc67178f2u)

(* ============================================================
   Block compression (FIPS 180-4, section 6.2.2)
   ============================================================ *)

(* Processes data[bo, bo + 64) into h, using w as the message schedule. *)
fn _compress {ld:agz}{nd:pos}{bo:nat | bo + 64 <= nd}{lw:agz}{lh:agz}
  (data: !$A.arr(byte, ld, nd), bo: int bo,
   w: !$A.arr(uint, lw, 64), h: !$A.arr(uint, lh, 8)): void = let
  fun load {t:nat | t <= 16} .<16 - t>.
    (data: !$A.arr(byte, ld, nd), w: !$A.arr(uint, lw, 64), t: int t): void =
    if t >= 16 then ()
    else let
      val o = bo + 4 * t
      val b0 = _u(byte2int0($A.get<byte>(data, o)))
      val b1 = _u(byte2int0($A.get<byte>(data, o + 1)))
      val b2 = _u(byte2int0($A.get<byte>(data, o + 2)))
      val b3 = _u(byte2int0($A.get<byte>(data, o + 3)))
      val () = $A.set<uint>(w, t, (b0 << 24) lor (b1 << 16) lor (b2 << 8) lor b3)
    in load(data, w, t + 1) end
  fun expand {t:int | 16 <= t; t <= 64} .<64 - t>.
    (w: !$A.arr(uint, lw, 64), t: int t): void =
    if t >= 64 then ()
    else let
      val v = _ssig1($A.get<uint>(w, t - 2)) + $A.get<uint>(w, t - 7)
            + _ssig0($A.get<uint>(w, t - 15)) + $A.get<uint>(w, t - 16)
      val () = $A.set<uint>(w, t, v)
    in expand(w, t + 1) end
  fun rounds {t:nat | t <= 64} .<64 - t>.
    (w: !$A.arr(uint, lw, 64), t: int t,
     a: uint, b: uint, c: uint, d: uint,
     e: uint, f: uint, g: uint, hh: uint): @(uint, uint, uint, uint, uint, uint, uint, uint) =
    if t >= 64 then @(a, b, c, d, e, f, g, hh)
    else let
      val t1 = hh + _bsig1(e) + _ch(e, f, g) + _k(t) + $A.get<uint>(w, t)
      val t2 = _bsig0(a) + _maj(a, b, c)
    in rounds(w, t + 1, t1 + t2, a, b, c, d + t1, e, f, g) end
  val () = load(data, w, 0)
  val () = expand(w, 16)
  val h0 = $A.get<uint>(h, 0) val h1 = $A.get<uint>(h, 1)
  val h2 = $A.get<uint>(h, 2) val h3 = $A.get<uint>(h, 3)
  val h4 = $A.get<uint>(h, 4) val h5 = $A.get<uint>(h, 5)
  val h6 = $A.get<uint>(h, 6) val h7 = $A.get<uint>(h, 7)
  val @(a, b, c, d, e, f, g, hh) = rounds(w, 0, h0, h1, h2, h3, h4, h5, h6, h7)
  val () = $A.set<uint>(h, 0, h0 + a) val () = $A.set<uint>(h, 1, h1 + b)
  val () = $A.set<uint>(h, 2, h2 + c) val () = $A.set<uint>(h, 3, h3 + d)
  val () = $A.set<uint>(h, 4, h4 + e) val () = $A.set<uint>(h, 5, h5 + f)
  val () = $A.set<uint>(h, 6, h6 + g) val () = $A.set<uint>(h, 7, h7 + hh)
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
   Main hash
   ============================================================ *)

implement hash {l}{n}{lo} (data, data_len, out) = let
  val h = $A.alloc<uint>(8)
  val () = $A.set<uint>(h, 0, 0x6a09e667u)
  val () = $A.set<uint>(h, 1, 0xbb67ae85u)
  val () = $A.set<uint>(h, 2, 0x3c6ef372u)
  val () = $A.set<uint>(h, 3, 0xa54ff53au)
  val () = $A.set<uint>(h, 4, 0x510e527fu)
  val () = $A.set<uint>(h, 5, 0x9b05688cu)
  val () = $A.set<uint>(h, 6, 0x1f83d9abu)
  val () = $A.set<uint>(h, 7, 0x5be0cd19u)
  val w = $A.alloc<uint>(64)
  (* Whole blocks; returns where the last partial block starts. *)
  fun blocks {lw,lh:agz}{bo:nat | bo <= n} .<n - bo>.
    (data: !$A.arr(byte, l, n), w: !$A.arr(uint, lw, 64), h: !$A.arr(uint, lh, 8),
     bo: int bo): [td:nat | td <= n; n < td + 64] int td =
    if bo + 64 > data_len then bo
    else let val () = _compress(data, bo, w, h) in blocks(data, w, h, bo + 64) end
  val td = blocks(data, w, h, 0)
  val tail = data_len - td
  (* The tail, 0x80, zeros and the 64-bit big-endian bit length, in one
     or two blocks. alloc zeroes the buffer. *)
  val pad = $A.alloc<byte>(128)
  fun copy {lp:agz}{b,t:nat | b + t <= n; t < 64}{i:nat | i <= t} .<t - i>.
    (data: !$A.arr(byte, l, n), pad: !$A.arr(byte, lp, 128),
     b: int b, t: int t, i: int i): void =
    if i >= t then ()
    else let
      val () = $A.set<byte>(pad, i, $A.get<byte>(data, b + i))
    in copy(data, pad, b, t, i + 1) end
  val () = copy(data, pad, td, tail, 0)
  val () = $A.set<byte>(pad, tail, $A.int2byte(128))
  val last = (if tail + 9 > 64 then 128 else 64): [e:int | e == 64 || e == 128] int e
  val nu = _u(data_len)
  val hi = nu >> 29
  val lo = nu << 3
  val () = $A.set<byte>(pad, last - 8, $A.int2byte(_byte(hi >> 24)))
  val () = $A.set<byte>(pad, last - 7, $A.int2byte(_byte(hi >> 16)))
  val () = $A.set<byte>(pad, last - 6, $A.int2byte(_byte(hi >> 8)))
  val () = $A.set<byte>(pad, last - 5, $A.int2byte(_byte(hi)))
  val () = $A.set<byte>(pad, last - 4, $A.int2byte(_byte(lo >> 24)))
  val () = $A.set<byte>(pad, last - 3, $A.int2byte(_byte(lo >> 16)))
  val () = $A.set<byte>(pad, last - 2, $A.int2byte(_byte(lo >> 8)))
  val () = $A.set<byte>(pad, last - 1, $A.int2byte(_byte(lo)))
  val () = _compress_pad(pad, last, w, h)
  fun put {lh:agz}{j:nat | j <= 8} .<8 - j>.
    (out: !$A.arr(byte, lo, 64), h: !$A.arr(uint, lh, 8), j: int j): void =
    if j >= 8 then ()
    else let val () = _put_word(out, 8 * j, $A.get<uint>(h, j)) in put(out, h, j + 1) end
  val () = put(out, h, 0)
  val () = $A.free<byte>(pad)
  val () = $A.free<uint>(w)
  val () = $A.free<uint>(h)
in end
