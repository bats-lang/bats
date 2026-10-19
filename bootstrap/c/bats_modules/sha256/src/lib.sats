staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"






















fn hash
  {l:agz}{n:pos}{lo:agz}
  (data: !$A.arr(byte, l, n), data_len: int n,
   out: !$A.arr(byte, lo, 64)): void




datavtype ctx =
  | {lh,lw,lb:agz}{b:nat | b < 64} ctx_mk of (
      $A.arr(uint, lh, 8),   (* the hash state *)
      $A.arr(uint, lw, 64),  (* the message schedule *)
      $A.arr(byte, lb, 64),  (* the bytes of the block being filled *)
      int b,                 (* how many of them there are *)
      uint, uint             (* the bytes hashed so far, high and low words *)
    )

fn init (): ctx


fn update
  {l:agz}{n:pos}{k:nat | k <= n}
  (c: !ctx, data: !$A.arr(byte, l, n), len: int k): void


fn finish {lo:agz} (c: ctx, out: !$A.arr(byte, lo, 64)): void




















































dataprop CH(int, int, int, int, int, int, int, int) =
  | {xh,xl,yh,yl,zh,zl,ah,al,nh,nl,bh,bl,rh,rl:nat}
    CH_mk(xh, xl, yh, yl, zh, zl, rh, rl) of (
      $AR.AND(xh, yh, ah), $AR.AND(xl, yl, al),
      $AR.NOT32(xh, xl, nh, nl),
      $AR.AND(nh, zh, bh), $AR.AND(nl, zl, bl),
      $AR.XOR(ah, bh, rh), $AR.XOR(al, bl, rl))



dataprop MAJ(int, int, int, int, int, int, int, int) =
  | {xh,xl,yh,yl,zh,zl,ah,al,bh,bl,ch,cl,sh,sl,rh,rl:nat}
    MAJ_mk(xh, xl, yh, yl, zh, zl, rh, rl) of (
      $AR.AND(xh, yh, ah), $AR.AND(xl, yl, al),
      $AR.AND(xh, zh, bh), $AR.AND(xl, zl, bl),
      $AR.AND(yh, zh, ch), $AR.AND(yl, zl, cl),
      $AR.XOR(ah, bh, sh), $AR.XOR(al, bl, sl),
      $AR.XOR(sh, ch, rh), $AR.XOR(sl, cl, rl))



dataprop BIG_SIGMA_0(int, int, int, int) =
  | {xh,xl,ah,al,bh,bl,ch,cl,sh,sl,rh,rl:nat}
    BIG_SIGMA_0_mk(xh, xl, rh, rl) of (
      $AR.ROTR(2, xh, xl, ah, al), $AR.ROTR(13, xh, xl, bh, bl), $AR.ROTR(22, xh, xl, ch, cl),
      $AR.XOR(ah, bh, sh), $AR.XOR(al, bl, sl),
      $AR.XOR(sh, ch, rh), $AR.XOR(sl, cl, rl))

dataprop BIG_SIGMA_1(int, int, int, int) =
  | {xh,xl,ah,al,bh,bl,ch,cl,sh,sl,rh,rl:nat}
    BIG_SIGMA_1_mk(xh, xl, rh, rl) of (
      $AR.ROTR(6, xh, xl, ah, al), $AR.ROTR(11, xh, xl, bh, bl), $AR.ROTR(25, xh, xl, ch, cl),
      $AR.XOR(ah, bh, sh), $AR.XOR(al, bl, sl),
      $AR.XOR(sh, ch, rh), $AR.XOR(sl, cl, rl))



dataprop SMALL_SIGMA_0(int, int, int, int) =
  | {xh,xl,ah,al,bh,bl,ch,cl,sh,sl,rh,rl:nat}
    SMALL_SIGMA_0_mk(xh, xl, rh, rl) of (
      $AR.ROTR(7, xh, xl, ah, al), $AR.ROTR(18, xh, xl, bh, bl), $AR.SHR(3, xh, xl, ch, cl),
      $AR.XOR(ah, bh, sh), $AR.XOR(al, bl, sl),
      $AR.XOR(sh, ch, rh), $AR.XOR(sl, cl, rl))

dataprop SMALL_SIGMA_1(int, int, int, int) =
  | {xh,xl,ah,al,bh,bl,ch,cl,sh,sl,rh,rl:nat}
    SMALL_SIGMA_1_mk(xh, xl, rh, rl) of (
      $AR.ROTR(17, xh, xl, ah, al), $AR.ROTR(19, xh, xl, bh, bl), $AR.SHR(10, xh, xl, ch, cl),
      $AR.XOR(ah, bh, sh), $AR.XOR(al, bl, sl),
      $AR.XOR(sh, ch, rh), $AR.XOR(sl, cl, rl))

fun word_ch {xh,xl,yh,yl,zh,zl:nat | xh < 65536; xl < 65536; yh < 65536; yl < 65536; zh < 65536; zl < 65536}
  (xh: int xh, xl: int xl, yh: int yh, yl: int yl, zh: int zh, zl: int zl)
  : [rh,rl:nat | rh < 65536; rl < 65536] (CH(xh, xl, yh, yl, zh, zl, rh, rl) | @(int rh, int rl))








fun word_maj {xh,xl,yh,yl,zh,zl:nat | xh < 65536; xl < 65536; yh < 65536; yl < 65536; zh < 65536; zl < 65536}
  (xh: int xh, xl: int xl, yh: int yh, yl: int yl, zh: int zh, zl: int zl)
  : [rh,rl:nat | rh < 65536; rl < 65536] (MAJ(xh, xl, yh, yl, zh, zl, rh, rl) | @(int rh, int rl))









fun big_sigma_0 {xh,xl:nat | xh < 65536; xl < 65536} (xh: int xh, xl: int xl)
  : [rh,rl:nat | rh < 65536; rl < 65536] (BIG_SIGMA_0(xh, xl, rh, rl) | @(int rh, int rl))









fun big_sigma_1 {xh,xl:nat | xh < 65536; xl < 65536} (xh: int xh, xl: int xl)
  : [rh,rl:nat | rh < 65536; rl < 65536] (BIG_SIGMA_1(xh, xl, rh, rl) | @(int rh, int rl))









fun small_sigma_0 {xh,xl:nat | xh < 65536; xl < 65536} (xh: int xh, xl: int xl)
  : [rh,rl:nat | rh < 65536; rl < 65536] (SMALL_SIGMA_0(xh, xl, rh, rl) | @(int rh, int rl))









fun small_sigma_1 {xh,xl:nat | xh < 65536; xl < 65536} (xh: int xh, xl: int xl)
  : [rh,rl:nat | rh < 65536; rl < 65536] (SMALL_SIGMA_1(xh, xl, rh, rl) | @(int rh, int rl))
























dataprop WORD_AT($A.cells, int, int, int) =
  | {cs:$A.cells}{at,b0,b1,b2,b3:nat | b0 < 256; b1 < 256; b2 < 256; b3 < 256}
    WORD_AT_mk(cs, at, 256*b0 + b1, 256*b2 + b3) of (
      $A.NTH(cs, at, b0), $A.NTH(cs, at + 1, b1),
      $A.NTH(cs, at + 2, b2), $A.NTH(cs, at + 3, b3))



dataprop WORD_SET($A.cells, int, int, int, $A.cells) =
  | {cs,cs1,cs2,cs3,cs4:$A.cells}{at,b0,b1,b2,b3:nat | b0 < 256; b1 < 256; b2 < 256; b3 < 256}
    WORD_SET_mk(cs, at, 256*b0 + b1, 256*b2 + b3, cs4) of (
      $A.SETC(cs, at, b0, cs1), $A.SETC(cs1, at + 1, b1, cs2),
      $A.SETC(cs2, at + 2, b2, cs3), $A.SETC(cs3, at + 3, b3, cs4))


fun word_get {l:agz}{n,at:nat | at + 3 < n}{cs:$A.cells}
  (cells: !$A.barr(l, n, cs), at: int at)
  : [high,low:nat | high < 65536; low < 65536] (WORD_AT(cs, at, high, low) | @(int high, int low))









fun word_set {l:agz}{n,at:nat | at + 3 < n}{cs:$A.cells}{high,low:nat | high < 65536; low < 65536}
  (cells: $A.barr(l, n, cs), at: int at, high: int high, low: int low)
  : [cs2:$A.cells] (WORD_SET(cs, at, high, low, cs2) | $A.barr(l, n, cs2))













prfun word_set_at {cs,cs2:$A.cells}{at,high,low:nat}
  (WORD_SET(cs, at, high, low, cs2)): WORD_AT(cs2, at, high, low)










prfun word_set_other {cs,cs2:$A.cells}{at,high,low,other,other_high,other_low:nat | at + 4 <= other || other + 4 <= at}
  (WORD_SET(cs, at, high, low, cs2), WORD_AT(cs, other, other_high, other_low))
  : WORD_AT(cs2, other, other_high, other_low)












prfun word_at_functional {cs:$A.cells}{at,high,low,high2,low2:nat}
  (WORD_AT(cs, at, high, low), WORD_AT(cs, at, high2, low2)): [high == high2; low == low2] void























datasort schedule_kind =
  | sha256_kind of ()
  | sha1_kind of ()

dataprop SCHEDULE(schedule_kind, $A.cells, int, int, int, int) =
  | {kind:schedule_kind}{msg:$A.cells}{at,t:nat | t < 16}{high,low:nat}
    SCHEDULE_message(kind, msg, at, t, high, low) of WORD_AT(msg, at + 4*t, high, low)
  | {msg:$A.cells}{at,t:nat | 16 <= t}
    {back2_high,back2_low,back7_high,back7_low,back15_high,back15_low,back16_high,back16_low:nat}
    {s1_high,s1_low,s0_high,s0_low,sum1_high,sum1_low,sum2_high,sum2_low,high,low:nat}
    SCHEDULE_sha256(sha256_kind(), msg, at, t, high, low) of (
      SCHEDULE(sha256_kind(), msg, at, t-2, back2_high, back2_low),
      SCHEDULE(sha256_kind(), msg, at, t-7, back7_high, back7_low),
      SCHEDULE(sha256_kind(), msg, at, t-15, back15_high, back15_low),
      SCHEDULE(sha256_kind(), msg, at, t-16, back16_high, back16_low),
      SMALL_SIGMA_1(back2_high, back2_low, s1_high, s1_low),
      SMALL_SIGMA_0(back15_high, back15_low, s0_high, s0_low),
      $AR.ADD32(s1_high, s1_low, back7_high, back7_low, sum1_high, sum1_low),
      $AR.ADD32(sum1_high, sum1_low, s0_high, s0_low, sum2_high, sum2_low),
      $AR.ADD32(sum2_high, sum2_low, back16_high, back16_low, high, low))
  | {msg:$A.cells}{at,t:nat | 16 <= t}
    {back3_high,back3_low,back8_high,back8_low,back14_high,back14_low,back16_high,back16_low:nat}
    {x1_high,x1_low,x2_high,x2_low,x3_high,x3_low,high,low:nat}
    SCHEDULE_sha1(sha1_kind(), msg, at, t, high, low) of (
      SCHEDULE(sha1_kind(), msg, at, t-3, back3_high, back3_low),
      SCHEDULE(sha1_kind(), msg, at, t-8, back8_high, back8_low),
      SCHEDULE(sha1_kind(), msg, at, t-14, back14_high, back14_low),
      SCHEDULE(sha1_kind(), msg, at, t-16, back16_high, back16_low),
      $AR.XOR(back3_high, back8_high, x1_high), $AR.XOR(back3_low, back8_low, x1_low),
      $AR.XOR(x1_high, back14_high, x2_high), $AR.XOR(x1_low, back14_low, x2_low),
      $AR.XOR(x2_high, back16_high, x3_high), $AR.XOR(x2_low, back16_low, x3_low),
      $AR.ROTR(31, x3_high, x3_low, high, low))




dataprop SCHEDULE_ARRAY(schedule_kind, $A.cells, $A.cells, int, int) =
  | {kind:schedule_kind}{words,msg:$A.cells}{at:nat}
    SCHEDULE_ARRAY_nil(kind, words, msg, at, 0)
  | {kind:schedule_kind}{words,msg:$A.cells}{at,count:nat}{high,low:nat}
    SCHEDULE_ARRAY_cons(kind, words, msg, at, count + 1) of (
      SCHEDULE_ARRAY(kind, words, msg, at, count),
      WORD_AT(words, 4*count, high, low),
      SCHEDULE(kind, msg, at, count, high, low))



prfun schedule_array_get {kind:schedule_kind}{words,msg:$A.cells}{at,count,i:nat | i < count}
  (SCHEDULE_ARRAY(kind, words, msg, at, count))
  : [high,low:nat] (WORD_AT(words, 4*i, high, low), SCHEDULE(kind, msg, at, i, high, low))








prfun schedule_array_frame {kind:schedule_kind}{words,words2,msg:$A.cells}{at,count,set_at,high,low:nat | 4*count <= set_at}
  (WORD_SET(words, set_at, high, low, words2), SCHEDULE_ARRAY(kind, words, msg, at, count))
  : SCHEDULE_ARRAY(kind, words2, msg, at, count)













































































fun schedule_sha256 {lm:agz}{nm:nat}{msg:$A.cells}{at:nat | at + 64 <= nm}{lw:agz}{words:$A.cells}
  (message: !$A.barr(lm, nm, msg), at: int at, array: $A.barr(lw, 256, words))
  : [words2:$A.cells] (SCHEDULE_ARRAY(sha256_kind(), words2, msg, at, 64) | $A.barr(lw, 256, words2))






fun schedule_sha1 {lm:agz}{nm:nat}{msg:$A.cells}{at:nat | at + 64 <= nm}{lw:agz}{words:$A.cells}
  (message: !$A.barr(lm, nm, msg), at: int at, array: $A.barr(lw, 320, words))
  : [words2:$A.cells] (SCHEDULE_ARRAY(sha1_kind(), words2, msg, at, 80) | $A.barr(lw, 320, words2))



















datasort word = | w32 of (int, int)

datasort eight_words =
  | eight of (word, word, word, word, word, word, word, word)

datasort five_words = | five of (word, word, word, word, word)




dataprop EIGHT_AT($A.cells, int, eight_words) =
  | {cs:$A.cells}{at:nat}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low,h5_high,h5_low,h6_high,h6_low,h7_high,h7_low:nat}
    EIGHT_AT_mk(cs, at, eight(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low), w32(h5_high, h5_low), w32(h6_high, h6_low), w32(h7_high, h7_low))) of (
      WORD_AT(cs, at + 0, h0_high, h0_low),
      WORD_AT(cs, at + 4, h1_high, h1_low),
      WORD_AT(cs, at + 8, h2_high, h2_low),
      WORD_AT(cs, at + 12, h3_high, h3_low),
      WORD_AT(cs, at + 16, h4_high, h4_low),
      WORD_AT(cs, at + 20, h5_high, h5_low),
      WORD_AT(cs, at + 24, h6_high, h6_low),
      WORD_AT(cs, at + 28, h7_high, h7_low))

dataprop FIVE_AT($A.cells, int, five_words) =
  | {cs:$A.cells}{at:nat}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low:nat}
    FIVE_AT_mk(cs, at, five(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low))) of (
      WORD_AT(cs, at + 0, h0_high, h0_low),
      WORD_AT(cs, at + 4, h1_high, h1_low),
      WORD_AT(cs, at + 8, h2_high, h2_low),
      WORD_AT(cs, at + 12, h3_high, h3_low),
      WORD_AT(cs, at + 16, h4_high, h4_low))



fun eight_get {lc:agz}{n,at:nat | at + 31 < n}{cs:$A.cells}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low,h5_high,h5_low,h6_high,h6_low,h7_high,h7_low:nat | h0_high < 65536; h0_low < 65536; h1_high < 65536; h1_low < 65536; h2_high < 65536; h2_low < 65536; h3_high < 65536; h3_low < 65536; h4_high < 65536; h4_low < 65536; h5_high < 65536; h5_low < 65536; h6_high < 65536; h6_low < 65536; h7_high < 65536; h7_low < 65536}
  (cells: !$A.barr(lc, n, cs), at: int at,
   have: EIGHT_AT(cs, at, eight(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low), w32(h5_high, h5_low), w32(h6_high, h6_low), w32(h7_high, h7_low))))
  : @(int h0_high, int h0_low, int h1_high, int h1_low, int h2_high, int h2_low, int h3_high, int h3_low, int h4_high, int h4_low, int h5_high, int h5_low, int h6_high, int h6_low, int h7_high, int h7_low)






















fun eight_set {lc:agz}{n,at:nat | at + 31 < n}{cs:$A.cells}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low,h5_high,h5_low,h6_high,h6_low,h7_high,h7_low:nat | h0_high < 65536; h0_low < 65536; h1_high < 65536; h1_low < 65536; h2_high < 65536; h2_low < 65536; h3_high < 65536; h3_low < 65536; h4_high < 65536; h4_low < 65536; h5_high < 65536; h5_low < 65536; h6_high < 65536; h6_low < 65536; h7_high < 65536; h7_low < 65536}
  (cells: $A.barr(lc, n, cs), at: int at, h0_high: int h0_high, h0_low: int h0_low, h1_high: int h1_high, h1_low: int h1_low, h2_high: int h2_high, h2_low: int h2_low, h3_high: int h3_high, h3_low: int h3_low, h4_high: int h4_high, h4_low: int h4_low, h5_high: int h5_high, h5_low: int h5_low, h6_high: int h6_high, h6_low: int h6_low, h7_high: int h7_high, h7_low: int h7_low)
  : [cs2:$A.cells] (EIGHT_AT(cs2, at, eight(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low), w32(h5_high, h5_low), w32(h6_high, h6_low), w32(h7_high, h7_low))) | $A.barr(lc, n, cs2))






















fun five_get {lc:agz}{n,at:nat | at + 19 < n}{cs:$A.cells}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low:nat | h0_high < 65536; h0_low < 65536; h1_high < 65536; h1_low < 65536; h2_high < 65536; h2_low < 65536; h3_high < 65536; h3_low < 65536; h4_high < 65536; h4_low < 65536}
  (cells: !$A.barr(lc, n, cs), at: int at,
   have: FIVE_AT(cs, at, five(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low))))
  : @(int h0_high, int h0_low, int h1_high, int h1_low, int h2_high, int h2_low, int h3_high, int h3_low, int h4_high, int h4_low)
















fun five_set {lc:agz}{n,at:nat | at + 19 < n}{cs:$A.cells}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low:nat | h0_high < 65536; h0_low < 65536; h1_high < 65536; h1_low < 65536; h2_high < 65536; h2_low < 65536; h3_high < 65536; h3_low < 65536; h4_high < 65536; h4_low < 65536}
  (cells: $A.barr(lc, n, cs), at: int at, h0_high: int h0_high, h0_low: int h0_low, h1_high: int h1_high, h1_low: int h1_low, h2_high: int h2_high, h2_low: int h2_low, h3_high: int h3_high, h3_low: int h3_low, h4_high: int h4_high, h4_low: int h4_low)
  : [cs2:$A.cells] (FIVE_AT(cs2, at, five(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low))) | $A.barr(lc, n, cs2))
























dataprop SHA256_K(int, int, int) =
  | SHA256_K_0(0, 0x428a, 0x2f98)
  | SHA256_K_1(1, 0x7137, 0x4491)
  | SHA256_K_2(2, 0xb5c0, 0xfbcf)
  | SHA256_K_3(3, 0xe9b5, 0xdba5)
  | SHA256_K_4(4, 0x3956, 0xc25b)
  | SHA256_K_5(5, 0x59f1, 0x11f1)
  | SHA256_K_6(6, 0x923f, 0x82a4)
  | SHA256_K_7(7, 0xab1c, 0x5ed5)
  | SHA256_K_8(8, 0xd807, 0xaa98)
  | SHA256_K_9(9, 0x1283, 0x5b01)
  | SHA256_K_10(10, 0x2431, 0x85be)
  | SHA256_K_11(11, 0x550c, 0x7dc3)
  | SHA256_K_12(12, 0x72be, 0x5d74)
  | SHA256_K_13(13, 0x80de, 0xb1fe)
  | SHA256_K_14(14, 0x9bdc, 0x06a7)
  | SHA256_K_15(15, 0xc19b, 0xf174)
  | SHA256_K_16(16, 0xe49b, 0x69c1)
  | SHA256_K_17(17, 0xefbe, 0x4786)
  | SHA256_K_18(18, 0x0fc1, 0x9dc6)
  | SHA256_K_19(19, 0x240c, 0xa1cc)
  | SHA256_K_20(20, 0x2de9, 0x2c6f)
  | SHA256_K_21(21, 0x4a74, 0x84aa)
  | SHA256_K_22(22, 0x5cb0, 0xa9dc)
  | SHA256_K_23(23, 0x76f9, 0x88da)
  | SHA256_K_24(24, 0x983e, 0x5152)
  | SHA256_K_25(25, 0xa831, 0xc66d)
  | SHA256_K_26(26, 0xb003, 0x27c8)
  | SHA256_K_27(27, 0xbf59, 0x7fc7)
  | SHA256_K_28(28, 0xc6e0, 0x0bf3)
  | SHA256_K_29(29, 0xd5a7, 0x9147)
  | SHA256_K_30(30, 0x06ca, 0x6351)
  | SHA256_K_31(31, 0x1429, 0x2967)
  | SHA256_K_32(32, 0x27b7, 0x0a85)
  | SHA256_K_33(33, 0x2e1b, 0x2138)
  | SHA256_K_34(34, 0x4d2c, 0x6dfc)
  | SHA256_K_35(35, 0x5338, 0x0d13)
  | SHA256_K_36(36, 0x650a, 0x7354)
  | SHA256_K_37(37, 0x766a, 0x0abb)
  | SHA256_K_38(38, 0x81c2, 0xc92e)
  | SHA256_K_39(39, 0x9272, 0x2c85)
  | SHA256_K_40(40, 0xa2bf, 0xe8a1)
  | SHA256_K_41(41, 0xa81a, 0x664b)
  | SHA256_K_42(42, 0xc24b, 0x8b70)
  | SHA256_K_43(43, 0xc76c, 0x51a3)
  | SHA256_K_44(44, 0xd192, 0xe819)
  | SHA256_K_45(45, 0xd699, 0x0624)
  | SHA256_K_46(46, 0xf40e, 0x3585)
  | SHA256_K_47(47, 0x106a, 0xa070)
  | SHA256_K_48(48, 0x19a4, 0xc116)
  | SHA256_K_49(49, 0x1e37, 0x6c08)
  | SHA256_K_50(50, 0x2748, 0x774c)
  | SHA256_K_51(51, 0x34b0, 0xbcb5)
  | SHA256_K_52(52, 0x391c, 0x0cb3)
  | SHA256_K_53(53, 0x4ed8, 0xaa4a)
  | SHA256_K_54(54, 0x5b9c, 0xca4f)
  | SHA256_K_55(55, 0x682e, 0x6ff3)
  | SHA256_K_56(56, 0x748f, 0x82ee)
  | SHA256_K_57(57, 0x78a5, 0x636f)
  | SHA256_K_58(58, 0x84c8, 0x7814)
  | SHA256_K_59(59, 0x8cc7, 0x0208)
  | SHA256_K_60(60, 0x90be, 0xfffa)
  | SHA256_K_61(61, 0xa450, 0x6ceb)
  | SHA256_K_62(62, 0xbef9, 0xa3f7)
  | SHA256_K_63(63, 0xc671, 0x78f2)


fun sha256_k {t:nat | t < 64} (t: int t)
  : [high,low:nat | high < 65536; low < 65536] (SHA256_K(t, high, low) | @(int high, int low))









































































































































































































dataprop SHA256_ROUND(word, word, word, word, word, word, word, word, word, word, word, word) =
  | {a_high,a_low,b_high,b_low,c_high,c_low,d_high,d_low,e_high,e_low,f_high,f_low,g_high,g_low,h_high,h_low,k_high,k_low,w_high,w_low,big1_high,big1_low,ch_high,ch_low,sum1_high,sum1_low,sum2_high,sum2_low,sum3_high,sum3_low,t1_high,t1_low,big0_high,big0_low,maj_high,maj_low,t2_high,t2_low,new_a_high,new_a_low,new_e_high,new_e_low:nat}
    SHA256_ROUND_mk(w32(a_high, a_low), w32(b_high, b_low), w32(c_high, c_low), w32(d_high, d_low), w32(e_high, e_low), w32(f_high, f_low), w32(g_high, g_low), w32(h_high, h_low), w32(k_high, k_low), w32(w_high, w_low), w32(new_a_high, new_a_low), w32(new_e_high, new_e_low)) of (
      BIG_SIGMA_1(e_high, e_low, big1_high, big1_low),
      CH(e_high, e_low, f_high, f_low, g_high, g_low, ch_high, ch_low),
      $AR.ADD32(h_high, h_low, big1_high, big1_low, sum1_high, sum1_low),
      $AR.ADD32(sum1_high, sum1_low, ch_high, ch_low, sum2_high, sum2_low),
      $AR.ADD32(sum2_high, sum2_low, k_high, k_low, sum3_high, sum3_low),
      $AR.ADD32(sum3_high, sum3_low, w_high, w_low, t1_high, t1_low),
      BIG_SIGMA_0(a_high, a_low, big0_high, big0_low),
      MAJ(a_high, a_low, b_high, b_low, c_high, c_low, maj_high, maj_low),
      $AR.ADD32(big0_high, big0_low, maj_high, maj_low, t2_high, t2_low),
      $AR.ADD32(t1_high, t1_low, t2_high, t2_low, new_a_high, new_a_low),
      $AR.ADD32(d_high, d_low, t1_high, t1_low, new_e_high, new_e_low))


fun sha256_round {a_high,a_low,b_high,b_low,c_high,c_low,d_high,d_low,e_high,e_low,f_high,f_low,g_high,g_low,h_high,h_low,k_high,k_low,w_high,w_low:nat | a_high < 65536; a_low < 65536; b_high < 65536; b_low < 65536; c_high < 65536; c_low < 65536; d_high < 65536; d_low < 65536; e_high < 65536; e_low < 65536; f_high < 65536; f_low < 65536; g_high < 65536; g_low < 65536; h_high < 65536; h_low < 65536; k_high < 65536; k_low < 65536; w_high < 65536; w_low < 65536}
  (a_high: int a_high, a_low: int a_low, b_high: int b_high, b_low: int b_low, c_high: int c_high, c_low: int c_low, d_high: int d_high, d_low: int d_low, e_high: int e_high, e_low: int e_low, f_high: int f_high, f_low: int f_low, g_high: int g_high, g_low: int g_low, h_high: int h_high, h_low: int h_low, k_high: int k_high, k_low: int k_low, w_high: int w_high, w_low: int w_low)
  : [new_a_high,new_a_low,new_e_high,new_e_low:nat | new_a_high < 65536; new_a_low < 65536; new_e_high < 65536; new_e_low < 65536]
    (SHA256_ROUND(w32(a_high, a_low), w32(b_high, b_low), w32(c_high, c_low), w32(d_high, d_low), w32(e_high, e_low), w32(f_high, f_low), w32(g_high, g_low), w32(h_high, h_low), w32(k_high, k_low), w32(w_high, w_low), w32(new_a_high, new_a_low), w32(new_e_high, new_e_low)) | @(int new_a_high, int new_a_low, int new_e_high, int new_e_low))





















dataprop SHA256_ROUNDS($A.cells, int, int, eight_words, eight_words) =
  | {msg:$A.cells}{at:nat}{init:eight_words}
    SHA256_ROUNDS_zero(msg, at, 0, init, init)
  | {msg:$A.cells}{at,t:nat | t < 64}{init:eight_words}
    {a_high,a_low,b_high,b_low,c_high,c_low,d_high,d_low,e_high,e_low,f_high,f_low,g_high,g_low,h_high,h_low,k_high,k_low,w_high,w_low,new_a_high,new_a_low,new_e_high,new_e_low:nat}
    SHA256_ROUNDS_next(msg, at, t+1, init,
      eight(w32(new_a_high, new_a_low), w32(a_high, a_low), w32(b_high, b_low), w32(c_high, c_low),
            w32(new_e_high, new_e_low), w32(e_high, e_low), w32(f_high, f_low), w32(g_high, g_low))) of (
      SHA256_ROUNDS(msg, at, t, init, eight(w32(a_high, a_low), w32(b_high, b_low), w32(c_high, c_low), w32(d_high, d_low), w32(e_high, e_low), w32(f_high, f_low), w32(g_high, g_low), w32(h_high, h_low))),
      SHA256_K(t, k_high, k_low),
      SCHEDULE(sha256_kind(), msg, at, t, w_high, w_low),
      SHA256_ROUND(w32(a_high, a_low), w32(b_high, b_low), w32(c_high, c_low), w32(d_high, d_low), w32(e_high, e_low), w32(f_high, f_low), w32(g_high, g_low), w32(h_high, h_low), w32(k_high, k_low), w32(w_high, w_low), w32(new_a_high, new_a_low), w32(new_e_high, new_e_low)))







dataprop SHA256_BLOCK($A.cells, int, eight_words, eight_words) =
  | {msg:$A.cells}{at:nat}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low,h5_high,h5_low,h6_high,h6_low,h7_high,h7_low,end_a_high,end_a_low,end_b_high,end_b_low,end_c_high,end_c_low,end_d_high,end_d_low,end_e_high,end_e_low,end_f_high,end_f_low,end_g_high,end_g_low,end_h_high,end_h_low,next_h0_high,next_h0_low,next_h1_high,next_h1_low,next_h2_high,next_h2_low,next_h3_high,next_h3_low,next_h4_high,next_h4_low,next_h5_high,next_h5_low,next_h6_high,next_h6_low,next_h7_high,next_h7_low:nat}
    SHA256_BLOCK_mk(msg, at, eight(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low), w32(h5_high, h5_low), w32(h6_high, h6_low), w32(h7_high, h7_low)), eight(w32(next_h0_high, next_h0_low), w32(next_h1_high, next_h1_low), w32(next_h2_high, next_h2_low), w32(next_h3_high, next_h3_low), w32(next_h4_high, next_h4_low), w32(next_h5_high, next_h5_low), w32(next_h6_high, next_h6_low), w32(next_h7_high, next_h7_low))) of (
      SHA256_ROUNDS(msg, at, 64, eight(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low), w32(h5_high, h5_low), w32(h6_high, h6_low), w32(h7_high, h7_low)), eight(w32(end_a_high, end_a_low), w32(end_b_high, end_b_low), w32(end_c_high, end_c_low), w32(end_d_high, end_d_low), w32(end_e_high, end_e_low), w32(end_f_high, end_f_low), w32(end_g_high, end_g_low), w32(end_h_high, end_h_low))),
      $AR.ADD32(h0_high, h0_low, end_a_high, end_a_low, next_h0_high, next_h0_low),
      $AR.ADD32(h1_high, h1_low, end_b_high, end_b_low, next_h1_high, next_h1_low),
      $AR.ADD32(h2_high, h2_low, end_c_high, end_c_low, next_h2_high, next_h2_low),
      $AR.ADD32(h3_high, h3_low, end_d_high, end_d_low, next_h3_high, next_h3_low),
      $AR.ADD32(h4_high, h4_low, end_e_high, end_e_low, next_h4_high, next_h4_low),
      $AR.ADD32(h5_high, h5_low, end_f_high, end_f_low, next_h5_high, next_h5_low),
      $AR.ADD32(h6_high, h6_low, end_g_high, end_g_low, next_h6_high, next_h6_low),
      $AR.ADD32(h7_high, h7_low, end_h_high, end_h_low, next_h7_high, next_h7_low))

























fun sha256_compress {lm:agz}{nm:nat}{msg:$A.cells}{at:nat | at + 64 <= nm}
  {lw:agz}{words:$A.cells}{lc:agz}{chain:$A.cells}
  {h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low,h5_high,h5_low,h6_high,h6_low,h7_high,h7_low:nat | h0_high < 65536; h0_low < 65536; h1_high < 65536; h1_low < 65536; h2_high < 65536; h2_low < 65536; h3_high < 65536; h3_low < 65536; h4_high < 65536; h4_low < 65536; h5_high < 65536; h5_low < 65536; h6_high < 65536; h6_low < 65536; h7_high < 65536; h7_low < 65536}
  (message: !$A.barr(lm, nm, msg), at: int at, schedule: $A.barr(lw, 256, words),
   chaining: $A.barr(lc, 32, chain), have: EIGHT_AT(chain, 0, eight(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low), w32(h5_high, h5_low), w32(h6_high, h6_low), w32(h7_high, h7_low))))
  : [words2:$A.cells][chain2:$A.cells][next_h0_high,next_h0_low,next_h1_high,next_h1_low,next_h2_high,next_h2_low,next_h3_high,next_h3_low,next_h4_high,next_h4_low,next_h5_high,next_h5_low,next_h6_high,next_h6_low,next_h7_high,next_h7_low:nat | next_h0_high < 65536; next_h0_low < 65536; next_h1_high < 65536; next_h1_low < 65536; next_h2_high < 65536; next_h2_low < 65536; next_h3_high < 65536; next_h3_low < 65536; next_h4_high < 65536; next_h4_low < 65536; next_h5_high < 65536; next_h5_low < 65536; next_h6_high < 65536; next_h6_low < 65536; next_h7_high < 65536; next_h7_low < 65536]
    (SHA256_BLOCK(msg, at, eight(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low), w32(h5_high, h5_low), w32(h6_high, h6_low), w32(h7_high, h7_low)), eight(w32(next_h0_high, next_h0_low), w32(next_h1_high, next_h1_low), w32(next_h2_high, next_h2_low), w32(next_h3_high, next_h3_low), w32(next_h4_high, next_h4_low), w32(next_h5_high, next_h5_low), w32(next_h6_high, next_h6_low), w32(next_h7_high, next_h7_low))),
     EIGHT_AT(chain2, 0, eight(w32(next_h0_high, next_h0_low), w32(next_h1_high, next_h1_low), w32(next_h2_high, next_h2_low), w32(next_h3_high, next_h3_low), w32(next_h4_high, next_h4_low), w32(next_h5_high, next_h5_low), w32(next_h6_high, next_h6_low), w32(next_h7_high, next_h7_low)))
     | @($A.barr(lw, 256, words2), $A.barr(lc, 32, chain2)))























dataprop PARITY(int, int, int, int, int, int, int, int) =
  | {xh,xl,yh,yl,zh,zl,ah,al,rh,rl:nat}
    PARITY_mk(xh, xl, yh, yl, zh, zl, rh, rl) of (
      $AR.XOR(xh, yh, ah), $AR.XOR(xl, yl, al),
      $AR.XOR(ah, zh, rh), $AR.XOR(al, zl, rl))



dataprop SHA1_F(int, int, int, int, int, int, int, int, int) =
  | {t:nat | t <= 19}{bh,bl,ch,cl,dh,dl,fh,fl:nat}
    SHA1_F_choose(t, bh, bl, ch, cl, dh, dl, fh, fl) of CH(bh, bl, ch, cl, dh, dl, fh, fl)
  | {t:nat | 20 <= t; t <= 39}{bh,bl,ch,cl,dh,dl,fh,fl:nat}
    SHA1_F_parity_first(t, bh, bl, ch, cl, dh, dl, fh, fl) of PARITY(bh, bl, ch, cl, dh, dl, fh, fl)
  | {t:nat | 40 <= t; t <= 59}{bh,bl,ch,cl,dh,dl,fh,fl:nat}
    SHA1_F_majority(t, bh, bl, ch, cl, dh, dl, fh, fl) of MAJ(bh, bl, ch, cl, dh, dl, fh, fl)
  | {t:nat | 60 <= t; t <= 79}{bh,bl,ch,cl,dh,dl,fh,fl:nat}
    SHA1_F_parity_second(t, bh, bl, ch, cl, dh, dl, fh, fl) of PARITY(bh, bl, ch, cl, dh, dl, fh, fl)


fun word_parity {xh,xl,yh,yl,zh,zl:nat | xh < 65536; xl < 65536; yh < 65536; yl < 65536; zh < 65536; zl < 65536}
  (xh: int xh, xl: int xl, yh: int yh, yl: int yl, zh: int zh, zl: int zl)
  : [rh,rl:nat | rh < 65536; rl < 65536] (PARITY(xh, xl, yh, yl, zh, zl, rh, rl) | @(int rh, int rl))







fun sha1_f {t:nat | t < 80}{bh,bl,ch,cl,dh,dl:nat | bh < 65536; bl < 65536; ch < 65536; cl < 65536; dh < 65536; dl < 65536}
  (t: int t, bh: int bh, bl: int bl, ch: int ch, cl: int cl, dh: int dh, dl: int dl)
  : [fh,fl:nat | fh < 65536; fl < 65536] (SHA1_F(t, bh, bl, ch, cl, dh, dl, fh, fl) | @(int fh, int fl))























dataprop SHA1_K(int, int, int) =
  | {t:nat | 0 <= t; t <= 19} SHA1_K_0_to_19(t, 0x5a82, 0x7999)
  | {t:nat | 20 <= t; t <= 39} SHA1_K_20_to_39(t, 0x6ed9, 0xeba1)
  | {t:nat | 40 <= t; t <= 59} SHA1_K_40_to_59(t, 0x8f1b, 0xbcdc)
  | {t:nat | 60 <= t; t <= 79} SHA1_K_60_to_79(t, 0xca62, 0xc1d6)


fun sha1_k {t:nat | t < 80} (t: int t)
  : [high,low:nat | high < 65536; low < 65536] (SHA1_K(t, high, low) | @(int high, int low))
















dataprop SHA1_ROUND(int, word, word, word, word, word, word, word, word, word) =
  | {t:nat}{a_high,a_low,b_high,b_low,c_high,c_low,d_high,d_low,e_high,e_low,k_high,k_low,w_high,w_low,sum1_high,sum1_low,sum2_high,sum2_low,sum3_high,sum3_low,turn5_high,turn5_low,f_high,f_low,new_a_high,new_a_low,new_c_high,new_c_low:nat}
    SHA1_ROUND_mk(t, w32(a_high, a_low), w32(b_high, b_low), w32(c_high, c_low), w32(d_high, d_low), w32(e_high, e_low), w32(k_high, k_low), w32(w_high, w_low), w32(new_a_high, new_a_low), w32(new_c_high, new_c_low)) of (
      $AR.ROTR(27, a_high, a_low, turn5_high, turn5_low),
      SHA1_F(t, b_high, b_low, c_high, c_low, d_high, d_low, f_high, f_low),
      $AR.ADD32(turn5_high, turn5_low, f_high, f_low, sum1_high, sum1_low),
      $AR.ADD32(sum1_high, sum1_low, e_high, e_low, sum2_high, sum2_low),
      $AR.ADD32(sum2_high, sum2_low, k_high, k_low, sum3_high, sum3_low),
      $AR.ADD32(sum3_high, sum3_low, w_high, w_low, new_a_high, new_a_low),
      $AR.ROTR(2, b_high, b_low, new_c_high, new_c_low))


fun sha1_round {t:nat | t < 80}{a_high,a_low,b_high,b_low,c_high,c_low,d_high,d_low,e_high,e_low,k_high,k_low,w_high,w_low:nat | a_high < 65536; a_low < 65536; b_high < 65536; b_low < 65536; c_high < 65536; c_low < 65536; d_high < 65536; d_low < 65536; e_high < 65536; e_low < 65536; k_high < 65536; k_low < 65536; w_high < 65536; w_low < 65536}
  (t: int t, a_high: int a_high, a_low: int a_low, b_high: int b_high, b_low: int b_low, c_high: int c_high, c_low: int c_low, d_high: int d_high, d_low: int d_low, e_high: int e_high, e_low: int e_low, k_high: int k_high, k_low: int k_low, w_high: int w_high, w_low: int w_low)
  : [new_a_high,new_a_low,new_c_high,new_c_low:nat | new_a_high < 65536; new_a_low < 65536; new_c_high < 65536; new_c_low < 65536]
    (SHA1_ROUND(t, w32(a_high, a_low), w32(b_high, b_low), w32(c_high, c_low), w32(d_high, d_low), w32(e_high, e_low), w32(k_high, k_low), w32(w_high, w_low), w32(new_a_high, new_a_low), w32(new_c_high, new_c_low)) | @(int new_a_high, int new_a_low, int new_c_high, int new_c_low))















dataprop SHA1_ROUNDS($A.cells, int, int, five_words, five_words) =
  | {msg:$A.cells}{at:nat}{init:five_words}
    SHA1_ROUNDS_zero(msg, at, 0, init, init)
  | {msg:$A.cells}{at,t:nat | t < 80}{init:five_words}
    {a_high,a_low,b_high,b_low,c_high,c_low,d_high,d_low,e_high,e_low,k_high,k_low,w_high,w_low,new_a_high,new_a_low,new_c_high,new_c_low:nat}
    SHA1_ROUNDS_next(msg, at, t+1, init,
      five(w32(new_a_high, new_a_low), w32(a_high, a_low), w32(new_c_high, new_c_low),
           w32(c_high, c_low), w32(d_high, d_low))) of (
      SHA1_ROUNDS(msg, at, t, init, five(w32(a_high, a_low), w32(b_high, b_low), w32(c_high, c_low), w32(d_high, d_low), w32(e_high, e_low))),
      SHA1_K(t, k_high, k_low),
      SCHEDULE(sha1_kind(), msg, at, t, w_high, w_low),
      SHA1_ROUND(t, w32(a_high, a_low), w32(b_high, b_low), w32(c_high, c_low), w32(d_high, d_low), w32(e_high, e_low), w32(k_high, k_low), w32(w_high, w_low), w32(new_a_high, new_a_low), w32(new_c_high, new_c_low)))






dataprop SHA1_BLOCK($A.cells, int, five_words, five_words) =
  | {msg:$A.cells}{at:nat}{h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low,end_a_high,end_a_low,end_b_high,end_b_low,end_c_high,end_c_low,end_d_high,end_d_low,end_e_high,end_e_low,next_h0_high,next_h0_low,next_h1_high,next_h1_low,next_h2_high,next_h2_low,next_h3_high,next_h3_low,next_h4_high,next_h4_low:nat}
    SHA1_BLOCK_mk(msg, at, five(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low)), five(w32(next_h0_high, next_h0_low), w32(next_h1_high, next_h1_low), w32(next_h2_high, next_h2_low), w32(next_h3_high, next_h3_low), w32(next_h4_high, next_h4_low))) of (
      SHA1_ROUNDS(msg, at, 80, five(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low)), five(w32(end_a_high, end_a_low), w32(end_b_high, end_b_low), w32(end_c_high, end_c_low), w32(end_d_high, end_d_low), w32(end_e_high, end_e_low))),
      $AR.ADD32(h0_high, h0_low, end_a_high, end_a_low, next_h0_high, next_h0_low),
      $AR.ADD32(h1_high, h1_low, end_b_high, end_b_low, next_h1_high, next_h1_low),
      $AR.ADD32(h2_high, h2_low, end_c_high, end_c_low, next_h2_high, next_h2_low),
      $AR.ADD32(h3_high, h3_low, end_d_high, end_d_low, next_h3_high, next_h3_low),
      $AR.ADD32(h4_high, h4_low, end_e_high, end_e_low, next_h4_high, next_h4_low))






















fun sha1_compress {lm:agz}{nm:nat}{msg:$A.cells}{at:nat | at + 64 <= nm}
  {lw:agz}{words:$A.cells}{lc:agz}{chain:$A.cells}
  {h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low:nat | h0_high < 65536; h0_low < 65536; h1_high < 65536; h1_low < 65536; h2_high < 65536; h2_low < 65536; h3_high < 65536; h3_low < 65536; h4_high < 65536; h4_low < 65536}
  (message: !$A.barr(lm, nm, msg), at: int at, schedule: $A.barr(lw, 320, words),
   chaining: $A.barr(lc, 20, chain), have: FIVE_AT(chain, 0, five(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low))))
  : [words2:$A.cells][chain2:$A.cells][next_h0_high,next_h0_low,next_h1_high,next_h1_low,next_h2_high,next_h2_low,next_h3_high,next_h3_low,next_h4_high,next_h4_low:nat | next_h0_high < 65536; next_h0_low < 65536; next_h1_high < 65536; next_h1_low < 65536; next_h2_high < 65536; next_h2_low < 65536; next_h3_high < 65536; next_h3_low < 65536; next_h4_high < 65536; next_h4_low < 65536]
    (SHA1_BLOCK(msg, at, five(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low)), five(w32(next_h0_high, next_h0_low), w32(next_h1_high, next_h1_low), w32(next_h2_high, next_h2_low), w32(next_h3_high, next_h3_low), w32(next_h4_high, next_h4_low))),
     FIVE_AT(chain2, 0, five(w32(next_h0_high, next_h0_low), w32(next_h1_high, next_h1_low), w32(next_h2_high, next_h2_low), w32(next_h3_high, next_h3_low), w32(next_h4_high, next_h4_low)))
     | @($A.barr(lw, 320, words2), $A.barr(lc, 20, chain2)))





























dataprop SNOC($A.cells, int, $A.cells) =
  | {value:int} SNOC_nil($A.cnil(), value, $A.ccons(value, $A.cnil()))
  | {head,value:int}{cells,cells_after:$A.cells} SNOC_cons($A.ccons(head, cells), value, $A.ccons(head, cells_after)) of SNOC(cells, value, cells_after)

dataprop LISTN($A.cells, int) =
  | LISTN_nil($A.cnil(), 0)
  | {head:int}{cells:$A.cells}{size:nat} LISTN_cons($A.ccons(head, cells), size + 1) of LISTN(cells, size)

dataprop LIST($A.cells) =
  | {message:$A.cells}{size:nat} LIST_mk(message) of LISTN(message, size)


prfun empty_is_a_list (): LIST($A.cnil())



dataprop HELD($A.cells, $A.cells, int, $A.cells) =
  | {base,cells:$A.cells} HELD_zero(base, cells, 0, base)
  | {base,cells,message,message_after:$A.cells}{n:nat}{value:int}
    HELD_next(base, cells, n + 1, message_after) of (HELD(base, cells, n, message), $A.NTH(cells, n, value), SNOC(message, value, message_after))


prfun snoc_list {message:$A.cells}{value:int} (LIST(message)): [message_after:$A.cells] (SNOC(message, value, message_after), LIST(message_after))















prfun held_frame {base,cells,cells_after,message:$A.cells}{n,i:nat | n <= i}{value:int}
  (HELD(base, cells, n, message), $A.SETC(cells, i, value, cells_after)): HELD(base, cells_after, n, message)


























dataprop NORM(int, int, int, int, int, int, int, int) =
  | {count_top,count_high:nat}{count_blocks:nat | count_blocks + 1 < 1024} NORM_block(count_top, count_high, count_blocks, 64, count_top, count_high, count_blocks + 1, 0)
  | {count_top,count_high:nat | count_high + 1 < 65536} NORM_carry(count_top, count_high, 1023, 64, count_top, count_high + 1, 0, 0)
  | {count_top:nat | count_top + 1 < 8192} NORM_carry2(count_top, 65535, 1023, 64, count_top + 1, 0, 0, 0)




dataprop COUNTED($A.cells, int, int, int, int) =
  | COUNTED_nil($A.cnil(), 0, 0, 0, 0)
  | {message,message_after:$A.cells}{count_top,count_high,count_blocks,fill:nat | fill < 64}{value:int}
    COUNTED_byte(message_after, count_top, count_high, count_blocks, fill + 1) of (COUNTED(message, count_top, count_high, count_blocks, fill), SNOC(message, value, message_after))
  | {message:$A.cells}{count_top,count_high,count_blocks,fill,count_top_after,count_high_after,count_blocks_after,fill_after:nat}
    COUNTED_norm(message, count_top_after, count_high_after, count_blocks_after, fill_after) of (COUNTED(message, count_top, count_high, count_blocks, fill), NORM(count_top, count_high, count_blocks, fill, count_top_after, count_high_after, count_blocks_after, fill_after))















dataprop BITLEN_LOW(int, int, int, int, int) =
  | {count_blocks,fill,carry_low,blocks_rest,byte6,byte7:nat | count_blocks == 128*carry_low + blocks_rest; blocks_rest < 128; carry_low < 8; fill < 64; byte6 < 256; byte7 < 256; 256*byte6 + byte7 == 512*blocks_rest + 8*fill}
    BITLEN_LOW_mk(count_blocks, fill, carry_low, byte6, byte7)

dataprop BITLEN_MID(int, int, int, int, int) =
  | {count_high,carry_low,carry_mid,high_rest,byte4,byte5:nat | count_high == 8192*carry_mid + high_rest; high_rest < 8192; carry_mid < 8; carry_low < 8; byte4 < 256; byte5 < 256; 256*byte4 + byte5 == 8*high_rest + carry_low}
    BITLEN_MID_mk(count_high, carry_low, carry_mid, byte4, byte5)

dataprop BITLEN_HIGH(int, int, int, int) =
  | {count_top,carry_mid,byte2,byte3:nat | count_top < 8192; carry_mid < 8; byte2 < 256; byte3 < 256; 256*byte2 + byte3 == 8*count_top + carry_mid}
    BITLEN_HIGH_mk(count_top, carry_mid, byte2, byte3)




dataprop BITLEN(int, int, int, int, int, int, int, int, int, int, int, int) =
  | {count_top,count_high,count_blocks,fill,carry_low,carry_mid,byte2,byte3,byte4,byte5,byte6,byte7:nat}
    BITLEN_mk(count_top, count_high, count_blocks, fill, 0, 0, byte2, byte3, byte4, byte5, byte6, byte7) of (
      BITLEN_LOW(count_blocks, fill, carry_low, byte6, byte7), BITLEN_MID(count_high, carry_low, carry_mid, byte4, byte5), BITLEN_HIGH(count_top, carry_mid, byte2, byte3))





dataprop ZCOUNT(int, int) =
  | {fill,zeros:nat | fill <= 55; zeros == 55 - fill} ZCOUNT_short(fill, zeros)
  | {fill,zeros:nat | 56 <= fill; fill < 64; zeros == 119 - fill} ZCOUNT_long(fill, zeros)


dataprop ZSNOC($A.cells, int, $A.cells) =
  | {start:$A.cells} ZSNOC_zero(start, 0, start)
  | {start,so_far,longer:$A.cells}{zeros:nat} ZSNOC_next(start, zeros + 1, longer) of (ZSNOC(start, zeros, so_far), SNOC(so_far, 0, longer))



dataprop LENSNOC($A.cells, int, int, int, int, int, int, int, int, $A.cells) =
  | {start,grown1,grown2,grown3,grown4,grown5,grown6,grown7,grown8:$A.cells}{byte0,byte1,byte2,byte3,byte4,byte5,byte6,byte7:int}
    LENSNOC_mk(start, byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7, grown8) of (
      SNOC(start, byte0, grown1), SNOC(grown1, byte1, grown2), SNOC(grown2, byte2, grown3), SNOC(grown3, byte3, grown4),
      SNOC(grown4, byte4, grown5), SNOC(grown5, byte5, grown6), SNOC(grown6, byte6, grown7), SNOC(grown7, byte7, grown8))






dataprop PAD($A.cells, int, int, int, int, $A.cells) =
  | {message,marked,zeroed,padded:$A.cells}{count_top,count_high,count_blocks,fill,zeros:nat}{byte0,byte1,byte2,byte3,byte4,byte5,byte6,byte7:int}
    PAD_mk(message, count_top, count_high, count_blocks, fill, padded) of (
      COUNTED(message, count_top, count_high, count_blocks, fill), ZCOUNT(fill, zeros),
      BITLEN(count_top, count_high, count_blocks, fill, byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7),
      SNOC(message, 128, marked), ZSNOC(marked, zeros, zeroed), LENSNOC(zeroed, byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7, padded))



fun bitlen_bytes {count_top,count_high,count_blocks,fill:nat | count_top < 8192; count_high < 65536; count_blocks < 1024; fill < 64}
  (count_top: int count_top, count_high: int count_high, count_blocks: int count_blocks, fill: int fill)
  : [byte2,byte3,byte4,byte5,byte6,byte7:nat | byte2 < 256; byte3 < 256; byte4 < 256; byte5 < 256; byte6 < 256; byte7 < 256]
    (BITLEN(count_top, count_high, count_blocks, fill, 0, 0, byte2, byte3, byte4, byte5, byte6, byte7) | @(int byte2, int byte3, int byte4, int byte5, int byte6, int byte7))














fun bitlen_low {count_blocks,fill:nat | count_blocks < 1024; fill < 64} (count_blocks: int count_blocks, fill: int fill)
  : [carry_low,byte6,byte7:nat | carry_low < 8; byte6 < 256; byte7 < 256] (BITLEN_LOW(count_blocks, fill, carry_low, byte6, byte7) | @(int carry_low, int byte6, int byte7))







fun bitlen_mid {count_high,carry_low:nat | count_high < 65536; carry_low < 8} (count_high: int count_high, carry_low: int carry_low)
  : [carry_mid,byte4,byte5:nat | carry_mid < 8; byte4 < 256; byte5 < 256] (BITLEN_MID(count_high, carry_low, carry_mid, byte4, byte5) | @(int carry_mid, int byte4, int byte5))







fun bitlen_high {count_top,carry_mid:nat | count_top < 8192; carry_mid < 8} (count_top: int count_top, carry_mid: int carry_mid)
  : [byte2,byte3:nat | byte2 < 256; byte3 < 256] (BITLEN_HIGH(count_top, carry_mid, byte2, byte3) | @(int byte2, int byte3))



















































fun pad_short {block_loc:agz}{block_cells,hashed_bytes,message:$A.cells}{count_top,count_high,count_blocks,fill:nat | count_top < 8192; count_high < 65536; count_blocks < 1024; fill <= 55}
  (block_array: $A.barr(block_loc, 64, block_cells), count_top: int count_top, count_high: int count_high, count_blocks: int count_blocks, fill: int fill,
   held: HELD(hashed_bytes, block_cells, fill, message), list: LIST(message), counted: COUNTED(message, count_top, count_high, count_blocks, fill))
  : [block_cells_after,padded:$A.cells] (HELD(hashed_bytes, block_cells_after, 64, padded), PAD(message, count_top, count_high, count_blocks, fill, padded) | $A.barr(block_loc, 64, block_cells_after))











fun pad_long_first {block_loc:agz}{block_cells,hashed_bytes,message:$A.cells}{fill:nat | 56 <= fill; fill < 64}
  (block_array: $A.barr(block_loc, 64, block_cells), fill: int fill, held: HELD(hashed_bytes, block_cells, fill, message), list: LIST(message))
  : [block_cells_after,marked,first_padded:$A.cells]
    (HELD(hashed_bytes, block_cells_after, 64, first_padded), LIST(first_padded), SNOC(message, 128, marked), ZSNOC(marked, 63 - fill, first_padded) | $A.barr(block_loc, 64, block_cells_after))






fun pad_long_second {block_loc:agz}{block_cells,message,marked,first_padded:$A.cells}{count_top,count_high,count_blocks,fill:nat | count_top < 8192; count_high < 65536; count_blocks < 1024; 56 <= fill; fill < 64}
  (block_array: $A.barr(block_loc, 64, block_cells), count_top: int count_top, count_high: int count_high, count_blocks: int count_blocks, fill: int fill,
   list: LIST(first_padded), counted: COUNTED(message, count_top, count_high, count_blocks, fill), snoc128: SNOC(message, 128, marked), zeros: ZSNOC(marked, 63 - fill, first_padded))
  : [block_cells_after,padded:$A.cells] (HELD(first_padded, block_cells_after, 64, padded), PAD(message, count_top, count_high, count_blocks, fill, padded) | $A.barr(block_loc, 64, block_cells_after))















dataprop SHA256_IV(eight_words) =
  | SHA256_IV_mk(eight(w32(0x6a09, 0xe667), w32(0xbb67, 0xae85), w32(0x3c6e, 0xf372), w32(0xa54f, 0xf53a),
                       w32(0x510e, 0x527f), w32(0x9b05, 0x688c), w32(0x1f83, 0xd9ab), w32(0x5be0, 0xcd19)))



dataprop SHA1_IV(five_words) =
  | SHA1_IV_mk(five(w32(0x6745, 0x2301), w32(0xefcd, 0xab89), w32(0x98ba, 0xdcfe), w32(0x1032, 0x5476), w32(0xc3d2, 0xe1f0)))



fun sha256_iv ()
  : (SHA256_IV(eight(w32(0x6a09, 0xe667), w32(0xbb67, 0xae85), w32(0x3c6e, 0xf372), w32(0xa54f, 0xf53a),
                     w32(0x510e, 0x527f), w32(0x9b05, 0x688c), w32(0x1f83, 0xd9ab), w32(0x5be0, 0xcd19))) |
     @(int(0x6a09), int(0xe667), int(0xbb67), int(0xae85), int(0x3c6e), int(0xf372), int(0xa54f), int(0xf53a),
       int(0x510e), int(0x527f), int(0x9b05), int(0x688c), int(0x1f83), int(0xd9ab), int(0x5be0), int(0xcd19)))




fun sha1_iv ()
  : (SHA1_IV(five(w32(0x6745, 0x2301), w32(0xefcd, 0xab89), w32(0x98ba, 0xdcfe), w32(0x1032, 0x5476), w32(0xc3d2, 0xe1f0))) |
     @(int(0x6745), int(0x2301), int(0xefcd), int(0xab89), int(0x98ba), int(0xdcfe), int(0x1032), int(0x5476), int(0xc3d2), int(0xe1f0)))









dataprop HASHED256($A.cells, eight_words) =
  | {chaining:eight_words} HASHED256_start($A.cnil(), chaining) of SHA256_IV(chaining)
  | {hashed_bytes,hashed_after,cells:$A.cells}{chaining,chaining_after:eight_words}
    HASHED256_block(hashed_after, chaining_after) of (HASHED256(hashed_bytes, chaining), SHA256_BLOCK(cells, 0, chaining, chaining_after), HELD(hashed_bytes, cells, 64, hashed_after))

dataprop HASHED1($A.cells, five_words) =
  | {chaining:five_words} HASHED1_start($A.cnil(), chaining) of SHA1_IV(chaining)
  | {hashed_bytes,hashed_after,cells:$A.cells}{chaining,chaining_after:five_words}
    HASHED1_block(hashed_after, chaining_after) of (HASHED1(hashed_bytes, chaining), SHA1_BLOCK(cells, 0, chaining, chaining_after), HELD(hashed_bytes, cells, 64, hashed_after))




dataprop DIGEST256($A.cells, eight_words) =
  | {message,padded:$A.cells}{count_top,count_high,count_blocks,fill:nat}{chaining:eight_words}
    DIGEST256_mk(message, chaining) of (PAD(message, count_top, count_high, count_blocks, fill, padded), HASHED256(padded, chaining))

dataprop DIGEST1($A.cells, five_words) =
  | {message,padded:$A.cells}{count_top,count_high,count_blocks,fill:nat}{chaining:five_words}
    DIGEST1_mk(message, chaining) of (PAD(message, count_top, count_high, count_blocks, fill, padded), HASHED1(padded, chaining))




prfun word_at_bound {cells:$A.cells}{at,high,low:nat} (WORD_AT(cells, at, high, low)): [high < 65536; low < 65536] void





prfun eight_at_bound {cells:$A.cells}{at,h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low,h5_high,h5_low,h6_high,h6_low,h7_high,h7_low:nat}
  (EIGHT_AT(cells, at, eight(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low), w32(h5_high, h5_low), w32(h6_high, h6_low), w32(h7_high, h7_low))))
  : [h0_high < 65536; h0_low < 65536; h1_high < 65536; h1_low < 65536; h2_high < 65536; h2_low < 65536; h3_high < 65536; h3_low < 65536; h4_high < 65536; h4_low < 65536; h5_high < 65536; h5_low < 65536; h6_high < 65536; h6_low < 65536; h7_high < 65536; h7_low < 65536] void


























datavtype ctx256($A.cells) =
  | {message:$A.cells}{chain_loc,schedule_loc,block_loc:agz}{chain_cells,schedule_cells,block_cells,hashed_bytes:$A.cells}{chaining:eight_words}{count_top,count_high,count_blocks,fill:nat | count_top < 8191; count_high < 65536; count_blocks < 1024; fill < 64}
    ctx256_mk(message) of (
      HASHED256(hashed_bytes, chaining), EIGHT_AT(chain_cells, 0, chaining), HELD(hashed_bytes, block_cells, fill, message), LIST(message), COUNTED(message, count_top, count_high, count_blocks, fill) |
      $A.barr(chain_loc, 32, chain_cells), $A.barr(schedule_loc, 256, schedule_cells), $A.barr(block_loc, 64, block_cells), int count_top, int count_high, int count_blocks, int fill)


















fn init256_proved (): ctx256($A.cnil())






































datavtype update256_result($A.cells, $A.cells, int) =
  | {message_before,data_cells:$A.cells}{length:nat}{message_after:$A.cells}
    Updated256(message_before, data_cells, length) of (HELD(message_before, data_cells, length, message_after) | ctx256(message_after))
  | {message_before,data_cells:$A.cells}{length:nat}{message_after:$A.cells}{i:nat | i < length}
    Stopped256(message_before, data_cells, length) of (HELD(message_before, data_cells, i, message_after) | ctx256(message_after))

























fn update256_proved {message,data_cells:$A.cells}{l:agz}{n:nat}{length:nat | length <= n}
  (c: ctx256(message), data: !$A.barr(l, n, data_cells), len: int length): update256_result(message, data_cells, length)











dataprop HEX_DIGIT(int, int) =
  | {digit:nat | digit < 10} HEX_DIGIT_decimal(digit, 48 + digit)
  | {digit:nat | 10 <= digit; digit < 16} HEX_DIGIT_letter(digit, 87 + digit)




dataprop HEXOF($A.cells, $A.cells, int) =
  | {out_cells,chain_cells:$A.cells} HEXOF_zero(out_cells, chain_cells, 0)
  | {out_cells,chain_cells:$A.cells}{n:nat}{value,high_nibble,low_nibble,first_char,second_char:nat | value < 256; high_nibble < 16; low_nibble < 16; value == 16*high_nibble + low_nibble}
    HEXOF_next(out_cells, chain_cells, n + 1) of (
      HEXOF(out_cells, chain_cells, n), $A.NTH(chain_cells, n, value), HEX_DIGIT(high_nibble, first_char), HEX_DIGIT(low_nibble, second_char),
      $A.NTH(out_cells, 2*n, first_char), $A.NTH(out_cells, 2*n + 1, second_char))




dataprop EIGHT_HEX($A.cells, eight_words) =
  | {out_cells,chain_cells:$A.cells}{chaining:eight_words} EIGHT_HEX_mk(out_cells, chaining) of (EIGHT_AT(chain_cells, 0, chaining), HEXOF(out_cells, chain_cells, 32))













































fn finish256_proved {message:$A.cells}{out_loc:agz}{out_cells:$A.cells} (c: ctx256(message), out: $A.barr(out_loc, 64, out_cells))
  : [out_cells_after:$A.cells][chaining:eight_words] (DIGEST256(message, chaining), EIGHT_HEX(out_cells_after, chaining) | $A.barr(out_loc, 64, out_cells_after))
























































fn sha256_digest_proved {l:agz}{n:nat}{data_cells:$A.cells}{length:nat | length <= n; length <= 65535}{out_loc:agz}{out_cells:$A.cells}
  (data: !$A.barr(l, n, data_cells), len: int length, out: $A.barr(out_loc, 64, out_cells))
  : [message,out_cells_after:$A.cells][chaining:eight_words]
    (HELD($A.cnil(), data_cells, length, message), DIGEST256(message, chaining), EIGHT_HEX(out_cells_after, chaining) | $A.barr(out_loc, 64, out_cells_after))











prfun five_at_bound {cells:$A.cells}{at,h0_high,h0_low,h1_high,h1_low,h2_high,h2_low,h3_high,h3_low,h4_high,h4_low:nat}
  (FIVE_AT(cells, at, five(w32(h0_high, h0_low), w32(h1_high, h1_low), w32(h2_high, h2_low), w32(h3_high, h3_low), w32(h4_high, h4_low))))
  : [h0_high < 65536; h0_low < 65536; h1_high < 65536; h1_low < 65536; h2_high < 65536; h2_low < 65536; h3_high < 65536; h3_low < 65536; h4_high < 65536; h4_low < 65536] void






























































































fn sha1_digest_proved {l:agz}{n:nat}{data_cells:$A.cells}{length:nat | length <= n; length <= 65535}{out_loc:agz}{out_cells:$A.cells}
  (data: !$A.barr(l, n, data_cells), len: int length, out: $A.barr(out_loc, 20, out_cells))
  : [message,out_cells_after:$A.cells][chaining:five_words]
    (HELD($A.cnil(), data_cells, length, message), DIGEST1(message, chaining), FIVE_AT(out_cells_after, 0, chaining) | $A.barr(out_loc, 20, out_cells_after))









datavtype ctx1($A.cells) =
  | {message:$A.cells}{chain_loc,schedule_loc,block_loc:agz}{chain_cells,schedule_cells,block_cells,hashed_bytes:$A.cells}{chaining:five_words}{count_top,count_high,count_blocks,fill:nat | count_top < 8191; count_high < 65536; count_blocks < 1024; fill < 64}
    ctx1_mk(message) of (
      HASHED1(hashed_bytes, chaining), FIVE_AT(chain_cells, 0, chaining), HELD(hashed_bytes, block_cells, fill, message), LIST(message), COUNTED(message, count_top, count_high, count_blocks, fill) |
      $A.barr(chain_loc, 20, chain_cells), $A.barr(schedule_loc, 320, schedule_cells), $A.barr(block_loc, 64, block_cells), int count_top, int count_high, int count_blocks, int fill)


fn init1_proved (): ctx1($A.cnil())











datavtype update1_result($A.cells, $A.cells, int) =
  | {message_before,data_cells:$A.cells}{length:nat}{message_after:$A.cells}
    Updated1(message_before, data_cells, length) of (HELD(message_before, data_cells, length, message_after) | ctx1(message_after))
  | {message_before,data_cells:$A.cells}{length:nat}{message_after:$A.cells}{i:nat | i < length}
    Stopped1(message_before, data_cells, length) of (HELD(message_before, data_cells, i, message_after) | ctx1(message_after))

























fn update1_proved {message,data_cells:$A.cells}{l:agz}{n:nat}{length:nat | length <= n}
  (c: ctx1(message), data: !$A.barr(l, n, data_cells), len: int length): update1_result(message, data_cells, length)








fn finish1_proved {message:$A.cells}{out_loc:agz}{out_cells:$A.cells} (c: ctx1(message), out: $A.barr(out_loc, 20, out_cells))
  : [out_cells_after:$A.cells][chaining:five_words] (DIGEST1(message, chaining), FIVE_AT(out_cells_after, 0, chaining) | $A.barr(out_loc, 20, out_cells_after))
































































































































































































































































































































































































datavtype proved_ctx =
  | {message:$A.cells} proved_ctx_mk of (ctx256(message))

fn proved_init (): proved_ctx





fn proved_update
  {l:agz}{n:pos}{k:nat | k <= n}
  (c: !proved_ctx, data: !$A.arr(byte, l, n), len: int k): void













fn proved_finish {lo:agz} (c: proved_ctx, out: !$A.arr(byte, lo, 64)): void











fn proved_hash
  {l:agz}{n:pos}{lo:agz}
  (data: !$A.arr(byte, l, n), data_len: int n,
   out: !$A.arr(byte, lo, 64)): void









fn sha1_digest {l:agz}{n:pos}{data_len:pos | data_len <= n}{lo:agz}
  (data: !$A.borrow(byte, l, n), data_len: int data_len, out: !$A.arr(byte, lo, 20)): void










