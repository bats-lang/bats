staload A = "array/src/lib.sats"
staload AR = "arith/src/lib.sats"












datavtype str_option(a:t@ype) =
  | str_some(a) of (a)
  | str_none(a) of ()





fun compare
  {la:agz}{na:pos}{lb:agz}{nb:pos}
  (a: !$A.borrow(byte, la, na), a_len: int na,
   b: !$A.borrow(byte, lb, nb), b_len: int nb): int





fun eq
  {la:agz}{na:pos}{lb:agz}{nb:pos}
  (a: !$A.borrow(byte, la, na), a_len: int na,
   b: !$A.borrow(byte, lb, nb), b_len: int nb): bool





fun index_of
  {la:agz}{na:pos}
  (haystack: !$A.borrow(byte, la, na), h_len: int na,
   needle_byte: int): str_option(int)





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
  (s: !$A.borrow(byte, la, na), s_len: int na): int





fun trim_right
  {la:agz}{na:pos}
  (s: !$A.borrow(byte, la, na), s_len: int na): int





fun to_upper_byte(b: int): int





fun to_lower_byte(b: int): int





fun int_to_str
  {l:agz}{n:pos}
  (buf: !$A.arr(byte, l, n), pos: int, max_len: int n, value: int): int





fun str_to_int
  {lb:agz}{n:pos}
  (s: !$A.borrow(byte, lb, n), len: int n): str_option(int)





fn from_char_array
  {n:pos | n <= 1048576}
  (src: &(@[char][n]), n: int n): [l:agz] $A.arr(byte, l, n)





fn text_of_chars
  {n:pos | n <= 1048576}
  (src: &(@[char][n]), n: int n): $A.text(n)





fun chars_match
  {l:agz}{n:pos}{sn:nat}
  (ent: !$A.arr(byte, l, n), p: int, max: int n,
   pat: string sn, pi: int, plen: int sn): bool





fun chars_match_borrow
  {l:agz}{n:pos}{sn:nat}
  (src: !$A.borrow(byte, l, n), p: int, max: int n,
   pat: string sn, pi: int, plen: int sn): bool





fn has_suffix
  {l:agz}{n:pos}{sn:nat}
  (ent: !$A.arr(byte, l, n), len: int, max: int n,
   suf: string sn, slen: int sn): bool





fn name_eq
  {l:agz}{n:pos}{sn:nat}
  (ent: !$A.arr(byte, l, n), len: int, max: int n,
   s: string sn, slen: int sn): bool

































































































































































































































































































































































































fn borrow_byte {l:agz}{n:pos}
  (src: !$A.borrow(byte, l, n), pos: int, max: int n): int







fun find_null {l:agz}{n:pos}{fuel:nat}
  (buf: !$A.arr(byte, l, n), pos: int, max: int n,
   fuel: int fuel): int










fun find_null_bv {l:agz}{n:pos}{fuel:nat}
  (bv: !$A.borrow(byte, l, n), pos: int, max: int n,
   fuel: int fuel): int















fun fill_exact {l:agz}{n:pos}{sn:nat}{i:nat | i <= sn}{fuel:nat}
  (arr: !$A.arr(byte, l, n), s: string sn, n: int n, slen: int sn,
   i: int i, fuel: int fuel): void











fn str_to_borrow {sn:pos}
  (s: string sn): [l:agz][n:pos] @($A.arr(byte, l, n), int n)









