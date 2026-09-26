staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"












datavtype str_option(a:t@ype) =
  | str_some(a) of (a)
  | str_none(a) of ()





fun compare
  {la:agz}{na:pos}{lb:agz}{nb:pos}
  (a: !$A.borrow(byte, la, na), a_len: int na,
   b: !$A.borrow(byte, lb, nb), b_len: int nb): [r:int | ~1 <= r; r <= 1] int r





fun eq
  {la:agz}{na:pos}{lb:agz}{nb:pos}
  (a: !$A.borrow(byte, la, na), a_len: int na,
   b: !$A.borrow(byte, lb, nb), b_len: int nb): bool





fun index_of
  {la:agz}{na:pos}
  (haystack: !$A.borrow(byte, la, na), h_len: int na,
   needle_byte: int): str_option([i:nat | i < na] int i)





fun starts_with
  {la:agz}{na:pos}{lb:agz}{nb:pos}
  (s: !$A.borrow(byte, la, na), s_len: int na,
   pfx: !$A.borrow(byte, lb, nb), p_len: int nb): bool





fun ends_with
  {la:agz}{na:pos}{lb:agz}{nb:pos}
  (s: !$A.borrow(byte, la, na), s_len: int na,
   suffix: !$A.borrow(byte, lb, nb), sf_len: int nb): bool





fun contains
  {la:agz}{na:pos}
  (s: !$A.borrow(byte, la, na), s_len: int na,
   byte_val: int): bool





fun trim_left
  {la:agz}{na:pos}
  (s: !$A.borrow(byte, la, na), s_len: int na): [r:nat | r <= na] int r





fun trim_right
  {la:agz}{na:pos}
  (s: !$A.borrow(byte, la, na), s_len: int na): [r:nat | r <= na] int r





fun to_upper_byte(b: int): int





fun to_lower_byte(b: int): int





fun int_to_str
  {l:agz}{n:pos}{p:nat | p <= n}{v:int}
  (buf: !$A.arr(byte, l, n), pos: int p, max_len: int n, value: int v)
  : [r:int | p <= r; r <= n] int r





fun str_to_int
  {lb:agz}{n:pos}
  (s: !$A.borrow(byte, lb, n), len: int n): str_option(int)





fn from_char_array
  {n:pos | n <= 1048576}
  (src: &(@[char][n]), n: int n): [l:agz] $A.arr(byte, l, n)





fn text_of_chars
  {n:pos | n <= 1048576}
  (src: &(@[char][n]), n: int n): $A.text(n)





fn has_suffix
  {l:agz}{n:pos}{k:nat | k <= n}{lp:agz}{np:pos}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n,
   suf: !$A.borrow(byte, lp, np), slen: int np): bool





fn name_eq
  {l:agz}{n:pos}{k:nat | k <= n}{lp:agz}{np:pos}
  (ent: !$A.arr(byte, l, n), len: int k, max: int n,
   s: !$A.borrow(byte, lp, np), slen: int np): bool






































































































































































































































































fn match_at {l:agz}{n:pos}{lp:agz}{np:pos}{p:nat | p + np <= n}
  (src: !$A.borrow(byte, l, n), p: int p,
   pat: !$A.borrow(byte, lp, np), np: int np): bool












fn match_at_arr {l:agz}{n:pos}{lp:agz}{np:pos}{p:nat | p + np <= n}
  (src: !$A.arr(byte, l, n), p: int p,
   pat: !$A.borrow(byte, lp, np), np: int np): bool










fn byte_at {l:agz}{n:pos}{p:nat | p < n}
  (src: !$A.borrow(byte, l, n), p: int p): int






fn find_null_at {l:agz}{n:pos}{p:nat | p <= n}
  (buf: !$A.arr(byte, l, n), p: int p, n: int n)
  : [r:int | p <= r; r <= n] int r











fn find_null_bv_at {l:agz}{n:pos}{p:nat | p <= n}
  (bv: !$A.borrow(byte, l, n), p: int p, n: int n)
  : [r:int | p <= r; r <= n] int r














fun copy_from_borrow
  {lb:agz}{nb:pos}{la:agz}{na:pos}{so:nat}{do_:nat}{c:nat | so+c <= nb; do_+c <= na}
  (src: !$A.borrow(byte, lb, nb), src_off: int so, src_max: int nb,
   dst: !$A.arr(byte, la, na), dst_off: int do_, dst_max: int na,
   count: int c): void





fn copy_arr_region
  {ls:agz}{ns:pos}{ld:agz}{nd:pos}{so:nat}{c:nat | so+c <= ns; c <= nd}
  (src: $A.arr(byte, ls, ns), src_off: int so, src_max: int ns,
   dst: !$A.arr(byte, ld, nd), dst_max: int nd,
   count: int c): $A.arr(byte, ls, ns)





fun borrow_region_eq
  {lb:agz}{n:pos}{oa:nat}{ob:nat}{c:nat | oa+c <= n; ob+c <= n}
  (data: !$A.borrow(byte, lb, n), len: int n,
   off_a: int oa, off_b: int ob, count: int c): bool






fn fill_exact {l:agz}{n:pos}{lb:agz}{nb:pos}{i:nat | i <= nb}
  (arr: !$A.arr(byte, l, n), src: !$A.borrow(byte, lb, nb), n: int n,
   slen: int nb, i: int i): void













































