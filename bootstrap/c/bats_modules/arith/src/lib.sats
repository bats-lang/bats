






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















fn low_byte(x: int): [v:nat | v < 256] int v









fn byte_of_char(c: char): [v:nat | v < 256] int v



