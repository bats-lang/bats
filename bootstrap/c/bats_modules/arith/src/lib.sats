






fun add_int_int(a: int, b: int): int = "mac#atspre_g0int_add_int"

fun sub_int_int(a: int, b: int): int = "mac#atspre_g0int_sub_int"

fun mul_int_int(a: int, b: int): int = "mac#atspre_g0int_mul_int"

fun div_int_int(a: int, b: int): int = "mac#atspre_g0int_div_int"

fun mod_int_int(a: int, b: int): int = "mac#atspre_g0int_mod_int"



fun eq_int_int(a: int, b: int): bool = "mac#atspre_g0int_eq_int"

fun neq_int_int(a: int, b: int): bool = "mac#atspre_g0int_neq_int"

fun gt_int_int(a: int, b: int): bool = "mac#atspre_g0int_gt_int"

fun gte_int_int(a: int, b: int): bool = "mac#atspre_g0int_gte_int"

fun lt_int_int(a: int, b: int): bool = "mac#atspre_g0int_lt_int"

fun lte_int_int(a: int, b: int): bool = "mac#atspre_g0int_lte_int"



fun gt1_int_int {a,b:int} (a: int a, b: int b): bool(a > b) = "mac#atspre_g0int_gt_int"

fun lt1_int_int {a,b:int} (a: int a, b: int b): bool(a < b) = "mac#atspre_g0int_lt_int"



fun bor_int_int(a: int, b: int): int = "mac#atspre_lor_int_int"

fun bsl_int_int(a: int, n: int): int = "mac#atspre_g0int_asl_int"

fun band_int_int(a: int, b: int): int = "mac#atspre_land_int_int"

fun bsr_int_int(a: int, n: int): int = "mac#atspre_g0int_asr_int"



fun add_g1 {a,b:int}(a: int(a), b: int(b)): int(a+b) = "mac#atspre_g0int_add_int"

fun sub_g1 {a,b:int}(a: int(a), b: int(b)): int(a-b) = "mac#atspre_g0int_sub_int"

fun mul_g1 {a,b:int}(a: int(a), b: int(b)): int(a*b) = "mac#atspre_g0int_mul_int"



fun lt_g1 {a,b:int}(a: int(a), b: int(b)): bool(a < b) = "mac#atspre_g0int_lt_int"

fun gt_g1 {a,b:int}(a: int(a), b: int(b)): bool(a > b) = "mac#atspre_g0int_gt_int"

fun eq_g1 {a,b:int}(a: int(a), b: int(b)): bool(a == b) = "mac#atspre_g0int_eq_int"

fun lte_g1 {a,b:int}(a: int(a), b: int(b)): bool(a <= b) = "mac#atspre_g0int_lte_int"

fun gte_g1 {a,b:int}(a: int(a), b: int(b)): bool(a >= b) = "mac#atspre_g0int_gte_int"



fun band_g1 {a,b:nat}(a: int(a), b: int(b)): [r:nat | r <= b] int(r) = "mac#atspre_land_int_int"





dataprop XOR(int, int, int) =
  | XOR_nil(0, 0, 0)
  | {a,b,c:nat | a + b > 0} XOR_00(2*a, 2*b, 2*c) of XOR(a, b, c)
  | {a,b,c:nat} XOR_01(2*a, 2*b + 1, 2*c + 1) of XOR(a, b, c)
  | {a,b,c:nat} XOR_10(2*a + 1, 2*b, 2*c + 1) of XOR(a, b, c)
  | {a,b,c:nat} XOR_11(2*a + 1, 2*b + 1, 2*c) of XOR(a, b, c)



dataprop AND(int, int, int) =
  | AND_nil(0, 0, 0)
  | {a,b,c:nat | a + b > 0} AND_00(2*a, 2*b, 2*c) of AND(a, b, c)
  | {a,b,c:nat} AND_01(2*a, 2*b + 1, 2*c) of AND(a, b, c)
  | {a,b,c:nat} AND_10(2*a + 1, 2*b, 2*c) of AND(a, b, c)
  | {a,b,c:nat} AND_11(2*a + 1, 2*b + 1, 2*c + 1) of AND(a, b, c)

dataprop OR(int, int, int) =
  | OR_nil(0, 0, 0)
  | {a,b,c:nat | a + b > 0} OR_00(2*a, 2*b, 2*c) of OR(a, b, c)
  | {a,b,c:nat} OR_01(2*a, 2*b + 1, 2*c + 1) of OR(a, b, c)
  | {a,b,c:nat} OR_10(2*a + 1, 2*b, 2*c + 1) of OR(a, b, c)
  | {a,b,c:nat} OR_11(2*a + 1, 2*b + 1, 2*c + 1) of OR(a, b, c)





fun and_proved {a,b:nat}(a: int(a), b: int(b)): [c:nat] (AND(a, b, c) | int(c)) = "mac#atspre_land_int_int"

fun or_proved {a,b:nat}(a: int(a), b: int(b)): [c:nat] (OR(a, b, c) | int(c)) = "mac#atspre_lor_int_int"














fun xor_g1 {a,b:nat}(a: int(a), b: int(b)): [c:nat] (XOR(a, b, c) | int(c))








prfun xor_functional {a,b,c1,c2:nat} (XOR(a, b, c1), XOR(a, b, c2)): [c1 == c2] void












dataprop POW2(int, int) =
  | POW2_zero(0, 1)
  | {k,p:nat} POW2_succ(k+1, 2*p) of POW2(k, p)


prfun xor_bound {k,p,a,b,c:nat | a < p; b < p} (POW2(k, p), XOR(a, b, c)): [c < p] void




















prfun xor_double {a,b,c:nat} (XOR(a, b, c)): XOR(2*a, 2*b, 2*c)










prfun xor_zero_right {a:nat} (): XOR(a, 0, a)








prfun xor_zero_left {a:nat} (): XOR(0, a, a)









prfun xor_comm {a,b,c:nat} (XOR(a, b, c)): XOR(b, a, c)










prfun xor_self {a:nat} (): XOR(a, a, 0)










prfun xor_half {a,b,c:nat} (XOR(a, b, c)): XOR(a/2, b/2, c/2)










prfun xor_zero_equal {a,b:nat} (XOR(a, b, 0)): [a == b] void












prfun xor_assoc {a,b,c,ab,bc,abc:nat}
  (XOR(a, b, ab), XOR(ab, c, abc), XOR(b, c, bc)): XOR(a, bc, abc)






































fn low_byte(x: int): [v:nat | v < 256] int v









fn byte_of_char(c: char): [v:nat | v < 256] int v





















dataprop ROTR1(int, int, int, int) =
  | {a,b:nat | a < 32768; b < 32768}{s,t:nat | s < 2; t < 2}
    ROTR1_mk(2*a + s, 2*b + t, a + 32768*t, b + 32768*s)


dataprop ROTR(int, int, int, int, int) =
  | {h,l:nat} ROTR_zero(0, h, l, h, l)
  | {n:nat}{h,l,h1,l1,h2,l2:nat}
    ROTR_succ(n + 1, h, l, h2, l2) of (ROTR1(h, l, h1, l1), ROTR(n, h1, l1, h2, l2))



dataprop SHR1(int, int, int, int) =
  | {a,b:nat | a < 32768; b < 32768}{s,t:nat | s < 2; t < 2}
    SHR1_mk(2*a + s, 2*b + t, a, b + 32768*s)

dataprop SHR(int, int, int, int, int) =
  | {h,l:nat} SHR_zero(0, h, l, h, l)
  | {n:nat}{h,l,h1,l1,h2,l2:nat}
    SHR_succ(n + 1, h, l, h2, l2) of (SHR1(h, l, h1, l1), SHR(n, h1, l1, h2, l2))




dataprop ADD32(int, int, int, int, int, int) =
  | {h1,l1,h2,l2,h3,l3:nat | h1 < 65536; l1 < 65536; h2 < 65536; l2 < 65536; h3 < 65536; l3 < 65536}
    {c,d:nat | c < 2; d < 2; l1 + l2 == l3 + 65536*c; h1 + h2 + c == h3 + 65536*d}
    ADD32_mk(h1, l1, h2, l2, h3, l3)


dataprop NOT32(int, int, int, int) =
  | {h,l:nat | h < 65536; l < 65536} NOT32_mk(h, l, 65535 - h, 65535 - l)







fun rotr1 {h,l:nat | h < 65536; l < 65536} (h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (ROTR1(h, l, h2, l2) | @(int h2, int l2))







fun shr1 {h,l:nat | h < 65536; l < 65536} (h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (SHR1(h, l, h2, l2) | @(int h2, int l2))








fun rotr {n,h,l:nat | h < 65536; l < 65536} (n: int n, h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (ROTR(n, h, l, h2, l2) | @(int h2, int l2))












fun shr {n,h,l:nat | h < 65536; l < 65536} (n: int n, h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (SHR(n, h, l, h2, l2) | @(int h2, int l2))












fun add32 {h1,l1,h2,l2:nat | h1 < 65536; l1 < 65536; h2 < 65536; l2 < 65536}
  (h1: int h1, l1: int l1, h2: int h2, l2: int l2)
  : [h3,l3:nat | h3 < 65536; l3 < 65536] (ADD32(h1, l1, h2, l2, h3, l3) | @(int h3, int l3))




















fun not32 {h,l:nat | h < 65536; l < 65536} (h: int h, l: int l)
  : (NOT32(h, l, 65535 - h, 65535 - l) | @(int(65535 - h), int(65535 - l)))




prfun and_bound {k,p,a,b,c:nat | a < p; b < p} (POW2(k, p), AND(a, b, c)): [c < p] void











prfun or_bound {k,p,a,b,c:nat | a < p; b < p} (POW2(k, p), OR(a, b, c)): [c < p] void












prfun pow2_half (): POW2(16, 65536)









fun xor32 {h1,l1,h2,l2:nat | h1 < 65536; l1 < 65536; h2 < 65536; l2 < 65536}
  (h1: int h1, l1: int l1, h2: int h2, l2: int l2)
  : [h3,l3:nat | h3 < 65536; l3 < 65536] (XOR(h1, h2, h3), XOR(l1, l2, l3) | @(int h3, int l3))








fun and32 {h1,l1,h2,l2:nat | h1 < 65536; l1 < 65536; h2 < 65536; l2 < 65536}
  (h1: int h1, l1: int l1, h2: int h2, l2: int l2)
  : [h3,l3:nat | h3 < 65536; l3 < 65536] (AND(h1, h2, h3), AND(l1, l2, l3) | @(int h3, int l3))








fun or32 {h1,l1,h2,l2:nat | h1 < 65536; l1 < 65536; h2 < 65536; l2 < 65536}
  (h1: int h1, l1: int l1, h2: int h2, l2: int l2)
  : [h3,l3:nat | h3 < 65536; l3 < 65536] (OR(h1, h2, h3), OR(l1, l2, l3) | @(int h3, int l3))









prfun rotr1_functional {h,l,h2,l2,h3,l3:nat} (ROTR1(h, l, h2, l2), ROTR1(h, l, h3, l3)): [h2 == h3; l2 == l3] void













prfun rotr_functional {n,h,l,h2,l2,h3,l3:nat} (ROTR(n, h, l, h2, l2), ROTR(n, h, l, h3, l3)): [h2 == h3; l2 == l3] void











prfun shr1_functional {h,l,h2,l2,h3,l3:nat} (SHR1(h, l, h2, l2), SHR1(h, l, h3, l3)): [h2 == h3; l2 == l3] void







prfun shr_functional {n,h,l,h2,l2,h3,l3:nat} (SHR(n, h, l, h2, l2), SHR(n, h, l, h3, l3)): [h2 == h3; l2 == l3] void











prfun add32_functional {h1,l1,h2,l2,h3,l3,h4,l4:nat}
  (ADD32(h1, l1, h2, l2, h3, l3), ADD32(h1, l1, h2, l2, h4, l4)): [h3 == h4; l3 == l4] void









































prfun rotr_add {a,b,h,l,h1,l1,h2,l2:nat} (ROTR(a, h, l, h1, l1), ROTR(b, h1, l1, h2, l2)): ROTR(a + b, h, l, h2, l2)









prfun shr_add {a,b,h,l,h1,l1,h2,l2:nat} (SHR(a, h, l, h1, l1), SHR(b, h1, l1, h2, l2)): SHR(a + b, h, l, h2, l2)













prfun rotr_digits_1 {a,b,r,t:nat | a < 32768; b < 32768; r < 2; t < 2} ()
  : ROTR(1, 2*a + r, 2*b + t, a + 32768*t, b + 32768*r)




prfun rotr_digits_2 {a,b,r,t:nat | a < 16384; b < 16384; r < 4; t < 4} ()
  : ROTR(2, 4*a + r, 4*b + t, a + 16384*t, b + 16384*r)







prfun rotr_digits_4 {a,b,r,t:nat | a < 4096; b < 4096; r < 16; t < 16} ()
  : ROTR(4, 16*a + r, 16*b + t, a + 4096*t, b + 4096*r)







prfun rotr_digits_8 {a,b,r,t:nat | a < 256; b < 256; r < 256; t < 256} ()
  : ROTR(8, 256*a + r, 256*b + t, a + 256*t, b + 256*r)







prfun rotr_by_16 {h,l:nat | h < 65536; l < 65536} ()
  : ROTR(16, h, l, l, h)










fun rotr_step_1 {h,l:nat | h < 65536; l < 65536} (h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (ROTR(1, h, l, h2, l2) | @(int h2, int l2))









fun rotr_step_2 {h,l:nat | h < 65536; l < 65536} (h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (ROTR(2, h, l, h2, l2) | @(int h2, int l2))









fun rotr_step_4 {h,l:nat | h < 65536; l < 65536} (h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (ROTR(4, h, l, h2, l2) | @(int h2, int l2))









fun rotr_step_8 {h,l:nat | h < 65536; l < 65536} (h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (ROTR(8, h, l, h2, l2) | @(int h2, int l2))









fun rotr_step_16 {h,l:nat | h < 65536; l < 65536} (h: int h, l: int l)
  : (ROTR(16, h, l, l, h) | @(int l, int h))











































fun rotr_fast {n,h,l:nat | n < 32; h < 65536; l < 65536} (n: int n, h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (ROTR(n, h, l, h2, l2) | @(int h2, int l2))



















prfun shr_digits_1 {a,b,r,t:nat | a < 32768; b < 32768; r < 2; t < 2} ()
  : SHR(1, 2*a + r, 2*b + t, a, b + 32768*r)




prfun shr_digits_2 {a,b,r,t:nat | a < 16384; b < 16384; r < 4; t < 4} ()
  : SHR(2, 4*a + r, 4*b + t, a, b + 16384*r)







prfun shr_digits_4 {a,b,r,t:nat | a < 4096; b < 4096; r < 16; t < 16} ()
  : SHR(4, 16*a + r, 16*b + t, a, b + 4096*r)







prfun shr_digits_8 {a,b,r,t:nat | a < 256; b < 256; r < 256; t < 256} ()
  : SHR(8, 256*a + r, 256*b + t, a, b + 256*r)








prfun shr_by_16 {h,l:nat | h < 65536; l < 65536} ()
  : SHR(16, h, l, 0, h)






fun shr_step_1 {h,l:nat | h < 65536; l < 65536} (h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (SHR(1, h, l, h2, l2) | @(int h2, int l2))








fun shr_step_2 {h,l:nat | h < 65536; l < 65536} (h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (SHR(2, h, l, h2, l2) | @(int h2, int l2))








fun shr_step_4 {h,l:nat | h < 65536; l < 65536} (h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (SHR(4, h, l, h2, l2) | @(int h2, int l2))








fun shr_step_8 {h,l:nat | h < 65536; l < 65536} (h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (SHR(8, h, l, h2, l2) | @(int h2, int l2))








fun shr_step_16 {h,l:nat | h < 65536; l < 65536} (h: int h, l: int l)
  : (SHR(16, h, l, 0, h) | @(int 0, int h))









































fun shr_fast {n,h,l:nat | n < 32; h < 65536; l < 65536} (n: int n, h: int h, l: int l)
  : [h2,l2:nat | h2 < 65536; l2 < 65536] (SHR(n, h, l, h2, l2) | @(int h2, int l2))


