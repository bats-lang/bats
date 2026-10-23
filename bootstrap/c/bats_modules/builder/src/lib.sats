staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"
















stadef BUILDER_CAP = 524288





stadef INITIAL_CAP = 64










datavtype builder_store(int) =
  | {m:nat}{cap:pos | m <= cap; cap <= BUILDER_CAP}{lb:agz}
    BuilderStore(m) of ($A.arr(byte, lb, cap), int(cap))

datavtype builder(int) =
  | {n:nat | n <= BUILDER_CAP}
    Builder(n) of (builder_store(n), int(n))

vtypedef builder_v = [n:nat | n <= BUILDER_CAP] builder(n)





fun create
  (): builder(0)




fn to_arr {n:nat | n <= BUILDER_CAP}
  (b: builder(n)): @([l:agz] $A.arr(byte, l, BUILDER_CAP), int n)



fn into_arr {n:nat | n <= BUILDER_CAP}
  (b: builder(n)): @([cap:pos | n <= cap; cap <= BUILDER_CAP][l:agz] $A.arr(byte, l, cap), int n)

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














datavtype rope_sized_list(int) =
  | rope_sized_nil(0)
  | {k:nat}{cap:pos}{lb:agz}{n:nat | n <= cap; cap <= BUILDER_CAP}
    rope_sized_cons(k + 1) of ($A.arr(byte, lb, cap), int n, rope_sized_list(k))





datavtype sized_rope =
  | {k:nat} SizedRope of (rope_sized_list(k), builder_v)

fun sized_rope_create (): sized_rope


fun sized_rope_put {v:nat | v < 256} (r: !sized_rope, v: int v): void


fun sized_rope_bput {sn:nat} (r: !sized_rope, s: string sn): void


fun sized_rope_copy {l:agz}{n:pos}{i,j:nat | i <= j; j <= n}
  (r: !sized_rope, src: !$A.borrow(byte, l, n), start: int i, stop: int j): void


fun sized_rope_append (r: !sized_rope, b: builder_v): void


fun sized_rope_chunks (r: sized_rope): [k:nat] rope_sized_list(k)


fun rope_sized_list_free {k:nat} (cs: rope_sized_list(k)): void















































































































































































































































































































































