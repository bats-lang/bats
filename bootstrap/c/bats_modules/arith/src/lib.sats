






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



castfn g0_of_g1 {n:int} (x: int(n)): int

castfn checked_pos(x: int): [n:pos] int n

castfn checked_nat(x: int): [n:nat] int n

castfn checked_byte(x: int): [v:nat | v < 256] int v

castfn checked_arr_size(x: int): [n:pos | n <= 1048576] int n

castfn checked_idx {n:pos} (x: int, len: int n): [i:nat | i < n] int i

