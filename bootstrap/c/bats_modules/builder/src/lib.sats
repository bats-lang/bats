staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"













stadef BUILDER_CAP = 524288







datavtype builder(int) =
  | {lb:agz}{n:nat | n <= BUILDER_CAP}
    Builder(n) of ($A.arr(byte, lb, BUILDER_CAP), int(n))

vtypedef builder_v = [n:nat | n <= BUILDER_CAP] builder(n)





fun create
  (): builder(0)

fn to_arr
  (b: builder_v): @([l:agz] $A.arr(byte, l, BUILDER_CAP), int)

fun builder_free
  (b: builder_v): void

fun length {n:nat | n <= BUILDER_CAP}
  (b: !builder(n)): int(n)

fun put_byte {n:nat | n < BUILDER_CAP}
  (b: !builder(n) >> builder(n+1), v: int): void

fun put_char {n:nat | n < BUILDER_CAP}
  (b: !builder(n) >> builder(n+1), v: int): void

fun put_newline {n:nat | n < BUILDER_CAP}
  (b: !builder(n) >> builder(n+1)): void

fun put_int {n:nat | n + 21 <= BUILDER_CAP}
  (b: !builder(n) >> [m:nat | n <= m; m <= n + 21] builder(m), num: int): void

fn bput {sn:nat}{n:nat | n + sn <= BUILDER_CAP}
  (b: !builder(n) >> [m:nat | n <= m; m <= n + sn] builder(m), s: string sn): void

fn bput_int {n:nat | n + 16 <= BUILDER_CAP}
  (b: !builder(n) >> [m:nat | n <= m; m <= n + 16] builder(m), v: int): void






































































































































































































