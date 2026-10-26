













absvtype arrx(a:t@ype, l:addr, n:int, o:addr)

vtypedef arr(a:t@ype, l:addr, n:int) = arrx(a, l, n, null)

absvtype frozenx(a:t@ype, l:addr, n:int, k:int, o:addr)

vtypedef frozen(a:t@ype, l:addr, n:int, k:int) = frozenx(a, l, n, k, null)

absvtype borrow(a:t@ype, l:addr, n:int)










fun{a:t@ype}
alloc
  {n:pos | n <= 1048576}
  (n: int n)
  : [l:agz] arr(a, l, n)




datavtype alloc_made(a:t@ype, n:int) =
  | {l:agz} alloc_some(a, n) of arr(a, l, n)
  | alloc_none(a, n) of ()



fun{a:t@ype}
alloc_checked
  {n:pos | n <= 1048576}
  (n: int n)
  : alloc_made(a, n)

fun{a:t@ype}
free
  {l:agz}{n:nat}
  (arr: arr(a, l, n))
  : void





fun{a:t@ype}
get
  {l:agz}{o:addr}{n,i:nat | i < n}
  (arr: !arrx(a, l, n, o), i: int i)
  : a

fun{a:t@ype}
set
  {l:agz}{o:addr}{n,i:nat | i < n}
  (arr: !arrx(a, l, n, o), i: int i, v: a)
  : void





fun{a:t@ype}
freeze
  {l:agz}{o:addr}{n:nat}
  (arr: arrx(a, l, n, o))
  : @(frozenx(a, l, n, 1, o), borrow(a, l, n))

fun{a:t@ype}
thaw
  {l:agz}{o:addr}{n:nat}
  (f: frozenx(a, l, n, 0, o))
  : arrx(a, l, n, o)

fun{a:t@ype}
dup
  {l:agz}{o:addr}{n:nat}{k:pos}
  (f: !frozenx(a, l, n, k, o) >> frozenx(a, l, n, k+1, o),
   b: !borrow(a, l, n))
  : borrow(a, l, n)

fun{a:t@ype}
drop
  {l:agz}{o:addr}{n:nat}{k:pos}
  (f: !frozenx(a, l, n, k, o) >> frozenx(a, l, n, k-1, o),
   b: borrow(a, l, n))
  : void





fun{a:t@ype}
read
  {l:agz}{n,i:nat | i < n}
  (b: !borrow(a, l, n), i: int i)
  : a





fun{a:t@ype}
borrow_split
  {l:agz}{o:addr}{n,m:nat | m <= n}{k:pos}
  (f: !frozenx(a, l, n, k, o) >> frozenx(a, l, n, k+1, o),
   b: borrow(a, l, n), m: int m)
  : @(borrow(a, l, m), borrow(a, l+m, n-m))

fun{a:t@ype}
borrow_join
  {l:agz}{o:addr}{n,m:nat}{k:int | k > 1}
  (f: !frozenx(a, l, n+m, k, o) >> frozenx(a, l, n+m, k-1, o),
   left: borrow(a, l, n), right: borrow(a, l+n, m))
  : borrow(a, l, n+m)





fun{a:t@ype}
borrow_at
  {l:agz}{o:addr}{n:pos}{i:nat | i < n}{k:pos}
  (f: !frozenx(a, l, n, k, o) >> frozenx(a, l, n, k+1, o),
   b: !borrow(a, l, n), i: int i)
  : borrow(a, l+i, 1)

fun{a:t@ype}
drop_borrow_at
  {l:agz}{o:addr}{n:pos}{i:nat | i < n}{k:int | k > 1}
  (f: !frozenx(a, l, n, k, o) >> frozenx(a, l, n, k-1, o),
   b: borrow(a, l+i, 1))
  : void





stadef SAFE_CHAR (c:int) =
  (c >= 0 && c < 256)

abstype text (n:int) = ptr

absvtype text_builder (n:int, filled:int)

fun text_build
  {n:pos}
  (n: int n)
  : text_builder(n, 0)

fun text_putc
  {c:int | SAFE_CHAR(c)} {n:pos} {i:nat | i < n}
  (b: text_builder(n, i), i: int i, c: int c)
  : text_builder(n, i+1)

fun text_done
  {n:pos}
  (b: text_builder(n, n))
  : text(n)

fun text_get
  {n,i:nat | i < n}
  (t: text(n), i: int i)
  : byte






fun text_lit
  {n:nat}
  (s: string n)
  : text(n)






datavtype text_result(n:int) =
  | {n:int} text_ok(n) of (text(n))
  | {n:int} text_fail(n) of ()

fun text_from_bytes
  {lb:agz}{n:pos}
  (src: !borrow(byte, lb, n), len: int n): text_result(n)





fun int2byte{i:nat | i < 256}(i: int i): byte





fun write_byte
  {l:agz}{o:addr}{n:nat}{i:nat | i < n}{v:nat | v < 256}
  (arr: !arrx(byte, l, n, o), i: int i, v: int v): void

fun write_u16le
  {l:agz}{o:addr}{n:nat}{i:nat | i + 2 <= n}{v:nat | v < 65536}
  (arr: !arrx(byte, l, n, o), i: int i, v: int v): void



fun write_i32
  {l:agz}{o:addr}{n:nat}{i:nat | i + 4 <= n}
  (arr: !arrx(byte, l, n, o), i: int i, v: int): void

fun write_borrow
  {ld:agz}{o:addr}{ls:agz}{m:nat}{n:nat}{off:nat | off + n <= m}
  (dst: !arrx(byte, ld, m, o), off: int off,
   src: !borrow(byte, ls, n), len: int n): void

fun write_text
  {l:agz}{o:addr}{m:nat}{n:nat}{off:nat | off + n <= m}
  (dst: !arrx(byte, l, m, o), off: int off,
   src: text(n), len: int n): void





stadef SAFE_CONTENT_CHAR(c:int) =
  (c >= 32 && c <= 126)
  && c != 34
  && c != 38
  && c != 60
  && c != 62

absvtype content_text(l:addr, n:int)

absvtype content_text_builder(l:addr, n:int, filled:int)

fun content_text_build
  {n:pos | n <= 1048576}
  (n: int n)
  : [l:agz] content_text_builder(l, n, 0)

fun content_text_putc
  {c:int | SAFE_CONTENT_CHAR(c)} {l:agz} {n:pos} {i:nat | i < n}
  (b: content_text_builder(l, n, i), i: int i, c: int c)
  : content_text_builder(l, n, i+1)

fun content_text_done
  {l:agz} {n:pos}
  (b: content_text_builder(l, n, n))
  : content_text(l, n)

fun content_text_get
  {l:agz} {n,i:nat | i < n}
  (t: !content_text(l, n), i: int i)
  : byte

fun content_text_free
  {l:agz} {n:nat}
  (t: content_text(l, n))
  : void

fun text_to_content
  {n:pos | n <= 1048576}
  (t: text(n), len: int n)
  : [l:agz] content_text(l, n)

fun write_content_text
  {ld:agz}{o:addr}{ls:agz}{m:nat}{n:nat}{off:nat | off + n <= m}
  (dst: !arrx(byte, ld, m, o), off: int off,
   src: !content_text(ls, n), len: int n): void
















absvtype arena(a:t@ype, l:addr, max:int, used:int, k:int)


datavtype arena_made(a:t@ype, max:int) =
  | {l:agz} arena_some(a, max) of arena(a, l, max, 0, 0)
  | arena_none(a, max) of ()
















dataprop ARENA_CLASS(int) =
  | Arena64KiB(65536)
  | Arena256KiB(262144)
  | Arena1MiB(1048576)
  | Arena4MiB(4194304)
  | Arena16MiB(16777216)


stadef ARENA_MOST = 16777216



datavtype arena_fit(n:int) =
  | {max:int | n <= max} arena_fits(n) of (ARENA_CLASS(max) | int max)
  | arena_too_large(n) of ()

fn arena_class_of {n:pos} (n: int n): arena_fit(n)


fun{a:t@ype}
arena_create_class
  {max:int}
  (class: ARENA_CLASS(max) | max: int max)
  : arena_made(a, max)



fun{a:t@ype}
arena_create
  {max:pos | max <= 268435456}
  (max: int max)
  : arena_made(a, max)


fun{a:t@ype}
arena_alloc
  {la:agz}{max,used,k:nat}{n:pos | used + n <= max}
  (ar: !arena(a, la, max, used, k) >> arena(a, la, max, used + n, k + 1),
   n: int n)
  : [l:agz] arrx(a, l, n, la)

fun{a:t@ype}
arena_return
  {la:agz}{max,used:nat}{k:pos}{l:agz}{n:nat}
  (ar: !arena(a, la, max, used, k) >> arena(a, la, max, used, k - 1),
   p: arrx(a, l, n, la))
  : void

fun{a:t@ype}
arena_destroy
  {la:agz}{max,used:nat}
  (ar: arena(a, la, max, used, 0))
  : void






datasort cells =
  | cnil of ()
  | ccons of (int, cells)


dataprop CLEN(cells, int) =
  | CLEN_nil(cnil(), 0)
  | {c:int}{cs:cells}{n:nat} CLEN_cons(ccons(c, cs), n + 1) of CLEN(cs, n)


dataprop NTH(cells, int, int) =
  | {c:int}{cs:cells} NTH_here(ccons(c, cs), 0, c)
  | {c,v:int}{cs:cells}{i:nat} NTH_there(ccons(c, cs), i + 1, v) of NTH(cs, i, v)


dataprop SETC(cells, int, int, cells) =
  | {c,v:int}{cs:cells} SETC_here(ccons(c, cs), 0, v, ccons(v, cs))
  | {c,v:int}{cs,cs2:cells}{i:nat} SETC_there(ccons(c, cs), i + 1, v, ccons(c, cs2)) of SETC(cs, i, v, cs2)


dataprop APPEND_SIZED(cells, cells, cells, int) =
  | {second:cells} APPEND_SIZED_nil(cnil(), second, second, 0)
  | {x:int}{first,second,both:cells}{n:nat} APPEND_SIZED_cons(ccons(x, first), second, ccons(x, both), n + 1) of APPEND_SIZED(first, second, both, n)




dataprop APPEND(cells, cells, cells) =
  | {first,second,both:cells}{n:nat} APPEND_made(first, second, both) of APPEND_SIZED(first, second, both, n)

prfun APPEND_nil {second:cells} (): APPEND(cnil(), second, second)



prfun APPEND_cons {x:int}{first,second,both:cells} (APPEND(first, second, both)): APPEND(ccons(x, first), second, ccons(x, both))





dataprop CELLS_EQ(cells, cells) =
  | {cs:cells} CELLS_EQ_refl(cs, cs)


dataprop HOLDS(cells, cells) =
  | {buffer,chunk,rest:cells} HOLDS_mk(buffer, chunk) of APPEND(chunk, rest, buffer)






prfun setc_len {cs,cs2:cells}{i:nat}{v:int}{n:nat} (SETC(cs, i, v, cs2), CLEN(cs, n)): CLEN(cs2, n)









prfun setc_nth_same {cs,cs2:cells}{i:nat}{v:int} (SETC(cs, i, v, cs2)): NTH(cs2, i, v)









prfun setc_nth_other {cs,cs2:cells}{i,j:nat | i != j}{v,w:int} (SETC(cs, i, v, cs2), NTH(cs, j, w)): NTH(cs2, j, w)












prfun nth_in_len {cs:cells}{i:nat}{v:int}{n:nat} (NTH(cs, i, v), CLEN(cs, n)): [i < n] void









prfun nth_functional {cs:cells}{i:nat}{v,w:int} (NTH(cs, i, v), NTH(cs, i, w)): [v == w] void









prfun append_functional {first,second,both,other:cells} (APPEND(first, second, both), APPEND(first, second, other)): CELLS_EQ(both, other)




















dataprop ALLIN(cells, int, int) =
  | {lo,hi:int} ALLIN_nil(cnil(), lo, hi)
  | {c,lo,hi:int | lo <= c; c <= hi}{cs:cells} ALLIN_cons(ccons(c, cs), lo, hi) of ALLIN(cs, lo, hi)


dataprop ZEROS(cells, int) =
  | ZEROS_nil(cnil(), 0)
  | {cs:cells}{n:nat} ZEROS_cons(ccons(0, cs), n + 1) of ZEROS(cs, n)


prfun allin_nth {cs:cells}{lo,hi:int}{i:nat}{v:int} (ALLIN(cs, lo, hi), NTH(cs, i, v)): [lo <= v; v <= hi] void









prfun allin_setc {cs,cs2:cells}{lo,hi:int}{i:nat}{v:int | lo <= v; v <= hi}
  (ALLIN(cs, lo, hi), SETC(cs, i, v, cs2)): ALLIN(cs2, lo, hi)










prfun allin_widen {cs:cells}{lo,hi,lo2,hi2:int | lo2 <= lo; hi <= hi2}{n:nat}
  (ALLIN(cs, lo, hi), CLEN(cs, n)): ALLIN(cs, lo2, hi2)










prfun allin_zeros {cs:cells}{lo,hi:int | lo <= 0; 0 <= hi}{n:nat} (ZEROS(cs, n)): ALLIN(cs, lo, hi)









prfun zeros_nth {cs:cells}{i:nat}{v:int}{n:nat} (ZEROS(cs, n), NTH(cs, i, v)): [v == 0] void









prfun zeros_len {cs:cells}{n:nat} (ZEROS(cs, n)): CLEN(cs, n)













absvtype barr(l:addr, n:int, cs:cells) = ptr



fun barr_alloc {n:pos | n <= 1048576} (n: int n): [l:agz][cs:cells] (CLEN(cs, n) | barr(l, n, cs))

fun barr_free {l:agz}{n:nat}{cs:cells} (a: barr(l, n, cs)): void


fun barr_get {l:agz}{n,i:nat | i < n}{cs:cells} (a: !barr(l, n, cs), i: int i)
  : [v:int | 0 <= v; v < 256] (NTH(cs, i, v) | int v)


fun barr_get_be32 {l:agz}{n,i:nat | i + 3 < n}{cs:cells} (a: !barr(l, n, cs), i: int i)
  : [b0,b1,b2,b3:int | 0 <= b0; b0 < 256; 0 <= b1; b1 < 256; 0 <= b2; b2 < 256; 0 <= b3; b3 < 256]
    (NTH(cs, i, b0), NTH(cs, i + 1, b1), NTH(cs, i + 2, b2), NTH(cs, i + 3, b3)
    | @(int b0, int b1, int b2, int b3))


fun barr_set {l:agz}{n,i:nat | i < n}{cs:cells}{v:int | 0 <= v; v < 256} (a: barr(l, n, cs), i: int i, v: int v)
  : [cs2:cells] (SETC(cs, i, v, cs2) | barr(l, n, cs2))







fun{} barr_get_inline {l:agz}{n,i:nat | i < n}{cs:cells} (a: !barr(l, n, cs), i: int i)
  : [v:int | 0 <= v; v < 256] (NTH(cs, i, v) | int v)

fun{} barr_get_be32_inline {l:agz}{n,i:nat | i + 3 < n}{cs:cells} (a: !barr(l, n, cs), i: int i)
  : [b0,b1,b2,b3:int | 0 <= b0; b0 < 256; 0 <= b1; b1 < 256; 0 <= b2; b2 < 256; 0 <= b3; b3 < 256]
    (NTH(cs, i, b0), NTH(cs, i + 1, b1), NTH(cs, i + 2, b2), NTH(cs, i + 3, b3)
    | @(int b0, int b1, int b2, int b3))

fun{} barr_set_inline {l:agz}{n,i:nat | i < n}{cs:cells}{v:int | 0 <= v; v < 256} (a: barr(l, n, cs), i: int i, v: int v)
  : [cs2:cells] (SETC(cs, i, v, cs2) | barr(l, n, cs2))



fun barr_of_arr {l:agz}{n:nat} (a: arr(byte, l, n)): [cs:cells] (CLEN(cs, n) | barr(l, n, cs))


fun barr_to_arr {l:agz}{n:nat}{cs:cells} (a: barr(l, n, cs)): arr(byte, l, n)










absview arrx_lent(l:addr, n:int, o:addr)

fun barr_of_arrx {l:agz}{n:nat}{o:addr} (a: arrx(byte, l, n, o))
  : [cs:cells] (CLEN(cs, n), arrx_lent(l, n, o) | barr(l, n, cs))

fun barr_to_arrx {l:agz}{n:nat}{o:addr}{cs:cells} (pf: arrx_lent(l, n, o) | a: barr(l, n, cs))
  : arrx(byte, l, n, o)


fun barr_copy {l:agz}{n:pos}{cs:cells} (a: !barr(l, n, cs), n: int n): [m:agz] barr(m, n, cs)










absvtype cfrozen(l:addr, n:int, k:int, cs:cells) = ptr

absvtype cborrow(l:addr, n:int, cs:cells) = ptr

fun barr_freeze {l:agz}{n:nat}{cs:cells} (a: barr(l, n, cs))
  : @(cfrozen(l, n, 1, cs), cborrow(l, n, cs))

fun barr_thaw {l:agz}{n:nat}{cs:cells} (f: cfrozen(l, n, 0, cs)): barr(l, n, cs)

fun cborrow_dup {l:agz}{n:nat}{cs:cells}{k:pos}
  (f: !cfrozen(l, n, k, cs) >> cfrozen(l, n, k+1, cs), b: !cborrow(l, n, cs))
  : cborrow(l, n, cs)

fun cborrow_drop {l:agz}{n:nat}{cs:cells}{k:pos}
  (f: !cfrozen(l, n, k, cs) >> cfrozen(l, n, k-1, cs), b: cborrow(l, n, cs)): void







fun cborrow_view {l:agz}{n:nat}{cs:cells}{k:pos}
  (f: !cfrozen(l, n, k, cs) >> cfrozen(l, n, k+1, cs), b: !cborrow(l, n, cs))
  : borrow(byte, l, n)

fun cborrow_view_drop {l:agz}{n:nat}{cs:cells}{k:pos}
  (f: !cfrozen(l, n, k, cs) >> cfrozen(l, n, k-1, cs), b: borrow(byte, l, n)): void


fun cborrow_get {l:agz}{n,i:nat | i < n}{cs:cells} (b: !cborrow(l, n, cs), i: int i)
  : [v:int | 0 <= v; v < 256] (NTH(cs, i, v) | int v)











absvtype iarr(l:addr, n:int, cs:cells) = ptr


fun iarr_alloc {n:pos | n <= 1048576} (n: int n)
  : [l:agz][cs:cells] (CLEN(cs, n), ZEROS(cs, n) | iarr(l, n, cs))

fun iarr_free {l:agz}{n:nat}{cs:cells} (a: iarr(l, n, cs)): void


fun iarr_get {l:agz}{n,i:nat | i < n}{cs:cells} (a: !iarr(l, n, cs), i: int i)
  : [v:int | ~2147483648 <= v; v <= 2147483647] (NTH(cs, i, v) | int v)


fun iarr_set {l:agz}{n,i:nat | i < n}{cs:cells}{v:int | ~2147483648 <= v; v <= 2147483647}
  (a: iarr(l, n, cs), i: int i, v: int v)
  : [cs2:cells] (SETC(cs, i, v, cs2) | iarr(l, n, cs2))




fun iarr_get_in {l:agz}{n,i:nat | i < n}{cs:cells}{lo,hi:int | ~2147483648 <= lo; hi <= 2147483647}
  (pf: ALLIN(cs, lo, hi) | a: !iarr(l, n, cs), i: int i): [v:int | lo <= v; v <= hi] int v



fun iarr_set_in {l:agz}{n,i:nat | i < n}{cs:cells}{lo,hi:int | ~2147483648 <= lo; hi <= 2147483647}{v:int | lo <= v; v <= hi}
  (pf: ALLIN(cs, lo, hi) | a: iarr(l, n, cs), i: int i, v: int v)
  : [cs2:cells] (ALLIN(cs2, lo, hi) | iarr(l, n, cs2))










































































































































































































































































































































































































