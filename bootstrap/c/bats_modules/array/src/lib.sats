













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



















































































































































































































































