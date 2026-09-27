staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"













stadef BUILDER_CAP = 524288







datavtype builder(int) =
  | {lb:agz}{n:nat | n <= BUILDER_CAP}
    Builder(n) of ($A.arr(byte, lb, BUILDER_CAP), int(n))

vtypedef builder_v = [n:nat | n <= BUILDER_CAP] builder(n)





fun create
  (): builder(0)

fn to_arr {n:nat | n <= BUILDER_CAP}
  (b: builder(n)): @([l:agz] $A.arr(byte, l, BUILDER_CAP), int n)

fun builder_free
  (b: builder_v): void

fun length {n:nat | n <= BUILDER_CAP}
  (b: !builder(n)): int(n)

fun put_byte {n:nat | n < BUILDER_CAP}{v:nat | v < 256}
  (b: !builder(n) >> builder(n+1), v: int v): void

fun put_char {n:nat | n < BUILDER_CAP}{v:nat | v < 256}
  (b: !builder(n) >> builder(n+1), v: int v): void

fun put_newline {n:nat | n < BUILDER_CAP}
  (b: !builder(n) >> builder(n+1)): void



fun put_int {n:nat | n + 11 <= BUILDER_CAP}
  (b: !builder(n) >> [m:nat | n < m; m <= n + 11] builder(m), num: int): void

fn bput {sn:nat}{n:nat | n + sn <= BUILDER_CAP}
  (b: !builder(n) >> builder(n + sn), s: string sn): void






datavtype rope_list(int) =
  | rope_nil(0)
  | {k:nat}{lb:agz}{n:nat | n <= BUILDER_CAP}
    rope_cons(k + 1) of ($A.arr(byte, lb, BUILDER_CAP), int n, rope_list(k))




datavtype rope =
  | {k:nat} Rope of (rope_list(k), builder_v)

fun rope_create (): rope


fun rope_put {v:nat | v < 256} (r: !rope, v: int v): void


fun rope_bput {sn:nat} (r: !rope, s: string sn): void


fun rope_copy {l:agz}{n:pos}{i,j:nat | i <= j; j <= n}
  (r: !rope, src: !$A.borrow(byte, l, n), start: int i, stop: int j): void


fun rope_append (r: !rope, b: builder_v): void


fun rope_chunks (r: rope): [k:nat] rope_list(k)


fun rope_list_free {k:nat} (cs: rope_list(k)): void





















































































































































































































